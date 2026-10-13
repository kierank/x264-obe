/*****************************************************************************
 * me8.c: 8-bit motion search functions for high bit depth encodes
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

/* Compiled into the 8-bit pass only (SRCS_8). */

#include "common/common.h"
#include "me8.h"

#if BIT_DEPTH == 8

x264_me8_func_t *x264_me8_init( uint32_t cpu )
{
    x264_me8_func_t *pf = x264_malloc( sizeof(x264_me8_func_t) );
    if( !pf )
        return NULL;
    x264_pixel_function_t pixf;
    x264_mc_functions_t mc;
    x264_pixel_init( cpu, &pixf );
    x264_mc_init( cpu, &mc, 0 );
    for( int i = 0; i < 8; i++ )
    {
        pf->fpelcmp[i] = pixf.sad[i];
        pf->mbcmp[0][i] = pixf.sad[i];
        pf->mbcmp[1][i] = pixf.satd[i];
    }
    for( int i = 0; i < 7; i++ )
    {
        pf->fpelcmp_x3[i] = pixf.sad_x3[i];
        pf->fpelcmp_x4[i] = pixf.sad_x4[i];
        pf->fpelcmp_x3_min[i] = pixf.sad_x3_min[i];
        pf->fpelcmp_x4_min[i] = pixf.sad_x4_min[i];
        pf->fpelcmp_avg2[i] = pixf.sad_avg2[i];
        pf->mbcmp_avg2[0][i] = NULL;
        pf->mbcmp_avg2[1][i] = pixf.satd_avg2[i];
    }
    /* Every _min call of the fullpel search is a step of a serial chain (hex
     * steps, square refine). Chained, 16x16 sad_x3/x4 + the C argmin beats the
     * _min kernels (rack01 lat9: 73-75 vs 109 ticks); the other sizes keep
     * _min (in situ 8x8 28-31 cycles a call, no chained measurement). */
    pf->fpelcmp_x3_min[PIXEL_16x16] = NULL;
    pf->fpelcmp_x4_min[PIXEL_16x16] = NULL;
    for( int i = 0; i < 2; i++ )
        pf->satd_fenc_pre[i] = pixf.satd_fenc_pre[i];
    for( int i = 0; i < 4; i++ )
    {
        pf->satd_pre[i] = pixf.satd_pre[i];
        pf->satd_avg2_pre[i] = pixf.satd_avg2_pre[i];
    }
    pf->get_ref = mc.get_ref;
    pf->mc_luma = mc.mc_luma;
    return pf;
}

#endif
