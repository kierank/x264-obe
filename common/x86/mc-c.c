/*****************************************************************************
 * mc-c.c: x86 motion compensation
 *****************************************************************************
 * Copyright (C) 2003-2014 x264 project
 *
 * Authors: Laurent Aimar <fenrir@via.ecp.fr>
 *          Loren Merritt <lorenm@u.washington.edu>
 *          Jason Garrett-Glaser <darkshikari@gmail.com>
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

#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#include "common/common.h"
#include "mc.h"
#define x264_frame_init_lowres_core_avx x264_template(frame_init_lowres_core_avx)
#define x264_frame_init_lowres_core_avx2 x264_template(frame_init_lowres_core_avx2)
#define x264_frame_init_lowres_core_avx512icl x264_template(frame_init_lowres_core_avx512icl)
#define x264_frame_init_lowres_core8_ssse3 x264_template(frame_init_lowres_core8_ssse3)
#define x264_frame_init_lowres_core8_avx2 x264_template(frame_init_lowres_core8_avx2)
#define x264_frame_init_lowres_core_cache32_mmx2 x264_template(frame_init_lowres_core_cache32_mmx2)
#define x264_frame_init_lowres_core_mmx2 x264_template(frame_init_lowres_core_mmx2)
#define x264_frame_init_lowres_core_sse2 x264_template(frame_init_lowres_core_sse2)
#define x264_frame_init_lowres_core_ssse3 x264_template(frame_init_lowres_core_ssse3)
#define x264_frame_init_lowres_core_xop x264_template(frame_init_lowres_core_xop)
#define x264_hpel_filter_avx x264_template(hpel_filter_avx)
#define x264_hpel_filter_avx2 x264_template(hpel_filter_avx2)
#define x264_hpel_filter_c_avx2 x264_template(hpel_filter_c_avx2)
#define x264_hpel_filter_copy_avx x264_template(hpel_filter_copy_avx)
#define x264_hpel_filter_copy_avx2 x264_template(hpel_filter_copy_avx2)
#define x264_hpel_filter_copy_sse2 x264_template(hpel_filter_copy_sse2)
#define x264_hpel_filter_copy_ssse3 x264_template(hpel_filter_copy_ssse3)
#define x264_hpel_filter_h_avx2 x264_template(hpel_filter_h_avx2)
#define x264_hpel_filter_h_copy_avx2 x264_template(hpel_filter_h_copy_avx2)
#define x264_hpel_filter_v_avx2 x264_template(hpel_filter_v_avx2)
#define x264_hpel_filter_c_mmx2 x264_template(hpel_filter_c_mmx2)
#define x264_hpel_filter_c_sse2 x264_template(hpel_filter_c_sse2)
#define x264_hpel_filter_h_mmx2 x264_template(hpel_filter_h_mmx2)
#define x264_hpel_filter_h_sse2 x264_template(hpel_filter_h_sse2)
#define x264_hpel_filter_sse2 x264_template(hpel_filter_sse2)
#define x264_hpel_filter_ssse3 x264_template(hpel_filter_ssse3)
#define x264_hpel_filter_v_mmx2 x264_template(hpel_filter_v_mmx2)
#define x264_hpel_filter_v_sse2 x264_template(hpel_filter_v_sse2)
#define x264_integral_init4h_avx2 x264_template(integral_init4h_avx2)
#define x264_integral_init4h_avx512icl x264_template(integral_init4h_avx512icl)
#define x264_integral_init8h_avx512icl x264_template(integral_init8h_avx512icl)
#define x264_integral_init4v_avx512icl x264_template(integral_init4v_avx512icl)
#define x264_integral_init8v_avx512icl x264_template(integral_init8v_avx512icl)
#define x264_integral_init4h_sse4 x264_template(integral_init4h_sse4)
#define x264_integral_init4v_avx2 x264_template(integral_init4v_avx2)
#define x264_integral_init4v_mmx x264_template(integral_init4v_mmx)
#define x264_integral_init4v_sse2 x264_template(integral_init4v_sse2)
#define x264_integral_init4v_ssse3 x264_template(integral_init4v_ssse3)
#define x264_integral_init8h_avx x264_template(integral_init8h_avx)
#define x264_integral_init8h_avx2 x264_template(integral_init8h_avx2)
#define x264_integral_init8h_sse4 x264_template(integral_init8h_sse4)
#define x264_integral_init8v_avx2 x264_template(integral_init8v_avx2)
#define x264_integral_init8v_mmx x264_template(integral_init8v_mmx)
#define x264_integral_init8v_sse2 x264_template(integral_init8v_sse2)
#define x264_load_deinterleave_chroma_fdec_avx x264_template(load_deinterleave_chroma_fdec_avx)
#define x264_load_deinterleave_chroma_fdec_mmx x264_template(load_deinterleave_chroma_fdec_mmx)
#define x264_load_deinterleave_chroma_fdec_sse2 x264_template(load_deinterleave_chroma_fdec_sse2)
#define x264_load_deinterleave_chroma_fdec_ssse3 x264_template(load_deinterleave_chroma_fdec_ssse3)
#define x264_load_deinterleave_chroma_fenc_avx x264_template(load_deinterleave_chroma_fenc_avx)
#define x264_load_deinterleave_chroma_fenc_mmx x264_template(load_deinterleave_chroma_fenc_mmx)
#define x264_load_deinterleave_chroma_fenc_sse2 x264_template(load_deinterleave_chroma_fenc_sse2)
#define x264_load_deinterleave_chroma_fenc_ssse3 x264_template(load_deinterleave_chroma_fenc_ssse3)
#define x264_mbtree_propagate_cost_avx x264_template(mbtree_propagate_cost_avx)
#define x264_mbtree_propagate_cost_avx2_fma3 x264_template(mbtree_propagate_cost_avx2_fma3)
#define x264_mbtree_propagate_cost_avx512 x264_template(mbtree_propagate_cost_avx512)
#define x264_mbtree_propagate_cost_fma4 x264_template(mbtree_propagate_cost_fma4)
#define x264_mbtree_propagate_cost_sse2 x264_template(mbtree_propagate_cost_sse2)
#define x264_mc_chroma_avx x264_template(mc_chroma_avx)
#define x264_mc_chroma_avx2 x264_template(mc_chroma_avx2)
#define x264_mc_chroma_mmx2 x264_template(mc_chroma_mmx2)
#define x264_mc_chroma_sse2 x264_template(mc_chroma_sse2)
#define x264_mc_chroma_ssse3 x264_template(mc_chroma_ssse3)
#define x264_mc_chroma_ssse3_cache64 x264_template(mc_chroma_ssse3_cache64)
#define x264_mc_copy_w16_aligned_avx x264_template(mc_copy_w16_aligned_avx)
#define x264_mc_copy_w16_aligned_sse x264_template(mc_copy_w16_aligned_sse)
#define x264_mc_copy_w16_avx x264_template(mc_copy_w16_avx)
#define x264_mc_copy_w16_mmx x264_template(mc_copy_w16_mmx)
#define x264_mc_copy_w16_sse x264_template(mc_copy_w16_sse)
#define x264_mc_copy_w4_mmx x264_template(mc_copy_w4_mmx)
#define x264_mc_copy_w8_mmx x264_template(mc_copy_w8_mmx)
#define x264_mc_copy_w8_sse x264_template(mc_copy_w8_sse)
#define x264_mc_offsetadd_plane_avx2 x264_template(mc_offsetadd_plane_avx2)
#define x264_mc_offsetadd_plane_avx512 x264_template(mc_offsetadd_plane_avx512)
#define x264_mc_offsetsub_plane_avx2 x264_template(mc_offsetsub_plane_avx2)
#define x264_mc_offsetsub_plane_avx512 x264_template(mc_offsetsub_plane_avx512)
#define x264_mc_weight_ns_plane_avx2 x264_template(mc_weight_ns_plane_avx2)
#define x264_mc_weight_ns_plane_avx512 x264_template(mc_weight_ns_plane_avx512)
#define x264_mc_weight_plane_avx2 x264_template(mc_weight_plane_avx2)
#define x264_mc_weight_plane_avx512 x264_template(mc_weight_plane_avx512)
#define x264_mc_offsetadd_w4_avx2 x264_template(mc_offsetadd_w4_avx2)
#define x264_mc_offsetadd_w8_avx2 x264_template(mc_offsetadd_w8_avx2)
#define x264_mc_offsetadd_w16_avx2 x264_template(mc_offsetadd_w16_avx2)
#define x264_mc_offsetadd_w20_avx2 x264_template(mc_offsetadd_w20_avx2)
#define x264_mc_offsetadd_w12_mmx2 x264_template(mc_offsetadd_w12_mmx2)
#define x264_mc_offsetadd_w12_sse2 x264_template(mc_offsetadd_w12_sse2)
#define x264_mc_offsetadd_w16_mmx2 x264_template(mc_offsetadd_w16_mmx2)
#define x264_mc_offsetadd_w16_sse2 x264_template(mc_offsetadd_w16_sse2)
#define x264_mc_offsetadd_w20_mmx2 x264_template(mc_offsetadd_w20_mmx2)
#define x264_mc_offsetadd_w20_sse2 x264_template(mc_offsetadd_w20_sse2)
#define x264_mc_offsetadd_w4_mmx2 x264_template(mc_offsetadd_w4_mmx2)
#define x264_mc_offsetadd_w8_mmx2 x264_template(mc_offsetadd_w8_mmx2)
#define x264_mc_offsetadd_w8_sse2 x264_template(mc_offsetadd_w8_sse2)
#define x264_mc_offsetsub_w4_avx2 x264_template(mc_offsetsub_w4_avx2)
#define x264_mc_offsetsub_w8_avx2 x264_template(mc_offsetsub_w8_avx2)
#define x264_mc_offsetsub_w16_avx2 x264_template(mc_offsetsub_w16_avx2)
#define x264_mc_offsetsub_w20_avx2 x264_template(mc_offsetsub_w20_avx2)
#define x264_mc_offsetsub_w12_mmx2 x264_template(mc_offsetsub_w12_mmx2)
#define x264_mc_offsetsub_w12_sse2 x264_template(mc_offsetsub_w12_sse2)
#define x264_mc_offsetsub_w16_mmx2 x264_template(mc_offsetsub_w16_mmx2)
#define x264_mc_offsetsub_w16_sse2 x264_template(mc_offsetsub_w16_sse2)
#define x264_mc_offsetsub_w20_mmx2 x264_template(mc_offsetsub_w20_mmx2)
#define x264_mc_offsetsub_w20_sse2 x264_template(mc_offsetsub_w20_sse2)
#define x264_mc_offsetsub_w4_mmx2 x264_template(mc_offsetsub_w4_mmx2)
#define x264_mc_offsetsub_w8_mmx2 x264_template(mc_offsetsub_w8_mmx2)
#define x264_mc_offsetsub_w8_sse2 x264_template(mc_offsetsub_w8_sse2)
#define x264_mc_weight_ns_w4_avx2 x264_template(mc_weight_ns_w4_avx2)
#define x264_mc_weight_ns_w8_avx2 x264_template(mc_weight_ns_w8_avx2)
#define x264_mc_weight_ns_w12_avx2 x264_template(mc_weight_ns_w12_avx2)
#define x264_mc_weight_ns_w16_avx2 x264_template(mc_weight_ns_w16_avx2)
#define x264_mc_weight_ns_w20_avx2 x264_template(mc_weight_ns_w20_avx2)
#define x264_mc_weight_ns_w12_avx512 x264_template(mc_weight_ns_w12_avx512)
#define x264_mc_weight_w12_avx2 x264_template(mc_weight_w12_avx2)
#define x264_mc_weight_w12_avx512 x264_template(mc_weight_w12_avx512)
#define x264_mc_weight_w16_avx512 x264_template(mc_weight_w16_avx512)
#define x264_mc_weight_w20_avx512 x264_template(mc_weight_w20_avx512)
#define x264_mc_weight_w12_mmx2 x264_template(mc_weight_w12_mmx2)
#define x264_mc_weight_w12_sse2 x264_template(mc_weight_w12_sse2)
#define x264_mc_weight_w12_ssse3 x264_template(mc_weight_w12_ssse3)
#define x264_mc_weight_w16_avx2 x264_template(mc_weight_w16_avx2)
#define x264_mc_weight_w16_mmx2 x264_template(mc_weight_w16_mmx2)
#define x264_mc_weight_w16_sse2 x264_template(mc_weight_w16_sse2)
#define x264_mc_weight_w16_ssse3 x264_template(mc_weight_w16_ssse3)
#define x264_mc_weight_w20_avx2 x264_template(mc_weight_w20_avx2)
#define x264_mc_weight_w20_mmx2 x264_template(mc_weight_w20_mmx2)
#define x264_mc_weight_w20_sse2 x264_template(mc_weight_w20_sse2)
#define x264_mc_weight_w20_ssse3 x264_template(mc_weight_w20_ssse3)
#define x264_mc_weight_w4_avx2 x264_template(mc_weight_w4_avx2)
#define x264_mc_weight_w4_mmx2 x264_template(mc_weight_w4_mmx2)
#define x264_mc_weight_w4_ssse3 x264_template(mc_weight_w4_ssse3)
#define x264_mc_weight_w8_avx2 x264_template(mc_weight_w8_avx2)
#define x264_mc_weight_w8_mmx2 x264_template(mc_weight_w8_mmx2)
#define x264_mc_weight_w8_sse2 x264_template(mc_weight_w8_sse2)
#define x264_mc_weight_w8_ssse3 x264_template(mc_weight_w8_ssse3)
#define x264_memcpy_aligned_mmx x264_template(memcpy_aligned_mmx)
#define x264_memcpy_aligned_sse x264_template(memcpy_aligned_sse)
#define x264_memcpy_aligned_avx x264_template(memcpy_aligned_avx)
#define x264_memcpy_aligned_avx512 x264_template(memcpy_aligned_avx512)
#define x264_memzero_aligned_avx x264_template(memzero_aligned_avx)
#define x264_memzero_aligned_avx512 x264_template(memzero_aligned_avx512)
#define x264_memzero_aligned_mmx x264_template(memzero_aligned_mmx)
#define x264_memzero_aligned_sse x264_template(memzero_aligned_sse)
#define x264_pixel_avg2_w10_avx2 x264_template(pixel_avg2_w10_avx2)
#define x264_pixel_avg2_w10_cache32_mmx2 x264_template(pixel_avg2_w10_cache32_mmx2)
#define x264_pixel_avg2_w10_cache64_mmx2 x264_template(pixel_avg2_w10_cache64_mmx2)
#define x264_pixel_avg2_w10_cache64_sse2 x264_template(pixel_avg2_w10_cache64_sse2)
#define x264_pixel_avg2_w10_cache64_ssse3 x264_template(pixel_avg2_w10_cache64_ssse3)
#define x264_pixel_avg2_w10_mmx2 x264_template(pixel_avg2_w10_mmx2)
#define x264_pixel_avg2_w10_sse2 x264_template(pixel_avg2_w10_sse2)
#define x264_pixel_avg2_w12_avx2 x264_template(pixel_avg2_w12_avx2)
#define x264_pixel_avg2_w12_cache32_mmx2 x264_template(pixel_avg2_w12_cache32_mmx2)
#define x264_pixel_avg2_w12_cache64_mmx2 x264_template(pixel_avg2_w12_cache64_mmx2)
#define x264_pixel_avg2_w12_cache64_sse2 x264_template(pixel_avg2_w12_cache64_sse2)
#define x264_pixel_avg2_w12_cache64_ssse3 x264_template(pixel_avg2_w12_cache64_ssse3)
#define x264_pixel_avg2_w12_mmx2 x264_template(pixel_avg2_w12_mmx2)
#define x264_pixel_avg2_w12_sse2 x264_template(pixel_avg2_w12_sse2)
#define x264_pixel_avg2_w16_avx2 x264_template(pixel_avg2_w16_avx2)
#define x264_pixel_avg2_w16_cache32_mmx2 x264_template(pixel_avg2_w16_cache32_mmx2)
#define x264_pixel_avg2_w16_cache64_mmx2 x264_template(pixel_avg2_w16_cache64_mmx2)
#define x264_pixel_avg2_w16_cache64_sse2 x264_template(pixel_avg2_w16_cache64_sse2)
#define x264_pixel_avg2_w16_cache64_ssse3 x264_template(pixel_avg2_w16_cache64_ssse3)
#define x264_pixel_avg2_w16_mmx2 x264_template(pixel_avg2_w16_mmx2)
#define x264_pixel_avg2_w16_sse2 x264_template(pixel_avg2_w16_sse2)
#define x264_pixel_avg2_w18_avx2 x264_template(pixel_avg2_w18_avx2)
#define x264_pixel_avg2_w18_cache32_mmx2 x264_template(pixel_avg2_w18_cache32_mmx2)
#define x264_pixel_avg2_w18_cache64_mmx2 x264_template(pixel_avg2_w18_cache64_mmx2)
#define x264_pixel_avg2_w18_cache64_sse2 x264_template(pixel_avg2_w18_cache64_sse2)
#define x264_pixel_avg2_w18_cache64_ssse3 x264_template(pixel_avg2_w18_cache64_ssse3)
#define x264_pixel_avg2_w18_mmx2 x264_template(pixel_avg2_w18_mmx2)
#define x264_pixel_avg2_w18_sse2 x264_template(pixel_avg2_w18_sse2)
#define x264_pixel_avg2_w20_avx2 x264_template(pixel_avg2_w20_avx2)
#define x264_pixel_avg2_w20_cache32_mmx2 x264_template(pixel_avg2_w20_cache32_mmx2)
#define x264_pixel_avg2_w20_cache64_mmx2 x264_template(pixel_avg2_w20_cache64_mmx2)
#define x264_pixel_avg2_w20_cache64_sse2 x264_template(pixel_avg2_w20_cache64_sse2)
#define x264_pixel_avg2_w20_cache64_ssse3 x264_template(pixel_avg2_w20_cache64_ssse3)
#define x264_pixel_avg2_w20_mmx2 x264_template(pixel_avg2_w20_mmx2)
#define x264_pixel_avg2_w20_sse2 x264_template(pixel_avg2_w20_sse2)
#define x264_pixel_avg2_w4_avx2 x264_template(pixel_avg2_w4_avx2)
#define x264_pixel_avg2_w4_cache32_mmx2 x264_template(pixel_avg2_w4_cache32_mmx2)
#define x264_pixel_avg2_w4_cache64_mmx2 x264_template(pixel_avg2_w4_cache64_mmx2)
#define x264_pixel_avg2_w4_cache64_sse2 x264_template(pixel_avg2_w4_cache64_sse2)
#define x264_pixel_avg2_w4_cache64_ssse3 x264_template(pixel_avg2_w4_cache64_ssse3)
#define x264_pixel_avg2_w4_mmx2 x264_template(pixel_avg2_w4_mmx2)
#define x264_pixel_avg2_w4_sse2 x264_template(pixel_avg2_w4_sse2)
#define x264_pixel_avg2_w8_avx2 x264_template(pixel_avg2_w8_avx2)
#define x264_pixel_avg2_w8_avx x264_template(pixel_avg2_w8_avx)
#define x264_pixel_avg2_w10_avx x264_template(pixel_avg2_w10_avx)
#define x264_pixel_avg2_w16_avx x264_template(pixel_avg2_w16_avx)
#define x264_pixel_avg2_w8_cache32_mmx2 x264_template(pixel_avg2_w8_cache32_mmx2)
#define x264_pixel_avg2_w8_cache64_mmx2 x264_template(pixel_avg2_w8_cache64_mmx2)
#define x264_pixel_avg2_w8_cache64_sse2 x264_template(pixel_avg2_w8_cache64_sse2)
#define x264_pixel_avg2_w8_cache64_ssse3 x264_template(pixel_avg2_w8_cache64_ssse3)
#define x264_pixel_avg2_w8_mmx2 x264_template(pixel_avg2_w8_mmx2)
#define x264_pixel_avg2_w8_sse2 x264_template(pixel_avg2_w8_sse2)
#define x264_pixel_avg_16x16_avx2 x264_template(pixel_avg_16x16_avx2)
#define x264_pixel_avg_16x16_avx512 x264_template(pixel_avg_16x16_avx512)
#define x264_pixel_avg_16x16_mmx2 x264_template(pixel_avg_16x16_mmx2)
#define x264_pixel_avg_16x16_sse2 x264_template(pixel_avg_16x16_sse2)
#define x264_pixel_avg_16x16_ssse3 x264_template(pixel_avg_16x16_ssse3)
#define x264_pixel_avg_16x8_avx2 x264_template(pixel_avg_16x8_avx2)
#define x264_pixel_avg_16x8_avx512 x264_template(pixel_avg_16x8_avx512)
#define x264_pixel_avg_16x8_mmx2 x264_template(pixel_avg_16x8_mmx2)
#define x264_pixel_avg_16x8_sse2 x264_template(pixel_avg_16x8_sse2)
#define x264_pixel_avg_16x8_ssse3 x264_template(pixel_avg_16x8_ssse3)
#define x264_pixel_avg_4x16_avx2 x264_template(pixel_avg_4x16_avx2)
#define x264_pixel_avg_4x16_avx512 x264_template(pixel_avg_4x16_avx512)
#define x264_pixel_avg_4x16_mmx2 x264_template(pixel_avg_4x16_mmx2)
#define x264_pixel_avg_4x16_sse2 x264_template(pixel_avg_4x16_sse2)
#define x264_pixel_avg_4x16_ssse3 x264_template(pixel_avg_4x16_ssse3)
#define x264_pixel_avg_4x2_avx2 x264_template(pixel_avg_4x2_avx2)
#define x264_pixel_avg_4x2_avx512 x264_template(pixel_avg_4x2_avx512)
#define x264_pixel_avg_4x2_mmx2 x264_template(pixel_avg_4x2_mmx2)
#define x264_pixel_avg_4x2_sse2 x264_template(pixel_avg_4x2_sse2)
#define x264_pixel_avg_4x2_ssse3 x264_template(pixel_avg_4x2_ssse3)
#define x264_pixel_avg_4x4_avx2 x264_template(pixel_avg_4x4_avx2)
#define x264_pixel_avg_4x4_avx512 x264_template(pixel_avg_4x4_avx512)
#define x264_pixel_avg_4x4_mmx2 x264_template(pixel_avg_4x4_mmx2)
#define x264_pixel_avg_4x4_sse2 x264_template(pixel_avg_4x4_sse2)
#define x264_pixel_avg_4x4_ssse3 x264_template(pixel_avg_4x4_ssse3)
#define x264_pixel_avg_4x8_avx2 x264_template(pixel_avg_4x8_avx2)
#define x264_pixel_avg_4x8_avx512 x264_template(pixel_avg_4x8_avx512)
#define x264_pixel_avg_4x8_mmx2 x264_template(pixel_avg_4x8_mmx2)
#define x264_pixel_avg_4x8_sse2 x264_template(pixel_avg_4x8_sse2)
#define x264_pixel_avg_4x8_ssse3 x264_template(pixel_avg_4x8_ssse3)
#define x264_pixel_avg_8x16_avx2 x264_template(pixel_avg_8x16_avx2)
#define x264_pixel_avg_8x16_avx512 x264_template(pixel_avg_8x16_avx512)
#define x264_pixel_avg_8x16_mmx2 x264_template(pixel_avg_8x16_mmx2)
#define x264_pixel_avg_8x16_sse2 x264_template(pixel_avg_8x16_sse2)
#define x264_pixel_avg_8x16_ssse3 x264_template(pixel_avg_8x16_ssse3)
#define x264_pixel_avg_8x4_avx2 x264_template(pixel_avg_8x4_avx2)
#define x264_pixel_avg_8x4_avx512 x264_template(pixel_avg_8x4_avx512)
#define x264_pixel_avg_8x4_mmx2 x264_template(pixel_avg_8x4_mmx2)
#define x264_pixel_avg_8x4_sse2 x264_template(pixel_avg_8x4_sse2)
#define x264_pixel_avg_8x4_ssse3 x264_template(pixel_avg_8x4_ssse3)
#define x264_pixel_avg_8x8_avx2 x264_template(pixel_avg_8x8_avx2)
#define x264_pixel_avg_8x8_avx512 x264_template(pixel_avg_8x8_avx512)
#define x264_pixel_avg_8x8_mmx2 x264_template(pixel_avg_8x8_mmx2)
#define x264_pixel_avg_8x8_sse2 x264_template(pixel_avg_8x8_sse2)
#define x264_pixel_avg_8x8_ssse3 x264_template(pixel_avg_8x8_ssse3)
#define x264_plane_copy_c x264_template(plane_copy_c)
#define x264_plane_copy_core_mmx2 x264_template(plane_copy_core_mmx2)
#define x264_plane_copy_deinterleave_avx x264_template(plane_copy_deinterleave_avx)
#define x264_plane_copy_deinterleave_mmx x264_template(plane_copy_deinterleave_mmx)
#define x264_plane_copy_deinterleave_rgb_sse2 x264_template(plane_copy_deinterleave_rgb_sse2)
#define x264_plane_copy_deinterleave_rgb_ssse3 x264_template(plane_copy_deinterleave_rgb_ssse3)
#define x264_plane_copy_deinterleave_rgb_avx512icl x264_template(plane_copy_deinterleave_rgb_avx512icl)
#define x264_plane_copy_deinterleave_sse2 x264_template(plane_copy_deinterleave_sse2)
#define x264_plane_copy_deinterleave_ssse3 x264_template(plane_copy_deinterleave_ssse3)
#define x264_plane_copy_deinterleave_v210_avx x264_template(plane_copy_deinterleave_v210_avx)
#define x264_plane_copy_deinterleave_v210_avx2 x264_template(plane_copy_deinterleave_v210_avx2)
#define x264_plane_copy_deinterleave_v210_avx512 x264_template(plane_copy_deinterleave_v210_avx512)
#define x264_plane_copy_deinterleave_v210_ssse3 x264_template(plane_copy_deinterleave_v210_ssse3)
#define x264_plane_copy_interleave_c x264_template(plane_copy_interleave_c)
#define x264_plane_copy_interleave_core_avx x264_template(plane_copy_interleave_core_avx)
#define x264_plane_copy_interleave_core_mmx2 x264_template(plane_copy_interleave_core_mmx2)
#define x264_plane_copy_interleave_core_sse2 x264_template(plane_copy_interleave_core_sse2)
#define x264_prefetch_fenc_420_mmx2 x264_template(prefetch_fenc_420_mmx2)
#define x264_prefetch_fenc_422_mmx2 x264_template(prefetch_fenc_422_mmx2)
#define x264_prefetch_ref_mmx2 x264_template(prefetch_ref_mmx2)
#define x264_store_interleave_chroma_avx x264_template(store_interleave_chroma_avx)
#define x264_store_interleave_chroma_mmx2 x264_template(store_interleave_chroma_mmx2)
#define x264_store_interleave_chroma_sse2 x264_template(store_interleave_chroma_sse2)

#define DECL_SUF( func, args )\
    void func##_mmx2 args;\
    void func##_sse2 args;\
    void func##_ssse3 args;\
    void func##_avx2 args;\
    void func##_avx512 args;

DECL_SUF( x264_pixel_avg_16x16, ( pixel *, intptr_t, pixel *, intptr_t, pixel *, intptr_t, int ))
DECL_SUF( x264_pixel_avg_16x8,  ( pixel *, intptr_t, pixel *, intptr_t, pixel *, intptr_t, int ))
DECL_SUF( x264_pixel_avg_8x16,  ( pixel *, intptr_t, pixel *, intptr_t, pixel *, intptr_t, int ))
DECL_SUF( x264_pixel_avg_8x8,   ( pixel *, intptr_t, pixel *, intptr_t, pixel *, intptr_t, int ))
DECL_SUF( x264_pixel_avg_8x4,   ( pixel *, intptr_t, pixel *, intptr_t, pixel *, intptr_t, int ))
DECL_SUF( x264_pixel_avg_4x16,  ( pixel *, intptr_t, pixel *, intptr_t, pixel *, intptr_t, int ))
DECL_SUF( x264_pixel_avg_4x8,   ( pixel *, intptr_t, pixel *, intptr_t, pixel *, intptr_t, int ))
DECL_SUF( x264_pixel_avg_4x4,   ( pixel *, intptr_t, pixel *, intptr_t, pixel *, intptr_t, int ))
DECL_SUF( x264_pixel_avg_4x2,   ( pixel *, intptr_t, pixel *, intptr_t, pixel *, intptr_t, int ))

#define MC_WEIGHT(w,type) \
    void x264_mc_weight_w##w##_##type( pixel *, intptr_t, pixel *, intptr_t, const x264_weight_t *, int );

#define MC_WEIGHT_OFFSET(w,type) \
    void x264_mc_offsetadd_w##w##_##type( pixel *, intptr_t, pixel *, intptr_t, const x264_weight_t *, int ); \
    void x264_mc_offsetsub_w##w##_##type( pixel *, intptr_t, pixel *, intptr_t, const x264_weight_t *, int ); \
    MC_WEIGHT(w,type)

MC_WEIGHT_OFFSET( 4, mmx2 )
MC_WEIGHT_OFFSET( 8, mmx2 )
MC_WEIGHT_OFFSET( 12, mmx2 )
MC_WEIGHT_OFFSET( 16, mmx2 )
MC_WEIGHT_OFFSET( 20, mmx2 )
MC_WEIGHT_OFFSET( 12, sse2 )
MC_WEIGHT_OFFSET( 16, sse2 )
MC_WEIGHT_OFFSET( 20, sse2 )
#if HIGH_BIT_DEPTH
MC_WEIGHT_OFFSET( 8, sse2 )
#endif
MC_WEIGHT( 8, sse2  )
MC_WEIGHT( 4, ssse3 )
MC_WEIGHT( 8, ssse3 )
MC_WEIGHT( 12, ssse3 )
MC_WEIGHT( 16, ssse3 )
MC_WEIGHT( 20, ssse3 )
MC_WEIGHT( 8, avx2 )
MC_WEIGHT( 16, avx2 )
MC_WEIGHT( 20, avx2 )
#if HIGH_BIT_DEPTH
MC_WEIGHT_OFFSET( 4, avx2 )
MC_WEIGHT_OFFSET( 8, avx2 )
MC_WEIGHT_OFFSET( 16, avx2 )
MC_WEIGHT_OFFSET( 20, avx2 )
MC_WEIGHT( 12, avx2 )
#define MC_WEIGHT_NS(w) \
    void x264_mc_weight_ns_w##w##_avx2( pixel *, intptr_t, pixel *, intptr_t, const x264_weight_t *, int );
MC_WEIGHT_NS( 4 )
MC_WEIGHT_NS( 8 )
MC_WEIGHT_NS( 12 )
MC_WEIGHT_NS( 16 )
MC_WEIGHT_NS( 20 )
#undef MC_WEIGHT_NS
MC_WEIGHT( 12, avx512 )
MC_WEIGHT( 16, avx512 )
MC_WEIGHT( 20, avx512 )
void x264_mc_weight_ns_w12_avx512( pixel *, intptr_t, pixel *, intptr_t, const x264_weight_t *, int );
#define MC_WEIGHT_PLANE(cpu) \
    void x264_mc_weight_plane_##cpu( pixel *, intptr_t, pixel *, intptr_t, const x264_weight_t *, int, int ); \
    void x264_mc_weight_ns_plane_##cpu( pixel *, intptr_t, pixel *, intptr_t, const x264_weight_t *, int, int ); \
    void x264_mc_offsetadd_plane_##cpu( pixel *, intptr_t, pixel *, intptr_t, const x264_weight_t *, int, int ); \
    void x264_mc_offsetsub_plane_##cpu( pixel *, intptr_t, pixel *, intptr_t, const x264_weight_t *, int, int );
MC_WEIGHT_PLANE( avx2 )
MC_WEIGHT_PLANE( avx512 )
#undef MC_WEIGHT_PLANE
#endif
#undef MC_OFFSET
#undef MC_WEIGHT

#if ARCH_X86_64
#if HIGH_BIT_DEPTH
#define x264_mc_weight_avg_w4_avx2 x264_template(mc_weight_avg_w4_avx2)
#define x264_mc_weight_avg_w8_avx2 x264_template(mc_weight_avg_w8_avx2)
#define x264_mc_weight_avg_w12_avx2 x264_template(mc_weight_avg_w12_avx2)
#define x264_mc_weight_avg_w16_avx2 x264_template(mc_weight_avg_w16_avx2)
#define x264_mc_weight_avg_w20_avx2 x264_template(mc_weight_avg_w20_avx2)
#define x264_mc_weight_ns_avg_w4_avx2 x264_template(mc_weight_ns_avg_w4_avx2)
#define x264_mc_weight_ns_avg_w8_avx2 x264_template(mc_weight_ns_avg_w8_avx2)
#define x264_mc_weight_ns_avg_w12_avx2 x264_template(mc_weight_ns_avg_w12_avx2)
#define x264_mc_weight_ns_avg_w16_avx2 x264_template(mc_weight_ns_avg_w16_avx2)
#define x264_mc_weight_ns_avg_w20_avx2 x264_template(mc_weight_ns_avg_w20_avx2)
#define x264_mc_offsetadd_avg_w4_avx2 x264_template(mc_offsetadd_avg_w4_avx2)
#define x264_mc_offsetadd_avg_w8_avx2 x264_template(mc_offsetadd_avg_w8_avx2)
#define x264_mc_offsetadd_avg_w12_avx2 x264_template(mc_offsetadd_avg_w12_avx2)
#define x264_mc_offsetadd_avg_w16_avx2 x264_template(mc_offsetadd_avg_w16_avx2)
#define x264_mc_offsetadd_avg_w20_avx2 x264_template(mc_offsetadd_avg_w20_avx2)
#define x264_mc_offsetsub_avg_w4_avx2 x264_template(mc_offsetsub_avg_w4_avx2)
#define x264_mc_offsetsub_avg_w8_avx2 x264_template(mc_offsetsub_avg_w8_avx2)
#define x264_mc_offsetsub_avg_w12_avx2 x264_template(mc_offsetsub_avg_w12_avx2)
#define x264_mc_offsetsub_avg_w16_avx2 x264_template(mc_offsetsub_avg_w16_avx2)
#define x264_mc_offsetsub_avg_w20_avx2 x264_template(mc_offsetsub_avg_w20_avx2)
#else
#define x264_mc_weight_avg_w4_avx2 x264_template(mc_weight_avg_w4_avx2)
#define x264_mc_weight_avg_w8_avx2 x264_template(mc_weight_avg_w8_avx2)
#define x264_mc_weight_avg_w16_avx2 x264_template(mc_weight_avg_w16_avx2)
#define x264_mc_weight_avg_w20_avx2 x264_template(mc_weight_avg_w20_avx2)
#define x264_mc_offsetadd_avg_w4_avx2 x264_template(mc_offsetadd_avg_w4_avx2)
#define x264_mc_offsetadd_avg_w8_avx2 x264_template(mc_offsetadd_avg_w8_avx2)
#define x264_mc_offsetadd_avg_w16_avx2 x264_template(mc_offsetadd_avg_w16_avx2)
#define x264_mc_offsetadd_avg_w20_avx2 x264_template(mc_offsetadd_avg_w20_avx2)
#define x264_mc_offsetsub_avg_w4_avx2 x264_template(mc_offsetsub_avg_w4_avx2)
#define x264_mc_offsetsub_avg_w8_avx2 x264_template(mc_offsetsub_avg_w8_avx2)
#define x264_mc_offsetsub_avg_w16_avx2 x264_template(mc_offsetsub_avg_w16_avx2)
#define x264_mc_offsetsub_avg_w20_avx2 x264_template(mc_offsetsub_avg_w20_avx2)
#endif
/* mc_X_avg_wN: mc_X_wN of pixel_avg2_wN( src1, src2 ), without storing the average */
#define MC_WEIGHT_AVG(name, w) \
    void x264_mc_##name##_avg_w##w##_avx2( pixel *, intptr_t, pixel *, intptr_t, const x264_weight_t *, int, pixel * );
