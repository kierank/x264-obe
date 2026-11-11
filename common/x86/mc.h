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

#define PROPAGATE_LIST_DECL( name )\
void name( x264_t *h, uint16_t *ref_costs, int16_t (*mvs)[2], int16_t *propagate_amount,\
           uint16_t *lowres_costs, int bipred_weight, int mb_y, int len, int list );
#define x264_mbtree_propagate_list_ssse3 x264_template(mbtree_propagate_list_ssse3)
#define x264_mbtree_propagate_list_avx x264_template(mbtree_propagate_list_avx)
#define x264_mbtree_propagate_list_avx2 x264_template(mbtree_propagate_list_avx2)
#define x264_mbtree_propagate_list_avx512 x264_template(mbtree_propagate_list_avx512)
#define x264_mbtree_propagate_list_strip_avx2 x264_template(mbtree_propagate_list_strip_avx2)
#define x264_mbtree_propagate_list_strip_avx512 x264_template(mbtree_propagate_list_strip_avx512)
PROPAGATE_LIST_DECL( x264_mbtree_propagate_list_ssse3 )
PROPAGATE_LIST_DECL( x264_mbtree_propagate_list_avx )
PROPAGATE_LIST_DECL( x264_mbtree_propagate_list_avx2 )
PROPAGATE_LIST_DECL( x264_mbtree_propagate_list_avx512 )
PROPAGATE_LIST_DECL( x264_mbtree_propagate_list_strip_avx2 )
PROPAGATE_LIST_DECL( x264_mbtree_propagate_list_strip_avx512 )
#undef PROPAGATE_LIST_DECL

#endif
