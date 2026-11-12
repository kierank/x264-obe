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

#endif
