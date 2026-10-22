/*****************************************************************************
 * macroblock.c: macroblock common functions
 *****************************************************************************
 * Copyright (C) 2003-2014 x264 project
 *
 * Authors: Jason Garrett-Glaser <darkshikari@gmail.com>
 *          Laurent Aimar <fenrir@via.ecp.fr>
 *          Loren Merritt <lorenm@u.washington.edu>
 *          Henrik Gramner <henrik@gramner.com>
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

#include "common.h"
#include "encoder/me.h"

#define MC_LUMA(list,p,w) \
    h->mc.mc_luma( &h->mb.pic.p_fdec[p][4*y*FDEC_STRIDE+4*x], FDEC_STRIDE, \
                   &h->mb.pic.p_fref[list][i_ref][p*4], h->mb.pic.i_stride[p], \
                   mvx, mvy, 4*width, 4*height, w );

static NOINLINE void x264_mb_mc_0xywh( x264_t *h, int x, int y, int width, int height )
{
    int i8    = x264_scan8[0]+x+8*y;
    int i_ref = h->mb.cache.ref[0][i8];
    int mvx   = x264_clip3( h->mb.cache.mv[0][i8][0], h->mb.mv_min[0], h->mb.mv_max[0] ) + 4*4*x;
    int mvy   = x264_clip3( h->mb.cache.mv[0][i8][1], h->mb.mv_min[1], h->mb.mv_max[1] ) + 4*4*y;
    /* H.264 8.4.3: a field mb's explicit weights are those of refIdxL0 >> 1 */
    x264_weight_t *weight = h->sh.weight[i_ref >> MB_INTERLACED];

    MC_LUMA( 0, 0, &weight[0] );

    if( CHROMA444 )
    {
        MC_LUMA( 0, 1, &weight[1] );
        MC_LUMA( 0, 2, &weight[2] );
    }
    else
    {
        int v_shift = CHROMA_V_SHIFT;
        // Chroma in 4:2:0 is offset if MCing from a field of opposite parity
        if( v_shift & MB_INTERLACED & i_ref )
            mvy += (h->mb.i_mb_y & 1)*4 - 2;

        int offset = (4*FDEC_STRIDE>>v_shift)*y + 2*x;
        int uv_dy = 2*mvy>>v_shift;
        height = 4*height >> v_shift;

        h->mc.mc_chroma( &h->mb.pic.p_fdec[1][offset],
                         &h->mb.pic.p_fdec[2][offset], FDEC_STRIDE,
                         x264_mb_fref_uv( h, h->mb.pic.p_fref[0][i_ref], h->mb.pic.i_fld_uv_y, uv_dy, height ),
                         h->mb.pic.i_stride[1], mvx, uv_dy, 2*width, height );

        if( weight[1].weightfn )
            weight[1].weightfn[width>>1]( &h->mb.pic.p_fdec[1][offset], FDEC_STRIDE,
                                          &h->mb.pic.p_fdec[1][offset], FDEC_STRIDE,
                                          &weight[1], height );
        if( weight[2].weightfn )
            weight[2].weightfn[width>>1]( &h->mb.pic.p_fdec[2][offset], FDEC_STRIDE,
                                          &h->mb.pic.p_fdec[2][offset], FDEC_STRIDE,
                                          &weight[2], height );
    }
}
static NOINLINE void x264_mb_mc_1xywh( x264_t *h, int x, int y, int width, int height )
{
    int i8    = x264_scan8[0]+x+8*y;
    int i_ref = h->mb.cache.ref[1][i8];
    int mvx   = x264_clip3( h->mb.cache.mv[1][i8][0], h->mb.mv_min[0], h->mb.mv_max[0] ) + 4*4*x;
    int mvy   = x264_clip3( h->mb.cache.mv[1][i8][1], h->mb.mv_min[1], h->mb.mv_max[1] ) + 4*4*y;

    MC_LUMA( 1, 0, x264_weight_none );

    if( CHROMA444 )
    {
        MC_LUMA( 1, 1, x264_weight_none );
        MC_LUMA( 1, 2, x264_weight_none );
    }
    else
    {
        int v_shift = CHROMA_V_SHIFT;
        if( v_shift & MB_INTERLACED & i_ref )
            mvy += (h->mb.i_mb_y & 1)*4 - 2;

        int offset = (4*FDEC_STRIDE>>v_shift)*y + 2*x;
        int uv_dy = 2*mvy>>v_shift;
        height = 4*height >> v_shift;
        h->mc.mc_chroma( &h->mb.pic.p_fdec[1][offset],
                         &h->mb.pic.p_fdec[2][offset], FDEC_STRIDE,
                         x264_mb_fref_uv( h, h->mb.pic.p_fref[1][i_ref], h->mb.pic.i_fld_uv_y, uv_dy, height ),
                         h->mb.pic.i_stride[1], mvx, uv_dy, 2*width, height );
    }
}

#define MC_LUMA_BI(p) \
    src0 = h->mc.get_ref( tmp0, &i_stride0, &h->mb.pic.p_fref[0][i_ref0][p*4], h->mb.pic.i_stride[p], \
                          mvx0, mvy0, 4*width, 4*height, x264_weight_none ); \
    src1 = h->mc.get_ref( tmp1, &i_stride1, &h->mb.pic.p_fref[1][i_ref1][p*4], h->mb.pic.i_stride[p], \
                          mvx1, mvy1, 4*width, 4*height, x264_weight_none ); \
    h->mc.avg[i_mode]( &h->mb.pic.p_fdec[p][4*y*FDEC_STRIDE+4*x], FDEC_STRIDE, \
                       src0, i_stride0, src1, i_stride1, weight );

static NOINLINE void x264_mb_mc_01xywh( x264_t *h, int x, int y, int width, int height )
{
    int i8 = x264_scan8[0]+x+8*y;
    int i_ref0 = h->mb.cache.ref[0][i8];
    int i_ref1 = h->mb.cache.ref[1][i8];
    int weight = h->mb.bipred_weight[i_ref0][i_ref1];
    int mvx0   = x264_clip3( h->mb.cache.mv[0][i8][0], h->mb.mv_min[0], h->mb.mv_max[0] ) + 4*4*x;
    int mvx1   = x264_clip3( h->mb.cache.mv[1][i8][0], h->mb.mv_min[0], h->mb.mv_max[0] ) + 4*4*x;
    int mvy0   = x264_clip3( h->mb.cache.mv[0][i8][1], h->mb.mv_min[1], h->mb.mv_max[1] ) + 4*4*y;
    int mvy1   = x264_clip3( h->mb.cache.mv[1][i8][1], h->mb.mv_min[1], h->mb.mv_max[1] ) + 4*4*y;
    int i_mode = x264_size2pixel[height][width];
    intptr_t i_stride0 = 16, i_stride1 = 16;
    ALIGNED_ARRAY_N( pixel, tmp0,[16*16] );
    ALIGNED_ARRAY_N( pixel, tmp1,[16*16] );
    pixel *src0, *src1;

    MC_LUMA_BI( 0 );

    if( CHROMA444 )
    {
        MC_LUMA_BI( 1 );
        MC_LUMA_BI( 2 );
    }
    else
    {
        int v_shift = CHROMA_V_SHIFT;
        if( v_shift & MB_INTERLACED & i_ref0 )
            mvy0 += (h->mb.i_mb_y & 1)*4 - 2;
        if( v_shift & MB_INTERLACED & i_ref1 )
            mvy1 += (h->mb.i_mb_y & 1)*4 - 2;

        int uv_dy0 = 2*mvy0>>v_shift;
        int uv_dy1 = 2*mvy1>>v_shift;
        int chroma_height = 4*height>>v_shift;
        h->mc.mc_chroma( tmp0, tmp0+8, 16,
                         x264_mb_fref_uv( h, h->mb.pic.p_fref[0][i_ref0], h->mb.pic.i_fld_uv_y, uv_dy0, chroma_height ),
                         h->mb.pic.i_stride[1], mvx0, uv_dy0, 2*width, chroma_height );
        h->mc.mc_chroma( tmp1, tmp1+8, 16,
                         x264_mb_fref_uv( h, h->mb.pic.p_fref[1][i_ref1], h->mb.pic.i_fld_uv_y, uv_dy1, chroma_height ),
                         h->mb.pic.i_stride[1], mvx1, uv_dy1, 2*width, chroma_height );

        int chromapix = h->luma2chroma_pixel[i_mode];
        int offset = (4*FDEC_STRIDE>>v_shift)*y + 2*x;
        h->mc.avg[chromapix]( &h->mb.pic.p_fdec[1][offset], FDEC_STRIDE, tmp0,   16, tmp1,   16, weight );
        h->mc.avg[chromapix]( &h->mb.pic.p_fdec[2][offset], FDEC_STRIDE, tmp0+8, 16, tmp1+8, 16, weight );
    }
}

#undef MC_LUMA
#undef MC_LUMA_BI

void x264_mb_mc_8x8( x264_t *h, int i8 )
{
    int x = 2*(i8&1);
    int y = 2*(i8>>1);

    if( h->sh.i_type == SLICE_TYPE_P )
    {
        switch( h->mb.i_sub_partition[i8] )
        {
            case D_L0_8x8:
                x264_mb_mc_0xywh( h, x, y, 2, 2 );
                break;
            case D_L0_8x4:
                x264_mb_mc_0xywh( h, x, y+0, 2, 1 );
                x264_mb_mc_0xywh( h, x, y+1, 2, 1 );
                break;
            case D_L0_4x8:
                x264_mb_mc_0xywh( h, x+0, y, 1, 2 );
                x264_mb_mc_0xywh( h, x+1, y, 1, 2 );
                break;
            case D_L0_4x4:
                x264_mb_mc_0xywh( h, x+0, y+0, 1, 1 );
                x264_mb_mc_0xywh( h, x+1, y+0, 1, 1 );
                x264_mb_mc_0xywh( h, x+0, y+1, 1, 1 );
                x264_mb_mc_0xywh( h, x+1, y+1, 1, 1 );
                break;
        }
    }
    else
    {
        int scan8 = x264_scan8[0] + x + 8*y;

        if( h->mb.cache.ref[0][scan8] >= 0 )
            if( h->mb.cache.ref[1][scan8] >= 0 )
                x264_mb_mc_01xywh( h, x, y, 2, 2 );
            else
                x264_mb_mc_0xywh( h, x, y, 2, 2 );
        else
            x264_mb_mc_1xywh( h, x, y, 2, 2 );
    }
}

void x264_mb_mc( x264_t *h )
{
    if( h->mb.i_partition == D_8x8 )
    {
        for( int i = 0; i < 4; i++ )
            x264_mb_mc_8x8( h, i );
    }
    else
    {
        int ref0a = h->mb.cache.ref[0][x264_scan8[ 0]];
        int ref0b = h->mb.cache.ref[0][x264_scan8[12]];
        int ref1a = h->mb.cache.ref[1][x264_scan8[ 0]];
        int ref1b = h->mb.cache.ref[1][x264_scan8[12]];

        if( h->mb.i_partition == D_16x16 )
        {
            if( ref0a >= 0 )
                if( ref1a >= 0 ) x264_mb_mc_01xywh( h, 0, 0, 4, 4 );
                else             x264_mb_mc_0xywh ( h, 0, 0, 4, 4 );
            else                 x264_mb_mc_1xywh ( h, 0, 0, 4, 4 );
        }
        else if( h->mb.i_partition == D_16x8 )
        {
            if( ref0a >= 0 )
                if( ref1a >= 0 ) x264_mb_mc_01xywh( h, 0, 0, 4, 2 );
                else             x264_mb_mc_0xywh ( h, 0, 0, 4, 2 );
            else                 x264_mb_mc_1xywh ( h, 0, 0, 4, 2 );

            if( ref0b >= 0 )
                if( ref1b >= 0 ) x264_mb_mc_01xywh( h, 0, 2, 4, 2 );
                else             x264_mb_mc_0xywh ( h, 0, 2, 4, 2 );
            else                 x264_mb_mc_1xywh ( h, 0, 2, 4, 2 );
        }
        else if( h->mb.i_partition == D_8x16 )
        {
            if( ref0a >= 0 )
                if( ref1a >= 0 ) x264_mb_mc_01xywh( h, 0, 0, 2, 4 );
                else             x264_mb_mc_0xywh ( h, 0, 0, 2, 4 );
            else                 x264_mb_mc_1xywh ( h, 0, 0, 2, 4 );

            if( ref0b >= 0 )
                if( ref1b >= 0 ) x264_mb_mc_01xywh( h, 2, 0, 2, 4 );
                else             x264_mb_mc_0xywh ( h, 2, 0, 2, 4 );
            else                 x264_mb_mc_1xywh ( h, 2, 0, 2, 4 );
        }
    }
}

int x264_macroblock_cache_allocate( x264_t *h )
{
    int i_mb_count = h->mb.i_mb_count;

    h->mb.i_mb_stride = h->mb.i_mb_width;
    h->mb.i_b8_stride = h->mb.i_mb_width * 2;
    h->mb.i_b4_stride = h->mb.i_mb_width * 4;

    h->mb.b_interlaced = PARAM_INTERLACED;

    PREALLOC_INIT

    PREALLOC( h->mb.qp, i_mb_count * sizeof(int8_t) );
    PREALLOC( h->mb.cbp, i_mb_count * sizeof(int16_t) );
    PREALLOC( h->mb.mb_transform_size, i_mb_count * sizeof(int8_t) );
    PREALLOC( h->mb.slice_table, i_mb_count * sizeof(uint16_t) );

    /* 0 -> 3 top(4), 4 -> 6 : left(3) */
    PREALLOC( h->mb.intra4x4_pred_mode, i_mb_count * 8 * sizeof(int8_t) );

    /* all coeffs */
    PREALLOC( h->mb.non_zero_count, i_mb_count * 48 * sizeof(uint8_t) );

    if( h->param.b_cabac )
    {
        PREALLOC( h->mb.skipbp, i_mb_count * sizeof(int8_t) );
        PREALLOC( h->mb.chroma_pred_mode, i_mb_count * sizeof(int8_t) );
        PREALLOC( h->mb.mvd[0], i_mb_count * sizeof( **h->mb.mvd ) );
        if( h->param.i_bframe )
            PREALLOC( h->mb.mvd[1], i_mb_count * sizeof( **h->mb.mvd ) );
    }

    for( int i = 0; i < 2; i++ )
    {
        int i_refs = X264_MIN(X264_REF_MAX, (i ? 1 + !!h->param.i_bframe_pyramid : h->param.i_frame_reference) );
        if( h->param.analyse.i_weighted_pred == X264_WEIGHTP_SMART )
            i_refs = X264_MIN(X264_REF_MAX, i_refs + 1 + (BIT_DEPTH == 8)); //smart weights add two duplicate frames, one in >8-bit
        i_refs <<= PARAM_INTERLACED; /* field refs */

        for( int j = !i; j < i_refs; j++ )
            PREALLOC( h->mb.mvr[i][j], 2 * (i_mb_count + 1) * sizeof(int16_t) );
    }

    if( h->param.analyse.i_weighted_pred )
    {
        int i_padv = PADV << PARAM_INTERLACED;
        int luma_plane_size = 0;
        int numweightbuf;

        if( h->param.analyse.i_weighted_pred == X264_WEIGHTP_FAKE )
        {
            // only need buffer for lookahead
            if( !h->param.i_sync_lookahead || h == h->thread[h->param.i_threads] )
            {
                // Fake analysis only works on lowres
                luma_plane_size = h->fdec->i_stride_lowres * (h->mb.i_mb_height*8+2*i_padv);
                // Only need 1 buffer for analysis
                numweightbuf = 1;
            }
            else
                numweightbuf = 0;
        }
        else
        {
            /* Both ref and fenc is stored for 4:2:0 and 4:2:2 which means that 4:2:0 and 4:4:4
             * needs the same amount of space and 4:2:2 needs twice that much */
            luma_plane_size = h->fdec->i_stride[0] * (h->mb.i_mb_height*(16<<(CHROMA_FORMAT==CHROMA_422))+2*i_padv);

            if( h->param.analyse.i_weighted_pred == X264_WEIGHTP_SMART )
                //smart can weight one ref and one offset -1 in 8-bit
                numweightbuf = 1 + (BIT_DEPTH == 8);
            else
                //simple only has one weighted ref
                numweightbuf = 1;
        }

        for( int i = 0; i < numweightbuf; i++ )
            PREALLOC( h->mb.p_weight_buf[i], luma_plane_size * sizeof(pixel) );
        if( h->param.analyse.i_weighted_pred != X264_WEIGHTP_FAKE )
            PREALLOC( h->mb.p_weight_sums, X264_WEIGHT_SUMS * ((h->mb.i_mb_width + 15) & ~15) * h->mb.i_mb_height * sizeof(int32_t) );
    }

    PREALLOC_END( h->mb.base );

    memset( h->mb.slice_table, -1, i_mb_count * sizeof(uint16_t) );

    for( int i = 0; i < 2; i++ )
    {
        int i_refs = X264_MIN(X264_REF_MAX, (i ? 1 + !!h->param.i_bframe_pyramid : h->param.i_frame_reference) );
        if( h->param.analyse.i_weighted_pred == X264_WEIGHTP_SMART )
            i_refs = X264_MIN(X264_REF_MAX, i_refs + 1 + (BIT_DEPTH == 8)); //smart weights add two duplicate frames, one in >8-bit
        i_refs <<= PARAM_INTERLACED; /* field refs */

        for( int j = !i; j < i_refs; j++ )
        {
            M32( h->mb.mvr[i][j][0] ) = 0;
            h->mb.mvr[i][j]++;
        }
    }

    return 0;
fail:
    return -1;
}
void x264_macroblock_cache_free( x264_t *h )
{
    x264_free( h->mb.base );
}

int x264_macroblock_thread_allocate( x264_t *h, int b_lookahead )
{
    if( !b_lookahead )
    {
        for( int i = 0; i < (PARAM_INTERLACED ? 5 : 2); i++ )
            for( int j = 0; j < (CHROMA444 ? 3 : 2); j++ )
            {
                CHECKED_MALLOC( h->intra_border_backup[i][j], (h->sps->i_mb_width*16+32) * sizeof(pixel) );
                h->intra_border_backup[i][j] += 16;
            }
        for( int i = 0; i <= PARAM_INTERLACED; i++ )
        {
            if( h->param.b_sliced_threads )
            {
                /* Only allocate the first one, and allocate it for the whole frame, because we
                 * won't be deblocking until after the frame is fully encoded. */
                if( h == h->thread[0] && !i )
                    CHECKED_MALLOC( h->deblock_strength[0], sizeof(**h->deblock_strength) * h->mb.i_mb_count );
                else
                    h->deblock_strength[i] = h->thread[0]->deblock_strength[0];
            }
            else
                CHECKED_MALLOC( h->deblock_strength[i], sizeof(**h->deblock_strength) * h->mb.i_mb_width );
            h->deblock_strength[1] = h->deblock_strength[i];
        }
        if( PARAM_INTERLACED && h->mb.b_adaptive_mbaff && h->param.analyse.i_weighted_pred > 0
            && h->i_thread_frames > 1 && h->mb.i_mb_height*16 > h->param.i_height )
            for( int i = 0; i < (CHROMA444 ? 3 : 2); i++ )
            {
                int rows = 2*(16 >> (i && CHROMA_V_SHIFT)) + 2;
                CHECKED_MALLOCZERO( h->mb.fenc_bot[i], h->thread[0]->fdec->i_stride[i] * rows * sizeof(pixel) );
            }
    }

    /* Allocate scratch buffer */
    int scratch_size = 0;
    if( !b_lookahead )
    {
        int buf_hpel = (h->thread[0]->fdec->i_width[0]+48+32) * sizeof(int16_t);
        CHECKED_MALLOC( h->scratch_hpel, buf_hpel );
        int buf_ssim = h->param.analyse.b_ssim * 8 * (h->param.i_width/4+3) * sizeof(int);
        int me_range = X264_MIN(h->param.analyse.i_me_range, h->param.analyse.i_mv_range);
        int buf_tesa = (h->param.analyse.i_me_method >= X264_ME_ESA) *
            ((me_range*2+24) * sizeof(int16_t) + (me_range+4) * (me_range+1) * 4 * sizeof(mvsad_t));
        scratch_size = X264_MAX3( buf_hpel, buf_ssim, buf_tesa );
    }
    int buf_mbtree = h->param.rc.b_mb_tree * ALIGN( h->mb.i_mb_width * sizeof(int16_t), NATIVE_ALIGN );
    scratch_size = X264_MAX( scratch_size, buf_mbtree );
    if( scratch_size )
        CHECKED_MALLOC( h->scratch_buffer, scratch_size );
    else
        h->scratch_buffer = NULL;

    int buf_lookahead_threads = (h->mb.i_mb_height + (4 + 32) * h->param.i_lookahead_threads) * sizeof(int) * 2;
    int buf_mbtree2 = buf_mbtree * 12; /* size of the internal propagate_list asm buffer */
    scratch_size = X264_MAX( buf_lookahead_threads, buf_mbtree2 );
    CHECKED_MALLOC( h->scratch_buffer2, scratch_size );

    return 0;
fail:
    return -1;
}