#define MC_WEIGHT_AVG_ALL(name) MC_WEIGHT_AVG(name, 4) MC_WEIGHT_AVG(name, 8) MC_WEIGHT_AVG(name, 16) MC_WEIGHT_AVG(name, 20)
MC_WEIGHT_AVG_ALL( weight )
MC_WEIGHT_AVG_ALL( offsetadd )
MC_WEIGHT_AVG_ALL( offsetsub )
#if HIGH_BIT_DEPTH
MC_WEIGHT_AVG_ALL( weight_ns )
MC_WEIGHT_AVG( weight, 12 )
MC_WEIGHT_AVG( weight_ns, 12 )
MC_WEIGHT_AVG( offsetadd, 12 )
MC_WEIGHT_AVG( offsetsub, 12 )
#else
#define x264_mc_offsetadd_avg_w20_avx512icl x264_template(mc_offsetadd_avg_w20_avx512icl)
#define x264_mc_offsetsub_avg_w20_avx512icl x264_template(mc_offsetsub_avg_w20_avx512icl)
void x264_mc_offsetadd_avg_w20_avx512icl( pixel *, intptr_t, pixel *, intptr_t, const x264_weight_t *, int, pixel * );
void x264_mc_offsetsub_avg_w20_avx512icl( pixel *, intptr_t, pixel *, intptr_t, const x264_weight_t *, int, pixel * );
#endif
#undef MC_WEIGHT_AVG_ALL
#undef MC_WEIGHT_AVG
#endif // ARCH_X86_64

