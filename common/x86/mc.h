/*****************************************************************************
 * mc.h: x86 motion compensation
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

#ifndef X264_I386_MC_H
#define X264_I386_MC_H

#define x264_mc_init_mmx x264_template(mc_init_mmx)
void x264_mc_init_mmx( int cpu, x264_mc_functions_t *pf );

#define x264_mb_fref_load_avx2 x264_template(mb_fref_load_avx2)
void x264_mb_fref_load_avx2( pixel **dst, pixel **src, intptr_t off_y, intptr_t off_c, int n0, int n1 );
#define x264_mb_fref_load_avx512 x264_template(mb_fref_load_avx512)
void x264_mb_fref_load_avx512( pixel **dst, pixel **src, intptr_t off_y, intptr_t off_c, int n0, int n1 );
#if !HIGH_BIT_DEPTH
#define x264_hpel_filter_copy_vc_avx2 x264_template(hpel_filter_copy_vc_avx2)
void x264_hpel_filter_copy_vc_avx2( uint8_t *dsth, uint8_t *dstv, uint8_t *dstc, uint8_t *src, intptr_t stride, int width, int height, int16_t *buf, uint8_t *dstf );
#define x264_hpel_filter_dual_avx2 x264_template(hpel_filter_dual_avx2)
void x264_hpel_filter_dual_avx2( uint8_t *dsth, uint8_t *dstv, uint8_t *dstc, uint8_t *src, intptr_t stride, int width, int height, int16_t *buf, uint8_t *dsth2 );
#define x264_frame_init_lowres_core_pad_avx2 x264_template(frame_init_lowres_core_pad_avx2)
void x264_frame_init_lowres_core_pad_avx2( uint8_t *src0, uint8_t *dst0, uint8_t *dsth, uint8_t *dstv, uint8_t *dstc,
                                           intptr_t src_stride, intptr_t dst_stride, int width, int height );
#define x264_frame_init_lowres_core_pad_avx512icl x264_template(frame_init_lowres_core_pad_avx512icl)
void x264_frame_init_lowres_core_pad_avx512icl( uint8_t *src0, uint8_t *dst0, uint8_t *dsth, uint8_t *dstv, uint8_t *dstc,
                                                intptr_t src_stride, intptr_t dst_stride, int width, int height );
#define x264_hpel_filter_pad_avx2 x264_template(hpel_filter_pad_avx2)
void x264_hpel_filter_pad_avx2( uint8_t *dsth, uint8_t *dstv, uint8_t *dstc, uint8_t *src, intptr_t stride, int width, int height, int16_t *buf, uint8_t *dst );
#define x264_hpel_filter_copy_pad_avx2 x264_template(hpel_filter_copy_pad_avx2)
void x264_hpel_filter_copy_pad_avx2( uint8_t *dsth, uint8_t *dstv, uint8_t *dstc, uint8_t *src, intptr_t stride, int width, int height, int16_t *buf, uint8_t *dst );
#define x264_hpel_filter_copy_vc_pad_avx2 x264_template(hpel_filter_copy_vc_pad_avx2)
void x264_hpel_filter_copy_vc_pad_avx2( uint8_t *dsth, uint8_t *dstv, uint8_t *dstc, uint8_t *src, intptr_t stride, int width, int height, int16_t *buf, uint8_t *dst );
#define x264_hpel_filter_dual_pad_avx2 x264_template(hpel_filter_dual_pad_avx2)
void x264_hpel_filter_dual_pad_avx2( uint8_t *dsth, uint8_t *dstv, uint8_t *dstc, uint8_t *src, intptr_t stride, int width, int height, int16_t *buf, uint8_t *dst );
#define x264_hpel_filter_vc_pad_avx2 x264_template(hpel_filter_vc_pad_avx2)
void x264_hpel_filter_vc_pad_avx2( uint8_t *dsth, uint8_t *dstv, uint8_t *dstc, uint8_t *src, intptr_t stride, int width, int height, int16_t *buf, uint8_t *dst );
#define x264_expand_border_sides_avx2 x264_template(expand_border_sides_avx2)
void x264_expand_border_sides_avx2( uint8_t *pix, uint8_t *pix2, intptr_t stride, int width, int height, int b_chroma );
#endif
/* mbtree_propagate_list wrappers: the original (internal kernel + clipped adds), strip (the same
 * kernel + int32 strip in C), strip_asm (the strip kernels); list2: both lists of a B row */
