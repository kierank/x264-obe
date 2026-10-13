/*****************************************************************************
 * me8.h: 8-bit motion search functions for high bit depth encodes
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

#ifndef X264_ENCODER_ME8_H
#define X264_ENCODER_ME8_H

/* With analyse.i_me_8bit, a high bit depth encoder runs the motion search on
 * the 8-bit msb planes of its references (x264_frame_t.msb8) and an 8-bit copy
 * of the fenc, with the 8-bit pixel functions. These come from the 8-bit pass
 * of a --bit-depth=all build (encoder/me8.c, SRCS_8), so the table is typed with
 * uint8_t and is the same at both depths. Indices are PIXEL_*. */
typedef struct x264_me8_func_t
{
    /* sad: the fullpel search runs on DIA, HEX and UMH only, where fpelcmp is sad */
    int  (*fpelcmp[8])( uint8_t *fenc, intptr_t i_fenc, uint8_t *pix, intptr_t i_pix );
    void (*fpelcmp_x3[7])( uint8_t *fenc, uint8_t *pix0, uint8_t *pix1, uint8_t *pix2,
                           intptr_t i_stride, int scores[3] );
    void (*fpelcmp_x4[7])( uint8_t *fenc, uint8_t *pix0, uint8_t *pix1, uint8_t *pix2, uint8_t *pix3,
                           intptr_t i_stride, int scores[4] );
    /* as x264_pixel_cmp_x3/x4_min_t, NULL without asm */
    int  (*fpelcmp_x3_min[7])( uint8_t *fenc, uint8_t *pix0, uint8_t *pix1, uint8_t *pix2,
                               intptr_t i_stride, uint64_t bias01, uint64_t bias2_best );
    int  (*fpelcmp_x4_min[7])( uint8_t *fenc, uint8_t *pix0, uint8_t *pix1, uint8_t *pix2, uint8_t *pix3,
                               intptr_t i_stride, uint64_t bias01, uint64_t bias23, int best );
} x264_me8_func_t;

/* NULL on failure; freed with x264_free. Only in builds with the 8-bit pass. */
x264_me8_func_t *x264_me8_init( uint32_t cpu );

#endif