void x264_mc_copy_w4_mmx ( pixel *, intptr_t, pixel *, intptr_t, int );
void x264_mc_copy_w8_mmx ( pixel *, intptr_t, pixel *, intptr_t, int );
void x264_mc_copy_w8_sse ( pixel *, intptr_t, pixel *, intptr_t, int );
void x264_mc_copy_w16_mmx( pixel *, intptr_t, pixel *, intptr_t, int );
void x264_mc_copy_w16_sse( pixel *, intptr_t, pixel *, intptr_t, int );
void x264_mc_copy_w16_aligned_sse( pixel *, intptr_t, pixel *, intptr_t, int );
void x264_mc_copy_w16_avx( uint16_t *, intptr_t, uint16_t *, intptr_t, int );
void x264_mc_copy_w16_aligned_avx( uint16_t *, intptr_t, uint16_t *, intptr_t, int );
void x264_prefetch_fenc_420_mmx2( pixel *, intptr_t, pixel *, intptr_t, int );
void x264_prefetch_fenc_422_mmx2( pixel *, intptr_t, pixel *, intptr_t, int );
void x264_prefetch_ref_mmx2( pixel *, intptr_t, int );
void x264_plane_copy_core_mmx2( pixel *, intptr_t, pixel *, intptr_t, int w, int h );
#define x264_plane_copy_core_avx2 x264_template(plane_copy_core_avx2)
void x264_plane_copy_core_avx2( pixel *, intptr_t, pixel *, intptr_t, int w, int h );
#define x264_plane_copy_avx512 x264_template(plane_copy_avx512)
void x264_plane_copy_avx512( pixel *, intptr_t, pixel *, intptr_t, int w, int h );
void x264_plane_copy_c( pixel *, intptr_t, pixel *, intptr_t, int w, int h );
void x264_plane_copy_interleave_core_mmx2( pixel *dst,  intptr_t i_dst,
                                           pixel *srcu, intptr_t i_srcu,
                                           pixel *srcv, intptr_t i_srcv, int w, int h );
void x264_plane_copy_interleave_core_sse2( pixel *dst,  intptr_t i_dst,
                                           pixel *srcu, intptr_t i_srcu,
                                           pixel *srcv, intptr_t i_srcv, int w, int h );
void x264_plane_copy_interleave_core_avx( pixel *dst,  intptr_t i_dst,
                                          pixel *srcu, intptr_t i_srcu,
                                          pixel *srcv, intptr_t i_srcv, int w, int h );
void x264_plane_copy_interleave_c( pixel *dst,  intptr_t i_dst,
                                   pixel *srcu, intptr_t i_srcu,
                                   pixel *srcv, intptr_t i_srcv, int w, int h );
void x264_plane_copy_deinterleave_mmx( pixel *dstu, intptr_t i_dstu,
                                       pixel *dstv, intptr_t i_dstv,
                                       pixel *src,  intptr_t i_src, int w, int h );
void x264_plane_copy_deinterleave_sse2( pixel *dstu, intptr_t i_dstu,
                                        pixel *dstv, intptr_t i_dstv,
                                        pixel *src,  intptr_t i_src, int w, int h );
void x264_plane_copy_deinterleave_ssse3( uint8_t *dstu, intptr_t i_dstu,
                                         uint8_t *dstv, intptr_t i_dstv,
                                         uint8_t *src,  intptr_t i_src, int w, int h );
void x264_plane_copy_deinterleave_avx( uint16_t *dstu, intptr_t i_dstu,
                                       uint16_t *dstv, intptr_t i_dstv,
                                       uint16_t *src,  intptr_t i_src, int w, int h );
void x264_plane_copy_deinterleave_rgb_sse2 ( pixel *dsta, intptr_t i_dsta,
                                             pixel *dstb, intptr_t i_dstb,
                                             pixel *dstc, intptr_t i_dstc,
                                             pixel *src,  intptr_t i_src, int pw, int w, int h );
