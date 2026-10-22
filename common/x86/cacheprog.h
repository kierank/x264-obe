/*****************************************************************************
 * cacheprog.h: x86 progressive macroblock cache load/save
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

#ifndef X264_X86_CACHEPROG_H
#define X264_X86_CACHEPROG_H

#define DECL_SAVE_NNZ( fmt, cpu )\
void x264_cacheprog_save_nnz_##fmt##_##cpu( uint8_t nnz[48], uint8_t nnz_cache[X264_SCAN8_SIZE] );
#define x264_cacheprog_save_nnz_420_avx2 x264_template(cacheprog_save_nnz_420_avx2)
#define x264_cacheprog_save_nnz_422_avx2 x264_template(cacheprog_save_nnz_422_avx2)
#define x264_cacheprog_save_nnz_420_avx512 x264_template(cacheprog_save_nnz_420_avx512)
#define x264_cacheprog_save_nnz_422_avx512 x264_template(cacheprog_save_nnz_422_avx512)
DECL_SAVE_NNZ( 420, avx2 )
DECL_SAVE_NNZ( 422, avx2 )
DECL_SAVE_NNZ( 420, avx512 )
DECL_SAVE_NNZ( 422, avx512 )

#endif