void x264_macroblock_thread_free( x264_t *h, int b_lookahead )
{
    if( !b_lookahead )
    {
        for( int i = 0; i <= PARAM_INTERLACED; i++ )
            if( !h->param.b_sliced_threads || (h == h->thread[0] && !i) )
                x264_free( h->deblock_strength[i] );
        for( int i = 0; i < (PARAM_INTERLACED ? 5 : 2); i++ )
            for( int j = 0; j < (CHROMA444 ? 3 : 2); j++ )
                x264_free( h->intra_border_backup[i][j] - 16 );
        for( int i = 0; i < 3; i++ )
            x264_free( h->mb.fenc_bot[i] );
    }
    x264_free( h->scratch_buffer );
    x264_free( h->scratch_buffer2 );
    x264_free( h->scratch_hpel );
}

void x264_macroblock_slice_init( x264_t *h )
{
    h->mb.mv[0] = h->fdec->mv[0];
    h->mb.mv[1] = h->fdec->mv[1];
    h->mb.mvr[0][0] = h->fdec->mv16x16;
    h->mb.ref[0] = h->fdec->ref[0];
    h->mb.ref[1] = h->fdec->ref[1];
    h->mb.type = h->fdec->mb_type;
    h->mb.partition = h->fdec->mb_partition;
    h->mb.field = h->fdec->field;

    h->fdec->i_ref[0] = h->i_ref[0];
    h->fdec->i_ref[1] = h->i_ref[1];
    for( int i = 0; i < h->i_ref[0]; i++ )
        h->fdec->ref_poc[0][i] = h->fref[0][i]->i_poc;
    if( h->sh.i_type == SLICE_TYPE_B )
    {
        for( int i = 0; i < h->i_ref[1]; i++ )
            h->fdec->ref_poc[1][i] = h->fref[1][i]->i_poc;

        map_col_to_list0(-1) = -1;
        map_col_to_list0(-2) = -2;
        for( int i = 0; i < h->fref[1][0]->i_ref[0]; i++ )
        {
            int poc = h->fref[1][0]->ref_poc[0][i];
            map_col_to_list0(i) = -2;
            for( int j = 0; j < h->i_ref[0]; j++ )
                if( h->fref[0][j]->i_poc == poc )
                {
                    map_col_to_list0(i) = j;
                    break;
                }
        }
    }
    else if( h->sh.i_type == SLICE_TYPE_P )
    {
        if( h->sh.i_disable_deblocking_filter_idc != 1 && h->param.analyse.i_weighted_pred == X264_WEIGHTP_SMART )
        {
            /* [0] frame mbs, [1] field mbs: field ref i is field i&1 (same or
             * opposite parity) of frame ref i>>1. Edges between a frame and a
             * field mb don't compare refs (x264_macroblock_deblock_strength_mbaff);
             * the others are between frame mbs or same parity field mbs. */
            for( int f = 0; f <= SLICE_MBAFF; f++ )
            {
                h->mb.deblock_ref_table[f][0] = -2;
                h->mb.deblock_ref_table[f][1] = -1;
            }
            /* Mask off high bits to avoid frame num collisions with -1/-2.
             * In current x264 frame num values don't cover a range of more
             * than 32, so 6 bits is enough for uniqueness. */
            for( int i = 0; i < h->i_ref[0]; i++ )
                h->mb.deblock_ref_table[0][i+2] = h->fref[0][i]->i_frame_num&63;
            if( SLICE_MBAFF )
                for( int i = 0; i < h->i_ref[0] << 1; i++ )
                    h->mb.deblock_ref_table[1][i+2] = ((h->fref[0][i>>1]->i_frame_num&63)<<1) + (i&1);
        }
    }

    /* init with not available (for top right idx=7,15) */
    memset( h->mb.cache.ref, -2, sizeof( h->mb.cache.ref ) );

    if( h->i_ref[0] > 0 )
        for( int field = 0; field <= SLICE_MBAFF; field++ )
        {
            int curpoc = h->fdec->i_poc + h->fdec->i_delta_poc[field];
            int refpoc = h->fref[0][0]->i_poc + h->fref[0][0]->i_delta_poc[field];
            int delta = curpoc - refpoc;

            h->fdec->inv_ref_poc[field] = (256 + delta/2) / delta;
        }

    h->mb.i_neighbour4[6] =
    h->mb.i_neighbour4[9] =
    h->mb.i_neighbour4[12] =
    h->mb.i_neighbour4[14] = MB_LEFT|MB_TOP|MB_TOPLEFT|MB_TOPRIGHT;
    h->mb.i_neighbour4[3] =
    h->mb.i_neighbour4[7] =
    h->mb.i_neighbour4[11] =
    h->mb.i_neighbour4[13] =
    h->mb.i_neighbour4[15] =
    h->mb.i_neighbour8[3] = MB_LEFT|MB_TOP|MB_TOPLEFT;
}

void x264_macroblock_thread_init( x264_t *h )
{
    h->mb.i_me_method = h->param.analyse.i_me_method;
    h->mb.i_subpel_refine = h->param.analyse.i_subpel_refine;
    if( h->sh.i_type == SLICE_TYPE_B && (h->mb.i_subpel_refine == 6 || h->mb.i_subpel_refine == 8) )
        h->mb.i_subpel_refine--;
    h->mb.b_chroma_me = h->param.analyse.b_chroma_me &&
                        ((h->sh.i_type == SLICE_TYPE_P && h->mb.i_subpel_refine >= 5) ||
                         (h->sh.i_type == SLICE_TYPE_B && h->mb.i_subpel_refine >= 9));
    h->mb.b_dct_decimate = h->sh.i_type == SLICE_TYPE_B ||
                          (h->param.analyse.b_dct_decimate && h->sh.i_type != SLICE_TYPE_I);
    h->mb.i_mb_prev_xy = -1;

    /*          4:2:0                      4:2:2                      4:4:4
     * fdec            fenc       fdec            fenc       fdec            fenc
     * y y y y y y y   Y Y Y Y    y y y y y y y   Y Y Y Y    y y y y y y y   Y Y Y Y
     * y Y Y Y Y       Y Y Y Y    y Y Y Y Y       Y Y Y Y    y Y Y Y Y       Y Y Y Y
     * y Y Y Y Y       Y Y Y Y    y Y Y Y Y       Y Y Y Y    y Y Y Y Y       Y Y Y Y
     * y Y Y Y Y       Y Y Y Y    y Y Y Y Y       Y Y Y Y    y Y Y Y Y       Y Y Y Y
     * y Y Y Y Y       U U V V    y Y Y Y Y       U U V V    y Y Y Y Y       U U U U
     * u u u   v v v   U U V V    u u u   v v v   U U V V    u u u u u u u   U U U U
     * u U U   v V V              u U U   v V V   U U V V    u U U U U       U U U U
     * u U U   v V V              u U U   v V V   U U V V    u U U U U       U U U U
     *                            u U U   v V V              u U U U U       V V V V
     *                            u U U   v V V              u U U U U       V V V V
     *                                                       v v v v v v v   V V V V
     *                                                       v V V V V       V V V V
     *                                                       v V V V V
     *                                                       v V V V V
     *                                                       v V V V V
     */
    h->mb.pic.p_fenc[0] = h->mb.pic.fenc_buf;
    h->mb.pic.p_fdec[0] = h->mb.pic.fdec_buf + 2*FDEC_STRIDE;
    h->mb.pic.p_fenc[1] = h->mb.pic.fenc_buf + 16*FENC_STRIDE;
    h->mb.pic.p_fdec[1] = h->mb.pic.fdec_buf + 20*FDEC_STRIDE;
    if( CHROMA444 )
    {
        h->mb.pic.p_fenc[2] = h->mb.pic.fenc_buf + 32*FENC_STRIDE;
        h->mb.pic.p_fdec[2] = h->mb.pic.fdec_buf + 38*FDEC_STRIDE;
    }
    else
    {
        h->mb.pic.p_fenc[2] = h->mb.pic.fenc_buf + 16*FENC_STRIDE + 8;
        h->mb.pic.p_fdec[2] = h->mb.pic.fdec_buf + 20*FDEC_STRIDE + 16;
    }
}

void x264_prefetch_fenc( x264_t *h, x264_frame_t *fenc, int i_mb_x, int i_mb_y )
{
    int stride_y  = fenc->i_stride[0];
    int stride_uv = fenc->i_stride[1];
    int off_y  = 16 * i_mb_x + 16 * i_mb_y * stride_y;
    int off_uv = 16 * i_mb_x + (16 * i_mb_y * stride_uv >> CHROMA_V_SHIFT);
    h->mc.prefetch_fenc( fenc->plane[0]+off_y, stride_y,
                         fenc->plane[1]+off_uv, stride_uv, i_mb_x );
}

NOINLINE void x264_copy_column8( pixel *dst, pixel *src )
{
    // input pointers are offset by 4 rows because that's faster (smaller instruction size on x86)
    for( int i = -4; i < 4; i++ )
        dst[i*FDEC_STRIDE] = src[i*FDEC_STRIDE];
}

static void ALWAYS_INLINE x264_macroblock_load_pic_pointers( x264_t *h, int mb_x, int mb_y, int i, int b_chroma, int b_mbaff )
{
    int mb_interlaced = b_mbaff && MB_INTERLACED;
    int height = b_chroma ? 16 >> CHROMA_V_SHIFT : 16;
    int i_stride = h->fdec->i_stride[i];
    int i_stride2 = i_stride << mb_interlaced;
    int i_pix_offset = mb_interlaced
                     ? 16 * mb_x + height * (mb_y&~1) * i_stride + (mb_y&1) * i_stride
                     : 16 * mb_x + height * mb_y * i_stride;
    pixel *plane_fdec = &h->fdec->plane[i][i_pix_offset];
    int fdec_idx = b_mbaff ? (mb_interlaced ? (3 + (mb_y&1)) : (mb_y&1) ? 2 : 4) : !(mb_y&1);
    pixel *intra_fdec = &h->intra_border_backup[fdec_idx][i][mb_x*16];
    int ref_pix_offset[2] = { i_pix_offset, i_pix_offset };
    /* ref_pix_offset[0] references the current field and [1] the opposite field. */
    if( mb_interlaced )
        ref_pix_offset[1] += (1-2*(mb_y&1)) * i_stride;
    h->mb.pic.i_stride[i] = i_stride2;
    h->mb.pic.p_fenc_plane[i] = &h->fenc->plane[i][i_pix_offset];
    if( b_mbaff && h->mb.b_fenc_bot && mb_y >= h->mb.i_mb_height - 2 )
        h->mb.pic.p_fenc_plane[i] = h->mb.fenc_bot[i] + PADH + i_pix_offset - (height*(h->mb.i_mb_height-2) - 2) * i_stride;
    h->mb.pic.i_fenc_pre = 0;
    if( b_chroma )
    {
        h->mc.load_deinterleave_chroma_fenc( h->mb.pic.p_fenc[1], h->mb.pic.p_fenc_plane[1], i_stride2, height );
        memcpy( h->mb.pic.p_fdec[1]-FDEC_STRIDE, intra_fdec, 8*sizeof(pixel) );
        memcpy( h->mb.pic.p_fdec[2]-FDEC_STRIDE, intra_fdec+8, 8*sizeof(pixel) );
        h->mb.pic.p_fdec[1][-FDEC_STRIDE-1] = intra_fdec[-1-8];
        h->mb.pic.p_fdec[2][-FDEC_STRIDE-1] = intra_fdec[-1];
        h->mb.pic.i_fld_uv_y = height * (mb_y >> 1);
        h->mb.pic.i_fld_uv_lines = height * h->mb.i_mb_height >> 1;
    }
    else
    {
        h->mc.copy[PIXEL_16x16]( h->mb.pic.p_fenc[i], FENC_STRIDE, h->mb.pic.p_fenc_plane[i], i_stride2, 16 );
        memcpy( h->mb.pic.p_fdec[i]-FDEC_STRIDE, intra_fdec, 24*sizeof(pixel) );
        h->mb.pic.p_fdec[i][-FDEC_STRIDE-1] = intra_fdec[-1];
    }
    if( b_mbaff || h->mb.b_reencode_mb )
    {
        for( int j = 0; j < height; j++ )
            if( b_chroma )
            {
                h->mb.pic.p_fdec[1][-1+j*FDEC_STRIDE] = plane_fdec[-2+j*i_stride2];
                h->mb.pic.p_fdec[2][-1+j*FDEC_STRIDE] = plane_fdec[-1+j*i_stride2];
            }
            else
                h->mb.pic.p_fdec[i][-1+j*FDEC_STRIDE] = plane_fdec[-1+j*i_stride2];
    }
    pixel *plane_src, **filtered_src;
    for( int j = 0; j < h->mb.pic.i_fref[0]; j++ )
    {
        // Interpolate between pixels in same field.
        if( mb_interlaced )
        {
            plane_src = h->fref[0][j>>1]->plane_fld[i];
            filtered_src = h->fref[0][j>>1]->filtered_fld[i];
        }
        else
        {
            plane_src = h->fref[0][j]->plane[i];
            filtered_src = h->fref[0][j]->filtered[i];
        }
        h->mb.pic.p_fref[0][j][i*4] = plane_src + ref_pix_offset[j&1];

        if( !b_chroma )
        {
            for( int k = 1; k < 4; k++ )
                h->mb.pic.p_fref[0][j][i*4+k] = filtered_src[k] + ref_pix_offset[j&1];
            if( !i )
            {
                /* both fields of a weighted frame: rows of its weighted plane */
                if( h->sh.weight[j >> mb_interlaced][0].weightfn )
                    h->mb.pic.p_fref_w[j] = &h->fenc->weighted[j >> mb_interlaced][ref_pix_offset[j&1]];
                else
                    h->mb.pic.p_fref_w[j] = h->mb.pic.p_fref[0][j][0];
            }
        }
        else
        {
            h->mb.pic.p_fref[0][j][5] = plane_src + ref_pix_offset[j&1];
            h->mb.pic.p_fref[0][j][4] = h->fref[0][j >> mb_interlaced]->plane[i] + ref_pix_offset[j&1];
        }
    }
    if( h->sh.i_type == SLICE_TYPE_B )
        for( int j = 0; j < h->mb.pic.i_fref[1]; j++ )
        {
            if( mb_interlaced )
            {
                plane_src = h->fref[1][j>>1]->plane_fld[i];
                filtered_src = h->fref[1][j>>1]->filtered_fld[i];
            }
            else
            {
                plane_src = h->fref[1][j]->plane[i];
                filtered_src = h->fref[1][j]->filtered[i];
            }
            h->mb.pic.p_fref[1][j][i*4] = plane_src + ref_pix_offset[j&1];

            if( !b_chroma )
                for( int k = 1; k < 4; k++ )
                    h->mb.pic.p_fref[1][j][i*4+k] = filtered_src[k] + ref_pix_offset[j&1];
            else
            {
                h->mb.pic.p_fref[1][j][5] = plane_src + ref_pix_offset[j&1];
                h->mb.pic.p_fref[1][j][4] = h->fref[1][j >> mb_interlaced]->plane[i] + ref_pix_offset[j&1];
            }
        }
}

static const x264_left_table_t left_indices[4] =
{
    /* Current is progressive */
    {{ 4, 4, 5, 5}, { 3,  3,  7,  7}, {16+1, 16+1, 32+1, 32+1}, {0, 0, 1, 1}, {0, 0, 0, 0}},
    {{ 6, 6, 3, 3}, {11, 11, 15, 15}, {16+5, 16+5, 32+5, 32+5}, {2, 2, 3, 3}, {1, 1, 1, 1}},
    /* Current is interlaced */
    {{ 4, 6, 4, 6}, { 3, 11,  3, 11}, {16+1, 16+1, 32+1, 32+1}, {0, 2, 0, 2}, {0, 1, 0, 1}},
    /* Both same */
    {{ 4, 5, 6, 3}, { 3,  7, 11, 15}, {16+1, 16+5, 32+1, 32+5}, {0, 1, 2, 3}, {0, 0, 1, 1}}
};