void x264_plane_copy_deinterleave_rgb_ssse3( pixel *dsta, intptr_t i_dsta,
                                             pixel *dstb, intptr_t i_dstb,
                                             pixel *dstc, intptr_t i_dstc,
                                             pixel *src,  intptr_t i_src, int pw, int w, int h );
void x264_plane_copy_deinterleave_rgb_avx512icl( pixel *dsta, intptr_t i_dsta,
                                                 pixel *dstb, intptr_t i_dstb,
                                                 pixel *dstc, intptr_t i_dstc,
                                                 pixel *src,  intptr_t i_src, int pw, int w, int h );
void x264_plane_copy_deinterleave_v210_ssse3( uint16_t *dstu, intptr_t i_dstu,
                                              uint16_t *dstv, intptr_t i_dstv,
                                              uint32_t *src,  intptr_t i_src, int w, int h );
void x264_plane_copy_deinterleave_v210_avx  ( uint16_t *dstu, intptr_t i_dstu,
                                              uint16_t *dstv, intptr_t i_dstv,
                                              uint32_t *src,  intptr_t i_src, int w, int h );
void x264_plane_copy_deinterleave_v210_avx2 ( uint16_t *dstu, intptr_t i_dstu,
                                              uint16_t *dstv, intptr_t i_dstv,
                                              uint32_t *src,  intptr_t i_src, int w, int h );
void x264_plane_copy_deinterleave_v210_avx512( uint16_t *dstu, intptr_t i_dstu,
                                               uint16_t *dstv, intptr_t i_dstv,
                                               uint32_t *src,  intptr_t i_src, int w, int h );
#define x264_plane_copy_interleave_core_avx512icl x264_template(plane_copy_interleave_core_avx512icl)
void x264_plane_copy_interleave_core_avx512icl( pixel *dst,  intptr_t i_dst,
                                                pixel *srcu, intptr_t i_srcu,
                                                pixel *srcv, intptr_t i_srcv, int w, int h );
#define x264_plane_copy_deinterleave_avx512icl x264_template(plane_copy_deinterleave_avx512icl)
void x264_plane_copy_deinterleave_avx512icl( pixel *dstu, intptr_t i_dstu,
                                             pixel *dstv, intptr_t i_dstv,
                                             pixel *src,  intptr_t i_src, int w, int h );
#define x264_store_interleave_chroma_avx512icl x264_template(store_interleave_chroma_avx512icl)
void x264_store_interleave_chroma_avx512icl( pixel *dst, intptr_t i_dst, pixel *srcu, pixel *srcv, int height );
void x264_store_interleave_chroma_mmx2( pixel *dst, intptr_t i_dst, pixel *srcu, pixel *srcv, int height );
void x264_store_interleave_chroma_sse2( pixel *dst, intptr_t i_dst, pixel *srcu, pixel *srcv, int height );
void x264_store_interleave_chroma_avx ( pixel *dst, intptr_t i_dst, pixel *srcu, pixel *srcv, int height );
void x264_load_deinterleave_chroma_fenc_mmx ( pixel *dst, pixel *src, intptr_t i_src, int height );
void x264_load_deinterleave_chroma_fenc_sse2( pixel *dst, pixel *src, intptr_t i_src, int height );
void x264_load_deinterleave_chroma_fenc_ssse3( uint8_t *dst, uint8_t *src, intptr_t i_src, int height );
void x264_load_deinterleave_chroma_fenc_avx( uint16_t *dst, uint16_t *src, intptr_t i_src, int height );
#define x264_load_deinterleave_chroma_fenc_avx2 x264_template(load_deinterleave_chroma_fenc_avx2)
void x264_load_deinterleave_chroma_fenc_avx2( uint16_t *dst, uint16_t *src, intptr_t i_src, int height );
#define x264_load_deinterleave_chroma_fenc_avx512 x264_template(load_deinterleave_chroma_fenc_avx512)
void x264_load_deinterleave_chroma_fenc_avx512( uint8_t *dst, uint8_t *src, intptr_t i_src, int height );
void x264_load_deinterleave_chroma_fdec_mmx ( pixel *dst, pixel *src, intptr_t i_src, int height );
void x264_load_deinterleave_chroma_fdec_sse2( pixel *dst, pixel *src, intptr_t i_src, int height );
void x264_load_deinterleave_chroma_fdec_ssse3( uint8_t *dst, uint8_t *src, intptr_t i_src, int height );
void x264_load_deinterleave_chroma_fdec_avx( uint16_t *dst, uint16_t *src, intptr_t i_src, int height );
#define x264_load_deinterleave_chroma_fdec_avx2 x264_template(load_deinterleave_chroma_fdec_avx2)
void x264_load_deinterleave_chroma_fdec_avx2( uint16_t *dst, uint16_t *src, intptr_t i_src, int height );
#define x264_load_deinterleave_chroma_fdec_avx512 x264_template(load_deinterleave_chroma_fdec_avx512)
void x264_load_deinterleave_chroma_fdec_avx512( uint8_t *dst, uint8_t *src, intptr_t i_src, int height );
void *x264_memcpy_aligned_mmx( void *dst, const void *src, size_t n );
void *x264_memcpy_aligned_sse( void *dst, const void *src, size_t n );
void *x264_memcpy_aligned_avx( void *dst, const void *src, size_t n );
void *x264_memcpy_aligned_avx512( void *dst, const void *src, size_t n );
void x264_memzero_aligned_mmx( void *dst, size_t n );
void x264_memzero_aligned_sse( void *dst, size_t n );
void x264_memzero_aligned_avx( void *dst, size_t n );
void x264_memzero_aligned_avx512( void *dst, size_t n );
void x264_integral_init4h_sse4( uint16_t *sum, uint8_t *pix, intptr_t stride );
void x264_integral_init4h_avx2( uint16_t *sum, uint8_t *pix, intptr_t stride );
void x264_integral_init8h_sse4( uint16_t *sum, uint8_t *pix, intptr_t stride );
void x264_integral_init8h_avx ( uint16_t *sum, uint8_t *pix, intptr_t stride );
void x264_integral_init8h_avx2( uint16_t *sum, uint8_t *pix, intptr_t stride );
void x264_integral_init4v_mmx  ( uint16_t *sum8, uint16_t *sum4, intptr_t stride );
void x264_integral_init4v_sse2 ( uint16_t *sum8, uint16_t *sum4, intptr_t stride );
void x264_integral_init4v_ssse3( uint16_t *sum8, uint16_t *sum4, intptr_t stride );
void x264_integral_init4v_avx2( uint16_t *sum8, uint16_t *sum4, intptr_t stride );
void x264_integral_init8v_mmx ( uint16_t *sum8, intptr_t stride );
void x264_integral_init8v_sse2( uint16_t *sum8, intptr_t stride );
void x264_integral_init8v_avx2( uint16_t *sum8, intptr_t stride );
void x264_integral_init4h_avx512icl( uint16_t *sum, uint8_t *pix, intptr_t stride );
void x264_integral_init8h_avx512icl( uint16_t *sum, uint8_t *pix, intptr_t stride );
void x264_integral_init4v_avx512icl( uint16_t *sum8, uint16_t *sum4, intptr_t stride );
void x264_integral_init8v_avx512icl( uint16_t *sum8, intptr_t stride );
void x264_mbtree_propagate_cost_sse2( int16_t *dst, uint16_t *propagate_in, uint16_t *intra_costs,
                                      uint16_t *inter_costs, uint16_t *inv_qscales, float *fps_factor, int len );
void x264_mbtree_propagate_cost_avx ( int16_t *dst, uint16_t *propagate_in, uint16_t *intra_costs,
                                      uint16_t *inter_costs, uint16_t *inv_qscales, float *fps_factor, int len );
void x264_mbtree_propagate_cost_fma4( int16_t *dst, uint16_t *propagate_in, uint16_t *intra_costs,
                                      uint16_t *inter_costs, uint16_t *inv_qscales, float *fps_factor, int len );
void x264_mbtree_propagate_cost_avx2_fma3( int16_t *dst, uint16_t *propagate_in, uint16_t *intra_costs,
                                           uint16_t *inter_costs, uint16_t *inv_qscales, float *fps_factor, int len );
void x264_mbtree_propagate_cost_avx512( int16_t *dst, uint16_t *propagate_in, uint16_t *intra_costs,
                                        uint16_t *inter_costs, uint16_t *inv_qscales, float *fps_factor, int len );

#define MC_CHROMA(cpu)\
void x264_mc_chroma_##cpu( pixel *dstu, pixel *dstv, intptr_t i_dst, pixel *src, intptr_t i_src,\
                           int dx, int dy, int i_width, int i_height );
MC_CHROMA(mmx2)
MC_CHROMA(sse2)
MC_CHROMA(ssse3)
MC_CHROMA(ssse3_cache64)
MC_CHROMA(avx)
MC_CHROMA(avx2)

#define LOWRES(cpu)\
void x264_frame_init_lowres_core_##cpu( pixel *src0, pixel *dst0, pixel *dsth, pixel *dstv, pixel *dstc,\
                                        intptr_t src_stride, intptr_t dst_stride, int width, int height );
LOWRES(mmx2)
LOWRES(cache32_mmx2)
LOWRES(sse2)
LOWRES(ssse3)
LOWRES(avx)
LOWRES(xop)
LOWRES(avx2)
LOWRES(avx512icl)
void x264_frame_init_lowres_core8_ssse3( pixel *src0, uint8_t *dst0, uint8_t *dsth, uint8_t *dstv, uint8_t *dstc,
                                         intptr_t src_stride, intptr_t dst_stride, int width, int height );
void x264_frame_init_lowres_core8_avx2( pixel *src0, uint8_t *dst0, uint8_t *dsth, uint8_t *dstv, uint8_t *dstc,
                                        intptr_t src_stride, intptr_t dst_stride, int width, int height );
#define x264_frame_init_lowres_core8_avx512icl x264_template(frame_init_lowres_core8_avx512icl)
void x264_frame_init_lowres_core8_avx512icl( pixel *src0, uint8_t *dst0, uint8_t *dsth, uint8_t *dstv, uint8_t *dstc,
                                             intptr_t src_stride, intptr_t dst_stride, int width, int height );

#define PIXEL_AVG_W(width,cpu)\
void x264_pixel_avg2_w##width##_##cpu( pixel *, intptr_t, pixel *, intptr_t, pixel *, intptr_t );
/* This declares some functions that don't exist, but that isn't a problem. */
#define PIXEL_AVG_WALL(cpu)\
PIXEL_AVG_W(4,cpu); PIXEL_AVG_W(8,cpu); PIXEL_AVG_W(10,cpu); PIXEL_AVG_W(12,cpu); PIXEL_AVG_W(16,cpu); PIXEL_AVG_W(18,cpu); PIXEL_AVG_W(20,cpu);

PIXEL_AVG_WALL(mmx2)
PIXEL_AVG_WALL(cache32_mmx2)
PIXEL_AVG_WALL(cache64_mmx2)
PIXEL_AVG_WALL(cache64_sse2)
PIXEL_AVG_WALL(sse2)
PIXEL_AVG_WALL(cache64_ssse3)
PIXEL_AVG_WALL(avx)
PIXEL_AVG_WALL(avx2)