#define PROPAGATE_LIST_DECL( name )\
void name( x264_t *h, uint16_t *ref_costs, int16_t (*mvs)[2], int16_t *propagate_amount,\
           uint16_t *lowres_costs, int bipred_weight, int mb_y, int len, int list );
#define PROPAGATE_LIST2_DECL( name )\
void name( x264_t *h, uint16_t *ref_costs0, uint16_t *ref_costs1, int16_t (*mvs0)[2], int16_t (*mvs1)[2],\
           int16_t *propagate_amount, uint16_t *lowres_costs, int bipred_weight0, int bipred_weight1,\
           int mb_y, int len );
#define x264_mbtree_propagate_list_ssse3 x264_template(mbtree_propagate_list_ssse3)
#define x264_mbtree_propagate_list_avx x264_template(mbtree_propagate_list_avx)
#define x264_mbtree_propagate_list_avx2 x264_template(mbtree_propagate_list_avx2)
#define x264_mbtree_propagate_list_avx512 x264_template(mbtree_propagate_list_avx512)
#define x264_mbtree_propagate_list_strip_avx2 x264_template(mbtree_propagate_list_strip_avx2)
#define x264_mbtree_propagate_list_strip_avx512 x264_template(mbtree_propagate_list_strip_avx512)
#define x264_mbtree_propagate_list2_strip_avx2 x264_template(mbtree_propagate_list2_strip_avx2)
#define x264_mbtree_propagate_list2_strip_avx512 x264_template(mbtree_propagate_list2_strip_avx512)
#define x264_mbtree_propagate_list_strip_asm_avx2 x264_template(mbtree_propagate_list_strip_asm_avx2)
#define x264_mbtree_propagate_list2_strip_asm_avx2 x264_template(mbtree_propagate_list2_strip_asm_avx2)
#define x264_mbtree_propagate_list_strip_asm_avx512 x264_template(mbtree_propagate_list_strip_asm_avx512)
#define x264_mbtree_propagate_list2_strip_asm_avx512 x264_template(mbtree_propagate_list2_strip_asm_avx512)
PROPAGATE_LIST_DECL( x264_mbtree_propagate_list_ssse3 )
PROPAGATE_LIST_DECL( x264_mbtree_propagate_list_avx )
PROPAGATE_LIST_DECL( x264_mbtree_propagate_list_avx2 )
PROPAGATE_LIST_DECL( x264_mbtree_propagate_list_avx512 )
PROPAGATE_LIST_DECL( x264_mbtree_propagate_list_strip_avx2 )
PROPAGATE_LIST_DECL( x264_mbtree_propagate_list_strip_avx512 )
PROPAGATE_LIST2_DECL( x264_mbtree_propagate_list2_strip_avx2 )
PROPAGATE_LIST2_DECL( x264_mbtree_propagate_list2_strip_avx512 )
PROPAGATE_LIST_DECL( x264_mbtree_propagate_list_strip_asm_avx2 )
PROPAGATE_LIST2_DECL( x264_mbtree_propagate_list2_strip_asm_avx2 )
PROPAGATE_LIST_DECL( x264_mbtree_propagate_list_strip_asm_avx512 )
PROPAGATE_LIST2_DECL( x264_mbtree_propagate_list2_strip_asm_avx512 )
#undef PROPAGATE_LIST_DECL
#undef PROPAGATE_LIST2_DECL

#endif