static void ALWAYS_INLINE x264_macroblock_cache_load_neighbours( x264_t *h, int mb_x, int mb_y, int b_interlaced )
{
    const int mb_interlaced = b_interlaced && MB_INTERLACED;
    int top_y = mb_y - (1 << mb_interlaced);
    int top = top_y * h->mb.i_mb_stride + mb_x;

    h->mb.i_mb_x = mb_x;
    h->mb.i_mb_y = mb_y;
    h->mb.i_mb_xy = mb_y * h->mb.i_mb_stride + mb_x;
    h->mb.i_b8_xy = 2*(mb_y * h->mb.i_b8_stride + mb_x);
    h->mb.i_b4_xy = 4*(mb_y * h->mb.i_b4_stride + mb_x);
    h->mb.left_b8[0] =
    h->mb.left_b8[1] = -1;
    h->mb.left_b4[0] =
    h->mb.left_b4[1] = -1;
    h->mb.i_neighbour = 0;
    h->mb.i_neighbour_intra = 0;
    h->mb.i_neighbour_frame = 0;
    h->mb.i_mb_top_xy = -1;
    h->mb.i_mb_top_y = -1;
    h->mb.i_mb_left_xy[0] = h->mb.i_mb_left_xy[1] = -1;
    h->mb.i_mb_topleft_xy = -1;
    h->mb.i_mb_topright_xy = -1;
    h->mb.i_mb_type_top = -1;
    h->mb.i_mb_type_left[0] = h->mb.i_mb_type_left[1] = -1;
    h->mb.i_mb_type_topleft = -1;
    h->mb.i_mb_type_topright = -1;
    h->mb.left_index_table = &left_indices[3];
    h->mb.topleft_partition = 0;

    int topleft_y = top_y;
    int topright_y = top_y;
    int left[2];

    left[0] = left[1] = h->mb.i_mb_xy - 1;
    h->mb.left_b8[0] = h->mb.left_b8[1] = h->mb.i_b8_xy - 2;
    h->mb.left_b4[0] = h->mb.left_b4[1] = h->mb.i_b4_xy - 4;

    if( b_interlaced )
    {
        h->mb.i_mb_top_mbpair_xy = h->mb.i_mb_xy - 2*h->mb.i_mb_stride;
        h->mb.i_mb_topleft_y = -1;
        h->mb.i_mb_topright_y = -1;

        if( mb_y&1 )
        {
            if( mb_x && mb_interlaced != h->mb.field[h->mb.i_mb_xy-1] )
            {
                left[0] = left[1] = h->mb.i_mb_xy - 1 - h->mb.i_mb_stride;
                h->mb.left_b8[0] = h->mb.left_b8[1] = h->mb.i_b8_xy - 2 - 2*h->mb.i_b8_stride;
                h->mb.left_b4[0] = h->mb.left_b4[1] = h->mb.i_b4_xy - 4 - 4*h->mb.i_b4_stride;

                if( mb_interlaced )
                {
                    h->mb.left_index_table = &left_indices[2];
                    left[1] += h->mb.i_mb_stride;
                    h->mb.left_b8[1] += 2*h->mb.i_b8_stride;
                    h->mb.left_b4[1] += 4*h->mb.i_b4_stride;
                }
                else
                {
                    h->mb.left_index_table = &left_indices[1];
                    topleft_y++;
                    h->mb.topleft_partition = 1;
                }
            }
            if( !mb_interlaced )
                topright_y = -1;
        }
        else
        {
            /* Unused at the threadslice start, where the previous threadslice may still write it. */
            if( mb_interlaced && top >= 0 && (h->i_threadslice_start >> 1) != (mb_y >> 1) )
            {
                if( !h->mb.field[top] )
                {
                    top += h->mb.i_mb_stride;
                    top_y++;
                }
                if( mb_x )
                    topleft_y += !h->mb.field[h->mb.i_mb_stride*topleft_y + mb_x - 1];
                if( mb_x < h->mb.i_mb_width-1 )
                    topright_y += !h->mb.field[h->mb.i_mb_stride*topright_y + mb_x + 1];
            }
            if( mb_x && mb_interlaced != h->mb.field[h->mb.i_mb_xy-1] )
            {
                if( mb_interlaced )
                {
                    h->mb.left_index_table = &left_indices[2];
                    left[1] += h->mb.i_mb_stride;
                    h->mb.left_b8[1] += 2*h->mb.i_b8_stride;
                    h->mb.left_b4[1] += 4*h->mb.i_b4_stride;
                }
                else
                    h->mb.left_index_table = &left_indices[0];
            }
        }
    }

    if( mb_x > 0 )
    {
        h->mb.i_neighbour_frame |= MB_LEFT;
        h->mb.i_mb_left_xy[0] = left[0];
        h->mb.i_mb_left_xy[1] = left[1];
        h->mb.i_mb_type_left[0] = h->mb.type[h->mb.i_mb_left_xy[0]];
        h->mb.i_mb_type_left[1] = h->mb.type[h->mb.i_mb_left_xy[1]];
        if( h->mb.slice_table[left[0]] == h->sh.i_first_mb )
        {
            h->mb.i_neighbour |= MB_LEFT;

            // FIXME: We don't currently support constrained intra + mbaff.
            if( !h->param.b_constrained_intra || IS_INTRA( h->mb.i_mb_type_left[0] ) )
                h->mb.i_neighbour_intra |= MB_LEFT;
        }
    }

    /* We can't predict from the previous threadslice since it hasn't been encoded yet. */
    if( (h->i_threadslice_start >> mb_interlaced) != (mb_y >> mb_interlaced) )
    {
        if( top >= 0 )
        {
            h->mb.i_neighbour_frame |= MB_TOP;
            h->mb.i_mb_top_xy = top;
            h->mb.i_mb_top_y = top_y;
            h->mb.i_mb_type_top = h->mb.type[h->mb.i_mb_top_xy];
            if( h->mb.slice_table[top] == h->sh.i_first_mb )
            {
                h->mb.i_neighbour |= MB_TOP;

                if( !h->param.b_constrained_intra || IS_INTRA( h->mb.i_mb_type_top ) )
                    h->mb.i_neighbour_intra |= MB_TOP;

                /* We only need to prefetch the top blocks because the left was just written
                 * to as part of the previous cache_save.  Since most target CPUs use write-allocate
                 * caches, left blocks are near-guaranteed to be in L1 cache.  Top--not so much. */
                x264_prefetch( &h->mb.cbp[top] );
                x264_prefetch( h->mb.intra4x4_pred_mode[top] );
                x264_prefetch( &h->mb.non_zero_count[top][12] );
                /* These aren't always allocated, but prefetching an invalid address can't hurt. */
                x264_prefetch( &h->mb.mb_transform_size[top] );
                x264_prefetch( &h->mb.skipbp[top] );
            }
        }

        if( mb_x > 0 && topleft_y >= 0  )
        {
            h->mb.i_neighbour_frame |= MB_TOPLEFT;
            h->mb.i_mb_topleft_xy = h->mb.i_mb_stride*topleft_y + mb_x - 1;
            h->mb.i_mb_topleft_y = topleft_y;
            h->mb.i_mb_type_topleft = h->mb.type[h->mb.i_mb_topleft_xy];
            if( h->mb.slice_table[h->mb.i_mb_topleft_xy] == h->sh.i_first_mb )
            {
                h->mb.i_neighbour |= MB_TOPLEFT;

                if( !h->param.b_constrained_intra || IS_INTRA( h->mb.i_mb_type_topleft ) )
                    h->mb.i_neighbour_intra |= MB_TOPLEFT;
            }
        }

        if( mb_x < h->mb.i_mb_width - 1 && topright_y >= 0 )
        {
            h->mb.i_neighbour_frame |= MB_TOPRIGHT;
            h->mb.i_mb_topright_xy = h->mb.i_mb_stride*topright_y + mb_x + 1;
            h->mb.i_mb_topright_y = topright_y;
            h->mb.i_mb_type_topright = h->mb.type[h->mb.i_mb_topright_xy];
            if( h->mb.slice_table[h->mb.i_mb_topright_xy] == h->sh.i_first_mb )
            {
                h->mb.i_neighbour |= MB_TOPRIGHT;

                if( !h->param.b_constrained_intra || IS_INTRA( h->mb.i_mb_type_topright ) )
                    h->mb.i_neighbour_intra |= MB_TOPRIGHT;
            }
        }
    }
}

/* i_neighbour8/i_neighbour4 of a progressive MB by its i_neighbour_intra, the entries
 * x264_macroblock_slice_init sets included */
#define NB_A(n) (((n)&(MB_TOP|MB_LEFT|MB_TOPLEFT)) | (((n)&MB_TOP) ? MB_TOPRIGHT : 0))
#define NB_B(n) (MB_LEFT | (((n)&MB_TOP) ? (MB_TOP|MB_TOPLEFT|MB_TOPRIGHT) : 0))
#define NB_C(n) (MB_TOP|MB_TOPRIGHT | (((n)&MB_LEFT) ? (MB_LEFT|MB_TOPLEFT) : 0))
#define NB_D(n) (MB_LEFT | ((n)&MB_TOPRIGHT) | (((n)&MB_TOP) ? MB_TOP|MB_TOPLEFT : 0))
#define NB_E    (MB_LEFT|MB_TOP|MB_TOPLEFT|MB_TOPRIGHT)
#define NB_F    (MB_LEFT|MB_TOP|MB_TOPLEFT)
#define NB_ROW(n) {{ NB_A(n), NB_D(n), NB_C(n), NB_F },\
                   { NB_A(n), NB_B(n), NB_C(n), NB_F, NB_B(n), NB_D(n), NB_E, NB_F,\
                     NB_C(n), NB_E, NB_C(n), NB_F, NB_E, NB_F, NB_E, NB_F }}
static const struct { unsigned int n8[4], n4[16]; } neighbour_rows[16] =
{
    NB_ROW(0),  NB_ROW(1),  NB_ROW(2),  NB_ROW(3),  NB_ROW(4),  NB_ROW(5),  NB_ROW(6),  NB_ROW(7),
    NB_ROW(8),  NB_ROW(9),  NB_ROW(10), NB_ROW(11), NB_ROW(12), NB_ROW(13), NB_ROW(14), NB_ROW(15),
};
#undef NB_ROW
#undef NB_F
#undef NB_E
#undef NB_D
#undef NB_C
#undef NB_B
#undef NB_A

static ALWAYS_INLINE void cacheprog_save_nnz( uint8_t nnz[48], uint8_t nnz_cache[X264_SCAN8_SIZE], int cf )
{
    CP32( &nnz[ 0+0*4], &nnz_cache[x264_scan8[ 0]] );
    CP32( &nnz[ 0+1*4], &nnz_cache[x264_scan8[ 2]] );
    CP32( &nnz[ 0+2*4], &nnz_cache[x264_scan8[ 8]] );
    CP32( &nnz[ 0+3*4], &nnz_cache[x264_scan8[10]] );
    CP32( &nnz[16+0*4], &nnz_cache[x264_scan8[16+0]] );
    CP32( &nnz[16+1*4], &nnz_cache[x264_scan8[16+2]] );
    CP32( &nnz[32+0*4], &nnz_cache[x264_scan8[32+0]] );
    CP32( &nnz[32+1*4], &nnz_cache[x264_scan8[32+2]] );
    if( cf == CHROMA_422 )
    {
        CP32( &nnz[16+2*4], &nnz_cache[x264_scan8[16+ 8]] );
        CP32( &nnz[16+3*4], &nnz_cache[x264_scan8[16+10]] );
        CP32( &nnz[32+2*4], &nnz_cache[x264_scan8[32+ 8]] );
        CP32( &nnz[32+3*4], &nnz_cache[x264_scan8[32+10]] );
    }
}

void x264_cacheprog_save_nnz_420_c( uint8_t nnz[48], uint8_t nnz_cache[X264_SCAN8_SIZE] )
{
    cacheprog_save_nnz( nnz, nnz_cache, CHROMA_420 );
}

void x264_cacheprog_save_nnz_422_c( uint8_t nnz[48], uint8_t nnz_cache[X264_SCAN8_SIZE] )
{
    cacheprog_save_nnz( nnz, nnz_cache, CHROMA_422 );
}

/* the rows load_nnz reads for an unavailable neighbour */
static const ALIGNED_64( uint8_t cacheprog_nnz_unavail[64] ) =
{
    0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,
    0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,
    0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,
    0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,
};
static const ALIGNED_8( int8_t cacheprog_i4x4_unavail[8] ) = { -1, -1, -1, -1, -1, -1, -1, -1 };

static ALWAYS_INLINE void cacheprog_load_nnz( uint8_t nnz_cache[X264_SCAN8_SIZE], int8_t i4x4_cache[X264_SCAN8_LUMA_SIZE],
                                              uint8_t *nnz_top, uint8_t *nnz_left, int8_t *i4x4_top, int8_t *i4x4_left, int cf )
{
    const int v_shift = cf == CHROMA_420;
    CP32( &i4x4_cache[x264_scan8[0] - 8], &i4x4_top[0] );
    CP32( &nnz_cache[x264_scan8[ 0] - 8], &nnz_top[12] );
    CP32( &nnz_cache[x264_scan8[16] - 8], &nnz_top[16-4 + (16>>v_shift)] );
    CP32( &nnz_cache[x264_scan8[32] - 8], &nnz_top[32-4 + (16>>v_shift)] );
    i4x4_cache[x264_scan8[ 0] - 1] = i4x4_left[4];
    i4x4_cache[x264_scan8[ 2] - 1] = i4x4_left[5];
    i4x4_cache[x264_scan8[ 8] - 1] = i4x4_left[6];
    i4x4_cache[x264_scan8[10] - 1] = i4x4_left[3];
    nnz_cache[x264_scan8[ 0] - 1] = nnz_left[ 3];
    nnz_cache[x264_scan8[ 2] - 1] = nnz_left[ 7];
    nnz_cache[x264_scan8[ 8] - 1] = nnz_left[11];
    nnz_cache[x264_scan8[10] - 1] = nnz_left[15];
    nnz_cache[x264_scan8[16+ 0] - 1] = nnz_left[16+1];
    nnz_cache[x264_scan8[16+ 2] - 1] = nnz_left[16+5];
    nnz_cache[x264_scan8[32+ 0] - 1] = nnz_left[32+1];
    nnz_cache[x264_scan8[32+ 2] - 1] = nnz_left[32+5];
    if( cf == CHROMA_422 )
    {
        nnz_cache[x264_scan8[16+ 8] - 1] = nnz_left[16+ 9];
        nnz_cache[x264_scan8[16+10] - 1] = nnz_left[16+13];
        nnz_cache[x264_scan8[32+ 8] - 1] = nnz_left[32+ 9];
        nnz_cache[x264_scan8[32+10] - 1] = nnz_left[32+13];
    }
}

void x264_cacheprog_load_nnz_420_c( uint8_t nnz_cache[X264_SCAN8_SIZE], int8_t i4x4_cache[X264_SCAN8_LUMA_SIZE],
                                    uint8_t *nnz_top, uint8_t *nnz_left, int8_t *i4x4_top, int8_t *i4x4_left )
{
    cacheprog_load_nnz( nnz_cache, i4x4_cache, nnz_top, nnz_left, i4x4_top, i4x4_left, CHROMA_420 );
}

void x264_cacheprog_load_nnz_422_c( uint8_t nnz_cache[X264_SCAN8_SIZE], int8_t i4x4_cache[X264_SCAN8_LUMA_SIZE],
                                    uint8_t *nnz_top, uint8_t *nnz_left, int8_t *i4x4_top, int8_t *i4x4_left )
{
    cacheprog_load_nnz( nnz_cache, i4x4_cache, nnz_top, nnz_left, i4x4_top, i4x4_left, CHROMA_422 );
}

static ALWAYS_INLINE void cacheprog_load_border( pixel *fdec_y, pixel *fdec_u, pixel *intra_y, pixel *intra_c, int cf )
{
    pixel *fdec_v = fdec_u + 16;
    for( int i = 0; i < 16; i++ )
        fdec_y[-1+i*FDEC_STRIDE] = fdec_y[15+i*FDEC_STRIDE];
    memcpy( fdec_y-FDEC_STRIDE, intra_y, 24*sizeof(pixel) );
    fdec_y[-FDEC_STRIDE-1] = intra_y[-1];
    for( int i = 0; i < (cf == CHROMA_422 ? 16 : 8); i++ )
    {
        fdec_u[-1+i*FDEC_STRIDE] = fdec_u[7+i*FDEC_STRIDE];
        fdec_v[-1+i*FDEC_STRIDE] = fdec_v[7+i*FDEC_STRIDE];
    }
    memcpy( fdec_u-FDEC_STRIDE, intra_c, 8*sizeof(pixel) );
    memcpy( fdec_v-FDEC_STRIDE, intra_c+8, 8*sizeof(pixel) );
    fdec_u[-FDEC_STRIDE-1] = intra_c[-1-8];
    fdec_v[-FDEC_STRIDE-1] = intra_c[-1];
}

void x264_cacheprog_load_border_420_c( pixel *fdec_y, pixel *fdec_u, pixel *intra_y, pixel *intra_c )
{
    cacheprog_load_border( fdec_y, fdec_u, intra_y, intra_c, CHROMA_420 );
}

void x264_cacheprog_load_border_422_c( pixel *fdec_y, pixel *fdec_u, pixel *intra_y, pixel *intra_c )
{
    cacheprog_load_border( fdec_y, fdec_u, intra_y, intra_c, CHROMA_422 );
}

#if HAVE_MMX
#include "x86/cacheprog.h"
#endif

/* layout twins of wip/x264-cacheprog: every build declares the hidden weak
 * x264_N_twin_cacheprog_*; a kernel set to 1 below dispatches its twin, which
 * links as 0, so its slot stays NULL and cache_load/cache_save run the C */