#define PIXEL_AVG_WTAB(instr, name1, name2, name3, name4, name5)\
static void (* const x264_pixel_avg_wtab_##instr[6])( pixel *, intptr_t, pixel *, intptr_t, pixel *, intptr_t ) =\
{\
    NULL,\
    x264_pixel_avg2_w4_##name1,\
    x264_pixel_avg2_w8_##name2,\
    x264_pixel_avg2_w12_##name3,\
    x264_pixel_avg2_w16_##name4,\
    x264_pixel_avg2_w20_##name5,\
};

#if HIGH_BIT_DEPTH
/* we can replace w12/w20 with w10/w18 as only 9/17 pixels in fact are important */
#undef x264_pixel_avg2_w12_mmx2
#undef x264_pixel_avg2_w20_mmx2
#undef x264_pixel_avg2_w12_sse2
#undef x264_pixel_avg2_w20_sse2
#undef x264_pixel_avg2_w12_avx2
#undef x264_pixel_avg2_w20_avx2
#define x264_pixel_avg2_w12_mmx2       x264_pixel_avg2_w10_mmx2
#define x264_pixel_avg2_w20_mmx2       x264_pixel_avg2_w18_mmx2
#define x264_pixel_avg2_w12_sse2         x264_pixel_avg2_w10_sse2
#define x264_pixel_avg2_w20_sse2         x264_pixel_avg2_w18_sse2
#define x264_pixel_avg2_w12_avx2         x264_pixel_avg2_w16_avx2
#define x264_pixel_avg2_w20_avx2         x264_pixel_avg2_w18_avx2
#else
/* w16 sse2 is faster than w12 mmx as long as the cacheline issue is resolved */
#undef x264_pixel_avg2_w12_cache64_ssse3
#undef x264_pixel_avg2_w12_cache64_sse2
#undef x264_pixel_avg2_w12_sse2
#define x264_pixel_avg2_w12_cache64_ssse3 x264_pixel_avg2_w16_cache64_ssse3
#define x264_pixel_avg2_w12_cache64_sse2 x264_pixel_avg2_w16_cache64_sse2
#define x264_pixel_avg2_w12_sse3         x264_pixel_avg2_w16_sse3
#define x264_pixel_avg2_w12_sse2         x264_pixel_avg2_w16_sse2
#endif // HIGH_BIT_DEPTH

PIXEL_AVG_WTAB(mmx2, mmx2, mmx2, mmx2, mmx2, mmx2)
#if HIGH_BIT_DEPTH
PIXEL_AVG_WTAB(sse2, mmx2, sse2, sse2, sse2, sse2)
PIXEL_AVG_WTAB(avx2, mmx2, avx, avx2, avx2, avx2)
#else // !HIGH_BIT_DEPTH
#if ARCH_X86
PIXEL_AVG_WTAB(cache32_mmx2, mmx2, cache32_mmx2, cache32_mmx2, cache32_mmx2, cache32_mmx2)
PIXEL_AVG_WTAB(cache64_mmx2, mmx2, cache64_mmx2, cache64_mmx2, cache64_mmx2, cache64_mmx2)
#endif
PIXEL_AVG_WTAB(sse2, mmx2, mmx2, sse2, sse2, sse2)
PIXEL_AVG_WTAB(cache64_sse2, mmx2, cache64_mmx2, cache64_sse2, cache64_sse2, cache64_sse2)
PIXEL_AVG_WTAB(cache64_ssse3, mmx2, cache64_mmx2, cache64_ssse3, cache64_ssse3, cache64_sse2)
PIXEL_AVG_WTAB(cache64_ssse3_atom, mmx2, mmx2, cache64_ssse3, cache64_ssse3, sse2)
PIXEL_AVG_WTAB(avx2, mmx2, mmx2, sse2, sse2, avx2)
#endif // HIGH_BIT_DEPTH

#define MC_COPY_WTAB(instr, name1, name2, name3)\
static void (* const x264_mc_copy_wtab_##instr[5])( pixel *, intptr_t, pixel *, intptr_t, int ) =\
{\
    NULL,\
    x264_mc_copy_w4_##name1,\
    x264_mc_copy_w8_##name2,\
    NULL,\
    x264_mc_copy_w16_##name3,\
};

MC_COPY_WTAB(mmx,mmx,mmx,mmx)
#if HIGH_BIT_DEPTH
MC_COPY_WTAB(sse,mmx,sse,sse)
MC_COPY_WTAB(avx,mmx,sse,avx)
#else
MC_COPY_WTAB(sse,mmx,mmx,sse)
#endif

#define MC_WEIGHT_WTAB(function, instr, name1, name2, w12version)\
    static void (* x264_mc_##function##_wtab_##instr[6])( pixel *, intptr_t, pixel *, intptr_t, const x264_weight_t *, int ) =\
{\
    x264_mc_##function##_w4_##name1,\
    x264_mc_##function##_w4_##name1,\
    x264_mc_##function##_w8_##name2,\
    x264_mc_##function##_w##w12version##_##instr,\
    x264_mc_##function##_w16_##instr,\
    x264_mc_##function##_w20_##instr,\
};

#if ARCH_X86_64
#define MC_WEIGHT_AVG_WTAB(function, w12version)\
static weight_avg_fn_t x264_mc_##function##_avg_wtab_avx2[6] =\
{\
    x264_mc_##function##_avg_w4_avx2,\
    x264_mc_##function##_avg_w4_avx2,\
    x264_mc_##function##_avg_w8_avx2,\
    x264_mc_##function##_avg_w##w12version##_avx2,\
    x264_mc_##function##_avg_w16_avx2,\
    x264_mc_##function##_avg_w20_avx2,\
};
#if HIGH_BIT_DEPTH
MC_WEIGHT_AVG_WTAB(weight,12)
MC_WEIGHT_AVG_WTAB(weight_ns,12)
MC_WEIGHT_AVG_WTAB(offsetadd,12)
MC_WEIGHT_AVG_WTAB(offsetsub,12)
#else
MC_WEIGHT_AVG_WTAB(weight,16)
MC_WEIGHT_AVG_WTAB(offsetadd,16)
MC_WEIGHT_AVG_WTAB(offsetsub,16)
/* avx512icl on the same cache: w20 (the others are slower or neutral on Zen 4) */
static weight_avg_fn_t x264_mc_offsetadd_avg_wtab_avx512icl[6] =
{
    x264_mc_offsetadd_avg_w4_avx2,
    x264_mc_offsetadd_avg_w4_avx2,
    x264_mc_offsetadd_avg_w8_avx2,
    x264_mc_offsetadd_avg_w16_avx2,
    x264_mc_offsetadd_avg_w16_avx2,
    x264_mc_offsetadd_avg_w20_avx512icl,
};
static weight_avg_fn_t x264_mc_offsetsub_avg_wtab_avx512icl[6] =
{
    x264_mc_offsetsub_avg_w4_avx2,
    x264_mc_offsetsub_avg_w4_avx2,
    x264_mc_offsetsub_avg_w8_avx2,
    x264_mc_offsetsub_avg_w16_avx2,
    x264_mc_offsetsub_avg_w16_avx2,
    x264_mc_offsetsub_avg_w20_avx512icl,
};
#endif
#undef MC_WEIGHT_AVG_WTAB
#endif

#if HIGH_BIT_DEPTH
MC_WEIGHT_WTAB(weight,mmx2,mmx2,mmx2,12)
MC_WEIGHT_WTAB(offsetadd,mmx2,mmx2,mmx2,12)
MC_WEIGHT_WTAB(offsetsub,mmx2,mmx2,mmx2,12)
MC_WEIGHT_WTAB(weight,sse2,mmx2,sse2,12)
MC_WEIGHT_WTAB(offsetadd,sse2,mmx2,sse2,16)
MC_WEIGHT_WTAB(offsetsub,sse2,mmx2,sse2,16)

static void x264_weight_cache_mmx2( x264_t *h, x264_weight_t *w )
{
    w->weightavgfn = NULL;
    if( w->i_scale == 1<<w->i_denom )
    {
        if( w->i_offset < 0 )
            w->weightfn = h->mc.offsetsub;
        else
            w->weightfn = h->mc.offsetadd;
        for( int i = 0; i < 8; i++ )
            w->cachea[i] = abs(w->i_offset<<(BIT_DEPTH-8));
        return;
    }
    w->weightfn = h->mc.weight;
    int den1 = 1<<w->i_denom;
    int den2 = w->i_scale<<1;
    int den3 = 1+(w->i_offset<<(BIT_DEPTH-8+1));
    for( int i = 0; i < 8; i++ )
    {
        w->cachea[i] = den1;
        w->cacheb[i] = i&1 ? den3 : den2;
    }
}

MC_WEIGHT_WTAB(weight,avx2,avx2,avx2,12)
MC_WEIGHT_WTAB(weight_ns,avx2,avx2,avx2,12)
MC_WEIGHT_WTAB(offsetadd,avx2,avx2,avx2,16)
MC_WEIGHT_WTAB(offsetsub,avx2,avx2,sse2,16)
MC_WEIGHT_WTAB(weight,avx512,avx2,avx2,12)
static weight_fn_t x264_mc_weight_ns_wtab_avx512[6] =
{
    x264_mc_weight_ns_w4_avx2,
    x264_mc_weight_ns_w4_avx2,
    x264_mc_weight_ns_w8_avx2,
    x264_mc_weight_ns_w12_avx512,
    x264_mc_weight_ns_w16_avx2,
    x264_mc_weight_ns_w20_avx2,
};

/* pmulhrsw( pix<<(15-BIT_DEPTH), scale<<(BIT_DEPTH-denom) ), or pix by scale<<(15-denom)
 * when scale < 1<<denom; cacheb = offset + 0x7fff-PIXEL_MAX for the paddsw/psubusw clip.
 * Negative scales and scale<<(BIT_DEPTH-denom) > 0x7fff stay on SSE2. */
static ALWAYS_INLINE void weight_cache_mulhrs( x264_t *h, x264_weight_t *w, weight_fn_t *ns_wtab )
{
    int scale = w->i_scale;
    int denom = w->i_denom;
    if( scale == 1<<denom || scale < 0 || scale > 0x7fff >> (BIT_DEPTH-denom) )
    {
        x264_weight_cache_mmx2( h, w );
        if( scale != 1<<denom )
            w->weightfn = x264_mc_weight_wtab_sse2;
#if ARCH_X86_64
        else
            w->weightavgfn = w->i_offset < 0 ? x264_mc_offsetsub_avg_wtab_avx2 : x264_mc_offsetadd_avg_wtab_avx2;
#endif
        return;
    }
    int ns = scale < 1<<denom;
    int mul = scale << (ns ? 15-denom : BIT_DEPTH-denom);
    int offset = w->i_offset * (1<<(BIT_DEPTH-8)) + 0x7fff - PIXEL_MAX;
    w->weightfn = ns ? ns_wtab : h->mc.weight;
#if ARCH_X86_64
    w->weightavgfn = ns ? x264_mc_weight_ns_avg_wtab_avx2 : x264_mc_weight_avg_wtab_avx2;
#else
    w->weightavgfn = NULL;
#endif
    for( int i = 0; i < 8; i++ )
    {
        w->cachea[i] = mul;
        w->cacheb[i] = offset;
    }
}

static void x264_weight_cache_avx2( x264_t *h, x264_weight_t *w )
{
    weight_cache_mulhrs( h, w, x264_mc_weight_ns_wtab_avx2 );
}

static void x264_weight_cache_avx512( x264_t *h, x264_weight_t *w )
{
    weight_cache_mulhrs( h, w, x264_mc_weight_ns_wtab_avx512 );
}

#if ARCH_X86_64
/* x264_weight_scale_plane row by row over what its w16/w8 strips write (width
 * up to a multiple of 8, height up to even), for the weights whose w16/w8
 * kernels share the plane kernel's cache and op; 0 for the others (SSE2). */
#define WEIGHT_PLANE(cpu, wtab, ns_wtab, offset_cpu)\
static int weight_plane_##cpu( pixel *dst, intptr_t i_dst, pixel *src, intptr_t i_src,\
                               const x264_weight_t *w, int width, int height )\
{\
    void (*f)( pixel *, intptr_t, pixel *, intptr_t, const x264_weight_t *, int, int );\
    if( w->weightfn == wtab )\
        f = x264_mc_weight_plane_##cpu;\
    else if( w->weightfn == ns_wtab )\
        f = x264_mc_weight_ns_plane_##cpu;\
    else if( w->weightfn == x264_mc_offsetadd_wtab_avx2 )\
        f = x264_mc_offsetadd_plane_##offset_cpu;\
    else if( w->weightfn == x264_mc_offsetsub_wtab_avx2 )\
        f = x264_mc_offsetsub_plane_##offset_cpu;\
    else\
        return 0;\
    if( width > 0 && height > 0 )\
        f( dst, i_dst, src, i_src, w, (width+7)&~7, (height+1)&~1 );\
    return 1;\
}

WEIGHT_PLANE( avx2, x264_mc_weight_wtab_avx2, x264_mc_weight_ns_wtab_avx2, avx2 )
/* zen4 prune, neutral (>= 1.000): offsetadd/offsetsub_plane avx512; kept assembled */
WEIGHT_PLANE( avx512, x264_mc_weight_wtab_avx512, x264_mc_weight_ns_wtab_avx512, avx2 )
#undef WEIGHT_PLANE
#endif
#else
MC_WEIGHT_WTAB(weight,mmx2,mmx2,mmx2,12)
MC_WEIGHT_WTAB(offsetadd,mmx2,mmx2,mmx2,12)
MC_WEIGHT_WTAB(offsetsub,mmx2,mmx2,mmx2,12)
MC_WEIGHT_WTAB(weight,sse2,mmx2,sse2,16)
MC_WEIGHT_WTAB(offsetadd,sse2,mmx2,mmx2,16)
MC_WEIGHT_WTAB(offsetsub,sse2,mmx2,mmx2,16)
MC_WEIGHT_WTAB(weight,ssse3,ssse3,ssse3,16)
MC_WEIGHT_WTAB(weight,avx2,ssse3,avx2,16)

static void x264_weight_cache_mmx2( x264_t *h, x264_weight_t *w )
{
    int i;
    int16_t den1;

    w->weightavgfn = NULL;
    if( w->i_scale == 1<<w->i_denom )
    {
        if( w->i_offset < 0 )
            w->weightfn = h->mc.offsetsub;
        else
            w->weightfn = h->mc.offsetadd;
        memset( w->cachea, abs(w->i_offset), sizeof(w->cachea) );
        return;
    }
    w->weightfn = h->mc.weight;
    den1 = 1 << (w->i_denom - 1) | w->i_offset << w->i_denom;
    for( i = 0; i < 8; i++ )
    {
        w->cachea[i] = w->i_scale;
        w->cacheb[i] = den1;
    }
}

static void x264_weight_cache_ssse3( x264_t *h, x264_weight_t *w )
{
    int i, den1;
    w->weightavgfn = NULL;
    if( w->i_scale == 1<<w->i_denom )
    {
        if( w->i_offset < 0 )
            w->weightfn = h->mc.offsetsub;
        else
            w->weightfn = h->mc.offsetadd;

        memset( w->cachea, abs( w->i_offset ), sizeof(w->cachea) );
        return;
    }
    w->weightfn = h->mc.weight;
    den1 = w->i_scale << (8 - w->i_denom);
    for( i = 0; i < 8; i++ )
    {
        w->cachea[i] = den1;
        w->cacheb[i] = w->i_offset;
    }
}

#if ARCH_X86_64
/* the ssse3 cache, and the kernels of the qpel average for its weight's op */
static void x264_weight_cache_avx2( x264_t *h, x264_weight_t *w )
{
    x264_weight_cache_ssse3( h, w );
    if( w->i_scale != 1<<w->i_denom )
        w->weightavgfn = x264_mc_weight_avg_wtab_avx2;
    else
        w->weightavgfn = w->i_offset < 0 ? x264_mc_offsetsub_avg_wtab_avx2 : x264_mc_offsetadd_avg_wtab_avx2;
}

static void x264_weight_cache_avx512icl( x264_t *h, x264_weight_t *w )
{
    x264_weight_cache_avx2( h, w );
    if( w->i_scale == 1<<w->i_denom )
        w->weightavgfn = w->i_offset < 0 ? x264_mc_offsetsub_avg_wtab_avx512icl : x264_mc_offsetadd_avg_wtab_avx512icl;
#if !HIGH_BIT_DEPTH
    x264_weight_lut( w );
#endif
}

#define x264_mc_weight_plane_avx512icl x264_template(mc_weight_plane_avx512icl)
#define x264_mc_offsetadd_plane_avx512icl x264_template(mc_offsetadd_plane_avx512icl)
#define x264_mc_offsetsub_plane_avx512icl x264_template(mc_offsetsub_plane_avx512icl)
void x264_mc_weight_plane_avx512icl( pixel *, intptr_t, pixel *, intptr_t, const x264_weight_t *, int, int );
void x264_mc_offsetadd_plane_avx512icl( pixel *, intptr_t, pixel *, intptr_t, const x264_weight_t *, int, int );
void x264_mc_offsetsub_plane_avx512icl( pixel *, intptr_t, pixel *, intptr_t, const x264_weight_t *, int, int );
/* x264_weight_scale_plane over what its w16/w8 strips write, for the tables
 * dispatched with the ssse3 cache at avx512icl */
static int weight_plane_icl8( pixel *dst, intptr_t i_dst, pixel *src, intptr_t i_src,
                              const x264_weight_t *w, int width, int height )
{
    void (*f)( pixel *, intptr_t, pixel *, intptr_t, const x264_weight_t *, int, int );
    if( w->weightfn == x264_mc_weight_wtab_avx2 )
        f = x264_mc_weight_plane_avx512icl;
    else if( w->weightfn == x264_mc_offsetadd_wtab_sse2 )
        f = x264_mc_offsetadd_plane_avx512icl;
    else if( w->weightfn == x264_mc_offsetsub_wtab_sse2 )
        f = x264_mc_offsetsub_plane_avx512icl;
    else
        return 0;
    if( width > 0 && height > 0 )
        f( dst, i_dst, src, i_src, w, (width+7)&~7, (height+1)&~1 );
    return 1;
}
#endif
#endif // !HIGH_BIT_DEPTH

static const uint8_t hpel_ref0[16] = {0,1,1,1,0,1,1,1,2,3,3,3,0,1,1,1};
static const uint8_t hpel_ref1[16] = {0,0,0,0,2,2,3,2,2,2,3,2,2,2,3,2};

#define MC_LUMA(name,instr1,instr2)\
static void mc_luma_##name( pixel *dst,    intptr_t i_dst_stride,\
                            pixel *src[4], intptr_t i_src_stride,\
                            int mvx, int mvy,\
                            int i_width, int i_height, const x264_weight_t *weight )\
{\
    int qpel_idx = ((mvy&3)<<2) + (mvx&3);\
    int offset = (mvy>>2)*i_src_stride + (mvx>>2);\
    pixel *src1 = src[hpel_ref0[qpel_idx]] + offset + ((mvy&3) == 3) * i_src_stride;\
    if( qpel_idx & 5 ) /* qpel interpolation needed */\
    {\
        pixel *src2 = src[hpel_ref1[qpel_idx]] + offset + ((mvx&3) == 3);\
        if( weight->weightfn && weight->weightavgfn )\
            weight->weightavgfn[i_width>>2]( dst, i_dst_stride, src1, i_src_stride, weight, i_height, src2 );\
        else\
        {\
            x264_pixel_avg_wtab_##instr1[i_width>>2](\
                    dst, i_dst_stride, src1, i_src_stride,\
                    src2, i_height );\
            if( weight->weightfn )\
                weight->weightfn[i_width>>2]( dst, i_dst_stride, dst, i_dst_stride, weight, i_height );\
        }\
    }\
    else if( weight->weightfn )\
        weight->weightfn[i_width>>2]( dst, i_dst_stride, src1, i_src_stride, weight, i_height );\
    else\
        x264_mc_copy_wtab_##instr2[i_width>>2](dst, i_dst_stride, src1, i_src_stride, i_height );\
}

