/*****************************************************************************
 * mbcache.h: x86 macroblock neighbour cache
 *****************************************************************************
 * Copyright (C) 2026 Open Broadcast Systems Ltd
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

#ifndef X264_X86_MBCACHE_H
#define X264_X86_MBCACHE_H

#define DECL_LOAD_LEFT_MBAFF( fmt, cpu )\
void x264_mbcache_load_left_mbaff_##fmt##_##cpu( uint8_t nnz_cache[X264_SCAN8_SIZE], int8_t i4x4_cache[X264_SCAN8_LUMA_SIZE],\
                                                 uint8_t *nnz_top, uint8_t *nnz_bot, int8_t *i4x4_top, int8_t *i4x4_bot,\
                                                 int left_case );
#define x264_mbcache_load_left_mbaff_420_avx512icl x264_template(mbcache_load_left_mbaff_420_avx512icl)
#define x264_mbcache_load_left_mbaff_422_avx512icl x264_template(mbcache_load_left_mbaff_422_avx512icl)
#define x264_mbcache_load_left_mbaff_444_avx512icl x264_template(mbcache_load_left_mbaff_444_avx512icl)
DECL_LOAD_LEFT_MBAFF( 420, avx512icl )
DECL_LOAD_LEFT_MBAFF( 422, avx512icl )
DECL_LOAD_LEFT_MBAFF( 444, avx512icl )

#endif