#if HAVE_MMX
#define CP_TWIN_SAVE   1
#define CP_TWIN_NNZ    1
#define CP_TWIN_BORDER 0
#define CP_STR( x ) #x
#define CP_XSTR( x ) CP_STR( x )
#define CP_TWIN1( f ) \
    extern __typeof__( x264_cacheprog_##f ) x264_template(twin_cacheprog_##f) __attribute__((weak, visibility("hidden"))); \
    __asm__( ".weak " CP_XSTR( x264_template(twin_cacheprog_##f) ) "\n.hidden " CP_XSTR( x264_template(twin_cacheprog_##f) ) );
CP_TWIN1( save_nnz_420_avx2 )
CP_TWIN1( save_nnz_422_avx2 )
CP_TWIN1( save_nnz_420_avx512 )
CP_TWIN1( save_nnz_422_avx512 )
CP_TWIN1( load_nnz_420_avx512icl )
CP_TWIN1( load_nnz_422_avx512icl )
CP_TWIN1( load_border_420_avx512icl )
CP_TWIN1( load_border_422_avx512icl )
/* the kernels themselves stay in the link in every arm */
static void (*const cp_twin_keep[])( void ) __attribute__((used)) =
{
    (void (*)( void ))x264_cacheprog_save_nnz_420_avx2, (void (*)( void ))x264_cacheprog_save_nnz_422_avx2,
    (void (*)( void ))x264_cacheprog_save_nnz_420_avx512, (void (*)( void ))x264_cacheprog_save_nnz_422_avx512,
    (void (*)( void ))x264_cacheprog_load_nnz_420_avx512icl, (void (*)( void ))x264_cacheprog_load_nnz_422_avx512icl,
    (void (*)( void ))x264_cacheprog_load_border_420_avx512icl, (void (*)( void ))x264_cacheprog_load_border_422_avx512icl,
};
#if CP_TWIN_SAVE
#undef x264_cacheprog_save_nnz_420_avx2
#define x264_cacheprog_save_nnz_420_avx2 x264_template(twin_cacheprog_save_nnz_420_avx2)
#undef x264_cacheprog_save_nnz_422_avx2
#define x264_cacheprog_save_nnz_422_avx2 x264_template(twin_cacheprog_save_nnz_422_avx2)
#undef x264_cacheprog_save_nnz_420_avx512
#define x264_cacheprog_save_nnz_420_avx512 x264_template(twin_cacheprog_save_nnz_420_avx512)
#undef x264_cacheprog_save_nnz_422_avx512
#define x264_cacheprog_save_nnz_422_avx512 x264_template(twin_cacheprog_save_nnz_422_avx512)
#endif
#if CP_TWIN_NNZ
#undef x264_cacheprog_load_nnz_420_avx512icl
#define x264_cacheprog_load_nnz_420_avx512icl x264_template(twin_cacheprog_load_nnz_420_avx512icl)
#undef x264_cacheprog_load_nnz_422_avx512icl
#define x264_cacheprog_load_nnz_422_avx512icl x264_template(twin_cacheprog_load_nnz_422_avx512icl)
#endif
#if CP_TWIN_BORDER
#undef x264_cacheprog_load_border_420_avx512icl
#define x264_cacheprog_load_border_420_avx512icl x264_template(twin_cacheprog_load_border_420_avx512icl)
#undef x264_cacheprog_load_border_422_avx512icl
#define x264_cacheprog_load_border_422_avx512icl x264_template(twin_cacheprog_load_border_422_avx512icl)
#endif
#endif

void x264_cacheprog_init( int cpu, x264_cacheprog_function_t *pf, int chroma_format )
{
    memset( pf, 0, sizeof(*pf) );
    if( chroma_format != CHROMA_420 && chroma_format != CHROMA_422 )
        return;
#if HAVE_MMX
    int b_422 = chroma_format == CHROMA_422;
    if( cpu&X264_CPU_AVX2 )
    {
        pf->save_nnz = b_422 ? x264_cacheprog_save_nnz_422_avx2 : x264_cacheprog_save_nnz_420_avx2;
    }
    if( cpu&X264_CPU_AVX512 )
    {
        pf->save_nnz = b_422 ? x264_cacheprog_save_nnz_422_avx512 : x264_cacheprog_save_nnz_420_avx512;
    }
    if( cpu&X264_CPU_AVX512ICL )
    {
        pf->load_nnz = b_422 ? x264_cacheprog_load_nnz_422_avx512icl : x264_cacheprog_load_nnz_420_avx512icl;
        pf->load_border = b_422 ? x264_cacheprog_load_border_422_avx512icl : x264_cacheprog_load_border_420_avx512icl;
    }
#endif
}

/* Reencode: the left column from the frame, progressive 4:2:0 or 4:2:2 */
static NOINLINE void x264_macroblock_load_left_reencode( x264_t *h, int off_y, int off_c, int height_c )
{
    pixel *fdec_y = h->mb.pic.p_fdec[0];
    pixel *fdec_u = h->mb.pic.p_fdec[1];
    pixel *fdec_v = h->mb.pic.p_fdec[2];
    int stride_y = h->fdec->i_stride[0];
    int stride_c = h->fdec->i_stride[1];
    pixel *plane_y = &h->fdec->plane[0][off_y];
    pixel *plane_c = &h->fdec->plane[1][off_c];
    for( int j = 0; j < 16; j++ )
        fdec_y[-1+j*FDEC_STRIDE] = plane_y[-1+j*stride_y];
    for( int j = 0; j < height_c; j++ )
    {
        fdec_u[-1+j*FDEC_STRIDE] = plane_c[-2+j*stride_c];
        fdec_v[-1+j*FDEC_STRIDE] = plane_c[-1+j*stride_c];
    }
}

static NOINLINE void x264_macroblock_load_integral( x264_t *h, int mb_x, int mb_y )
{
    int offset = 16 * (mb_x + mb_y * h->fdec->i_stride[0]);
    for( int list = 0; list < 2; list++ )
        for( int i = 0; i < h->mb.pic.i_fref[list]; i++ )
            h->mb.pic.p_integral[list][i] = &h->fref[list][i]->integral[offset];
}

/* intra4x4 and non_zero_count of the top and left MBs, or the unavailable values */
static ALWAYS_INLINE void x264_macroblock_load_nnz_prog( x264_t *h, unsigned int neighbour, int top, int left, int cf )
{
    const int v_shift = cf == CHROMA_420;
    int8_t (*i4x4)[8] = h->mb.intra4x4_pred_mode;
    uint8_t (*nnz)[48] = h->mb.non_zero_count;
    if( neighbour & MB_TOP )
    {
        CP32( &h->mb.cache.intra4x4_pred_mode[x264_scan8[0] - 8], &i4x4[top][0] );
        CP32( &h->mb.cache.non_zero_count[x264_scan8[ 0] - 8], &nnz[top][12] );
        CP32( &h->mb.cache.non_zero_count[x264_scan8[16] - 8], &nnz[top][16-4 + (16>>v_shift)] );
        CP32( &h->mb.cache.non_zero_count[x264_scan8[32] - 8], &nnz[top][32-4 + (16>>v_shift)] );
    }
    else
    {
        M32( &h->mb.cache.intra4x4_pred_mode[x264_scan8[0] - 8] ) = 0xFFFFFFFFU;
        M32( &h->mb.cache.non_zero_count[x264_scan8[ 0] - 8] ) = 0x80808080U;
        M32( &h->mb.cache.non_zero_count[x264_scan8[16] - 8] ) = 0x80808080U;
        M32( &h->mb.cache.non_zero_count[x264_scan8[32] - 8] ) = 0x80808080U;
    }
    if( neighbour & MB_LEFT )
    {
        h->mb.cache.intra4x4_pred_mode[x264_scan8[ 0] - 1] = i4x4[left][4];
        h->mb.cache.intra4x4_pred_mode[x264_scan8[ 2] - 1] = i4x4[left][5];
        h->mb.cache.intra4x4_pred_mode[x264_scan8[ 8] - 1] = i4x4[left][6];
        h->mb.cache.intra4x4_pred_mode[x264_scan8[10] - 1] = i4x4[left][3];
        h->mb.cache.non_zero_count[x264_scan8[ 0] - 1] = nnz[left][ 3];
        h->mb.cache.non_zero_count[x264_scan8[ 2] - 1] = nnz[left][ 7];
        h->mb.cache.non_zero_count[x264_scan8[ 8] - 1] = nnz[left][11];
        h->mb.cache.non_zero_count[x264_scan8[10] - 1] = nnz[left][15];
        h->mb.cache.non_zero_count[x264_scan8[16+ 0] - 1] = nnz[left][16+1];
        h->mb.cache.non_zero_count[x264_scan8[16+ 2] - 1] = nnz[left][16+5];
        h->mb.cache.non_zero_count[x264_scan8[32+ 0] - 1] = nnz[left][32+1];
        h->mb.cache.non_zero_count[x264_scan8[32+ 2] - 1] = nnz[left][32+5];
        if( cf == CHROMA_422 )
        {
            h->mb.cache.non_zero_count[x264_scan8[16+ 8] - 1] = nnz[left][16+ 9];
            h->mb.cache.non_zero_count[x264_scan8[16+10] - 1] = nnz[left][16+13];
            h->mb.cache.non_zero_count[x264_scan8[32+ 8] - 1] = nnz[left][32+ 9];
            h->mb.cache.non_zero_count[x264_scan8[32+10] - 1] = nnz[left][32+13];
        }
    }
    else
    {
        h->mb.cache.intra4x4_pred_mode[x264_scan8[ 0] - 1] =
        h->mb.cache.intra4x4_pred_mode[x264_scan8[ 2] - 1] =
        h->mb.cache.intra4x4_pred_mode[x264_scan8[ 8] - 1] =
        h->mb.cache.intra4x4_pred_mode[x264_scan8[10] - 1] = -1;
        h->mb.cache.non_zero_count[x264_scan8[ 0] - 1] =
        h->mb.cache.non_zero_count[x264_scan8[ 2] - 1] =
        h->mb.cache.non_zero_count[x264_scan8[ 8] - 1] =
        h->mb.cache.non_zero_count[x264_scan8[10] - 1] =
        h->mb.cache.non_zero_count[x264_scan8[16+ 0] - 1] =
        h->mb.cache.non_zero_count[x264_scan8[16+ 2] - 1] =
        h->mb.cache.non_zero_count[x264_scan8[32+ 0] - 1] =
        h->mb.cache.non_zero_count[x264_scan8[32+ 2] - 1] = 0x80;
        if( cf == CHROMA_422 )
        {
            h->mb.cache.non_zero_count[x264_scan8[16+ 8] - 1] =
            h->mb.cache.non_zero_count[x264_scan8[16+10] - 1] =
            h->mb.cache.non_zero_count[x264_scan8[32+ 8] - 1] =
            h->mb.cache.non_zero_count[x264_scan8[32+10] - 1] = 0x80;
        }
    }
}

/* x264_macroblock_cache_load for progressive slices in 4:2:0 or 4:2:2 (cf): the same stores,
 * with the chroma format a constant and the MBAFF cases left out. */
static ALWAYS_INLINE void x264_macroblock_cache_load_prog( x264_t *h, int mb_x, int mb_y, int cf )
{
    const int v_shift = cf == CHROMA_420;
    const int s8x8 = h->mb.i_b8_stride;
    const int s4x4 = h->mb.i_b4_stride;
    const int mb_stride = h->mb.i_mb_stride;
    const int mb_xy = mb_y * mb_stride + mb_x;
    const int b8_xy = 2*(mb_y * s8x8 + mb_x);
    const int b4_xy = 4*(mb_y * s4x4 + mb_x);
    const int first_mb = h->sh.i_first_mb;
    const int b_ci = h->param.b_constrained_intra;
    int8_t *mb_type = h->mb.type;
    uint16_t *slice_table = h->mb.slice_table;
    int8_t (*i4x4)[8] = h->mb.intra4x4_pred_mode;
    uint8_t (*nnz)[48] = h->mb.non_zero_count;
    int16_t *cbp = h->mb.cbp;
    pixel *fdec_y = h->mb.pic.p_fdec[0];
    pixel *fdec_u = h->mb.pic.p_fdec[1];
    pixel *fdec_v = h->mb.pic.p_fdec[2];
    unsigned int neighbour = 0, neighbour_intra = 0, neighbour_frame = 0;
    int left = -1, top = -1, topleft = -1, topright = -1, top_y = -1;
    int type_left = -1, type_top = -1, type_topleft = -1, type_topright = -1;

    h->mb.i_mb_x = mb_x;
    h->mb.i_mb_y = mb_y;
    h->mb.i_mb_xy = mb_xy;
    h->mb.i_b8_xy = b8_xy;
    h->mb.i_b4_xy = b4_xy;
    h->mb.left_b8[0] = h->mb.left_b8[1] = b8_xy - 2;
    h->mb.left_b4[0] = h->mb.left_b4[1] = b4_xy - 4;
    h->mb.left_index_table = &left_indices[3];
    h->mb.topleft_partition = 0;

    /* Slices are runs of MBs in raster order: with the top left MB in this slice, the top, top right
     * and left ones are too. */
    if( mb_x > 0 && mb_x < h->mb.i_mb_width - 1 && h->i_threadslice_start != mb_y &&
        slice_table[mb_xy - mb_stride - 1] == first_mb )
    {
        left = mb_xy - 1;
        top = mb_xy - mb_stride;
        topleft = top - 1;
        topright = top + 1;
        top_y = mb_y - 1;
        h->mb.i_mb_topleft_y = top_y;
        h->mb.i_mb_topright_y = top_y;
        type_left = mb_type[left];
        type_top = mb_type[top];
        type_topleft = mb_type[topleft];
        type_topright = mb_type[topright];
        neighbour = neighbour_frame = neighbour_intra = MB_LEFT|MB_TOP|MB_TOPLEFT|MB_TOPRIGHT;
        if( b_ci )
            neighbour_intra = (IS_INTRA( type_left ) ? MB_LEFT : 0) | (IS_INTRA( type_top ) ? MB_TOP : 0)
                            | (IS_INTRA( type_topleft ) ? MB_TOPLEFT : 0) | (IS_INTRA( type_topright ) ? MB_TOPRIGHT : 0);
        x264_prefetch( &cbp[top] );
        x264_prefetch( i4x4[top] );
        x264_prefetch( &nnz[top][12] );
        x264_prefetch( &h->mb.mb_transform_size[top] );
        x264_prefetch( &h->mb.skipbp[top] );
    }
    else
    {
        if( mb_x > 0 )
        {
            neighbour_frame |= MB_LEFT;
            left = mb_xy - 1;
            type_left = mb_type[left];
            if( slice_table[left] == first_mb )
            {
                neighbour |= MB_LEFT;
                if( !b_ci || IS_INTRA( type_left ) )
                    neighbour_intra |= MB_LEFT;
            }
        }

        /* We can't predict from the previous threadslice since it hasn't been encoded yet. */
        if( h->i_threadslice_start != mb_y )
        {
            if( mb_xy - mb_stride >= 0 )
            {
                neighbour_frame |= MB_TOP;
                top = mb_xy - mb_stride;
                top_y = mb_y - 1;
                type_top = mb_type[top];
                if( slice_table[top] == first_mb )
                {
                    neighbour |= MB_TOP;
                    if( !b_ci || IS_INTRA( type_top ) )
                        neighbour_intra |= MB_TOP;
                    x264_prefetch( &cbp[top] );
                    x264_prefetch( i4x4[top] );
                    x264_prefetch( &nnz[top][12] );
                    x264_prefetch( &h->mb.mb_transform_size[top] );
                    x264_prefetch( &h->mb.skipbp[top] );
                }
            }
            if( mb_x > 0 && mb_y - 1 >= 0 )
            {
                neighbour_frame |= MB_TOPLEFT;
                topleft = mb_xy - mb_stride - 1;
                h->mb.i_mb_topleft_y = mb_y - 1;
                type_topleft = mb_type[topleft];
                if( slice_table[topleft] == first_mb )
                {
                    neighbour |= MB_TOPLEFT;
                    if( !b_ci || IS_INTRA( type_topleft ) )
                        neighbour_intra |= MB_TOPLEFT;
                }
            }
            if( mb_x < h->mb.i_mb_width - 1 && mb_y - 1 >= 0 )
            {
                neighbour_frame |= MB_TOPRIGHT;
                topright = mb_xy - mb_stride + 1;
                h->mb.i_mb_topright_y = mb_y - 1;
                type_topright = mb_type[topright];
                if( slice_table[topright] == first_mb )
                {
                    neighbour |= MB_TOPRIGHT;
                    if( !b_ci || IS_INTRA( type_topright ) )
                        neighbour_intra |= MB_TOPRIGHT;
                }
            }
        }
    }

    h->mb.i_neighbour = neighbour;
    h->mb.i_neighbour_intra = neighbour_intra;
    h->mb.i_neighbour_frame = neighbour_frame;
    h->mb.i_mb_type_top = type_top;
    h->mb.i_mb_type_left[0] = h->mb.i_mb_type_left[1] = type_left;
    h->mb.i_mb_type_topleft = type_topleft;
    h->mb.i_mb_type_topright = type_topright;
    h->mb.i_mb_left_xy[0] = h->mb.i_mb_left_xy[1] = left;
    h->mb.i_mb_top_xy = top;
    h->mb.i_mb_topleft_xy = topleft;
    h->mb.i_mb_topright_xy = topright;
    h->mb.i_mb_top_y = top_y;

    /* Rows of the top neighbours, used only where they are available. */
    const int top_8x8 = (2*mb_y-1) * s8x8 + 2*mb_x;
    const int top_4x4 = (4*mb_y-1) * s4x4 + 4*mb_x;
    const int lists = (1 << h->sh.i_type) & 3;

    h->mb.cache.deblock_strength = h->deblock_strength[mb_y&1][h->param.b_sliced_threads?mb_xy:mb_x];
    h->mb.mvp16_valid[0] = h->mb.mvp16_valid[1] = 0;

    if( neighbour & MB_TOP )
    {
        h->mb.cache.i_cbp_top = cbp[top];
        for( int l = 0; l < lists; l++ )
        {
            x264_prefetch( &h->mb.mv[l][top_4x4-1] );
            x264_prefetch( &h->mb.mv[l][top_4x4+4] );
            x264_prefetch( &h->mb.ref[l][top_8x8-1] );
            x264_prefetch( &h->mb.mvd[l][top] );
        }
    }
    else
        h->mb.cache.i_cbp_top = -1;
    h->mb.cache.i_cbp_left = (neighbour & MB_LEFT) ? cbp[left] : -1;

    /* load intra4x4 and non_zero_count */
    if( h->cachef.load_nnz )
        h->cachef.load_nnz( h->mb.cache.non_zero_count, h->mb.cache.intra4x4_pred_mode,
                            (neighbour & MB_TOP) ? nnz[top] : (uint8_t*)cacheprog_nnz_unavail,
                            (neighbour & MB_LEFT) ? nnz[left] : (uint8_t*)cacheprog_nnz_unavail,
                            (neighbour & MB_TOP) ? i4x4[top] : (int8_t*)cacheprog_i4x4_unavail,
                            (neighbour & MB_LEFT) ? i4x4[left] : (int8_t*)cacheprog_i4x4_unavail );
    else
        x264_macroblock_load_nnz_prog( h, neighbour, top, left, cf );

    if( h->pps->b_transform_8x8_mode )
    {
        h->mb.cache.i_neighbour_transform_size =
            ( (neighbour & MB_LEFT) && h->mb.mb_transform_size[left] )
          + ( (neighbour & MB_TOP) && h->mb.mb_transform_size[top]  );
    }

    /* pixels: progressive load_pic_pointers of luma and chroma */
    {
        const int stride_y = h->fdec->i_stride[0];
        const int stride_c = h->fdec->i_stride[1];
        const int height_c = 16 >> v_shift;
        const int off_y = 16 * mb_x + 16 * mb_y * stride_y;
        const int off_c = 16 * mb_x + height_c * mb_y * stride_c;
        pixel *intra_y = &h->intra_border_backup[!(mb_y&1)][0][mb_x*16];
        pixel *intra_c = &h->intra_border_backup[!(mb_y&1)][1][mb_x*16];

        /* fdec left column and top row */
        if( h->cachef.load_border )
            h->cachef.load_border( fdec_y, fdec_u, intra_y, intra_c );
        else
        {
            x264_copy_column8( fdec_y-1+ 4*FDEC_STRIDE, fdec_y+15+ 4*FDEC_STRIDE );
            x264_copy_column8( fdec_y-1+12*FDEC_STRIDE, fdec_y+15+12*FDEC_STRIDE );
            memcpy( fdec_y-FDEC_STRIDE, intra_y, 24*sizeof(pixel) );
            fdec_y[-FDEC_STRIDE-1] = intra_y[-1];
            x264_copy_column8( fdec_u-1+ 4*FDEC_STRIDE, fdec_u+ 7+ 4*FDEC_STRIDE );
            x264_copy_column8( fdec_v-1+ 4*FDEC_STRIDE, fdec_v+ 7+ 4*FDEC_STRIDE );
            if( cf == CHROMA_422 )
            {
                x264_copy_column8( fdec_u-1+12*FDEC_STRIDE, fdec_u+ 7+12*FDEC_STRIDE );
                x264_copy_column8( fdec_v-1+12*FDEC_STRIDE, fdec_v+ 7+12*FDEC_STRIDE );
            }
            memcpy( fdec_u-FDEC_STRIDE, intra_c, 8*sizeof(pixel) );
            memcpy( fdec_v-FDEC_STRIDE, intra_c+8, 8*sizeof(pixel) );
            fdec_u[-FDEC_STRIDE-1] = intra_c[-1-8];
            fdec_v[-FDEC_STRIDE-1] = intra_c[-1];
        }
        if( h->mb.b_reencode_mb )
            x264_macroblock_load_left_reencode( h, off_y, off_c, height_c );

        h->mb.pic.i_stride[0] = stride_y;
        h->mb.pic.i_stride[1] = stride_c;
        h->mb.pic.p_fenc_plane[0] = &h->fenc->plane[0][off_y];
        h->mb.pic.p_fenc_plane[1] = &h->fenc->plane[1][off_c];
        h->mb.pic.i_fenc_pre = 0;
        h->mb.pic.i_fld_uv_y = height_c * (mb_y >> 1);
        h->mb.pic.i_fld_uv_lines = height_c * h->mb.i_mb_height >> 1;
        h->mc.copy[PIXEL_16x16]( h->mb.pic.p_fenc[0], FENC_STRIDE, h->mb.pic.p_fenc_plane[0], stride_y, 16 );
        h->mc.load_deinterleave_chroma_fenc( h->mb.pic.p_fenc[1], h->mb.pic.p_fenc_plane[1], stride_c, height_c );

        for( int j = 0; j < h->mb.pic.i_fref[0]; j++ )
        {
            x264_frame_t *fref = h->fref[0][j];
            pixel *plane = fref->plane[0] + off_y;
            h->mb.pic.p_fref[0][j][0] = plane;
            h->mb.pic.p_fref[0][j][1] = fref->filtered[0][1] + off_y;
            h->mb.pic.p_fref[0][j][2] = fref->filtered[0][2] + off_y;
            h->mb.pic.p_fref[0][j][3] = fref->filtered[0][3] + off_y;
            h->mb.pic.p_fref[0][j][4] =
            h->mb.pic.p_fref[0][j][5] = fref->plane[1] + off_c;
            if( h->sh.weight[j][0].weightfn )
                h->mb.pic.p_fref_w[j] = &h->fenc->weighted[j][off_y];
            else
                h->mb.pic.p_fref_w[j] = plane;
        }
        if( h->sh.i_type == SLICE_TYPE_B )
            for( int j = 0; j < h->mb.pic.i_fref[1]; j++ )
            {
                x264_frame_t *fref = h->fref[1][j];
                h->mb.pic.p_fref[1][j][0] = fref->plane[0] + off_y;
                h->mb.pic.p_fref[1][j][1] = fref->filtered[0][1] + off_y;
                h->mb.pic.p_fref[1][j][2] = fref->filtered[0][2] + off_y;
                h->mb.pic.p_fref[1][j][3] = fref->filtered[0][3] + off_y;
                h->mb.pic.p_fref[1][j][4] =
                h->mb.pic.p_fref[1][j][5] = fref->plane[1] + off_c;
            }

        /* x264_prefetch_fenc: frames share the stride */
        h->mc.prefetch_fenc( h->fenc->plane[0]+off_y, stride_y, h->fenc->plane[1]+off_c, stride_c, mb_x );
    }

    if( h->fdec->integral )
        x264_macroblock_load_integral( h, mb_x, mb_y );

    /* load ref/mv/mvd */
    for( int l = 0; l < lists; l++ )
    {
        int16_t (*mv)[2] = h->mb.mv[l];
        int8_t *ref = h->mb.ref[l];

        int i8 = x264_scan8[0] - 1 - 1*8;
        if( neighbour & MB_TOPLEFT )
        {
            h->mb.cache.ref[l][i8] = ref[top_8x8 - 1];
            CP32( h->mb.cache.mv[l][i8], mv[top_4x4 - 1] );
        }
        else
        {
            h->mb.cache.ref[l][i8] = -2;
            M32( h->mb.cache.mv[l][i8] ) = 0;
        }

        i8 = x264_scan8[0] - 8;
        if( neighbour & MB_TOP )
        {
            h->mb.cache.ref[l][i8+0] =
            h->mb.cache.ref[l][i8+1] = ref[top_8x8 + 0];
            h->mb.cache.ref[l][i8+2] =
            h->mb.cache.ref[l][i8+3] = ref[top_8x8 + 1];
            CP128( h->mb.cache.mv[l][i8], mv[top_4x4] );
        }
        else
        {
            M128( h->mb.cache.mv[l][i8] ) = M128_ZERO;
            M32( &h->mb.cache.ref[l][i8] ) = (uint8_t)(-2) * 0x01010101U;
        }

        i8 = x264_scan8[0] + 4 - 1*8;
        if( neighbour & MB_TOPRIGHT )
        {
            h->mb.cache.ref[l][i8] = ref[top_8x8 + 2];
            CP32( h->mb.cache.mv[l][i8], mv[top_4x4 + 4] );
        }
        else
             h->mb.cache.ref[l][i8] = -2;

        i8 = x264_scan8[0] - 1;
        if( neighbour & MB_LEFT )
        {
            const int ir = b8_xy - 1;
            const int iv = b4_xy - 1;
            h->mb.cache.ref[l][i8+0*8] =
            h->mb.cache.ref[l][i8+1*8] = ref[ir + 0*s8x8];
            h->mb.cache.ref[l][i8+2*8] =
            h->mb.cache.ref[l][i8+3*8] = ref[ir + 1*s8x8];

            CP32( h->mb.cache.mv[l][i8+0*8], mv[iv + 0*s4x4] );
            CP32( h->mb.cache.mv[l][i8+1*8], mv[iv + 1*s4x4] );
            CP32( h->mb.cache.mv[l][i8+2*8], mv[iv + 2*s4x4] );
            CP32( h->mb.cache.mv[l][i8+3*8], mv[iv + 3*s4x4] );
        }
        else
        {
            for( int i = 0; i < 4; i++ )
            {
                h->mb.cache.ref[l][i8+i*8] = -2;
                M32( h->mb.cache.mv[l][i8+i*8] ) = 0;
            }
        }

        if( h->param.b_cabac )
        {
            uint8_t (*mvd)[8][2] = h->mb.mvd[l];
            if( neighbour & MB_TOP )
                CP64( h->mb.cache.mvd[l][x264_scan8[0] - 8], mvd[top][0] );
            else
                M64( h->mb.cache.mvd[l][x264_scan8[0] - 8] ) = 0;

            if( neighbour & MB_LEFT )
            {
                CP16( h->mb.cache.mvd[l][x264_scan8[0 ] - 1], mvd[left][4] );
                CP16( h->mb.cache.mvd[l][x264_scan8[2 ] - 1], mvd[left][5] );
                CP16( h->mb.cache.mvd[l][x264_scan8[8 ] - 1], mvd[left][6] );
                CP16( h->mb.cache.mvd[l][x264_scan8[10] - 1], mvd[left][3] );
            }
            else
            {
                M16( h->mb.cache.mvd[l][x264_scan8[0]-1+0*8] ) = 0;
                M16( h->mb.cache.mvd[l][x264_scan8[0]-1+1*8] ) = 0;
                M16( h->mb.cache.mvd[l][x264_scan8[0]-1+2*8] ) = 0;
                M16( h->mb.cache.mvd[l][x264_scan8[0]-1+3*8] ) = 0;
            }
        }
    }

    h->mb.b_allow_skip = 1;

    if( h->param.b_cabac )
    {
        /* !IS_SKIP of the available neighbours' types */
        const uint32_t not_skip = ~((1u << P_SKIP) | (1u << B_SKIP));
        h->mb.cache.i_neighbour_skip = ((neighbour >> 0) & (not_skip >> (type_left&31)) & 1)
                                     + ((neighbour >> 1) & (not_skip >> (type_top&31)) & 1);
    }

    /* load skip */
    if( h->sh.i_type == SLICE_TYPE_B )
    {
        h->mb.bipred_weight = h->mb.bipred_weight_buf[MB_INTERLACED][MB_INTERLACED&(mb_y&1)];
        h->mb.dist_scale_factor = h->mb.dist_scale_factor_buf[MB_INTERLACED][MB_INTERLACED&(mb_y&1)];
        if( h->param.b_cabac )
        {
            uint8_t skipbp;
            x264_macroblock_cache_skip( h, 0, 0, 4, 4, 0 );
            skipbp = (neighbour & MB_LEFT) ? h->mb.skipbp[left] : 0;
            h->mb.cache.skip[x264_scan8[0] - 1] = skipbp & 0x2;
            h->mb.cache.skip[x264_scan8[8] - 1] = skipbp & 0x8;
            skipbp = (neighbour & MB_TOP) ? h->mb.skipbp[top] : 0;
            h->mb.cache.skip[x264_scan8[0] - 8] = skipbp & 0x4;
            h->mb.cache.skip[x264_scan8[4] - 8] = skipbp & 0x8;
        }
    }

    if( h->sh.i_type == SLICE_TYPE_P )
        x264_mb_predict_mv_pskip( h, h->mb.cache.pskip_mv );

    memcpy( h->mb.i_neighbour8, neighbour_rows[neighbour_intra].n8, sizeof(h->mb.i_neighbour8) );
    memcpy( h->mb.i_neighbour4, neighbour_rows[neighbour_intra].n4, sizeof(h->mb.i_neighbour4) );
}

#define LTOP 0
#if HAVE_INTERLACED
#   define LBOT 1
#else
#   define LBOT 0
#endif

static void ALWAYS_INLINE x264_macroblock_cache_load( x264_t *h, int mb_x, int mb_y, int b_mbaff )
{
    x264_macroblock_cache_load_neighbours( h, mb_x, mb_y, b_mbaff );

    int *left = h->mb.i_mb_left_xy;
    int top  = h->mb.i_mb_top_xy;
    int top_y = h->mb.i_mb_top_y;
    int s8x8 = h->mb.i_b8_stride;
    int s4x4 = h->mb.i_b4_stride;
    int top_8x8 = (2*top_y+1) * s8x8 + 2*mb_x;
    int top_4x4 = (4*top_y+3) * s4x4 + 4*mb_x;
    int lists = (1 << h->sh.i_type) & 3;

    /* GCC pessimizes direct loads from heap-allocated arrays due to aliasing. */
    /* By only dereferencing them once, we avoid this issue. */
    int8_t (*i4x4)[8] = h->mb.intra4x4_pred_mode;
    uint8_t (*nnz)[48] = h->mb.non_zero_count;
    int16_t *cbp = h->mb.cbp;

    const x264_left_table_t *left_index_table = h->mb.left_index_table;

    h->mb.cache.deblock_strength = h->deblock_strength[mb_y&1][h->param.b_sliced_threads?h->mb.i_mb_xy:mb_x];
    h->mb.mvp16_valid[0] = h->mb.mvp16_valid[1] = 0;

    /* load cache */
    if( h->mb.i_neighbour & MB_TOP )
    {
        h->mb.cache.i_cbp_top = cbp[top];
        /* load intra4x4 */
        CP32( &h->mb.cache.intra4x4_pred_mode[x264_scan8[0] - 8], &i4x4[top][0] );

        /* load non_zero_count */
        CP32( &h->mb.cache.non_zero_count[x264_scan8[ 0] - 8], &nnz[top][12] );
        CP32( &h->mb.cache.non_zero_count[x264_scan8[16] - 8], &nnz[top][16-4 + (16>>CHROMA_V_SHIFT)] );
        CP32( &h->mb.cache.non_zero_count[x264_scan8[32] - 8], &nnz[top][32-4 + (16>>CHROMA_V_SHIFT)] );

        /* Finish the prefetching */
        for( int l = 0; l < lists; l++ )
        {
            x264_prefetch( &h->mb.mv[l][top_4x4-1] );
            /* Top right being not in the same cacheline as top left will happen
             * once every 4 MBs, so one extra prefetch is worthwhile */
            x264_prefetch( &h->mb.mv[l][top_4x4+4] );
            x264_prefetch( &h->mb.ref[l][top_8x8-1] );
            x264_prefetch( &h->mb.mvd[l][top] );
        }
    }
    else
    {
        h->mb.cache.i_cbp_top = -1;

        /* load intra4x4 */
        M32( &h->mb.cache.intra4x4_pred_mode[x264_scan8[0] - 8] ) = 0xFFFFFFFFU;

        /* load non_zero_count */
        M32( &h->mb.cache.non_zero_count[x264_scan8[ 0] - 8] ) = 0x80808080U;
        M32( &h->mb.cache.non_zero_count[x264_scan8[16] - 8] ) = 0x80808080U;
        M32( &h->mb.cache.non_zero_count[x264_scan8[32] - 8] ) = 0x80808080U;
    }

    if( h->mb.i_neighbour & MB_LEFT )
    {
        int ltop = left[LTOP];
        int lbot = b_mbaff ? left[LBOT] : ltop;
        if( b_mbaff )
        {
            const int16_t top_luma = (cbp[ltop] >> (left_index_table->mv[0]&(~1))) & 2;
            const int16_t bot_luma = (cbp[lbot] >> (left_index_table->mv[2]&(~1))) & 2;
            h->mb.cache.i_cbp_left = (cbp[ltop] & 0xfff0) | (bot_luma<<2) | top_luma;
        }
        else
            h->mb.cache.i_cbp_left = cbp[ltop];

        /* load intra4x4 */
        h->mb.cache.intra4x4_pred_mode[x264_scan8[ 0] - 1] = i4x4[ltop][left_index_table->intra[0]];
        h->mb.cache.intra4x4_pred_mode[x264_scan8[ 2] - 1] = i4x4[ltop][left_index_table->intra[1]];
        h->mb.cache.intra4x4_pred_mode[x264_scan8[ 8] - 1] = i4x4[lbot][left_index_table->intra[2]];
        h->mb.cache.intra4x4_pred_mode[x264_scan8[10] - 1] = i4x4[lbot][left_index_table->intra[3]];

        /* load non_zero_count */
        h->mb.cache.non_zero_count[x264_scan8[ 0] - 1] = nnz[ltop][left_index_table->nnz[0]];
        h->mb.cache.non_zero_count[x264_scan8[ 2] - 1] = nnz[ltop][left_index_table->nnz[1]];
        h->mb.cache.non_zero_count[x264_scan8[ 8] - 1] = nnz[lbot][left_index_table->nnz[2]];
        h->mb.cache.non_zero_count[x264_scan8[10] - 1] = nnz[lbot][left_index_table->nnz[3]];

        if( CHROMA_FORMAT >= CHROMA_422 )
        {
            int offset = (4>>CHROMA_H_SHIFT) - 4;
            h->mb.cache.non_zero_count[x264_scan8[16+ 0] - 1] = nnz[ltop][left_index_table->nnz[0]+16+offset];
            h->mb.cache.non_zero_count[x264_scan8[16+ 2] - 1] = nnz[ltop][left_index_table->nnz[1]+16+offset];
            h->mb.cache.non_zero_count[x264_scan8[16+ 8] - 1] = nnz[lbot][left_index_table->nnz[2]+16+offset];
            h->mb.cache.non_zero_count[x264_scan8[16+10] - 1] = nnz[lbot][left_index_table->nnz[3]+16+offset];
            h->mb.cache.non_zero_count[x264_scan8[32+ 0] - 1] = nnz[ltop][left_index_table->nnz[0]+32+offset];
            h->mb.cache.non_zero_count[x264_scan8[32+ 2] - 1] = nnz[ltop][left_index_table->nnz[1]+32+offset];
            h->mb.cache.non_zero_count[x264_scan8[32+ 8] - 1] = nnz[lbot][left_index_table->nnz[2]+32+offset];
            h->mb.cache.non_zero_count[x264_scan8[32+10] - 1] = nnz[lbot][left_index_table->nnz[3]+32+offset];
        }
        else
        {
            h->mb.cache.non_zero_count[x264_scan8[16+ 0] - 1] = nnz[ltop][left_index_table->nnz_chroma[0]];
            h->mb.cache.non_zero_count[x264_scan8[16+ 2] - 1] = nnz[lbot][left_index_table->nnz_chroma[1]];
            h->mb.cache.non_zero_count[x264_scan8[32+ 0] - 1] = nnz[ltop][left_index_table->nnz_chroma[2]];
            h->mb.cache.non_zero_count[x264_scan8[32+ 2] - 1] = nnz[lbot][left_index_table->nnz_chroma[3]];
        }
    }
    else
    {
        h->mb.cache.i_cbp_left = -1;

        h->mb.cache.intra4x4_pred_mode[x264_scan8[ 0] - 1] =
        h->mb.cache.intra4x4_pred_mode[x264_scan8[ 2] - 1] =
        h->mb.cache.intra4x4_pred_mode[x264_scan8[ 8] - 1] =
        h->mb.cache.intra4x4_pred_mode[x264_scan8[10] - 1] = -1;

        /* load non_zero_count */
        h->mb.cache.non_zero_count[x264_scan8[ 0] - 1] =
        h->mb.cache.non_zero_count[x264_scan8[ 2] - 1] =
        h->mb.cache.non_zero_count[x264_scan8[ 8] - 1] =
        h->mb.cache.non_zero_count[x264_scan8[10] - 1] =
        h->mb.cache.non_zero_count[x264_scan8[16+ 0] - 1] =
        h->mb.cache.non_zero_count[x264_scan8[16+ 2] - 1] =
        h->mb.cache.non_zero_count[x264_scan8[32+ 0] - 1] =
        h->mb.cache.non_zero_count[x264_scan8[32+ 2] - 1] = 0x80;
        if( CHROMA_FORMAT >= CHROMA_422 )
        {
            h->mb.cache.non_zero_count[x264_scan8[16+ 8] - 1] =
            h->mb.cache.non_zero_count[x264_scan8[16+10] - 1] =
            h->mb.cache.non_zero_count[x264_scan8[32+ 8] - 1] =
            h->mb.cache.non_zero_count[x264_scan8[32+10] - 1] = 0x80;
        }
    }

    if( h->pps->b_transform_8x8_mode )
    {
        h->mb.cache.i_neighbour_transform_size =
            ( (h->mb.i_neighbour & MB_LEFT) && h->mb.mb_transform_size[left[0]] )
          + ( (h->mb.i_neighbour & MB_TOP) && h->mb.mb_transform_size[top]  );
    }

    if( b_mbaff )
    {
        h->mb.pic.i_fref[0] = h->i_ref[0] << MB_INTERLACED;
        h->mb.pic.i_fref[1] = h->i_ref[1] << MB_INTERLACED;
    }

    if( !b_mbaff )
    {
        x264_copy_column8( h->mb.pic.p_fdec[0]-1+ 4*FDEC_STRIDE, h->mb.pic.p_fdec[0]+15+ 4*FDEC_STRIDE );
        x264_copy_column8( h->mb.pic.p_fdec[0]-1+12*FDEC_STRIDE, h->mb.pic.p_fdec[0]+15+12*FDEC_STRIDE );
        x264_macroblock_load_pic_pointers( h, mb_x, mb_y, 0, 0, 0 );
        if( CHROMA444 )
        {
            x264_copy_column8( h->mb.pic.p_fdec[1]-1+ 4*FDEC_STRIDE, h->mb.pic.p_fdec[1]+15+ 4*FDEC_STRIDE );
            x264_copy_column8( h->mb.pic.p_fdec[1]-1+12*FDEC_STRIDE, h->mb.pic.p_fdec[1]+15+12*FDEC_STRIDE );
            x264_copy_column8( h->mb.pic.p_fdec[2]-1+ 4*FDEC_STRIDE, h->mb.pic.p_fdec[2]+15+ 4*FDEC_STRIDE );
            x264_copy_column8( h->mb.pic.p_fdec[2]-1+12*FDEC_STRIDE, h->mb.pic.p_fdec[2]+15+12*FDEC_STRIDE );
            x264_macroblock_load_pic_pointers( h, mb_x, mb_y, 1, 0, 0 );
            x264_macroblock_load_pic_pointers( h, mb_x, mb_y, 2, 0, 0 );
        }
        else
        {
            x264_copy_column8( h->mb.pic.p_fdec[1]-1+ 4*FDEC_STRIDE, h->mb.pic.p_fdec[1]+ 7+ 4*FDEC_STRIDE );
            x264_copy_column8( h->mb.pic.p_fdec[2]-1+ 4*FDEC_STRIDE, h->mb.pic.p_fdec[2]+ 7+ 4*FDEC_STRIDE );
            if( CHROMA_FORMAT == CHROMA_422 )
            {
                x264_copy_column8( h->mb.pic.p_fdec[1]-1+12*FDEC_STRIDE, h->mb.pic.p_fdec[1]+ 7+12*FDEC_STRIDE );
                x264_copy_column8( h->mb.pic.p_fdec[2]-1+12*FDEC_STRIDE, h->mb.pic.p_fdec[2]+ 7+12*FDEC_STRIDE );
            }
            x264_macroblock_load_pic_pointers( h, mb_x, mb_y, 1, 1, 0 );
        }
    }
    else
    {
        x264_macroblock_load_pic_pointers( h, mb_x, mb_y, 0, 0, 1 );
        if( CHROMA444 )
        {
            x264_macroblock_load_pic_pointers( h, mb_x, mb_y, 1, 0, 1 );
            x264_macroblock_load_pic_pointers( h, mb_x, mb_y, 2, 0, 1 );
        }
        else
            x264_macroblock_load_pic_pointers( h, mb_x, mb_y, 1, 1, 1 );
    }

    if( h->fdec->integral )
    {
        int offset = 16 * (mb_x + mb_y * h->fdec->i_stride[0]);
        for( int list = 0; list < 2; list++ )
            for( int i = 0; i < h->mb.pic.i_fref[list]; i++ )
                h->mb.pic.p_integral[list][i] = &h->fref[list][i]->integral[offset];
    }

    x264_prefetch_fenc( h, h->fenc, mb_x, mb_y );

    /* load ref/mv/mvd */
    for( int l = 0; l < lists; l++ )
    {
        int16_t (*mv)[2] = h->mb.mv[l];
        int8_t *ref = h->mb.ref[l];

        int i8 = x264_scan8[0] - 1 - 1*8;
        if( h->mb.i_neighbour & MB_TOPLEFT )
        {
            int ir = b_mbaff ? 2*(s8x8*h->mb.i_mb_topleft_y + mb_x-1)+1+s8x8 : top_8x8 - 1;
            int iv = b_mbaff ? 4*(s4x4*h->mb.i_mb_topleft_y + mb_x-1)+3+3*s4x4 : top_4x4 - 1;
            if( b_mbaff && h->mb.topleft_partition )
            {
                /* Take motion vector from the middle of macroblock instead of
                 * the bottom right as usual. */
                iv -= 2*s4x4;
                ir -= s8x8;
            }
            h->mb.cache.ref[l][i8] = ref[ir];
            CP32( h->mb.cache.mv[l][i8], mv[iv] );
        }
        else
        {
            h->mb.cache.ref[l][i8] = -2;
            M32( h->mb.cache.mv[l][i8] ) = 0;
        }

        i8 = x264_scan8[0] - 8;
        if( h->mb.i_neighbour & MB_TOP )
        {
            h->mb.cache.ref[l][i8+0] =
            h->mb.cache.ref[l][i8+1] = ref[top_8x8 + 0];
            h->mb.cache.ref[l][i8+2] =
            h->mb.cache.ref[l][i8+3] = ref[top_8x8 + 1];
            CP128( h->mb.cache.mv[l][i8], mv[top_4x4] );
        }
        else
        {
            M128( h->mb.cache.mv[l][i8] ) = M128_ZERO;
            M32( &h->mb.cache.ref[l][i8] ) = (uint8_t)(-2) * 0x01010101U;
        }

        i8 = x264_scan8[0] + 4 - 1*8;
        if( h->mb.i_neighbour & MB_TOPRIGHT )
        {
            int ir = b_mbaff ? 2*(s8x8*h->mb.i_mb_topright_y + (mb_x+1))+s8x8 : top_8x8 + 2;
            int iv = b_mbaff ? 4*(s4x4*h->mb.i_mb_topright_y + (mb_x+1))+3*s4x4 : top_4x4 + 4;
            h->mb.cache.ref[l][i8] = ref[ir];
            CP32( h->mb.cache.mv[l][i8], mv[iv] );
        }
        else
             h->mb.cache.ref[l][i8] = -2;

        i8 = x264_scan8[0] - 1;
        if( h->mb.i_neighbour & MB_LEFT )
        {
            if( b_mbaff )
            {
                h->mb.cache.ref[l][i8+0*8] = ref[h->mb.left_b8[LTOP] + 1 + s8x8*left_index_table->ref[0]];
                h->mb.cache.ref[l][i8+1*8] = ref[h->mb.left_b8[LTOP] + 1 + s8x8*left_index_table->ref[1]];
                h->mb.cache.ref[l][i8+2*8] = ref[h->mb.left_b8[LBOT] + 1 + s8x8*left_index_table->ref[2]];
                h->mb.cache.ref[l][i8+3*8] = ref[h->mb.left_b8[LBOT] + 1 + s8x8*left_index_table->ref[3]];

                CP32( h->mb.cache.mv[l][i8+0*8], mv[h->mb.left_b4[LTOP] + 3 + s4x4*left_index_table->mv[0]] );
                CP32( h->mb.cache.mv[l][i8+1*8], mv[h->mb.left_b4[LTOP] + 3 + s4x4*left_index_table->mv[1]] );
                CP32( h->mb.cache.mv[l][i8+2*8], mv[h->mb.left_b4[LBOT] + 3 + s4x4*left_index_table->mv[2]] );
                CP32( h->mb.cache.mv[l][i8+3*8], mv[h->mb.left_b4[LBOT] + 3 + s4x4*left_index_table->mv[3]] );
            }
            else
            {
                const int ir = h->mb.i_b8_xy - 1;
                const int iv = h->mb.i_b4_xy - 1;
                h->mb.cache.ref[l][i8+0*8] =
                h->mb.cache.ref[l][i8+1*8] = ref[ir + 0*s8x8];
                h->mb.cache.ref[l][i8+2*8] =
                h->mb.cache.ref[l][i8+3*8] = ref[ir + 1*s8x8];

                CP32( h->mb.cache.mv[l][i8+0*8], mv[iv + 0*s4x4] );
                CP32( h->mb.cache.mv[l][i8+1*8], mv[iv + 1*s4x4] );
                CP32( h->mb.cache.mv[l][i8+2*8], mv[iv + 2*s4x4] );
                CP32( h->mb.cache.mv[l][i8+3*8], mv[iv + 3*s4x4] );
            }
        }
        else
        {
            for( int i = 0; i < 4; i++ )
            {
                h->mb.cache.ref[l][i8+i*8] = -2;
                M32( h->mb.cache.mv[l][i8+i*8] ) = 0;
            }
        }

        /* Extra logic for top right mv in mbaff.
         * . . . d  . . a .
         * . . . e  . . . .
         * . . . f  b . c .
         * . . . .  . . . .
         *
         * If the top right of the 4x4 partitions labeled a, b and c in the
         * above diagram do not exist, but the entries d, e and f exist (in
         * the macroblock to the left) then use those instead.
         */
        if( b_mbaff && (h->mb.i_neighbour & MB_LEFT) )
        {
            if( MB_INTERLACED && !h->mb.field[h->mb.i_mb_xy-1] )
            {
                h->mb.cache.topright_ref[l][0] = ref[h->mb.left_b8[0] + 1 + s8x8*0];
                h->mb.cache.topright_ref[l][1] = ref[h->mb.left_b8[0] + 1 + s8x8*1];
                h->mb.cache.topright_ref[l][2] = ref[h->mb.left_b8[1] + 1 + s8x8*0];
                CP32( h->mb.cache.topright_mv[l][0], mv[h->mb.left_b4[0] + 3 + s4x4*(left_index_table->mv[0]+1)] );
                CP32( h->mb.cache.topright_mv[l][1], mv[h->mb.left_b4[0] + 3 + s4x4*(left_index_table->mv[1]+1)] );
                CP32( h->mb.cache.topright_mv[l][2], mv[h->mb.left_b4[1] + 3 + s4x4*(left_index_table->mv[2]+1)] );
            }
            else if( !MB_INTERLACED && h->mb.field[h->mb.i_mb_xy-1] )
            {
                // Looking at the bottom field so always take the bottom macroblock of the pair.
                h->mb.cache.topright_ref[l][0] = ref[h->mb.left_b8[0] + 1 + s8x8*2 + s8x8*left_index_table->ref[0]];
                h->mb.cache.topright_ref[l][1] = ref[h->mb.left_b8[0] + 1 + s8x8*2 + s8x8*left_index_table->ref[0]];
                h->mb.cache.topright_ref[l][2] = ref[h->mb.left_b8[0] + 1 + s8x8*2 + s8x8*left_index_table->ref[2]];
                CP32( h->mb.cache.topright_mv[l][0], mv[h->mb.left_b4[0] + 3 + s4x4*4 + s4x4*left_index_table->mv[0]] );
                CP32( h->mb.cache.topright_mv[l][1], mv[h->mb.left_b4[0] + 3 + s4x4*4 + s4x4*left_index_table->mv[1]] );
                CP32( h->mb.cache.topright_mv[l][2], mv[h->mb.left_b4[0] + 3 + s4x4*4 + s4x4*left_index_table->mv[2]] );
            }
        }

        if( h->param.b_cabac )
        {
            uint8_t (*mvd)[8][2] = h->mb.mvd[l];
            if( h->mb.i_neighbour & MB_TOP )
                CP64( h->mb.cache.mvd[l][x264_scan8[0] - 8], mvd[top][0] );
            else
                M64( h->mb.cache.mvd[l][x264_scan8[0] - 8] ) = 0;

            if( h->mb.i_neighbour & MB_LEFT && (!b_mbaff || h->mb.cache.ref[l][x264_scan8[0]-1] >= 0) )
            {
                CP16( h->mb.cache.mvd[l][x264_scan8[0 ] - 1], mvd[left[LTOP]][left_index_table->intra[0]] );
                CP16( h->mb.cache.mvd[l][x264_scan8[2 ] - 1], mvd[left[LTOP]][left_index_table->intra[1]] );
            }
            else
            {
                M16( h->mb.cache.mvd[l][x264_scan8[0]-1+0*8] ) = 0;
                M16( h->mb.cache.mvd[l][x264_scan8[0]-1+1*8] ) = 0;
            }
            if( h->mb.i_neighbour & MB_LEFT && (!b_mbaff || h->mb.cache.ref[l][x264_scan8[0]-1+2*8] >=0) )
            {
                CP16( h->mb.cache.mvd[l][x264_scan8[8 ] - 1], mvd[left[LBOT]][left_index_table->intra[2]] );
                CP16( h->mb.cache.mvd[l][x264_scan8[10] - 1], mvd[left[LBOT]][left_index_table->intra[3]] );
            }
            else
            {
                M16( h->mb.cache.mvd[l][x264_scan8[0]-1+2*8] ) = 0;
                M16( h->mb.cache.mvd[l][x264_scan8[0]-1+3*8] ) = 0;
            }
        }

        /* If motion vectors are cached from frame macroblocks but this
         * macroblock is a field macroblock then the motion vector must be
         * halved. Similarly, motion vectors from field macroblocks are doubled. */
        if( b_mbaff )
        {
#define MAP_MVS\
                if( FIELD_DIFFERENT(h->mb.i_mb_topleft_xy) )\
                    MAP_F2F(mv, ref, x264_scan8[0] - 1 - 1*8)\
                if( FIELD_DIFFERENT(top) )\
                {\
                    MAP_F2F(mv, ref, x264_scan8[0] + 0 - 1*8)\
                    MAP_F2F(mv, ref, x264_scan8[0] + 1 - 1*8)\
                    MAP_F2F(mv, ref, x264_scan8[0] + 2 - 1*8)\
                    MAP_F2F(mv, ref, x264_scan8[0] + 3 - 1*8)\
                }\
                if( FIELD_DIFFERENT(h->mb.i_mb_topright_xy) )\
                    MAP_F2F(mv, ref, x264_scan8[0] + 4 - 1*8)\
                if( FIELD_DIFFERENT(left[0]) )\
                {\
                    MAP_F2F(mv, ref, x264_scan8[0] - 1 + 0*8)\
                    MAP_F2F(mv, ref, x264_scan8[0] - 1 + 1*8)\
                    MAP_F2F(mv, ref, x264_scan8[0] - 1 + 2*8)\
                    MAP_F2F(mv, ref, x264_scan8[0] - 1 + 3*8)\
                    MAP_F2F(topright_mv, topright_ref, 0)\
                    MAP_F2F(topright_mv, topright_ref, 1)\
                    MAP_F2F(topright_mv, topright_ref, 2)\
                }

            if( MB_INTERLACED )
            {
#define FIELD_DIFFERENT(macroblock) (macroblock >= 0 && !h->mb.field[macroblock])
#define MAP_F2F(varmv, varref, index)\
                if( h->mb.cache.varref[l][index] >= 0 )\
                {\
                    h->mb.cache.varref[l][index] <<= 1;\
                    h->mb.cache.varmv[l][index][1] /= 2;\
                    h->mb.cache.mvd[l][index][1] >>= 1;\
                }
                MAP_MVS
#undef MAP_F2F
#undef FIELD_DIFFERENT
            }
            else
            {
#define FIELD_DIFFERENT(macroblock) (macroblock >= 0 && h->mb.field[macroblock])
#define MAP_F2F(varmv, varref, index)\
                if( h->mb.cache.varref[l][index] >= 0 )\
                {\
                    h->mb.cache.varref[l][index] >>= 1;\
                    h->mb.cache.varmv[l][index][1] <<= 1;\
                    h->mb.cache.mvd[l][index][1] <<= 1;\
                }
                MAP_MVS
#undef MAP_F2F
#undef FIELD_DIFFERENT
            }
        }
    }

    if( b_mbaff && mb_x == 0 && !(mb_y&1) )
    {
        if( h->mb.i_mb_top_xy >= h->sh.i_first_mb )
            h->mb.field_decoding_flag = h->mb.field[h->mb.i_mb_top_xy];
        else
            h->mb.field_decoding_flag = 0;
    }

    /* Check whether skip here would cause decoder to predict interlace mode incorrectly.
     * FIXME: It might be better to change the interlace type rather than forcing a skip to be non-skip. */
    h->mb.b_allow_skip = 1;
    if( b_mbaff )
    {
        if( MB_INTERLACED != h->mb.field_decoding_flag &&
            (mb_y&1) && IS_SKIP(h->mb.type[h->mb.i_mb_xy - h->mb.i_mb_stride]) )
            h->mb.b_allow_skip = 0;
    }

    if( h->param.b_cabac )
    {
        if( b_mbaff )
        {
            int left_xy, top_xy;
            /* Rows of the previous threadslice are another slice, and may still be written. */
            int first_xy = h->i_threadslice_start * h->mb.i_mb_stride;
            /* Neighbours here are calculated based on field_decoding_flag */
            int mb_xy = mb_x + (mb_y&~1)*h->mb.i_mb_stride;
            left_xy = mb_xy - 1;
            if( (mb_y&1) && mb_x > 0 && h->mb.field_decoding_flag == h->mb.field[left_xy] )
                left_xy += h->mb.i_mb_stride;
            if( h->mb.field_decoding_flag )
            {
                top_xy = mb_xy - h->mb.i_mb_stride;
                if( !(mb_y&1) && top_xy >= first_xy && h->mb.slice_table[top_xy] == h->sh.i_first_mb && h->mb.field[top_xy] )
                    top_xy -= h->mb.i_mb_stride;
            }
            else
                top_xy = mb_x + (mb_y-1)*h->mb.i_mb_stride;

            h->mb.cache.i_neighbour_skip =   (mb_x >  0 && h->mb.slice_table[left_xy] == h->sh.i_first_mb && !IS_SKIP( h->mb.type[left_xy] ))
                                         + (top_xy >= first_xy && h->mb.slice_table[top_xy]  == h->sh.i_first_mb && !IS_SKIP( h->mb.type[top_xy] ));
        }
        else
        {
            h->mb.cache.i_neighbour_skip = ((h->mb.i_neighbour & MB_LEFT) && !IS_SKIP( h->mb.i_mb_type_left[0] ))
                                         + ((h->mb.i_neighbour & MB_TOP)  && !IS_SKIP( h->mb.i_mb_type_top ));
        }
    }

    /* load skip */
    if( h->sh.i_type == SLICE_TYPE_B )
    {
        h->mb.bipred_weight = h->mb.bipred_weight_buf[MB_INTERLACED][MB_INTERLACED&(mb_y&1)];
        h->mb.dist_scale_factor = h->mb.dist_scale_factor_buf[MB_INTERLACED][MB_INTERLACED&(mb_y&1)];
        if( h->param.b_cabac )
        {
            uint8_t skipbp;
            x264_macroblock_cache_skip( h, 0, 0, 4, 4, 0 );
            if( b_mbaff )
            {
                skipbp = (h->mb.i_neighbour & MB_LEFT) ? h->mb.skipbp[left[LTOP]] : 0;
                h->mb.cache.skip[x264_scan8[0] - 1] = (skipbp >> (1+(left_index_table->mv[0]&~1))) & 1;
                skipbp = (h->mb.i_neighbour & MB_LEFT) ? h->mb.skipbp[left[LBOT]] : 0;
                h->mb.cache.skip[x264_scan8[8] - 1] = (skipbp >> (1+(left_index_table->mv[2]&~1))) & 1;
            }
            else
            {
                skipbp = (h->mb.i_neighbour & MB_LEFT) ? h->mb.skipbp[left[0]] : 0;
                h->mb.cache.skip[x264_scan8[0] - 1] = skipbp & 0x2;
                h->mb.cache.skip[x264_scan8[8] - 1] = skipbp & 0x8;
            }
            skipbp = (h->mb.i_neighbour & MB_TOP) ? h->mb.skipbp[top] : 0;
            h->mb.cache.skip[x264_scan8[0] - 8] = skipbp & 0x4;
            h->mb.cache.skip[x264_scan8[4] - 8] = skipbp & 0x8;
        }
    }

    if( h->sh.i_type == SLICE_TYPE_P )
        x264_mb_predict_mv_pskip( h, h->mb.cache.pskip_mv );

    h->mb.i_neighbour4[0] =
    h->mb.i_neighbour8[0] = (h->mb.i_neighbour_intra & (MB_TOP|MB_LEFT|MB_TOPLEFT))
                            | ((h->mb.i_neighbour_intra & MB_TOP) ? MB_TOPRIGHT : 0);
    h->mb.i_neighbour4[4] =
    h->mb.i_neighbour4[1] = MB_LEFT | ((h->mb.i_neighbour_intra & MB_TOP) ? (MB_TOP|MB_TOPLEFT|MB_TOPRIGHT) : 0);
    h->mb.i_neighbour4[2] =
    h->mb.i_neighbour4[8] =
    h->mb.i_neighbour4[10] =
    h->mb.i_neighbour8[2] = MB_TOP|MB_TOPRIGHT | ((h->mb.i_neighbour_intra & MB_LEFT) ? (MB_LEFT|MB_TOPLEFT) : 0);
    h->mb.i_neighbour4[5] =
    h->mb.i_neighbour8[1] = MB_LEFT | (h->mb.i_neighbour_intra & MB_TOPRIGHT)
                            | ((h->mb.i_neighbour_intra & MB_TOP) ? MB_TOP|MB_TOPLEFT : 0);
}

static NOINLINE void x264_macroblock_cache_load_generic( x264_t *h, int mb_x, int mb_y )
{
    x264_macroblock_cache_load( h, mb_x, mb_y, 0 );
}

static NOINLINE void x264_macroblock_cache_load_prog420( x264_t *h, int mb_x, int mb_y )
{
    x264_macroblock_cache_load_prog( h, mb_x, mb_y, CHROMA_420 );
}

static NOINLINE void x264_macroblock_cache_load_prog422( x264_t *h, int mb_x, int mb_y )
{
    x264_macroblock_cache_load_prog( h, mb_x, mb_y, CHROMA_422 );
}

void x264_macroblock_cache_load_progressive( x264_t *h, int mb_x, int mb_y )
{
    if( CHROMA_FORMAT == CHROMA_420 )
        x264_macroblock_cache_load_prog420( h, mb_x, mb_y );
    else if( CHROMA_FORMAT == CHROMA_422 )
        x264_macroblock_cache_load_prog422( h, mb_x, mb_y );
    else
        x264_macroblock_cache_load_generic( h, mb_x, mb_y );
}

void x264_macroblock_cache_load_interlaced( x264_t *h, int mb_x, int mb_y )
{
    x264_macroblock_cache_load( h, mb_x, mb_y, 1 );
}

static void x264_macroblock_deblock_strength_mbaff( x264_t *h, uint8_t (*bs)[8][4] )
{
    if( (h->mb.i_neighbour & MB_LEFT) && h->mb.field[h->mb.i_mb_left_xy[0]] != MB_INTERLACED )
    {
        static const uint8_t offset[2][2][8] =
        {   {   { 0, 0, 0, 0, 1, 1, 1, 1 },
                { 2, 2, 2, 2, 3, 3, 3, 3 }, },
            {   { 0, 1, 2, 3, 0, 1, 2, 3 },
                { 0, 1, 2, 3, 0, 1, 2, 3 }, }
        };
        ALIGNED_ARRAY_8( uint8_t, tmpbs, [8] );

        const uint8_t *off = offset[MB_INTERLACED][h->mb.i_mb_y&1];
        uint8_t (*nnz)[48] = h->mb.non_zero_count;

        for( int i = 0; i < 8; i++ )
        {
            int left = h->mb.i_mb_left_xy[MB_INTERLACED ? i>>2 : i&1];
            int nnz_this = h->mb.cache.non_zero_count[x264_scan8[0]+8*(i>>1)];
            int nnz_left = nnz[left][3 + 4*off[i]];
            if( !h->param.b_cabac && h->pps->b_transform_8x8_mode )
            {
                int j = off[i]&~1;
                if( h->mb.mb_transform_size[left] )
                    nnz_left = !!(M16( &nnz[left][2+4*j] ) | M16( &nnz[left][2+4*(1+j)] ));
            }
            tmpbs[i] = (nnz_left || nnz_this) ? 2 : 1;
        }

        if( MB_INTERLACED )
        {
            CP32( bs[0][0], &tmpbs[0] );
            CP32( bs[0][4], &tmpbs[4] );
        }
        else
        {
            for( int i = 0; i < 4; i++ ) bs[0][0][i] = tmpbs[2*i];
            for( int i = 0; i < 4; i++ ) bs[0][4][i] = tmpbs[1+2*i];
        }
    }

    if( (h->mb.i_neighbour & MB_TOP) && MB_INTERLACED != h->mb.field[h->mb.i_mb_top_xy] )
    {
        if( !(h->mb.i_mb_y&1) && !MB_INTERLACED )
        {
            /* Need to filter both fields (even for frame macroblocks).
             * Filter top two rows using the top macroblock of the above
             * pair and then the bottom one. */
            int mbn_xy = h->mb.i_mb_xy - 2 * h->mb.i_mb_stride;
            uint8_t *nnz_cur = &h->mb.cache.non_zero_count[x264_scan8[0]];

            for( int j = 0; j < 2; j++, mbn_xy += h->mb.i_mb_stride )
            {
                uint8_t (*nnz)[48] = h->mb.non_zero_count;

                ALIGNED_4( uint8_t nnz_top[4] );
                CP32( nnz_top, &nnz[mbn_xy][3*4] );

                if( !h->param.b_cabac && h->pps->b_transform_8x8_mode && h->mb.mb_transform_size[mbn_xy] )
                {
                    nnz_top[0] = nnz_top[1] = M16( &nnz[mbn_xy][ 8] ) || M16( &nnz[mbn_xy][12] );
                    nnz_top[2] = nnz_top[3] = M16( &nnz[mbn_xy][10] ) || M16( &nnz[mbn_xy][14] );
                }

                for( int i = 0; i < 4; i++ )
                    bs[1][4*j][i] = (nnz_cur[i] || nnz_top[i]) ? 2 : 1;
            }
        }
        else
            for( int i = 0; i < 4; i++ )
                bs[1][0][i] = X264_MAX( bs[1][0][i], 1 );
    }
}

void x264_macroblock_deblock_strength( x264_t *h )
{
    uint8_t (*bs)[8][4] = h->mb.cache.deblock_strength;
    if( IS_INTRA( h->mb.i_type ) )
    {
        memset( bs[0][1], 3, 3*4*sizeof(uint8_t) );
        memset( bs[1][1], 3, 3*4*sizeof(uint8_t) );
        return;
    }

    /* Early termination: in this case, nnz guarantees all edges use strength 2.*/
    if( h->mb.b_transform_8x8 && !CHROMA444 )
    {
        int cbp_mask = 0xf >> CHROMA_V_SHIFT;
        if( (h->mb.i_cbp_luma&cbp_mask) == cbp_mask )
        {
            M32( bs[0][0] ) = 0x02020202;
            M32( bs[0][2] ) = 0x02020202;
            M32( bs[0][4] ) = 0x02020202;
            memset( bs[1][0], 2, 5*4*sizeof(uint8_t) ); /* [1][1] and [1][3] has to be set for 4:2:2 */
            return;
        }
    }

    int neighbour_changed = 0;
    if( h->sh.i_disable_deblocking_filter_idc != 2 )
    {
        neighbour_changed = h->mb.i_neighbour_frame&~h->mb.i_neighbour;
        h->mb.i_neighbour = h->mb.i_neighbour_frame;
    }

    /* MBAFF deblock uses different left neighbors from encoding */
    if( SLICE_MBAFF && (h->mb.i_neighbour & MB_LEFT) && (h->mb.field[h->mb.i_mb_xy - 1] != MB_INTERLACED) )
    {
        h->mb.i_mb_left_xy[1] =
        h->mb.i_mb_left_xy[0] = h->mb.i_mb_xy - 1;
        if( h->mb.i_mb_y&1 )
            h->mb.i_mb_left_xy[0] -= h->mb.i_mb_stride;
        else
            h->mb.i_mb_left_xy[1] += h->mb.i_mb_stride;
    }

    /* If we have multiple slices and we're deblocking on slice edges, we
     * have to reload neighbour data. */
    if( neighbour_changed )
    {
        int top_y = h->mb.i_mb_top_y;
        int top_8x8 = (2*top_y+1) * h->mb.i_b8_stride + 2*h->mb.i_mb_x;
        int top_4x4 = (4*top_y+3) * h->mb.i_b4_stride + 4*h->mb.i_mb_x;
        int s8x8 = h->mb.i_b8_stride;
        int s4x4 = h->mb.i_b4_stride;

        uint8_t (*nnz)[48] = h->mb.non_zero_count;
        const x264_left_table_t *left_index_table = SLICE_MBAFF ? h->mb.left_index_table : &left_indices[3];

        if( neighbour_changed & MB_TOP )
            CP32( &h->mb.cache.non_zero_count[x264_scan8[0] - 8], &nnz[h->mb.i_mb_top_xy][12] );

        if( neighbour_changed & MB_LEFT )
        {
            int *left = h->mb.i_mb_left_xy;
            h->mb.cache.non_zero_count[x264_scan8[0 ] - 1] = nnz[left[0]][left_index_table->nnz[0]];
            h->mb.cache.non_zero_count[x264_scan8[2 ] - 1] = nnz[left[0]][left_index_table->nnz[1]];
            h->mb.cache.non_zero_count[x264_scan8[8 ] - 1] = nnz[left[1]][left_index_table->nnz[2]];
            h->mb.cache.non_zero_count[x264_scan8[10] - 1] = nnz[left[1]][left_index_table->nnz[3]];
        }

        for( int l = 0; l <= (h->sh.i_type == SLICE_TYPE_B); l++ )
        {
            int16_t (*mv)[2] = h->mb.mv[l];
            int8_t *ref = h->mb.ref[l];

            int i8 = x264_scan8[0] - 8;
            if( neighbour_changed & MB_TOP )
            {
                h->mb.cache.ref[l][i8+0] =
                h->mb.cache.ref[l][i8+1] = ref[top_8x8 + 0];
                h->mb.cache.ref[l][i8+2] =
                h->mb.cache.ref[l][i8+3] = ref[top_8x8 + 1];
                CP128( h->mb.cache.mv[l][i8], mv[top_4x4] );
            }

            i8 = x264_scan8[0] - 1;
            if( neighbour_changed & MB_LEFT )
            {
                h->mb.cache.ref[l][i8+0*8] =
                h->mb.cache.ref[l][i8+1*8] = ref[h->mb.left_b8[0] + 1 + s8x8*left_index_table->ref[0]];
                h->mb.cache.ref[l][i8+2*8] =
                h->mb.cache.ref[l][i8+3*8] = ref[h->mb.left_b8[1] + 1 + s8x8*left_index_table->ref[2]];

                CP32( h->mb.cache.mv[l][i8+0*8], mv[h->mb.left_b4[0] + 3 + s4x4*left_index_table->mv[0]] );
                CP32( h->mb.cache.mv[l][i8+1*8], mv[h->mb.left_b4[0] + 3 + s4x4*left_index_table->mv[1]] );
                CP32( h->mb.cache.mv[l][i8+2*8], mv[h->mb.left_b4[1] + 3 + s4x4*left_index_table->mv[2]] );
                CP32( h->mb.cache.mv[l][i8+3*8], mv[h->mb.left_b4[1] + 3 + s4x4*left_index_table->mv[3]] );
            }
        }
    }

    if( h->param.analyse.i_weighted_pred == X264_WEIGHTP_SMART && h->sh.i_type == SLICE_TYPE_P )
    {
        /* Handle reference frame duplicates */
        int i8 = x264_scan8[0] - 8;
        h->mb.cache.ref[0][i8+0] =
        h->mb.cache.ref[0][i8+1] = deblock_ref_table(h->mb.cache.ref[0][i8+0]);
        h->mb.cache.ref[0][i8+2] =
        h->mb.cache.ref[0][i8+3] = deblock_ref_table(h->mb.cache.ref[0][i8+2]);

        i8 = x264_scan8[0] - 1;
        h->mb.cache.ref[0][i8+0*8] =
        h->mb.cache.ref[0][i8+1*8] = deblock_ref_table(h->mb.cache.ref[0][i8+0*8]);
        h->mb.cache.ref[0][i8+2*8] =
        h->mb.cache.ref[0][i8+3*8] = deblock_ref_table(h->mb.cache.ref[0][i8+2*8]);

        int ref0 = deblock_ref_table(h->mb.cache.ref[0][x264_scan8[ 0]]);
        int ref1 = deblock_ref_table(h->mb.cache.ref[0][x264_scan8[ 4]]);
        int ref2 = deblock_ref_table(h->mb.cache.ref[0][x264_scan8[ 8]]);
        int ref3 = deblock_ref_table(h->mb.cache.ref[0][x264_scan8[12]]);
        uint32_t reftop = pack16to32( (uint8_t)ref0, (uint8_t)ref1 ) * 0x0101;
        uint32_t refbot = pack16to32( (uint8_t)ref2, (uint8_t)ref3 ) * 0x0101;

        M32( &h->mb.cache.ref[0][x264_scan8[0]+8*0] ) = reftop;
        M32( &h->mb.cache.ref[0][x264_scan8[0]+8*1] ) = reftop;
        M32( &h->mb.cache.ref[0][x264_scan8[0]+8*2] ) = refbot;
        M32( &h->mb.cache.ref[0][x264_scan8[0]+8*3] ) = refbot;
    }

    /* Munge NNZ for cavlc + 8x8dct */
    if( !h->param.b_cabac && h->pps->b_transform_8x8_mode )
    {
        uint8_t (*nnz)[48] = h->mb.non_zero_count;
        int top = h->mb.i_mb_top_xy;
        int *left = h->mb.i_mb_left_xy;

        if( (h->mb.i_neighbour & MB_TOP) && h->mb.mb_transform_size[top] )
        {
            int i8 = x264_scan8[0] - 8;
            int nnz_top0 = M16( &nnz[top][8] ) | M16( &nnz[top][12] );
            int nnz_top1 = M16( &nnz[top][10] ) | M16( &nnz[top][14] );
            M16( &h->mb.cache.non_zero_count[i8+0] ) = nnz_top0 ? 0x0101 : 0;
            M16( &h->mb.cache.non_zero_count[i8+2] ) = nnz_top1 ? 0x0101 : 0;
        }

        if( h->mb.i_neighbour & MB_LEFT )
        {
            int i8 = x264_scan8[0] - 1;
            if( h->mb.mb_transform_size[left[0]] )
            {
                int nnz_left0 = M16( &nnz[left[0]][2] ) | M16( &nnz[left[0]][6] );
                h->mb.cache.non_zero_count[i8+8*0] = !!nnz_left0;
                h->mb.cache.non_zero_count[i8+8*1] = !!nnz_left0;
            }
            if( h->mb.mb_transform_size[left[1]] )
            {
                int nnz_left1 = M16( &nnz[left[1]][10] ) | M16( &nnz[left[1]][14] );
                h->mb.cache.non_zero_count[i8+8*2] = !!nnz_left1;
                h->mb.cache.non_zero_count[i8+8*3] = !!nnz_left1;
            }
        }

        if( h->mb.b_transform_8x8 )
        {
            int nnz0 = M16( &h->mb.cache.non_zero_count[x264_scan8[ 0]] ) | M16( &h->mb.cache.non_zero_count[x264_scan8[ 2]] );
            int nnz1 = M16( &h->mb.cache.non_zero_count[x264_scan8[ 4]] ) | M16( &h->mb.cache.non_zero_count[x264_scan8[ 6]] );
            int nnz2 = M16( &h->mb.cache.non_zero_count[x264_scan8[ 8]] ) | M16( &h->mb.cache.non_zero_count[x264_scan8[10]] );
            int nnz3 = M16( &h->mb.cache.non_zero_count[x264_scan8[12]] ) | M16( &h->mb.cache.non_zero_count[x264_scan8[14]] );
            uint32_t nnztop = pack16to32( !!nnz0, !!nnz1 ) * 0x0101;
            uint32_t nnzbot = pack16to32( !!nnz2, !!nnz3 ) * 0x0101;

            M32( &h->mb.cache.non_zero_count[x264_scan8[0]+8*0] ) = nnztop;
            M32( &h->mb.cache.non_zero_count[x264_scan8[0]+8*1] ) = nnztop;
            M32( &h->mb.cache.non_zero_count[x264_scan8[0]+8*2] ) = nnzbot;
            M32( &h->mb.cache.non_zero_count[x264_scan8[0]+8*3] ) = nnzbot;
        }
    }

    h->loopf.deblock_strength( h->mb.cache.non_zero_count, h->mb.cache.ref, h->mb.cache.mv,
                               bs, 4 >> MB_INTERLACED, h->sh.i_type == SLICE_TYPE_B );

    if( SLICE_MBAFF )
        x264_macroblock_deblock_strength_mbaff( h, bs );
}

static void ALWAYS_INLINE x264_macroblock_store_pic( x264_t *h, int mb_x, int mb_y, int i, int b_chroma, int b_mbaff )
{
    int height = b_chroma ? 16>>CHROMA_V_SHIFT : 16;
    int i_stride = h->fdec->i_stride[i];
    int i_stride2 = i_stride << (b_mbaff && MB_INTERLACED);
    int i_pix_offset = (b_mbaff && MB_INTERLACED)
                     ? 16 * mb_x + height * (mb_y&~1) * i_stride + (mb_y&1) * i_stride
                     : 16 * mb_x + height * mb_y * i_stride;
    if( b_chroma )
        h->mc.store_interleave_chroma( &h->fdec->plane[1][i_pix_offset], i_stride2, h->mb.pic.p_fdec[1], h->mb.pic.p_fdec[2], height );
    else
        h->mc.copy[PIXEL_16x16]( &h->fdec->plane[i][i_pix_offset], i_stride2, h->mb.pic.p_fdec[i], FDEC_STRIDE, 16 );
}

static void ALWAYS_INLINE x264_macroblock_backup_intra( x264_t *h, int mb_x, int mb_y, int b_mbaff )
{
    /* In MBAFF we store the last two rows in intra_border_backup[0] and [1].
     * For progressive mbs this is the bottom two rows, and for interlaced the
     * bottom row of each field. We also store samples needed for the next
     * mbpair in intra_border_backup[2]. */
    int backup_dst = !b_mbaff ? (mb_y&1) : (mb_y&1) ? 1 : MB_INTERLACED ? 0 : 2;
    memcpy( &h->intra_border_backup[backup_dst][0][mb_x*16  ], h->mb.pic.p_fdec[0]+FDEC_STRIDE*15, 16*sizeof(pixel) );
    if( CHROMA444 )
    {
        memcpy( &h->intra_border_backup[backup_dst][1][mb_x*16  ], h->mb.pic.p_fdec[1]+FDEC_STRIDE*15, 16*sizeof(pixel) );
        memcpy( &h->intra_border_backup[backup_dst][2][mb_x*16  ], h->mb.pic.p_fdec[2]+FDEC_STRIDE*15, 16*sizeof(pixel) );
    }
    else
    {
        int backup_src = (15>>CHROMA_V_SHIFT) * FDEC_STRIDE;
        memcpy( &h->intra_border_backup[backup_dst][1][mb_x*16  ], h->mb.pic.p_fdec[1]+backup_src, 8*sizeof(pixel) );
        memcpy( &h->intra_border_backup[backup_dst][1][mb_x*16+8], h->mb.pic.p_fdec[2]+backup_src, 8*sizeof(pixel) );
    }
    if( b_mbaff )
    {
        if( mb_y&1 )
        {
            int backup_src = (MB_INTERLACED ? 7 : 14) * FDEC_STRIDE;
            backup_dst = MB_INTERLACED ? 2 : 0;
            memcpy( &h->intra_border_backup[backup_dst][0][mb_x*16  ], h->mb.pic.p_fdec[0]+backup_src, 16*sizeof(pixel) );
            if( CHROMA444 )
            {
                memcpy( &h->intra_border_backup[backup_dst][1][mb_x*16  ], h->mb.pic.p_fdec[1]+backup_src, 16*sizeof(pixel) );
                memcpy( &h->intra_border_backup[backup_dst][2][mb_x*16  ], h->mb.pic.p_fdec[2]+backup_src, 16*sizeof(pixel) );
            }
            else
            {
                if( CHROMA_FORMAT == CHROMA_420 )
                    backup_src = (MB_INTERLACED ? 3 : 6) * FDEC_STRIDE;
                memcpy( &h->intra_border_backup[backup_dst][1][mb_x*16  ], h->mb.pic.p_fdec[1]+backup_src,  8*sizeof(pixel) );
                memcpy( &h->intra_border_backup[backup_dst][1][mb_x*16+8], h->mb.pic.p_fdec[2]+backup_src,  8*sizeof(pixel) );
            }
        }
    }
}

/* x264_macroblock_cache_save for progressive slices in 4:2:0 or 4:2:2 (cf) */
static ALWAYS_INLINE void x264_macroblock_cache_save_prog( x264_t *h, int cf )
{
    const int v_shift = cf == CHROMA_420;
    const int mb_x = h->mb.i_mb_x;
    const int mb_y = h->mb.i_mb_y;
    const int i_mb_xy = h->mb.i_mb_xy;
    const int i_mb_type = x264_mb_type_fix[h->mb.i_type];
    const int s8x8 = h->mb.i_b8_stride;
    const int s4x4 = h->mb.i_b4_stride;
    const int i_mb_4x4 = h->mb.i_b4_xy;
    const int i_mb_8x8 = h->mb.i_b8_xy;
    const int slice_type = h->sh.i_type;
    pixel *fdec_y = h->mb.pic.p_fdec[0];
    pixel *fdec_u = h->mb.pic.p_fdec[1];
    pixel *fdec_v = h->mb.pic.p_fdec[2];

    int8_t *i4x4 = h->mb.intra4x4_pred_mode[i_mb_xy];
    uint8_t *nnz = h->mb.non_zero_count[i_mb_xy];

    /* backup_intra, store_pic */
    {
        pixel *intra_y = &h->intra_border_backup[mb_y&1][0][mb_x*16];
        pixel *intra_c = &h->intra_border_backup[mb_y&1][1][mb_x*16];
        const int stride_y = h->fdec->i_stride[0];
        const int stride_c = h->fdec->i_stride[1];
        const int height_c = 16 >> v_shift;
        const int off_y = 16 * mb_x + 16 * mb_y * stride_y;
        const int off_c = 16 * mb_x + height_c * mb_y * stride_c;
        memcpy( intra_y, fdec_y+FDEC_STRIDE*15, 16*sizeof(pixel) );
        memcpy( intra_c,   fdec_u+(15>>v_shift)*FDEC_STRIDE, 8*sizeof(pixel) );
        memcpy( intra_c+8, fdec_v+(15>>v_shift)*FDEC_STRIDE, 8*sizeof(pixel) );
        h->mc.copy[PIXEL_16x16]( &h->fdec->plane[0][off_y], stride_y, fdec_y, FDEC_STRIDE, 16 );
        h->mc.store_interleave_chroma( &h->fdec->plane[1][off_c], stride_c, fdec_u, fdec_v, height_c );
        h->mc.prefetch_fenc( h->fdec->plane[0]+off_y, stride_y, h->fdec->plane[1]+off_c, stride_c, mb_x );
    }

    h->mb.type[i_mb_xy] = i_mb_type;
    h->mb.slice_table[i_mb_xy] = h->sh.i_first_mb;
    h->mb.partition[i_mb_xy] = IS_INTRA( i_mb_type ) ? D_16x16 : h->mb.i_partition;
    h->mb.i_mb_prev_xy = i_mb_xy;

    /* save intra4x4 */
    if( i_mb_type == I_4x4 )
    {
        CP32( &i4x4[0], &h->mb.cache.intra4x4_pred_mode[x264_scan8[10]] );
        M32( &i4x4[4] ) = pack8to32( h->mb.cache.intra4x4_pred_mode[x264_scan8[5] ],
                                     h->mb.cache.intra4x4_pred_mode[x264_scan8[7] ],
                                     h->mb.cache.intra4x4_pred_mode[x264_scan8[13] ], 0);
    }
    else if( !h->param.b_constrained_intra || IS_INTRA(i_mb_type) )
        M64( i4x4 ) = I_PRED_4x4_DC * 0x0101010101010101ULL;
    else
        M64( i4x4 ) = (uint8_t)(-1) * 0x0101010101010101ULL;

    if( i_mb_type == I_PCM )
    {
        h->mb.qp[i_mb_xy] = 0;
        h->mb.i_last_dqp = 0;
        h->mb.i_cbp_chroma = 2;
        h->mb.i_cbp_luma = 0xf;
        h->mb.cbp[i_mb_xy] = (h->mb.i_cbp_chroma << 4) | h->mb.i_cbp_luma | 0x700;
        h->mb.b_transform_8x8 = 0;
        for( int i = 0; i < 48; i++ )
            h->mb.cache.non_zero_count[x264_scan8[i]] = h->param.b_cabac ? 1 : 16;
    }
    else
    {
        if( h->mb.i_type != I_16x16 && h->mb.i_cbp_luma == 0 && h->mb.i_cbp_chroma == 0 )
            h->mb.i_qp = h->mb.i_last_qp;
        h->mb.qp[i_mb_xy] = h->mb.i_qp;
        h->mb.i_last_dqp = h->mb.i_qp - h->mb.i_last_qp;
        h->mb.i_last_qp = h->mb.i_qp;
    }

    /* save non zero count */
    if( h->cachef.save_nnz )
        h->cachef.save_nnz( nnz, h->mb.cache.non_zero_count );
    else
        cacheprog_save_nnz( nnz, h->mb.cache.non_zero_count, cf );

    if( h->mb.i_cbp_luma == 0 && h->mb.i_type != I_8x8 )
        h->mb.b_transform_8x8 = 0;
    h->mb.mb_transform_size[i_mb_xy] = h->mb.b_transform_8x8;

    if( slice_type != SLICE_TYPE_I )
    {
        int16_t (*mv0)[2] = &h->mb.mv[0][i_mb_4x4];
        int16_t (*mv1)[2] = &h->mb.mv[1][i_mb_4x4];
        int8_t *ref0 = &h->mb.ref[0][i_mb_8x8];
        int8_t *ref1 = &h->mb.ref[1][i_mb_8x8];
        if( !IS_INTRA( i_mb_type ) )
        {
            ref0[0+0*s8x8] = h->mb.cache.ref[0][x264_scan8[0]];
            ref0[1+0*s8x8] = h->mb.cache.ref[0][x264_scan8[4]];
            ref0[0+1*s8x8] = h->mb.cache.ref[0][x264_scan8[8]];
            ref0[1+1*s8x8] = h->mb.cache.ref[0][x264_scan8[12]];
            CP128( &mv0[0*s4x4], h->mb.cache.mv[0][x264_scan8[0]+8*0] );
            CP128( &mv0[1*s4x4], h->mb.cache.mv[0][x264_scan8[0]+8*1] );
            CP128( &mv0[2*s4x4], h->mb.cache.mv[0][x264_scan8[0]+8*2] );
            CP128( &mv0[3*s4x4], h->mb.cache.mv[0][x264_scan8[0]+8*3] );
            if( slice_type == SLICE_TYPE_B )
            {
                ref1[0+0*s8x8] = h->mb.cache.ref[1][x264_scan8[0]];
                ref1[1+0*s8x8] = h->mb.cache.ref[1][x264_scan8[4]];
                ref1[0+1*s8x8] = h->mb.cache.ref[1][x264_scan8[8]];
                ref1[1+1*s8x8] = h->mb.cache.ref[1][x264_scan8[12]];
                CP128( &mv1[0*s4x4], h->mb.cache.mv[1][x264_scan8[0]+8*0] );
                CP128( &mv1[1*s4x4], h->mb.cache.mv[1][x264_scan8[0]+8*1] );
                CP128( &mv1[2*s4x4], h->mb.cache.mv[1][x264_scan8[0]+8*2] );
                CP128( &mv1[3*s4x4], h->mb.cache.mv[1][x264_scan8[0]+8*3] );
            }
        }
        else
        {
            M16( &ref0[0*s8x8] ) = (uint8_t)(-1) * 0x0101;
            M16( &ref0[1*s8x8] ) = (uint8_t)(-1) * 0x0101;
            M128( &mv0[0*s4x4] ) = M128_ZERO;
            M128( &mv0[1*s4x4] ) = M128_ZERO;
            M128( &mv0[2*s4x4] ) = M128_ZERO;
            M128( &mv0[3*s4x4] ) = M128_ZERO;
            if( slice_type == SLICE_TYPE_B )
            {
                M16( &ref1[0*s8x8] ) = (uint8_t)(-1) * 0x0101;
                M16( &ref1[1*s8x8] ) = (uint8_t)(-1) * 0x0101;
                M128( &mv1[0*s4x4] ) = M128_ZERO;
                M128( &mv1[1*s4x4] ) = M128_ZERO;
                M128( &mv1[2*s4x4] ) = M128_ZERO;
                M128( &mv1[3*s4x4] ) = M128_ZERO;
            }
        }
    }

    if( h->param.b_cabac )
    {
        uint8_t (*mvd0)[2] = h->mb.mvd[0][i_mb_xy];
        uint8_t (*mvd1)[2] = h->mb.mvd[1][i_mb_xy];
        if( IS_INTRA(i_mb_type) && i_mb_type != I_PCM )
            h->mb.chroma_pred_mode[i_mb_xy] = x264_mb_chroma_pred_mode_fix[h->mb.i_chroma_pred_mode];
        else
            h->mb.chroma_pred_mode[i_mb_xy] = I_PRED_CHROMA_DC;

        if( (0x3FF30 >> i_mb_type) & 1 ) /* !INTRA && !SKIP && !DIRECT */
        {
            CP64( mvd0[0], h->mb.cache.mvd[0][x264_scan8[10]] );
            CP16( mvd0[4], h->mb.cache.mvd[0][x264_scan8[5 ]] );
            CP16( mvd0[5], h->mb.cache.mvd[0][x264_scan8[7 ]] );
            CP16( mvd0[6], h->mb.cache.mvd[0][x264_scan8[13]] );
            if( slice_type == SLICE_TYPE_B )
            {
                CP64( mvd1[0], h->mb.cache.mvd[1][x264_scan8[10]] );
                CP16( mvd1[4], h->mb.cache.mvd[1][x264_scan8[5 ]] );
                CP16( mvd1[5], h->mb.cache.mvd[1][x264_scan8[7 ]] );
                CP16( mvd1[6], h->mb.cache.mvd[1][x264_scan8[13]] );
            }
        }
        else
        {
            M128( mvd0[0] ) = M128_ZERO;
            if( slice_type == SLICE_TYPE_B )
                M128( mvd1[0] ) = M128_ZERO;
        }

        if( slice_type == SLICE_TYPE_B )
        {
            if( i_mb_type == B_SKIP || i_mb_type == B_DIRECT )
                h->mb.skipbp[i_mb_xy] = 0xf;
            else if( i_mb_type == B_8x8 )
            {
                int skipbp = ( h->mb.i_sub_partition[0] == D_DIRECT_8x8 ) << 0;
                skipbp    |= ( h->mb.i_sub_partition[1] == D_DIRECT_8x8 ) << 1;
                skipbp    |= ( h->mb.i_sub_partition[2] == D_DIRECT_8x8 ) << 2;
                skipbp    |= ( h->mb.i_sub_partition[3] == D_DIRECT_8x8 ) << 3;
                h->mb.skipbp[i_mb_xy] = skipbp;
            }
            else
                h->mb.skipbp[i_mb_xy] = 0;
        }
    }
}

static NOINLINE void x264_macroblock_cache_save_prog420( x264_t *h )
{
    x264_macroblock_cache_save_prog( h, CHROMA_420 );
}

static NOINLINE void x264_macroblock_cache_save_prog422( x264_t *h )
{
    x264_macroblock_cache_save_prog( h, CHROMA_422 );
}

static NOINLINE void x264_macroblock_cache_save_generic( x264_t *h )
{
    const int i_mb_xy = h->mb.i_mb_xy;
    const int i_mb_type = x264_mb_type_fix[h->mb.i_type];
    const int s8x8 = h->mb.i_b8_stride;
    const int s4x4 = h->mb.i_b4_stride;
    const int i_mb_4x4 = h->mb.i_b4_xy;
    const int i_mb_8x8 = h->mb.i_b8_xy;

    /* GCC pessimizes direct stores to heap-allocated arrays due to aliasing. */
    /* By only dereferencing them once, we avoid this issue. */
    int8_t *i4x4 = h->mb.intra4x4_pred_mode[i_mb_xy];
    uint8_t *nnz = h->mb.non_zero_count[i_mb_xy];

    if( SLICE_MBAFF )
    {
        x264_macroblock_backup_intra( h, h->mb.i_mb_x, h->mb.i_mb_y, 1 );
        x264_macroblock_store_pic( h, h->mb.i_mb_x, h->mb.i_mb_y, 0, 0, 1 );
        if( CHROMA444 )
        {
            x264_macroblock_store_pic( h, h->mb.i_mb_x, h->mb.i_mb_y, 1, 0, 1 );
            x264_macroblock_store_pic( h, h->mb.i_mb_x, h->mb.i_mb_y, 2, 0, 1 );
        }
        else
            x264_macroblock_store_pic( h, h->mb.i_mb_x, h->mb.i_mb_y, 1, 1, 1 );
    }
    else
    {
        x264_macroblock_backup_intra( h, h->mb.i_mb_x, h->mb.i_mb_y, 0 );
        x264_macroblock_store_pic( h, h->mb.i_mb_x, h->mb.i_mb_y, 0, 0, 0 );
        if( CHROMA444 )
        {
            x264_macroblock_store_pic( h, h->mb.i_mb_x, h->mb.i_mb_y, 1, 0, 0 );
            x264_macroblock_store_pic( h, h->mb.i_mb_x, h->mb.i_mb_y, 2, 0, 0 );
        }
        else
            x264_macroblock_store_pic( h, h->mb.i_mb_x, h->mb.i_mb_y, 1, 1, 0 );
    }

    x264_prefetch_fenc( h, h->fdec, h->mb.i_mb_x, h->mb.i_mb_y );

    h->mb.type[i_mb_xy] = i_mb_type;
    h->mb.slice_table[i_mb_xy] = h->sh.i_first_mb;
    h->mb.partition[i_mb_xy] = IS_INTRA( i_mb_type ) ? D_16x16 : h->mb.i_partition;
    h->mb.i_mb_prev_xy = i_mb_xy;

    /* save intra4x4 */
    if( i_mb_type == I_4x4 )
    {
        CP32( &i4x4[0], &h->mb.cache.intra4x4_pred_mode[x264_scan8[10]] );
        M32( &i4x4[4] ) = pack8to32( h->mb.cache.intra4x4_pred_mode[x264_scan8[5] ],
                                     h->mb.cache.intra4x4_pred_mode[x264_scan8[7] ],
                                     h->mb.cache.intra4x4_pred_mode[x264_scan8[13] ], 0);
    }
    else if( !h->param.b_constrained_intra || IS_INTRA(i_mb_type) )
        M64( i4x4 ) = I_PRED_4x4_DC * 0x0101010101010101ULL;
    else
        M64( i4x4 ) = (uint8_t)(-1) * 0x0101010101010101ULL;


    if( i_mb_type == I_PCM )
    {
        h->mb.qp[i_mb_xy] = 0;
        h->mb.i_last_dqp = 0;
        h->mb.i_cbp_chroma = CHROMA444 ? 0 : 2;
        h->mb.i_cbp_luma = 0xf;
        h->mb.cbp[i_mb_xy] = (h->mb.i_cbp_chroma << 4) | h->mb.i_cbp_luma | 0x700;
        h->mb.b_transform_8x8 = 0;
        for( int i = 0; i < 48; i++ )
            h->mb.cache.non_zero_count[x264_scan8[i]] = h->param.b_cabac ? 1 : 16;
    }
    else
    {
        if( h->mb.i_type != I_16x16 && h->mb.i_cbp_luma == 0 && h->mb.i_cbp_chroma == 0 )
            h->mb.i_qp = h->mb.i_last_qp;
        h->mb.qp[i_mb_xy] = h->mb.i_qp;
        h->mb.i_last_dqp = h->mb.i_qp - h->mb.i_last_qp;
        h->mb.i_last_qp = h->mb.i_qp;
    }

    /* save non zero count */
    CP32( &nnz[ 0+0*4], &h->mb.cache.non_zero_count[x264_scan8[ 0]] );
    CP32( &nnz[ 0+1*4], &h->mb.cache.non_zero_count[x264_scan8[ 2]] );
    CP32( &nnz[ 0+2*4], &h->mb.cache.non_zero_count[x264_scan8[ 8]] );
    CP32( &nnz[ 0+3*4], &h->mb.cache.non_zero_count[x264_scan8[10]] );
    CP32( &nnz[16+0*4], &h->mb.cache.non_zero_count[x264_scan8[16+0]] );
    CP32( &nnz[16+1*4], &h->mb.cache.non_zero_count[x264_scan8[16+2]] );
    CP32( &nnz[32+0*4], &h->mb.cache.non_zero_count[x264_scan8[32+0]] );
    CP32( &nnz[32+1*4], &h->mb.cache.non_zero_count[x264_scan8[32+2]] );
    if( CHROMA_FORMAT >= CHROMA_422 )
    {
        CP32( &nnz[16+2*4], &h->mb.cache.non_zero_count[x264_scan8[16+ 8]] );
        CP32( &nnz[16+3*4], &h->mb.cache.non_zero_count[x264_scan8[16+10]] );
        CP32( &nnz[32+2*4], &h->mb.cache.non_zero_count[x264_scan8[32+ 8]] );
        CP32( &nnz[32+3*4], &h->mb.cache.non_zero_count[x264_scan8[32+10]] );
    }

    if( h->mb.i_cbp_luma == 0 && h->mb.i_type != I_8x8 )
        h->mb.b_transform_8x8 = 0;
    h->mb.mb_transform_size[i_mb_xy] = h->mb.b_transform_8x8;

    if( h->sh.i_type != SLICE_TYPE_I )
    {
        int16_t (*mv0)[2] = &h->mb.mv[0][i_mb_4x4];
        int16_t (*mv1)[2] = &h->mb.mv[1][i_mb_4x4];
        int8_t *ref0 = &h->mb.ref[0][i_mb_8x8];
        int8_t *ref1 = &h->mb.ref[1][i_mb_8x8];
        if( !IS_INTRA( i_mb_type ) )
        {
            ref0[0+0*s8x8] = h->mb.cache.ref[0][x264_scan8[0]];
            ref0[1+0*s8x8] = h->mb.cache.ref[0][x264_scan8[4]];
            ref0[0+1*s8x8] = h->mb.cache.ref[0][x264_scan8[8]];
            ref0[1+1*s8x8] = h->mb.cache.ref[0][x264_scan8[12]];
            CP128( &mv0[0*s4x4], h->mb.cache.mv[0][x264_scan8[0]+8*0] );
            CP128( &mv0[1*s4x4], h->mb.cache.mv[0][x264_scan8[0]+8*1] );
            CP128( &mv0[2*s4x4], h->mb.cache.mv[0][x264_scan8[0]+8*2] );
            CP128( &mv0[3*s4x4], h->mb.cache.mv[0][x264_scan8[0]+8*3] );
            if( h->sh.i_type == SLICE_TYPE_B )
            {
                ref1[0+0*s8x8] = h->mb.cache.ref[1][x264_scan8[0]];
                ref1[1+0*s8x8] = h->mb.cache.ref[1][x264_scan8[4]];
                ref1[0+1*s8x8] = h->mb.cache.ref[1][x264_scan8[8]];
                ref1[1+1*s8x8] = h->mb.cache.ref[1][x264_scan8[12]];
                CP128( &mv1[0*s4x4], h->mb.cache.mv[1][x264_scan8[0]+8*0] );
                CP128( &mv1[1*s4x4], h->mb.cache.mv[1][x264_scan8[0]+8*1] );
                CP128( &mv1[2*s4x4], h->mb.cache.mv[1][x264_scan8[0]+8*2] );
                CP128( &mv1[3*s4x4], h->mb.cache.mv[1][x264_scan8[0]+8*3] );
            }
        }
        else
        {
            M16( &ref0[0*s8x8] ) = (uint8_t)(-1) * 0x0101;
            M16( &ref0[1*s8x8] ) = (uint8_t)(-1) * 0x0101;
            M128( &mv0[0*s4x4] ) = M128_ZERO;
            M128( &mv0[1*s4x4] ) = M128_ZERO;
            M128( &mv0[2*s4x4] ) = M128_ZERO;
            M128( &mv0[3*s4x4] ) = M128_ZERO;
            if( h->sh.i_type == SLICE_TYPE_B )
            {
                M16( &ref1[0*s8x8] ) = (uint8_t)(-1) * 0x0101;
                M16( &ref1[1*s8x8] ) = (uint8_t)(-1) * 0x0101;
                M128( &mv1[0*s4x4] ) = M128_ZERO;
                M128( &mv1[1*s4x4] ) = M128_ZERO;
                M128( &mv1[2*s4x4] ) = M128_ZERO;
                M128( &mv1[3*s4x4] ) = M128_ZERO;
            }
        }
    }

    if( h->param.b_cabac )
    {
        uint8_t (*mvd0)[2] = h->mb.mvd[0][i_mb_xy];
        uint8_t (*mvd1)[2] = h->mb.mvd[1][i_mb_xy];
        if( IS_INTRA(i_mb_type) && i_mb_type != I_PCM )
            h->mb.chroma_pred_mode[i_mb_xy] = x264_mb_chroma_pred_mode_fix[h->mb.i_chroma_pred_mode];
        else
            h->mb.chroma_pred_mode[i_mb_xy] = I_PRED_CHROMA_DC;

        if( (0x3FF30 >> i_mb_type) & 1 ) /* !INTRA && !SKIP && !DIRECT */
        {
            CP64( mvd0[0], h->mb.cache.mvd[0][x264_scan8[10]] );
            CP16( mvd0[4], h->mb.cache.mvd[0][x264_scan8[5 ]] );
            CP16( mvd0[5], h->mb.cache.mvd[0][x264_scan8[7 ]] );
            CP16( mvd0[6], h->mb.cache.mvd[0][x264_scan8[13]] );
            if( h->sh.i_type == SLICE_TYPE_B )
            {
                CP64( mvd1[0], h->mb.cache.mvd[1][x264_scan8[10]] );
                CP16( mvd1[4], h->mb.cache.mvd[1][x264_scan8[5 ]] );
                CP16( mvd1[5], h->mb.cache.mvd[1][x264_scan8[7 ]] );
                CP16( mvd1[6], h->mb.cache.mvd[1][x264_scan8[13]] );
            }
        }
        else
        {
            M128( mvd0[0] ) = M128_ZERO;
            if( h->sh.i_type == SLICE_TYPE_B )
                M128( mvd1[0] ) = M128_ZERO;
        }

        if( h->sh.i_type == SLICE_TYPE_B )
        {
            if( i_mb_type == B_SKIP || i_mb_type == B_DIRECT )
                h->mb.skipbp[i_mb_xy] = 0xf;
            else if( i_mb_type == B_8x8 )
            {
                int skipbp = ( h->mb.i_sub_partition[0] == D_DIRECT_8x8 ) << 0;
                skipbp    |= ( h->mb.i_sub_partition[1] == D_DIRECT_8x8 ) << 1;
                skipbp    |= ( h->mb.i_sub_partition[2] == D_DIRECT_8x8 ) << 2;
                skipbp    |= ( h->mb.i_sub_partition[3] == D_DIRECT_8x8 ) << 3;
                h->mb.skipbp[i_mb_xy] = skipbp;
            }
            else
                h->mb.skipbp[i_mb_xy] = 0;
        }
    }
}

void x264_macroblock_cache_save( x264_t *h )
{
    if( !SLICE_MBAFF && CHROMA_FORMAT == CHROMA_420 )
        x264_macroblock_cache_save_prog420( h );
    else if( !SLICE_MBAFF && CHROMA_FORMAT == CHROMA_422 )
        x264_macroblock_cache_save_prog422( h );
    else
        x264_macroblock_cache_save_generic( h );
}

void x264_macroblock_bipred_init( x264_t *h )
{
    for( int mbfield = 0; mbfield <= SLICE_MBAFF; mbfield++ )
        for( int field = 0; field <= SLICE_MBAFF; field++ )
            for( int i_ref0 = 0; i_ref0 < (h->i_ref[0]<<mbfield); i_ref0++ )
            {
                x264_frame_t *l0 = h->fref[0][i_ref0>>mbfield];
                int poc0 = l0->i_poc + mbfield*l0->i_delta_poc[field^(i_ref0&1)];
                for( int i_ref1 = 0; i_ref1 < (h->i_ref[1]<<mbfield); i_ref1++ )
                {
                    int dist_scale_factor;
                    x264_frame_t *l1 = h->fref[1][i_ref1>>mbfield];
                    int cur_poc = h->fdec->i_poc + mbfield*h->fdec->i_delta_poc[field];
                    int poc1 = l1->i_poc + mbfield*l1->i_delta_poc[field^(i_ref1&1)];
                    int td = x264_clip3( poc1 - poc0, -128, 127 );
                    if( td == 0 /* || pic0 is a long-term ref */ )
                        dist_scale_factor = 256;
                    else
                    {
                        int tb = x264_clip3( cur_poc - poc0, -128, 127 );
                        int tx = (16384 + (abs(td) >> 1)) / td;
                        dist_scale_factor = x264_clip3( (tb * tx + 32) >> 6, -1024, 1023 );
                    }

                    h->mb.dist_scale_factor_buf[mbfield][field][i_ref0][i_ref1] = dist_scale_factor;

                    dist_scale_factor >>= 2;
                    if( h->param.analyse.b_weighted_bipred
                          && dist_scale_factor >= -64
                          && dist_scale_factor <= 128 )
                    {
                        h->mb.bipred_weight_buf[mbfield][field][i_ref0][i_ref1] = 64 - dist_scale_factor;
                        // ssse3 implementation of biweight doesn't support the extrema.
                        // if we ever generate them, we'll have to drop that optimization.
                        assert( dist_scale_factor >= -63 && dist_scale_factor <= 127 );
                    }
                    else
                        h->mb.bipred_weight_buf[mbfield][field][i_ref0][i_ref1] = 32;
                }
            }
}