MC_LUMA(mmx2,mmx2,mmx)
MC_LUMA(sse2,sse2,sse)
#if HIGH_BIT_DEPTH
MC_LUMA(avx2,avx2,avx)
#else
#if ARCH_X86
MC_LUMA(cache32_mmx2,cache32_mmx2,mmx)
MC_LUMA(cache64_mmx2,cache64_mmx2,mmx)
#endif
MC_LUMA(cache64_sse2,cache64_sse2,sse)
MC_LUMA(cache64_ssse3,cache64_ssse3,sse)
MC_LUMA(cache64_ssse3_atom,cache64_ssse3_atom,sse)
#endif // !HIGH_BIT_DEPTH

#define GET_REF(name)\
static pixel *get_ref_##name( pixel *dst,   intptr_t *i_dst_stride,\
                              pixel *src[4], intptr_t i_src_stride,\
                              int mvx, int mvy,\
                              int i_width, int i_height, const x264_weight_t *weight )\
{\
    int qpel_idx = ((mvy&3)<<2) + (mvx&3);\
    int offset = (mvy>>2)*i_src_stride + (mvx>>2);\
    pixel *src1 = src[hpel_ref0[qpel_idx]] + offset + ((mvy&3) == 3) * i_src_stride;\
    if( qpel_idx & 5 ) /* qpel interpolation needed */\
    {\
        pixel *src2 = src[hpel_ref1[qpel_idx]] + offset + ((mvx&3) == 3);\
        if( weight->weightfn && weight->weightavgfn )\
            weight->weightavgfn[i_width>>2]( dst, *i_dst_stride, src1, i_src_stride, weight, i_height, src2 );\
        else\
        {\
            x264_pixel_avg_wtab_##name[i_width>>2](\
                    dst, *i_dst_stride, src1, i_src_stride,\
                    src2, i_height );\
            if( weight->weightfn )\
                weight->weightfn[i_width>>2]( dst, *i_dst_stride, dst, *i_dst_stride, weight, i_height );\
        }\
        return dst;\
    }\
    else if( weight->weightfn )\
    {\
        weight->weightfn[i_width>>2]( dst, *i_dst_stride, src1, i_src_stride, weight, i_height );\
        return dst;\
    }\
    else\
    {\
        *i_dst_stride = i_src_stride;\
        return src1;\
    }\
}

GET_REF(mmx2)
GET_REF(sse2)
GET_REF(avx2)
#if !HIGH_BIT_DEPTH
#if ARCH_X86
GET_REF(cache32_mmx2)
GET_REF(cache64_mmx2)
#endif
GET_REF(cache64_sse2)
GET_REF(cache64_ssse3)
GET_REF(cache64_ssse3_atom)
#endif // !HIGH_BIT_DEPTH

#define HPEL(align, cpu, cpuv, cpuc, cpuh)\
void x264_hpel_filter_v_##cpuv( pixel *dst, pixel *src, int16_t *buf, intptr_t stride, intptr_t width);\
void x264_hpel_filter_c_##cpuc( pixel *dst, int16_t *buf, intptr_t width );\
void x264_hpel_filter_h_##cpuh( pixel *dst, pixel *src, intptr_t width );\
static void x264_hpel_filter_##cpu( pixel *dsth, pixel *dstv, pixel *dstc, pixel *src,\
                                    intptr_t stride, int width, int height, int16_t *buf )\
{\
    intptr_t realign = ((intptr_t)src & (align-1)) / sizeof(pixel);\
    src -= realign;\
    dstv -= realign;\
    dstc -= realign;\
    dsth -= realign;\
    width += realign;\
    while( height-- )\
    {\
        x264_hpel_filter_v_##cpuv( dstv, src, buf+16, stride, width );\
        x264_hpel_filter_c_##cpuc( dstc, buf+16, width );\
        x264_hpel_filter_h_##cpuh( dsth, src, width );\
        dsth += stride;\
        dstv += stride;\
        dstc += stride;\
        src  += stride;\
    }\
    x264_sfence();\
}

#define HPEL_COPY(align, cpu, cpuv, cpuc, cpuh)\
void x264_hpel_filter_h_copy_##cpuh( pixel *dst, pixel *src, intptr_t width, pixel *dstf );\
static void x264_hpel_filter_copy_##cpu( pixel *dsth, pixel *dstv, pixel *dstc, pixel *src,\
                                         intptr_t stride, int width, int height, int16_t *buf, pixel *dstf )\
{\
    intptr_t realign = ((intptr_t)src & (align-1)) / sizeof(pixel);\
    src -= realign;\
    dstv -= realign;\
    dstc -= realign;\
    dsth -= realign;\
    dstf -= realign;\
    width += realign;\
    while( height-- )\
    {\
        x264_hpel_filter_v_##cpuv( dstv, src, buf+16, stride, width );\
        x264_hpel_filter_c_##cpuc( dstc, buf+16, width );\
        x264_hpel_filter_h_copy_##cpuh( dsth, src, width, dstf );\
        dsth += stride;\
        dstv += stride;\
        dstc += stride;\
        dstf += stride;\
        src  += stride;\
    }\
    x264_sfence();\
}

HPEL(8, mmx2, mmx2, mmx2, mmx2)
#if HIGH_BIT_DEPTH
HPEL(16, sse2, sse2, sse2, sse2)
#if ARCH_X86_64
void x264_hpel_filter_avx2( uint16_t *dsth, uint16_t *dstv, uint16_t *dstc, uint16_t *src, intptr_t stride, int width, int height, int16_t *buf );
/* the field pass copy still uses the 3-pass kernels */
void x264_hpel_filter_v_avx2( pixel *dst, pixel *src, int16_t *buf, intptr_t stride, intptr_t width );
void x264_hpel_filter_c_avx2( pixel *dst, int16_t *buf, intptr_t width );
#else
HPEL(32, avx2, avx2, avx2, avx2)
#endif
HPEL_COPY(32, avx2, avx2, avx2, avx2)
#else // !HIGH_BIT_DEPTH
HPEL(16, sse2_amd, mmx2, mmx2, sse2)
#if ARCH_X86_64
void x264_hpel_filter_sse2 ( uint8_t *dsth, uint8_t *dstv, uint8_t *dstc, uint8_t *src, intptr_t stride, int width, int height, int16_t *buf );
void x264_hpel_filter_ssse3( uint8_t *dsth, uint8_t *dstv, uint8_t *dstc, uint8_t *src, intptr_t stride, int width, int height, int16_t *buf );
void x264_hpel_filter_avx  ( uint8_t *dsth, uint8_t *dstv, uint8_t *dstc, uint8_t *src, intptr_t stride, int width, int height, int16_t *buf );
void x264_hpel_filter_avx2 ( uint8_t *dsth, uint8_t *dstv, uint8_t *dstc, uint8_t *src, intptr_t stride, int width, int height, int16_t *buf );
void x264_hpel_filter_copy_sse2 ( uint8_t *dsth, uint8_t *dstv, uint8_t *dstc, uint8_t *src, intptr_t stride, int width, int height, int16_t *buf, uint8_t *dstf );
void x264_hpel_filter_copy_ssse3( uint8_t *dsth, uint8_t *dstv, uint8_t *dstc, uint8_t *src, intptr_t stride, int width, int height, int16_t *buf, uint8_t *dstf );
void x264_hpel_filter_copy_avx  ( uint8_t *dsth, uint8_t *dstv, uint8_t *dstc, uint8_t *src, intptr_t stride, int width, int height, int16_t *buf, uint8_t *dstf );
void x264_hpel_filter_copy_avx2 ( uint8_t *dsth, uint8_t *dstv, uint8_t *dstc, uint8_t *src, intptr_t stride, int width, int height, int16_t *buf, uint8_t *dstf );
#else
HPEL(16, sse2, sse2, sse2, sse2)
HPEL(16, ssse3, ssse3, ssse3, ssse3)
HPEL(16, avx, avx, avx, avx)
HPEL(32, avx2, avx2, avx2, avx2)
#endif
#endif // HIGH_BIT_DEPTH

#define PLANE_COPY(align, cpu)\
static void x264_plane_copy_##cpu( pixel *dst, intptr_t i_dst, pixel *src, intptr_t i_src, int w, int h )\
{\
    int c_w = (align)/sizeof(pixel) - 1;\
    if( w < 256 ) /* tiny resolutions don't want non-temporal hints. dunno the exact threshold. */\
        x264_plane_copy_c( dst, i_dst, src, i_src, w, h );\
    else if( !(w&c_w) )\
        x264_plane_copy_core_##cpu( dst, i_dst, src, i_src, w, h );\
    else\
    {\
        if( --h > 0 )\
        {\
            if( i_src > 0 )\
            {\
                x264_plane_copy_core_##cpu( dst, i_dst, src, i_src, (w+c_w)&~c_w, h );\
                dst += i_dst * h;\
                src += i_src * h;\
            }\
            else\
                x264_plane_copy_core_##cpu( dst+i_dst, i_dst, src+i_src, i_src, (w+c_w)&~c_w, h );\
        }\
        /* use plain memcpy on the last line (in memory order) to avoid overreading src. */\
        memcpy( dst, src, w*sizeof(pixel) );\
    }\
}

PLANE_COPY(16, mmx2)
PLANE_COPY(32, avx2)

#define PLANE_INTERLEAVE(cpu) \
static void x264_plane_copy_interleave_##cpu( pixel *dst,  intptr_t i_dst,\
                                              pixel *srcu, intptr_t i_srcu,\
                                              pixel *srcv, intptr_t i_srcv, int w, int h )\
{\
    if( !(w&15) ) {\
        x264_plane_copy_interleave_core_##cpu( dst, i_dst, srcu, i_srcu, srcv, i_srcv, w, h );\
    } else if( w < 16 || (i_srcu ^ i_srcv) ) {\
        x264_plane_copy_interleave_c( dst, i_dst, srcu, i_srcu, srcv, i_srcv, w, h );\
    } else if( i_srcu > 0 ) {\
        x264_plane_copy_interleave_core_##cpu( dst, i_dst, srcu, i_srcu, srcv, i_srcv, (w+15)&~15, h-1 );\
        x264_plane_copy_interleave_c( dst+i_dst*(h-1), 0, srcu+i_srcu*(h-1), 0, srcv+i_srcv*(h-1), 0, w, 1 );\
    } else {\
        x264_plane_copy_interleave_c( dst, 0, srcu, 0, srcv, 0, w, 1 );\
        x264_plane_copy_interleave_core_##cpu( dst+i_dst, i_dst, srcu+i_srcu, i_srcu, srcv+i_srcv, i_srcv, (w+15)&~15, h-1 );\
    }\
}

PLANE_INTERLEAVE(mmx2)
PLANE_INTERLEAVE(sse2)
#if HIGH_BIT_DEPTH
PLANE_INTERLEAVE(avx)
#endif
#if ARCH_X86_64 && !HIGH_BIT_DEPTH
PLANE_INTERLEAVE(avx512icl)
/* the avx512icl core's ymm non-temporal stores need 32-byte aligned rows */
static void plane_copy_interleave_icl( pixel *dst,  intptr_t i_dst,
                                       pixel *srcu, intptr_t i_srcu,
                                       pixel *srcv, intptr_t i_srcv, int w, int h )
{
    if( ((intptr_t)dst | (i_dst * (intptr_t)sizeof(pixel))) & 31 )
        x264_plane_copy_interleave_sse2( dst, i_dst, srcu, i_srcu, srcv, i_srcv, w, h );
    else
        x264_plane_copy_interleave_avx512icl( dst, i_dst, srcu, i_srcu, srcv, i_srcv, w, h );
}
#endif

#if HAVE_X86_INLINE_ASM
#define CLIP_ADD(s,x)\
do\
{\
    int temp;\
    asm("movd       %0, %%xmm0     \n"\
        "movd       %2, %%xmm1     \n"\
        "paddsw %%xmm1, %%xmm0     \n"\
        "movd   %%xmm0, %1         \n"\
        :"+m"(s), "=&r"(temp)\
        :"m"(x)\
    );\
    s = temp;\
} while(0)

#define CLIP_ADD2(s,x)\
do\
{\
    asm("movd       %0, %%xmm0     \n"\
        "movd       %1, %%xmm1     \n"\
        "paddsw %%xmm1, %%xmm0     \n"\
        "movd   %%xmm0, %0         \n"\
        :"+m"(M32(s))\
        :"m"(M32(x))\
    );\
} while(0)
#else
#define CLIP_ADD(s,x) (s) = X264_MIN((s)+(x),(1<<15)-1)
#define CLIP_ADD2(s,x)\
do\
{\
    CLIP_ADD((s)[0], (x)[0]);\
    CLIP_ADD((s)[1], (x)[1]);\
} while(0)
#endif

#define PROPAGATE_LIST(cpu)\
void x264_mbtree_propagate_list_internal_##cpu( int16_t (*mvs)[2], int16_t *propagate_amount,\
                                                uint16_t *lowres_costs, int16_t *output,\
                                                int bipred_weight, int mb_y, int len );\
\
static void x264_mbtree_propagate_list_##cpu( x264_t *h, uint16_t *ref_costs, int16_t (*mvs)[2],\
                                              int16_t *propagate_amount, uint16_t *lowres_costs,\
                                              int bipred_weight, int mb_y, int len, int list )\
{\
    int16_t *current = h->scratch_buffer2;\
\
    x264_mbtree_propagate_list_internal_##cpu( mvs, propagate_amount, lowres_costs,\
                                               current, bipred_weight, mb_y, len );\
\
    unsigned stride = h->mb.i_mb_stride;\
    unsigned width = h->mb.i_mb_width;\
    unsigned height = h->mb.i_mb_height;\
\
    for( unsigned i = 0; i < len; current += 32 )\
    {\
        int end = X264_MIN( i+8, len );\
        for( ; i < end; i++, current += 2 )\
        {\
            if( !(lowres_costs[i] & (1 << (list+LOWRES_COST_SHIFT))) )\
                continue;\
\
            unsigned mbx = current[0];\
            unsigned mby = current[1];\
            unsigned idx0 = mbx + mby * stride;\
            unsigned idx2 = idx0 + stride;\
\
            /* Shortcut for the simple/common case of zero MV */\
            if( !M32( mvs[i] ) )\
            {\
                CLIP_ADD( ref_costs[idx0], current[16] );\
                continue;\
            }\
\
            if( mbx < width-1 && mby < height-1 )\
            {\
                CLIP_ADD2( ref_costs+idx0, current+16 );\
                CLIP_ADD2( ref_costs+idx2, current+32 );\
            }\
            else\
            {\
                /* Note: this takes advantage of unsigned representation to\
                 * catch negative mbx/mby. */\
                if( mby < height )\
                {\
                    if( mbx < width )\
                        CLIP_ADD( ref_costs[idx0+0], current[16] );\
                    if( mbx+1 < width )\
                        CLIP_ADD( ref_costs[idx0+1], current[17] );\
                }\
                if( mby+1 < height )\
                {\
                    if( mbx < width )\
                        CLIP_ADD( ref_costs[idx2+0], current[32] );\
                    if( mbx+1 < width )\
                        CLIP_ADD( ref_costs[idx2+1], current[33] );\
                }\
            }\
        }\
    }\
}

#define x264_mbtree_propagate_list_internal_ssse3 x264_template(mbtree_propagate_list_internal_ssse3)
#define x264_mbtree_propagate_list_internal_avx x264_template(mbtree_propagate_list_internal_avx)
PROPAGATE_LIST(ssse3)
PROPAGATE_LIST(avx)
#if ARCH_X86_64
#define x264_mbtree_propagate_list_internal_avx512 x264_template(mbtree_propagate_list_internal_avx512)
PROPAGATE_LIST(avx512)
#endif
#undef CLIP_ADD
#undef CLIP_ADD2


void x264_mc_init_mmx( int cpu, x264_mc_functions_t *pf )
{
    if( !(cpu&X264_CPU_MMX) )
        return;

    pf->load_deinterleave_chroma_fenc = x264_load_deinterleave_chroma_fenc_mmx;
    pf->load_deinterleave_chroma_fdec = x264_load_deinterleave_chroma_fdec_mmx;

    pf->plane_copy_deinterleave = x264_plane_copy_deinterleave_mmx;

    pf->copy_16x16_unaligned = x264_mc_copy_w16_mmx;
    pf->copy[PIXEL_16x16] = x264_mc_copy_w16_mmx;
    pf->copy[PIXEL_8x8]   = x264_mc_copy_w8_mmx;
    pf->copy[PIXEL_4x4]   = x264_mc_copy_w4_mmx;
    pf->memcpy_aligned  = x264_memcpy_aligned_mmx;
    pf->memzero_aligned = x264_memzero_aligned_mmx;
    pf->integral_init4v = x264_integral_init4v_mmx;
    pf->integral_init8v = x264_integral_init8v_mmx;

    if( !(cpu&X264_CPU_MMX2) )
        return;

    pf->prefetch_fenc_420 = x264_prefetch_fenc_420_mmx2;
    pf->prefetch_fenc_422 = x264_prefetch_fenc_422_mmx2;
    pf->prefetch_ref  = x264_prefetch_ref_mmx2;

    pf->plane_copy = x264_plane_copy_mmx2;
    pf->plane_copy_interleave = x264_plane_copy_interleave_mmx2;
    pf->store_interleave_chroma = x264_store_interleave_chroma_mmx2;

    pf->avg[PIXEL_16x16] = x264_pixel_avg_16x16_mmx2;
    pf->avg[PIXEL_16x8]  = x264_pixel_avg_16x8_mmx2;
    pf->avg[PIXEL_8x16]  = x264_pixel_avg_8x16_mmx2;
    pf->avg[PIXEL_8x8]   = x264_pixel_avg_8x8_mmx2;
    pf->avg[PIXEL_8x4]   = x264_pixel_avg_8x4_mmx2;
    pf->avg[PIXEL_4x16]  = x264_pixel_avg_4x16_mmx2;
    pf->avg[PIXEL_4x8]   = x264_pixel_avg_4x8_mmx2;
    pf->avg[PIXEL_4x4]   = x264_pixel_avg_4x4_mmx2;
    pf->avg[PIXEL_4x2]   = x264_pixel_avg_4x2_mmx2;

    pf->mc_luma = mc_luma_mmx2;
    pf->get_ref = get_ref_mmx2;
    pf->mc_chroma = x264_mc_chroma_mmx2;
    pf->hpel_filter = x264_hpel_filter_mmx2;
    pf->weight = x264_mc_weight_wtab_mmx2;
    pf->weight_cache = x264_weight_cache_mmx2;
    pf->offsetadd = x264_mc_offsetadd_wtab_mmx2;
    pf->offsetsub = x264_mc_offsetsub_wtab_mmx2;

    pf->frame_init_lowres_core = x264_frame_init_lowres_core_mmx2;

    if( cpu&X264_CPU_SSE )
    {
        pf->memcpy_aligned  = x264_memcpy_aligned_sse;
        pf->memzero_aligned = x264_memzero_aligned_sse;
    }

#if HIGH_BIT_DEPTH
#if ARCH_X86 // all x86_64 cpus with cacheline split issues use sse2 instead
    if( cpu&(X264_CPU_CACHELINE_32|X264_CPU_CACHELINE_64) )
        pf->frame_init_lowres_core = x264_frame_init_lowres_core_cache32_mmx2;
#endif

    if( !(cpu&X264_CPU_SSE2) )
        return;

    pf->frame_init_lowres_core = x264_frame_init_lowres_core_sse2;

    pf->load_deinterleave_chroma_fenc = x264_load_deinterleave_chroma_fenc_sse2;
    pf->load_deinterleave_chroma_fdec = x264_load_deinterleave_chroma_fdec_sse2;

    pf->plane_copy_interleave   = x264_plane_copy_interleave_sse2;
    pf->plane_copy_deinterleave = x264_plane_copy_deinterleave_sse2;

    if( cpu&X264_CPU_SSE2_IS_FAST )
    {
        pf->get_ref = get_ref_sse2;
        pf->mc_luma = mc_luma_sse2;
        pf->hpel_filter = x264_hpel_filter_sse2;
    }

    pf->integral_init4v = x264_integral_init4v_sse2;
    pf->integral_init8v = x264_integral_init8v_sse2;
    pf->mbtree_propagate_cost = x264_mbtree_propagate_cost_sse2;
    pf->store_interleave_chroma = x264_store_interleave_chroma_sse2;
    pf->offsetadd = x264_mc_offsetadd_wtab_sse2;
    pf->offsetsub = x264_mc_offsetsub_wtab_sse2;

    if( cpu&X264_CPU_SSE2_IS_SLOW )
        return;

    pf->avg[PIXEL_16x16] = x264_pixel_avg_16x16_sse2;
    pf->avg[PIXEL_16x8]  = x264_pixel_avg_16x8_sse2;
    pf->avg[PIXEL_8x16]  = x264_pixel_avg_8x16_sse2;
    pf->avg[PIXEL_8x8]   = x264_pixel_avg_8x8_sse2;
    pf->avg[PIXEL_8x4]   = x264_pixel_avg_8x4_sse2;
    pf->avg[PIXEL_4x16]  = x264_pixel_avg_4x16_sse2;
    pf->avg[PIXEL_4x8]   = x264_pixel_avg_4x8_sse2;
    pf->avg[PIXEL_4x4]   = x264_pixel_avg_4x4_sse2;
    pf->avg[PIXEL_4x2]   = x264_pixel_avg_4x2_sse2;

    pf->copy[PIXEL_16x16] = x264_mc_copy_w16_aligned_sse;
    pf->weight = x264_mc_weight_wtab_sse2;

    if( !(cpu&X264_CPU_STACK_MOD4) )
        pf->mc_chroma = x264_mc_chroma_sse2;

    if( !(cpu&X264_CPU_SSSE3) )
        return;

    pf->frame_init_lowres_core = x264_frame_init_lowres_core_ssse3;
#if ARCH_X86_64
    pf->frame_init_lowres_core8 = x264_frame_init_lowres_core8_ssse3;
#endif
    pf->plane_copy_deinterleave_v210 = x264_plane_copy_deinterleave_v210_ssse3;
    pf->mbtree_propagate_list = x264_mbtree_propagate_list_ssse3;

    if( !(cpu&(X264_CPU_SLOW_SHUFFLE|X264_CPU_SLOW_ATOM|X264_CPU_SLOW_PALIGNR)) )
        pf->integral_init4v = x264_integral_init4v_ssse3;

    if( !(cpu&X264_CPU_AVX) )
        return;

    pf->frame_init_lowres_core = x264_frame_init_lowres_core_avx;
    pf->load_deinterleave_chroma_fenc = x264_load_deinterleave_chroma_fenc_avx;
    pf->load_deinterleave_chroma_fdec = x264_load_deinterleave_chroma_fdec_avx;
    pf->plane_copy_interleave        = x264_plane_copy_interleave_avx;
    pf->plane_copy_deinterleave      = x264_plane_copy_deinterleave_avx;
    pf->plane_copy_deinterleave_v210 = x264_plane_copy_deinterleave_v210_avx;
    pf->store_interleave_chroma      = x264_store_interleave_chroma_avx;
    pf->copy[PIXEL_16x16]            = x264_mc_copy_w16_aligned_avx;

    if( !(cpu&X264_CPU_STACK_MOD4) )
        pf->mc_chroma = x264_mc_chroma_avx;

    if( cpu&X264_CPU_XOP )
        pf->frame_init_lowres_core = x264_frame_init_lowres_core_xop;

    if( cpu&X264_CPU_AVX2 )
    {
        pf->mc_luma = mc_luma_avx2;
        pf->plane_copy_deinterleave_v210 = x264_plane_copy_deinterleave_v210_avx2;
        pf->hpel_filter = x264_hpel_filter_avx2;
        pf->hpel_filter_copy = x264_hpel_filter_copy_avx2;
        pf->frame_init_lowres_core = x264_frame_init_lowres_core_avx2;
#if ARCH_X86_64
        pf->frame_init_lowres_core8 = x264_frame_init_lowres_core8_avx2;
#endif
        pf->load_deinterleave_chroma_fenc = x264_load_deinterleave_chroma_fenc_avx2;
        pf->load_deinterleave_chroma_fdec = x264_load_deinterleave_chroma_fdec_avx2;
        if( !(cpu&X264_CPU_STACK_MOD4) )
            pf->mc_chroma = x264_mc_chroma_avx2;
        pf->avg[PIXEL_16x16] = x264_pixel_avg_16x16_avx2;
        pf->avg[PIXEL_16x8]  = x264_pixel_avg_16x8_avx2;
        pf->avg[PIXEL_8x16]  = x264_pixel_avg_8x16_avx2;
        pf->avg[PIXEL_8x8]   = x264_pixel_avg_8x8_avx2;
        pf->avg[PIXEL_8x4]   = x264_pixel_avg_8x4_avx2;
        pf->weight = x264_mc_weight_wtab_avx2;
        pf->weight_cache = x264_weight_cache_avx2;
        pf->offsetadd = x264_mc_offsetadd_wtab_avx2;
        pf->offsetsub = x264_mc_offsetsub_wtab_avx2;
#if ARCH_X86_64
        pf->weight_plane = weight_plane_avx2;
#endif
    }

    if( cpu&X264_CPU_AVX512 )
    {
        pf->plane_copy_deinterleave_v210 = x264_plane_copy_deinterleave_v210_avx512;
        pf->weight = x264_mc_weight_wtab_avx512;
        pf->weight_cache = x264_weight_cache_avx512;
#if ARCH_X86_64
        pf->weight_plane = weight_plane_avx512;
#endif
    }

    if( cpu&X264_CPU_AVX512ICL )
    {
#if ARCH_X86_64
        /* zen4 prune, neutral (>= 1.000): frame_init_lowres_core8, plane_copy_interleave; kept assembled */
        pf->frame_init_lowres_core = x264_frame_init_lowres_core_avx512icl;
        pf->plane_copy_deinterleave = x264_plane_copy_deinterleave_avx512icl;
        pf->store_interleave_chroma = x264_store_interleave_chroma_avx512icl;
        pf->integral_init4v = x264_integral_init4v_avx512icl;
        pf->integral_init8v = x264_integral_init8v_avx512icl;
#endif
    }
#else // !HIGH_BIT_DEPTH

#if ARCH_X86 // all x86_64 cpus with cacheline split issues use sse2 instead
    if( cpu&X264_CPU_CACHELINE_32 )
    {
        pf->mc_luma = mc_luma_cache32_mmx2;
        pf->get_ref = get_ref_cache32_mmx2;
        pf->frame_init_lowres_core = x264_frame_init_lowres_core_cache32_mmx2;
    }
    else if( cpu&X264_CPU_CACHELINE_64 )
    {
        pf->mc_luma = mc_luma_cache64_mmx2;
        pf->get_ref = get_ref_cache64_mmx2;
        pf->frame_init_lowres_core = x264_frame_init_lowres_core_cache32_mmx2;
    }
#endif

    if( !(cpu&X264_CPU_SSE2) )
        return;

    pf->integral_init4v = x264_integral_init4v_sse2;
    pf->integral_init8v = x264_integral_init8v_sse2;
    pf->hpel_filter = x264_hpel_filter_sse2_amd;
    pf->mbtree_propagate_cost = x264_mbtree_propagate_cost_sse2;
    pf->plane_copy_deinterleave_rgb = x264_plane_copy_deinterleave_rgb_sse2;

    if( !(cpu&X264_CPU_SSE2_IS_SLOW) )
    {
        pf->weight = x264_mc_weight_wtab_sse2;
        if( !(cpu&X264_CPU_SLOW_ATOM) )
        {
            pf->offsetadd = x264_mc_offsetadd_wtab_sse2;
            pf->offsetsub = x264_mc_offsetsub_wtab_sse2;
        }

        pf->copy[PIXEL_16x16] = x264_mc_copy_w16_aligned_sse;
        pf->avg[PIXEL_16x16] = x264_pixel_avg_16x16_sse2;
        pf->avg[PIXEL_16x8]  = x264_pixel_avg_16x8_sse2;
        pf->avg[PIXEL_8x16] = x264_pixel_avg_8x16_sse2;
        pf->avg[PIXEL_8x8]  = x264_pixel_avg_8x8_sse2;
        pf->avg[PIXEL_8x4]  = x264_pixel_avg_8x4_sse2;
        pf->hpel_filter = x264_hpel_filter_sse2;
#if ARCH_X86_64
        pf->hpel_filter_copy = x264_hpel_filter_copy_sse2;
#endif
        pf->frame_init_lowres_core = x264_frame_init_lowres_core_sse2;
        if( !(cpu&X264_CPU_STACK_MOD4) )
            pf->mc_chroma = x264_mc_chroma_sse2;

        if( cpu&X264_CPU_SSE2_IS_FAST )
        {
            pf->store_interleave_chroma = x264_store_interleave_chroma_sse2; // FIXME sse2fast? sse2medium?
            pf->load_deinterleave_chroma_fenc = x264_load_deinterleave_chroma_fenc_sse2;
            pf->load_deinterleave_chroma_fdec = x264_load_deinterleave_chroma_fdec_sse2;
            pf->plane_copy_interleave   = x264_plane_copy_interleave_sse2;
            pf->plane_copy_deinterleave = x264_plane_copy_deinterleave_sse2;
            pf->mc_luma = mc_luma_sse2;
            pf->get_ref = get_ref_sse2;
            if( cpu&X264_CPU_CACHELINE_64 )
            {
                pf->mc_luma = mc_luma_cache64_sse2;
                pf->get_ref = get_ref_cache64_sse2;
            }
        }
    }

    if( !(cpu&X264_CPU_SSSE3) )
        return;

    pf->avg[PIXEL_16x16] = x264_pixel_avg_16x16_ssse3;
    pf->avg[PIXEL_16x8]  = x264_pixel_avg_16x8_ssse3;
    pf->avg[PIXEL_8x16]  = x264_pixel_avg_8x16_ssse3;
    pf->avg[PIXEL_8x8]   = x264_pixel_avg_8x8_ssse3;
    pf->avg[PIXEL_8x4]   = x264_pixel_avg_8x4_ssse3;
    pf->avg[PIXEL_4x16]  = x264_pixel_avg_4x16_ssse3;
    pf->avg[PIXEL_4x8]   = x264_pixel_avg_4x8_ssse3;
    pf->avg[PIXEL_4x4]   = x264_pixel_avg_4x4_ssse3;
    pf->avg[PIXEL_4x2]   = x264_pixel_avg_4x2_ssse3;
    pf->plane_copy_deinterleave_rgb = x264_plane_copy_deinterleave_rgb_ssse3;
    pf->mbtree_propagate_list = x264_mbtree_propagate_list_ssse3;

    if( !(cpu&X264_CPU_SLOW_PSHUFB) )
    {
        pf->load_deinterleave_chroma_fenc = x264_load_deinterleave_chroma_fenc_ssse3;
        pf->load_deinterleave_chroma_fdec = x264_load_deinterleave_chroma_fdec_ssse3;
        pf->plane_copy_deinterleave = x264_plane_copy_deinterleave_ssse3;
    }

    if( !(cpu&X264_CPU_SLOW_PALIGNR) )
    {
#if ARCH_X86_64
        if( !(cpu&X264_CPU_SLOW_ATOM) ) /* The 64-bit version is slower, but the 32-bit version is faster? */
        {
            pf->hpel_filter = x264_hpel_filter_ssse3;
            pf->hpel_filter_copy = x264_hpel_filter_copy_ssse3;
        }
#else
        pf->hpel_filter = x264_hpel_filter_ssse3;
#endif
        pf->frame_init_lowres_core = x264_frame_init_lowres_core_ssse3;
    }
    if( !(cpu&X264_CPU_STACK_MOD4) )
        pf->mc_chroma = x264_mc_chroma_ssse3;

    if( cpu&X264_CPU_CACHELINE_64 )
    {
        if( !(cpu&X264_CPU_STACK_MOD4) )
            pf->mc_chroma = x264_mc_chroma_ssse3_cache64;
        pf->mc_luma = mc_luma_cache64_ssse3;
        pf->get_ref = get_ref_cache64_ssse3;
        if( cpu&X264_CPU_SLOW_ATOM )
        {
            pf->mc_luma = mc_luma_cache64_ssse3_atom;
            pf->get_ref = get_ref_cache64_ssse3_atom;
        }
    }

    pf->weight_cache = x264_weight_cache_ssse3;
    pf->weight = x264_mc_weight_wtab_ssse3;

    if( !(cpu&(X264_CPU_SLOW_SHUFFLE|X264_CPU_SLOW_ATOM|X264_CPU_SLOW_PALIGNR)) )
        pf->integral_init4v = x264_integral_init4v_ssse3;

    if( !(cpu&X264_CPU_SSE4) )
        return;

    pf->integral_init4h = x264_integral_init4h_sse4;
    pf->integral_init8h = x264_integral_init8h_sse4;

    if( !(cpu&X264_CPU_AVX) )
        return;

    pf->frame_init_lowres_core = x264_frame_init_lowres_core_avx;
    pf->integral_init8h = x264_integral_init8h_avx;
    pf->hpel_filter = x264_hpel_filter_avx;
#if ARCH_X86_64
    pf->hpel_filter_copy = x264_hpel_filter_copy_avx;
#endif

    if( !(cpu&X264_CPU_STACK_MOD4) )
        pf->mc_chroma = x264_mc_chroma_avx;

    if( cpu&X264_CPU_XOP )
        pf->frame_init_lowres_core = x264_frame_init_lowres_core_xop;

    if( cpu&X264_CPU_AVX2 )
    {
        pf->hpel_filter = x264_hpel_filter_avx2;
#if ARCH_X86_64
        pf->hpel_filter_copy = x264_hpel_filter_copy_avx2;
#endif
        pf->mc_chroma = x264_mc_chroma_avx2;
        pf->weight = x264_mc_weight_wtab_avx2;
#if ARCH_X86_64
        pf->weight_cache = x264_weight_cache_avx2;
#endif
        pf->avg[PIXEL_16x16] = x264_pixel_avg_16x16_avx2;
        pf->avg[PIXEL_16x8]  = x264_pixel_avg_16x8_avx2;
        pf->avg[PIXEL_8x16]  = x264_pixel_avg_8x16_avx2;
        pf->avg[PIXEL_8x8]   = x264_pixel_avg_8x8_avx2;
        pf->avg[PIXEL_8x4]   = x264_pixel_avg_8x4_avx2;
        pf->integral_init8v = x264_integral_init8v_avx2;
        pf->integral_init4v = x264_integral_init4v_avx2;
        pf->integral_init8h = x264_integral_init8h_avx2;
        pf->integral_init4h = x264_integral_init4h_avx2;
        pf->frame_init_lowres_core = x264_frame_init_lowres_core_avx2;
    }

    if( cpu&X264_CPU_AVX512 )
    {
        pf->avg[PIXEL_16x8]  = x264_pixel_avg_16x8_avx512;
        pf->avg[PIXEL_8x16]  = x264_pixel_avg_8x16_avx512;
        pf->avg[PIXEL_8x8]   = x264_pixel_avg_8x8_avx512;
        pf->avg[PIXEL_8x4]   = x264_pixel_avg_8x4_avx512;
        pf->load_deinterleave_chroma_fdec = x264_load_deinterleave_chroma_fdec_avx512;
        pf->load_deinterleave_chroma_fenc = x264_load_deinterleave_chroma_fenc_avx512;
    }

    if( cpu&X264_CPU_AVX512ICL )
    {
#if ARCH_X86_64
        pf->frame_init_lowres_core = x264_frame_init_lowres_core_avx512icl;
        pf->plane_copy_interleave = plane_copy_interleave_icl;
        pf->plane_copy_deinterleave = x264_plane_copy_deinterleave_avx512icl;
        pf->integral_init4h = x264_integral_init4h_avx512icl;
        pf->integral_init8h = x264_integral_init8h_avx512icl;
        pf->plane_copy_deinterleave_rgb = x264_plane_copy_deinterleave_rgb_avx512icl;
        pf->weight_cache = x264_weight_cache_avx512icl;
        pf->weight_plane = weight_plane_icl8;
        pf->integral_init4v = x264_integral_init4v_avx512icl;
        pf->integral_init8v = x264_integral_init8v_avx512icl;
#endif
    }
#endif // HIGH_BIT_DEPTH

    if( !(cpu&X264_CPU_AVX) )
        return;
    pf->memzero_aligned = x264_memzero_aligned_avx;
    pf->mbtree_propagate_cost = x264_mbtree_propagate_cost_avx;
    pf->mbtree_propagate_list = x264_mbtree_propagate_list_avx;

    if( cpu&X264_CPU_FMA4 )
        pf->mbtree_propagate_cost = x264_mbtree_propagate_cost_fma4;

    if( !(cpu&X264_CPU_AVX2) )
        return;
    pf->memcpy_aligned = x264_memcpy_aligned_avx;
    pf->plane_copy = x264_plane_copy_avx2;
    pf->get_ref = get_ref_avx2;

    if( cpu&X264_CPU_FMA3 )
        pf->mbtree_propagate_cost = x264_mbtree_propagate_cost_avx2_fma3;

    if( !(cpu&X264_CPU_AVX512) )
        return;
    /* zen4 prune: memcpy_aligned avx512 8-bit 1.103x avx, 10-bit neutral (>= 1.000) on rack01 Zen 4; kept assembled */
    pf->memzero_aligned = x264_memzero_aligned_avx512;
    pf->plane_copy = x264_plane_copy_avx512;
    pf->mbtree_propagate_cost = x264_mbtree_propagate_cost_avx512;
#if ARCH_X86_64
    pf->mbtree_propagate_list = x264_mbtree_propagate_list_avx512;
#endif
}
