/*****************************************************************************
 * frame.c: frame handling
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

#include "common.h"

static int align_stride( int x, int align, int disalign )
{
    x = ALIGN( x, align );
    if( !(x&(disalign-1)) )
        x += align;
    return x;
}

static int align_plane_size( int x, int disalign )
{
    if( !(x&(disalign-1)) )
        x += 128;
    return x;
}

static int x264_frame_internal_csp( int external_csp )
{
    switch( external_csp & X264_CSP_MASK )
    {
        case X264_CSP_NV12:
        case X264_CSP_I420:
        case X264_CSP_YV12:
            return X264_CSP_NV12;
        case X264_CSP_NV16:
        case X264_CSP_I422:
        case X264_CSP_YV16:
        case X264_CSP_V210:
            return X264_CSP_NV16;
        case X264_CSP_I444:
        case X264_CSP_YV24:
        case X264_CSP_BGR:
        case X264_CSP_BGRA:
        case X264_CSP_RGB:
            return X264_CSP_I444;
        default:
            return X264_CSP_NONE;
    }
}

/* hpel read counters */
#define HPEL_CNT_SLOTS 1024
#define HPEL_CNT_FRAMES 65536
#define HPEL_CNT_GRAN 8
static x264_frame_t *hpel_cnt_reg[HPEL_CNT_SLOTS];
static int hpel_cnt_nreg;
/* [set][granularity]: built units, read units; granularities: 16-row bands x 16/32/64/128/256 px,
 * 16-row bands, pixel rows, 1x16 row spans */
static uint64_t hpel_cnt_frames[2];
static uint64_t hpel_cnt_units[2][HPEL_CNT_GRAN][2];
static float hpel_cnt_share[2][HPEL_CNT_GRAN][HPEL_CNT_FRAMES];

static void hpel_cnt_flush( x264_frame_t *f )
{
    int mbw = f->i_width[0] >> 4;
    int mbh = f->i_lines[0] >> 4;
    int lines = f->i_lines[0];
    for( int i = 0; i < 2; i++ )
    {
        if( !f->hpel_cnt_tile[i] )
            continue;
        if( (f->hpel_cnt_built & (1<<i)) && f->hpel_cnt_used )
        {
            int tot[HPEL_CNT_GRAN] = {0}, rd[HPEL_CNT_GRAN] = {0};
            /* field sets: bands of 16 field rows, parity-major */
            for( int b = 0; b < mbh; b++ )
            {
                uint8_t *t = f->hpel_cnt_tile[i] + b*mbw;
                for( int j = 0; j < 5; j++ )
                    for( int x = 0; x < mbw; x += 1<<j )
                    {
                        int any = 0;
                        for( int k = x; k < X264_MIN( x + (1<<j), mbw ); k++ )
                            any |= t[k];
                        tot[j]++;
                        rd[j] += any;
                    }
                int any = 0;
                for( int x = 0; x < mbw; x++ )
                    any |= t[x];
                tot[5]++;
                rd[5] += any;
            }
            for( int y = 0; y < lines; y++ )
            {
                uint8_t *r = f->hpel_cnt_row[i] + y*mbw;
                int any = 0;
                for( int x = 0; x < mbw; x++ )
                    any |= r[x], rd[7] += r[x];
                tot[6]++;
                rd[6] += any;
                tot[7] += mbw;
            }
            for( int g = 0; g < HPEL_CNT_GRAN; g++ )
            {
                if( hpel_cnt_frames[i] < HPEL_CNT_FRAMES )
                    hpel_cnt_share[i][g][hpel_cnt_frames[i]] = (float)rd[g] / tot[g];
                hpel_cnt_units[i][g][0] += tot[g];
                hpel_cnt_units[i][g][1] += rd[g];
            }
            hpel_cnt_frames[i]++;
        }
        memset( f->hpel_cnt_tile[i], 0, mbw*mbh );
        memset( f->hpel_cnt_row[i], 0, mbw*lines );
    }
    f->hpel_cnt_built = 0;
    f->hpel_cnt_used = 0;
}

static int hpel_cnt_cmp( const void *a, const void *b )
{
    float x = *(const float*)a, y = *(const float*)b;
    return (x > y) - (x < y);
}

void x264_hpel_cnt_print( void )
{
    static const char *set_name[2] = { "frame", "field" };
    static const char *gran_name[HPEL_CNT_GRAN] = { "16x16", "16x32", "16x64", "16x128", "16x256", "band", "row", "row-span16" };
    for( int i = 0; i < 2; i++ )
    {
        if( !hpel_cnt_frames[i] )
            continue;
        int n = X264_MIN( hpel_cnt_frames[i], HPEL_CNT_FRAMES );
        fprintf( stderr, "hpel_cnt %d-bit %s hpel, %d referenced frames: read share total, per frame min/p10/p50/p90/max\n",
                 BIT_DEPTH, set_name[i], n );
        for( int g = 0; g < HPEL_CNT_GRAN; g++ )
        {
            float *v = hpel_cnt_share[i][g];
            qsort( v, n, sizeof(float), hpel_cnt_cmp );
            fprintf( stderr, "hpel_cnt %d-bit %s %-10s %6.2f%%   %5.1f %5.1f %5.1f %5.1f %5.1f\n",
                     BIT_DEPTH, set_name[i], gran_name[g], 100. * hpel_cnt_units[i][g][1] / hpel_cnt_units[i][g][0],
                     100*v[0], 100*v[n/10], 100*v[n/2], 100*v[n*9/10], 100*v[n-1] );
        }
    }
    if( hpel_cnt_frames[0] && hpel_cnt_frames[1] )
        for( int g = 0; g < HPEL_CNT_GRAN; g++ )
            fprintf( stderr, "hpel_cnt %d-bit both sets %-10s %6.2f%%\n", BIT_DEPTH, gran_name[g],
                     100. * (hpel_cnt_units[0][g][1] + hpel_cnt_units[1][g][1]) / (hpel_cnt_units[0][g][0] + hpel_cnt_units[1][g][0]) );
    memset( hpel_cnt_frames, 0, sizeof(hpel_cnt_frames) );
    memset( hpel_cnt_units, 0, sizeof(hpel_cnt_units) );
}

static void hpel_cnt_region( x264_frame_t *f, int fld, intptr_t row, intptr_t x, int w, int hh )
{
    int mbw = f->i_width[0] >> 4;
    int mbh = f->i_lines[0] >> 4;
    int lines = f->i_lines[0];
    uint8_t *tile = f->hpel_cnt_tile[fld];
    uint8_t *rows = f->hpel_cnt_row[fld];
    intptr_t y0 = row, y1 = row + hh - 1;
    if( fld )
    {
        int parity = row & 1;
        y0 = row >> 1;
        y1 = y0 + hh - 1;
        lines >>= 1;
        mbh >>= 1;
        tile += parity * mbh * mbw;
        rows += parity * lines * mbw;
    }
    y0 = x264_clip3( y0, 0, lines-1 );
    y1 = x264_clip3( y1, 0, lines-1 );
    int x0 = x264_clip3( x, 0, mbw*16-1 ) >> 4;
    int x1 = x264_clip3( x + w - 1, 0, mbw*16-1 ) >> 4;
    for( intptr_t y = y0; y <= y1; y++ )
        for( int bx = x0; bx <= x1; bx++ )
        {
            if( !__atomic_load_n( &rows[y*mbw+bx], __ATOMIC_RELAXED ) )
                __atomic_store_n( &rows[y*mbw+bx], 1, __ATOMIC_RELAXED );
            if( !__atomic_load_n( &tile[(y>>4)*mbw+bx], __ATOMIC_RELAXED ) )
                __atomic_store_n( &tile[(y>>4)*mbw+bx], 1, __ATOMIC_RELAXED );
        }
}

void x264_hpel_cnt_mark( pixel *src, int w, int hh )
{
    int n = __atomic_load_n( &hpel_cnt_nreg, __ATOMIC_ACQUIRE );
    for( int r = 0; r < n; r++ )
    {
        x264_frame_t *f = hpel_cnt_reg[r];
        if( !f )
            continue;
        int padv = (PADV << !!f->hpel_cnt_tile[1]);
        for( int p = 0; p < f->hpel_cnt_planes; p++ )
        {
            intptr_t stride = f->i_stride[p];
            int lines = f->i_lines[p];
            for( int fld = 0; fld < 2; fld++ )
            {
                if( !f->hpel_cnt_tile[fld] )
                    continue;
                for( int k = 1; k < 4; k++ )
                {
                    pixel *base = fld ? f->filtered_fld[p][k] : f->filtered[p][k];
                    intptr_t off = ((intptr_t)src - (intptr_t)base) / (intptr_t)sizeof(pixel) + f->hpel_cnt_padx;
                    intptr_t row = off >= 0 ? off / stride : -((-off + stride - 1) / stride);
                    if( row < -padv || row >= lines + padv )
                        continue;
                    hpel_cnt_region( f, fld, row, off - row*stride - f->hpel_cnt_padx, w, hh );
                    return;
                }
            }
        }
    }
}

static x264_frame_t *x264_frame_new( x264_t *h, int b_fdec, int b_touch )
{
    x264_frame_t *frame;
    int i_csp = x264_frame_internal_csp( h->param.i_csp );
    int i_mb_count = h->mb.i_mb_count;
    int i_stride, i_width, i_lines, luma_plane_count;
    int i_padv = PADV << PARAM_INTERLACED;
    int align = 16;
#if ARCH_X86 || ARCH_X86_64
    if( h->param.cpu&X264_CPU_CACHELINE_64 || h->param.cpu&X264_CPU_AVX512 )
        align = 64;
    else if( h->param.cpu&X264_CPU_CACHELINE_32 || h->param.cpu&X264_CPU_AVX2 )
        align = 32;
#endif
#if ARCH_PPC
    int disalign = 1<<9;
#else
    int disalign = 1<<10;
#endif

    /* ensure frame alignment after PADH is added */
    int padh_align = X264_MAX( align - PADH * (int)sizeof(pixel), 0 ) / (int)sizeof(pixel);

    CHECKED_MALLOCZERO( frame, sizeof(x264_frame_t) );
    PREALLOC_INIT

    /* allocate frame data (+64 for extra data for me) */
    i_width  = h->mb.i_mb_width*16;
    i_lines  = h->mb.i_mb_height*16;
    i_stride = align_stride( i_width + 2*PADH, align, disalign );

    if( i_csp == X264_CSP_NV12 || i_csp == X264_CSP_NV16 )
    {
        luma_plane_count = 1;
        frame->i_plane = 2;
        for( int i = 0; i < 2; i++ )
        {
            frame->i_width[i] = i_width >> i;
            frame->i_lines[i] = i_lines >> (i && i_csp == X264_CSP_NV12);
            frame->i_stride[i] = i_stride;
        }
    }
    else if( i_csp == X264_CSP_I444 )
    {
        luma_plane_count = 3;
        frame->i_plane = 3;
        for( int i = 0; i < 3; i++ )
        {
            frame->i_width[i] = i_width;
            frame->i_lines[i] = i_lines;
            frame->i_stride[i] = i_stride;
        }
    }
    else
        goto fail;

    frame->i_csp = i_csp;
    frame->i_width_lowres = frame->i_width[0]/2;
    frame->i_lines_lowres = frame->i_lines[0]/2;
    frame->i_stride_lowres = align_stride( frame->i_width_lowres + 2*PADH, align, disalign<<1 );

    for( int i = 0; i < h->param.i_bframe + 2; i++ )
        for( int j = 0; j < h->param.i_bframe + 2; j++ )
            PREALLOC( frame->i_row_satds[i][j], i_lines/16 * sizeof(int) );

    frame->i_poc = -1;
    frame->i_type = X264_TYPE_AUTO;
    frame->i_qpplus1 = X264_QP_AUTO;
    frame->i_pts = -1;
    frame->i_frame = -1;
    frame->i_frame_num = -1;
    frame->i_lines_completed = -1;
    frame->b_fdec = b_fdec;
    frame->i_pic_struct = PIC_STRUCT_AUTO;
    frame->i_field_cnt = -1;
    frame->i_duration =
    frame->i_cpb_duration =
    frame->i_dpb_output_delay =
    frame->i_cpb_delay = 0;
    frame->i_coded_fields_lookahead =
    frame->i_cpb_delay_lookahead = -1;

    frame->orig = frame;

    if( i_csp == X264_CSP_NV12 || i_csp == X264_CSP_NV16 )
    {
        int chroma_padv = i_padv >> (i_csp == X264_CSP_NV12);
        int chroma_plane_size = (frame->i_stride[1] * (frame->i_lines[1] + 2*chroma_padv));
        PREALLOC( frame->buffer[1], (chroma_plane_size + padh_align) * sizeof(pixel) );
        if( PARAM_INTERLACED )
            PREALLOC( frame->buffer_fld[1], (chroma_plane_size + padh_align) * sizeof(pixel) );
    }

    /* all 4 luma planes allocated together, since the cacheline split code
     * requires them to be in-phase wrt cacheline alignment. */

    for( int p = 0; p < luma_plane_count; p++ )
    {
        int luma_plane_size = align_plane_size( frame->i_stride[p] * (frame->i_lines[p] + 2*i_padv), disalign );
        if( h->param.analyse.i_subpel_refine && b_fdec )
        {
            /* FIXME: Don't allocate both buffers in non-adaptive MBAFF. */
            PREALLOC( frame->buffer[p], (4*luma_plane_size + padh_align) * sizeof(pixel) );
            if( PARAM_INTERLACED )
                PREALLOC( frame->buffer_fld[p], (4*luma_plane_size + padh_align) * sizeof(pixel) );
        }
        else
        {
            PREALLOC( frame->buffer[p], (luma_plane_size + padh_align) * sizeof(pixel) );
            if( PARAM_INTERLACED )
                PREALLOC( frame->buffer_fld[p], (luma_plane_size + padh_align) * sizeof(pixel) );
        }
    }

    frame->b_duplicate = 0;

    if( b_fdec ) /* fdec frame */
    {
        PREALLOC( frame->mb_type, i_mb_count * sizeof(int8_t) );
        PREALLOC( frame->mb_partition, i_mb_count * sizeof(uint8_t) );
        PREALLOC( frame->mv[0], 2*16 * i_mb_count * sizeof(int16_t) );
        PREALLOC( frame->mv16x16, 2*(i_mb_count+1) * sizeof(int16_t) );
        PREALLOC( frame->ref[0], 4 * i_mb_count * sizeof(int8_t) );
        if( h->param.i_bframe )
        {
            PREALLOC( frame->mv[1], 2*16 * i_mb_count * sizeof(int16_t) );
            PREALLOC( frame->ref[1], 4 * i_mb_count * sizeof(int8_t) );
        }
        else
        {
            frame->mv[1]  = NULL;
            frame->ref[1] = NULL;
        }
        PREALLOC( frame->i_row_bits, i_lines/16 * sizeof(int) );
        PREALLOC( frame->f_row_qp, i_lines/16 * sizeof(float) );
        PREALLOC( frame->f_row_qscale, i_lines/16 * sizeof(float) );
        if( h->param.analyse.i_me_method >= X264_ME_ESA )
            PREALLOC( frame->buffer[3], frame->i_stride[0] * (frame->i_lines[0] + 2*i_padv) * sizeof(uint16_t) << h->frames.b_have_sub8x8_esa );
        if( PARAM_INTERLACED )
            PREALLOC( frame->field, i_mb_count * sizeof(uint8_t) );
        if( h->param.analyse.b_mb_info )
            PREALLOC( frame->effective_qp, i_mb_count * sizeof(uint8_t) );
    }
    else /* fenc frame */
    {
        if( h->frames.b_have_lowres )
        {
            int luma_plane_size = align_plane_size( frame->i_stride_lowres * (frame->i_lines[0]/2 + 2*PADV), disalign );

            PREALLOC( frame->buffer_lowres[0], 4 * luma_plane_size * sizeof(pixel) );
            if( h->param.rc.b_lookahead_8bit )
                PREALLOC( frame->buffer_lowres8, 4 * luma_plane_size );

            for( int j = 0; j <= !!h->param.i_bframe; j++ )
                for( int i = 0; i <= h->param.i_bframe; i++ )
                {
                    PREALLOC( frame->lowres_mvs[j][i], 2*i_mb_count*sizeof(int16_t) );
                    PREALLOC( frame->lowres_mv_costs[j][i], i_mb_count*sizeof(int) );
                }
            PREALLOC( frame->i_propagate_cost, i_mb_count * sizeof(uint16_t) );
            for( int j = 0; j <= h->param.i_bframe+1; j++ )
                for( int i = 0; i <= h->param.i_bframe+1; i++ )
                    PREALLOC( frame->lowres_costs[j][i], i_mb_count * sizeof(uint16_t) );
        }
        if( h->param.rc.i_aq_mode )
        {
            PREALLOC( frame->f_qp_offset, i_mb_count * sizeof(float) );
            PREALLOC( frame->f_qp_offset_aq, i_mb_count * sizeof(float) );
            if( h->frames.b_have_lowres )
                PREALLOC( frame->i_inv_qscale_factor, i_mb_count * sizeof(uint16_t) );
        }

        if( h->param.analyse.i_weighted_pred && !PARAM_INTERLACED &&
            (i_csp == X264_CSP_NV12 || i_csp == X264_CSP_NV16) )
            PREALLOC( frame->i_weight_csum, 2 * ((h->mb.i_mb_width + 15) & ~15) * h->mb.i_mb_height * sizeof(int32_t) );

        /* mbtree asm can overread the input buffers, make sure we don't read outside of allocated memory. */
        if( h->frames.b_have_lowres )
            prealloc_size += NATIVE_ALIGN;
    }

    PREALLOC_END( frame->base );

    if( i_csp == X264_CSP_NV12 || i_csp == X264_CSP_NV16 )
    {
        int chroma_padv = i_padv >> (i_csp == X264_CSP_NV12);
        frame->plane[1] = frame->buffer[1] + frame->i_stride[1] * chroma_padv + PADH + padh_align;
        if( PARAM_INTERLACED )
            frame->plane_fld[1] = frame->buffer_fld[1] + frame->i_stride[1] * chroma_padv + PADH + padh_align;
    }

    for( int p = 0; p < luma_plane_count; p++ )
    {
        int luma_plane_size = align_plane_size( frame->i_stride[p] * (frame->i_lines[p] + 2*i_padv), disalign );
        if( h->param.analyse.i_subpel_refine && b_fdec )
        {
            for( int i = 0; i < 4; i++ )
            {
                frame->filtered[p][i] = frame->buffer[p] + i*luma_plane_size + frame->i_stride[p] * i_padv + PADH + padh_align;
                frame->filtered_fld[p][i] = frame->buffer_fld[p] + i*luma_plane_size + frame->i_stride[p] * i_padv + PADH + padh_align;
            }
            frame->plane[p] = frame->filtered[p][0];
            frame->plane_fld[p] = frame->filtered_fld[p][0];
        }
        else
        {
            frame->filtered[p][0] = frame->plane[p] = frame->buffer[p] + frame->i_stride[p] * i_padv + PADH + padh_align;
            frame->filtered_fld[p][0] = frame->plane_fld[p] = frame->buffer_fld[p] + frame->i_stride[p] * i_padv + PADH + padh_align;
        }
    }

    /* Fault the pages in now, not in the first frames that use them: all of an
     * fdec; of an fenc, the picture rows and the lowres planes, as its borders,
     * field planes and per-mb lowres data may never be used. */
    if( b_touch )
    {
        if( b_fdec )
            memset( frame->base, 0, prealloc_size );
        else
        {
            for( int p = 0; p < frame->i_plane; p++ )
                memset( frame->plane[p] - PADH, 0, frame->i_stride[p] * frame->i_lines[p] * sizeof(pixel) );
            if( h->frames.b_have_lowres )
            {
                int luma_plane_size = align_plane_size( frame->i_stride_lowres * (frame->i_lines[0]/2 + 2*PADV), disalign );
                memset( frame->buffer_lowres[0], 0, 4 * luma_plane_size * sizeof(pixel) );
                if( h->param.rc.b_lookahead_8bit )
                    memset( frame->buffer_lowres8, 0, 4 * luma_plane_size );
            }
        }
    }

    if( b_fdec )
    {
        M32( frame->mv16x16[0] ) = 0;
        frame->mv16x16++;

        if( h->param.analyse.i_me_method >= X264_ME_ESA )
            frame->integral = (uint16_t*)frame->buffer[3] + frame->i_stride[0] * i_padv + PADH;
    }
    else
    {
        if( h->frames.b_have_lowres )
        {
            int luma_plane_size = align_plane_size( frame->i_stride_lowres * (frame->i_lines[0]/2 + 2*PADV), disalign );
            for( int i = 0; i < 4; i++ )
                frame->lowres[i] = frame->buffer_lowres[0] + (frame->i_stride_lowres * PADV + PADH) + i * luma_plane_size;
            if( h->param.rc.b_lookahead_8bit )
                for( int i = 0; i < 4; i++ )
                    frame->lowres8[i] = frame->buffer_lowres8 + (frame->i_stride_lowres * PADV + PADH) + i * luma_plane_size;

            for( int j = 0; j <= !!h->param.i_bframe; j++ )
                for( int i = 0; i <= h->param.i_bframe; i++ )
                    memset( frame->lowres_mvs[j][i], 0, 2*i_mb_count*sizeof(int16_t) );

            frame->i_intra_cost = frame->lowres_costs[0][0];
            memset( frame->i_intra_cost, -1, i_mb_count * sizeof(uint16_t) );

            if( h->param.rc.i_aq_mode )
                /* shouldn't really be initialized, just silences a valgrind false-positive in x264_mbtree_propagate_cost_sse2 */
                memset( frame->i_inv_qscale_factor, 0, i_mb_count * sizeof(uint16_t) );
        }
    }

    if( b_fdec && h->param.analyse.i_subpel_refine )
    {
        for( int i = 0; i < 1 + PARAM_INTERLACED; i++ )
        {
            CHECKED_MALLOCZERO( frame->hpel_cnt_tile[i], i_mb_count );
            CHECKED_MALLOCZERO( frame->hpel_cnt_row[i], frame->i_lines[0] * h->mb.i_mb_width );
        }
        frame->hpel_cnt_planes = luma_plane_count;
        frame->hpel_cnt_padx = PADH + padh_align;
        int slot = __atomic_load_n( &hpel_cnt_nreg, __ATOMIC_RELAXED );
        if( slot < HPEL_CNT_SLOTS )
        {
            hpel_cnt_reg[slot] = frame;
            __atomic_store_n( &hpel_cnt_nreg, slot+1, __ATOMIC_RELEASE );
        }
    }

    if( x264_pthread_mutex_init( &frame->mutex, NULL ) )
        goto fail;
    if( x264_pthread_cond_init( &frame->cv, NULL ) )
        goto fail;

#if HAVE_OPENCL
    frame->opencl.ocl = h->opencl.ocl;
#endif

    return frame;

fail:
    x264_free( frame );
    return NULL;
}

void x264_frame_delete( x264_frame_t *frame )
{
    /* Duplicate frames are blank copies of real frames (including pointers),
     * so freeing those pointers would cause a double free later. */
    if( !frame->b_duplicate )
    {
        if( frame->hpel_cnt_tile[0] )
        {
            hpel_cnt_flush( frame );
            for( int r = 0; r < hpel_cnt_nreg; r++ )
                if( hpel_cnt_reg[r] == frame )
                    hpel_cnt_reg[r] = NULL;
            for( int i = 0; i < 2; i++ )
            {
                x264_free( frame->hpel_cnt_tile[i] );
                x264_free( frame->hpel_cnt_row[i] );
            }
        }
        x264_free( frame->base );

        if( frame->param && frame->param->param_free )
            frame->param->param_free( frame->param );
        if( frame->mb_info_free )
            frame->mb_info_free( frame->mb_info );
        if( frame->extra_sei.sei_free )
        {
            for( int i = 0; i < frame->extra_sei.num_payloads; i++ )
                frame->extra_sei.sei_free( frame->extra_sei.payloads[i].payload );
            frame->extra_sei.sei_free( frame->extra_sei.payloads );
        }
        x264_pthread_mutex_destroy( &frame->mutex );
        x264_pthread_cond_destroy( &frame->cv );
#if HAVE_OPENCL
        x264_opencl_frame_delete( frame );
#endif
    }
    x264_free( frame );
}

static int get_plane_ptr( x264_t *h, x264_picture_t *src, uint8_t **pix, int *stride, int plane, int xshift, int yshift )
{
    int width = h->param.i_width >> xshift;
    int height = h->param.i_height >> yshift;
    *pix = src->img.plane[plane];
    *stride = src->img.i_stride[plane];
    if( src->img.i_csp & X264_CSP_VFLIP )
    {
        *pix += (height-1) * *stride;
        *stride = -*stride;
    }
    if( width > abs(*stride) )
    {
        x264_log( h, X264_LOG_ERROR, "Input picture width (%d) is greater than stride (%d)\n", width, *stride );
        return -1;
    }
    return 0;
}

#define get_plane_ptr(...) do{ if( get_plane_ptr(__VA_ARGS__) < 0 ) return -1; }while(0)

/* Validate the picture and copy its properties; the pixels are copied by
 * x264_frame_copy_picture_rows. */
int x264_frame_copy_picture_init( x264_t *h, x264_frame_t *dst, x264_picture_t *src )
{
    int i_csp = src->img.i_csp & X264_CSP_MASK;
    if( dst->i_csp != x264_frame_internal_csp( i_csp ) )
    {
        x264_log( h, X264_LOG_ERROR, "Invalid input colorspace\n" );
        return -1;
    }

#if HIGH_BIT_DEPTH
    if( !(src->img.i_csp & X264_CSP_HIGH_DEPTH) )
    {
        x264_log( h, X264_LOG_ERROR, "This build of x264 requires high depth input. Rebuild to support 8-bit input.\n" );
        return -1;
    }
#else
    if( src->img.i_csp & X264_CSP_HIGH_DEPTH )
    {
        x264_log( h, X264_LOG_ERROR, "This build of x264 requires 8-bit input. Rebuild to support high depth input.\n" );
        return -1;
    }
#endif

    if( BIT_DEPTH != 10 && i_csp == X264_CSP_V210 )
    {
        x264_log( h, X264_LOG_ERROR, "v210 input is only compatible with bit-depth of 10 bits\n" );
        return -1;
    }

    dst->i_type     = dst->i_forced_type = src->i_type;
    dst->i_qpplus1  = src->i_qpplus1;
    dst->i_pts      = dst->i_reordered_pts = src->i_pts;
    dst->param      = src->param;
    memcpy( dst->timecode, src->timecode, sizeof(dst->timecode) );
    dst->i_pic_struct = src->i_pic_struct;
    dst->extra_sei  = src->extra_sei;
    dst->opaque     = src->opaque;
    dst->mb_info    = h->param.analyse.b_mb_info ? src->prop.mb_info : NULL;
    dst->mb_info_free = h->param.analyse.b_mb_info ? src->prop.mb_info_free : NULL;

    /* The stride checks, before any row is copied */
    if( i_csp != X264_CSP_V210 && i_csp < X264_CSP_BGR )
    {
        int v_shift = CHROMA_V_SHIFT;
        uint8_t *pix;
        int stride;
        get_plane_ptr( h, src, &pix, &stride, 0, 0, 0 );
        if( i_csp == X264_CSP_NV12 || i_csp == X264_CSP_NV16 )
            get_plane_ptr( h, src, &pix, &stride, 1, 0, v_shift );
        else if( i_csp == X264_CSP_I420 || i_csp == X264_CSP_I422 || i_csp == X264_CSP_YV12 || i_csp == X264_CSP_YV16 )
        {
            int uv_swap = i_csp == X264_CSP_YV12 || i_csp == X264_CSP_YV16;
            get_plane_ptr( h, src, &pix, &stride, uv_swap ? 2 : 1, 1, v_shift );
            get_plane_ptr( h, src, &pix, &stride, uv_swap ? 1 : 2, 1, v_shift );
        }
        else //if( i_csp == X264_CSP_I444 || i_csp == X264_CSP_YV24 )
        {
            get_plane_ptr( h, src, &pix, &stride, i_csp==X264_CSP_I444 ? 1 : 2, 0, 0 );
            get_plane_ptr( h, src, &pix, &stride, i_csp==X264_CSP_I444 ? 2 : 1, 0, 0 );
        }
    }
    return 0;
}

/* Copy luma rows [y0,y1) of the picture and the chroma rows they cover, after
 * x264_frame_copy_picture_init. y0 and y1 are multiples of 16 or past the picture
 * height, so disjoint bands can be copied concurrently. */
void x264_frame_copy_picture_rows( x264_t *h, x264_frame_t *dst, x264_picture_t *src, int y0, int y1 )
{
    int i_csp = src->img.i_csp & X264_CSP_MASK;
    y1 = X264_MIN( y1, h->param.i_height );
    if( y1 <= y0 )
        return;
    int rows = y1 - y0;

    uint8_t *pix[3];
    int stride[3];
    if( i_csp == X264_CSP_V210 )
    {
         stride[0] = src->img.i_stride[0];
         pix[0] = src->img.plane[0];
         intptr_t i_src = stride[0]/sizeof(uint32_t);

         h->mc.plane_copy_deinterleave_v210( dst->plane[0] + y0 * dst->i_stride[0], dst->i_stride[0],
                                             dst->plane[1] + y0 * dst->i_stride[1], dst->i_stride[1],
                                             (uint32_t *)pix[0] + y0 * i_src, i_src, h->param.i_width, rows );
    }
    else if( i_csp >= X264_CSP_BGR )
    {
         stride[0] = src->img.i_stride[0];
         pix[0] = src->img.plane[0];
         if( src->img.i_csp & X264_CSP_VFLIP )
         {
             pix[0] += (h->param.i_height-1) * stride[0];
             stride[0] = -stride[0];
         }
         pix[0] += (intptr_t)y0 * stride[0];
         int b = i_csp==X264_CSP_RGB;
         h->mc.plane_copy_deinterleave_rgb( dst->plane[1+b] + y0 * dst->i_stride[1+b], dst->i_stride[1+b],
                                            dst->plane[0] + y0 * dst->i_stride[0], dst->i_stride[0],
                                            dst->plane[2-b] + y0 * dst->i_stride[2-b], dst->i_stride[2-b],
                                            (pixel*)pix[0], stride[0]/sizeof(pixel), i_csp==X264_CSP_BGRA ? 4 : 3, h->param.i_width, rows );
    }
    else
    {
        int v_shift = CHROMA_V_SHIFT;
        int c0 = y0 >> v_shift;
        int c_rows = (y1 >> v_shift) - c0;
        /* parenthesised: the checking macro returns, x264_frame_copy_picture_init checked */
        (get_plane_ptr)( h, src, &pix[0], &stride[0], 0, 0, 0 );
        h->mc.plane_copy( dst->plane[0] + y0 * dst->i_stride[0], dst->i_stride[0], (pixel*)(pix[0] + (intptr_t)y0 * stride[0]),
                          stride[0]/sizeof(pixel), h->param.i_width, rows );
        if( i_csp == X264_CSP_NV12 || i_csp == X264_CSP_NV16 )
        {
            (get_plane_ptr)( h, src, &pix[1], &stride[1], 1, 0, v_shift );
            h->mc.plane_copy( dst->plane[1] + c0 * dst->i_stride[1], dst->i_stride[1], (pixel*)(pix[1] + (intptr_t)c0 * stride[1]),
                              stride[1]/sizeof(pixel), h->param.i_width, c_rows );
        }
        else if( i_csp == X264_CSP_I420 || i_csp == X264_CSP_I422 || i_csp == X264_CSP_YV12 || i_csp == X264_CSP_YV16 )
        {
            int uv_swap = i_csp == X264_CSP_YV12 || i_csp == X264_CSP_YV16;
            (get_plane_ptr)( h, src, &pix[1], &stride[1], uv_swap ? 2 : 1, 1, v_shift );
            (get_plane_ptr)( h, src, &pix[2], &stride[2], uv_swap ? 1 : 2, 1, v_shift );
            h->mc.plane_copy_interleave( dst->plane[1] + c0 * dst->i_stride[1], dst->i_stride[1],
                                         (pixel*)(pix[1] + (intptr_t)c0 * stride[1]), stride[1]/sizeof(pixel),
                                         (pixel*)(pix[2] + (intptr_t)c0 * stride[2]), stride[2]/sizeof(pixel),
                                         h->param.i_width>>1, c_rows );
        }
        else //if( i_csp == X264_CSP_I444 || i_csp == X264_CSP_YV24 )
        {
            (get_plane_ptr)( h, src, &pix[1], &stride[1], i_csp==X264_CSP_I444 ? 1 : 2, 0, 0 );
            (get_plane_ptr)( h, src, &pix[2], &stride[2], i_csp==X264_CSP_I444 ? 2 : 1, 0, 0 );
            h->mc.plane_copy( dst->plane[1] + y0 * dst->i_stride[1], dst->i_stride[1], (pixel*)(pix[1] + (intptr_t)y0 * stride[1]),
                              stride[1]/sizeof(pixel), h->param.i_width, rows );
            h->mc.plane_copy( dst->plane[2] + y0 * dst->i_stride[2], dst->i_stride[2], (pixel*)(pix[2] + (intptr_t)y0 * stride[2]),
                              stride[2]/sizeof(pixel), h->param.i_width, rows );
        }
    }
}

int x264_frame_copy_picture( x264_t *h, x264_frame_t *dst, x264_picture_t *src )
{
    if( x264_frame_copy_picture_init( h, dst, src ) < 0 )
        return -1;
    x264_frame_copy_picture_rows( h, dst, src, 0, h->param.i_height );
    return 0;
}

static void ALWAYS_INLINE pixel_memset( pixel *dst, pixel *src, int len, int size )
{
    uint8_t *dstp = (uint8_t*)dst;
    uint32_t v1 = *src;
    uint32_t v2 = size == 1 ? v1 + (v1 <<  8) : M16( src );
    uint32_t v4 = size <= 2 ? v2 + (v2 << 16) : M32( src );
    int i = 0;
    len *= size;

    /* Align the input pointer if it isn't already */
    if( (intptr_t)dstp & (WORD_SIZE - 1) )
    {
        if( size <= 2 && ((intptr_t)dstp & 3) )
        {
            if( size == 1 && ((intptr_t)dstp & 1) )
                dstp[i++] = v1;
            if( (intptr_t)dstp & 2 )
            {
                M16( dstp+i ) = v2;
                i += 2;
            }
        }
        if( WORD_SIZE == 8 && (intptr_t)dstp & 4 )
        {
            M32( dstp+i ) = v4;
            i += 4;
        }
    }

    /* Main copy loop */
    if( WORD_SIZE == 8 )
    {
        uint64_t v8 = v4 + ((uint64_t)v4<<32);
        for( ; i < len - 7; i+=8 )
            M64( dstp+i ) = v8;
    }
    for( ; i < len - 3; i+=4 )
        M32( dstp+i ) = v4;

    /* Finish up the last few bytes */
    if( size <= 2 )
    {
        if( i < len - 1 )
        {
            M16( dstp+i ) = v2;
            i += 2;
        }
        if( size == 1 && i != len )
            dstp[i] = v1;
    }
}

/* src: same layout as pix, already expanded wherever its padded rows are copied */
static void ALWAYS_INLINE plane_expand_border_src( pixel *pix, pixel *src, int i_stride, int i_width, int i_height, int i_padh, int i_padv, int b_pad_top, int b_pad_bottom, int b_chroma )
{
#define PPIXEL(x, y) ( pix + (x) + (y)*i_stride )
#define SPIXEL(x, y) ( src + (x) + (y)*i_stride )
    for( int y = 0; y < i_height; y++ )
    {
        /* left band */
        pixel_memset( PPIXEL(-i_padh, y), SPIXEL(0, y), i_padh>>b_chroma, sizeof(pixel)<<b_chroma );
        /* right band */
        pixel_memset( PPIXEL(i_width, y), SPIXEL(i_width-1-b_chroma, y), i_padh>>b_chroma, sizeof(pixel)<<b_chroma );
    }
    /* upper band */
    if( b_pad_top )
        for( int y = 0; y < i_padv; y++ )
            memcpy( PPIXEL(-i_padh, -y-1), SPIXEL(-i_padh, 0), (i_width+2*i_padh) * sizeof(pixel) );
    /* lower band */
    if( b_pad_bottom )
        for( int y = 0; y < i_padv; y++ )
            memcpy( PPIXEL(-i_padh, i_height+y), SPIXEL(-i_padh, i_height-1), (i_width+2*i_padh) * sizeof(pixel) );
#undef SPIXEL
#undef PPIXEL
}

static void ALWAYS_INLINE plane_expand_border( pixel *pix, int i_stride, int i_width, int i_height, int i_padh, int i_padv, int b_pad_top, int b_pad_bottom, int b_chroma )
{
    plane_expand_border_src( pix, pix, i_stride, i_width, i_height, i_padh, i_padv, b_pad_top, b_pad_bottom, b_chroma );
}

void x264_frame_expand_border( x264_t *h, x264_frame_t *frame, int mb_y )
{
    int pad_top = mb_y == 0;
    int pad_bot = mb_y == h->mb.i_mb_height - (1 << SLICE_MBAFF);
    int b_start = mb_y == h->i_threadslice_start;
    int b_end   = mb_y == h->i_threadslice_end - (1 << SLICE_MBAFF);
    if( mb_y & SLICE_MBAFF )
        return;
    for( int i = 0; i < frame->i_plane; i++ )
    {
        int h_shift = i && CHROMA_H_SHIFT;
        int v_shift = i && CHROMA_V_SHIFT;
        int stride = frame->i_stride[i];
        int width = 16*h->mb.i_mb_width;
        int height = (pad_bot ? 16*(h->mb.i_mb_height - mb_y) >> SLICE_MBAFF : 16) >> v_shift;
        int padh = PADH;
        int padv = PADV >> v_shift;
        // buffer: 2 chroma, 3 luma (rounded to 4) because deblocking goes beyond the top of the mb
        if( b_end && !b_start )
            height += 4 >> (v_shift + SLICE_MBAFF);
        pixel *pix;
        int starty = 16*mb_y - 4*!b_start;
        if( SLICE_MBAFF )
        {
            int height_frm = (pad_bot ? 16*(h->mb.i_mb_height - mb_y) : 32) >> v_shift;
            if( b_end && !b_start )
                height_frm += 4 >> v_shift;
            pixel *pix_frm = frame->plane[i] + (starty*stride >> v_shift);
            plane_expand_border( pix_frm, stride, width, height_frm, padh, padv, pad_top, pad_bot, h_shift );

            /* border samples for each field are extended separately, from the
             * frame plane: plane_fld rows may not have been copied yet */
            pix = frame->plane_fld[i] + (starty*stride >> v_shift);
            plane_expand_border_src( pix, pix_frm, stride*2, width, height, padh, padv, pad_top, pad_bot, h_shift );
            plane_expand_border_src( pix+stride, pix_frm+stride, stride*2, width, height, padh, padv, pad_top, pad_bot, h_shift );
        }
        else
        {
            pix = frame->plane[i] + (starty*stride >> v_shift);
            plane_expand_border( pix, stride, width, height, padh, padv, pad_top, pad_bot, h_shift );
        }
    }
}

void x264_frame_expand_border_filtered( x264_t *h, x264_frame_t *frame, int mb_y, int b_end )
{
    /* during filtering, 8 extra pixels were filtered on each edge,
     * but up to 3 of the horizontal ones may be wrong.
       we want to expand border from the last filtered pixel */
    int b_start = !mb_y;
    int width = 16*h->mb.i_mb_width + 8;
    int height = b_end ? (16*(h->mb.i_mb_height - mb_y) >> SLICE_MBAFF) + 16 : 16;
    int padh = PADH - 4;
    int padv = PADV - 8;
    for( int p = 0; p < (CHROMA444 ? 3 : 1); p++ )
        for( int i = 1; i < 4; i++ )
        {
            int stride = frame->i_stride[p];
            // buffer: 8 luma, to match the hpel filter
            pixel *pix;
            if( SLICE_MBAFF )
            {
                pix = frame->filtered_fld[p][i] + (16*mb_y - 16) * stride - 4;
                plane_expand_border( pix, stride*2, width, height, padh, padv, b_start, b_end, 0 );
                plane_expand_border( pix+stride, stride*2, width, height, padh, padv, b_start, b_end, 0 );
            }

            pix = frame->filtered[p][i] + (16*mb_y - 8) * stride - 4;
            plane_expand_border( pix, stride, width, height << SLICE_MBAFF, padh, padv, b_start, b_end, 0 );
        }
}

void x264_frame_expand_border_lowres( x264_frame_t *frame )
{
    for( int i = 0; i < 4; i++ )
        plane_expand_border( frame->lowres[i], frame->i_stride_lowres, frame->i_width_lowres, frame->i_lines_lowres, PADH, PADV, 1, 1, 0 );
}

/* Lowres rows [y0,y1): side padding, and the padding above or below when the
 * band is the first or last. */
void x264_frame_expand_border_lowres_rows( x264_frame_t *frame, int y0, int y1 )
{
    for( int i = 0; i < 4; i++ )
        plane_expand_border( frame->lowres[i] + y0 * frame->i_stride_lowres, frame->i_stride_lowres, frame->i_width_lowres, y1 - y0,
                             PADH, PADV, !y0, y1 == frame->i_lines_lowres, 0 );
}

#if HIGH_BIT_DEPTH
/* x264_frame_expand_border_lowres_rows on lowres8[] */
void x264_frame_expand_border_lowres8_rows( x264_frame_t *frame, int y0, int y1 )
{
    int stride = frame->i_stride_lowres;
    int width = frame->i_width_lowres;
    for( int i = 0; i < 4; i++ )
    {
        uint8_t *pix = frame->lowres8[i];
        for( int y = y0; y < y1; y++ )
        {
            memset( pix + y*stride - PADH, pix[y*stride], PADH );
            memset( pix + y*stride + width, pix[y*stride + width-1], PADH );
        }
        if( !y0 )
            for( int y = 0; y < PADV; y++ )
                memcpy( pix - (y+1)*stride - PADH, pix - PADH, width + 2*PADH );
        if( y1 == frame->i_lines_lowres )
            for( int y = 0; y < PADV; y++ )
                memcpy( pix + (y1+y)*stride - PADH, pix + (y1-1)*stride - PADH, width + 2*PADH );
    }
}
#endif

void x264_frame_expand_border_chroma( x264_t *h, x264_frame_t *frame, int plane )
{
    int v_shift = CHROMA_V_SHIFT;
    plane_expand_border( frame->plane[plane], frame->i_stride[plane], 16*h->mb.i_mb_width, 16*h->mb.i_mb_height>>v_shift,
                         PADH, PADV>>v_shift, 1, 1, CHROMA_H_SHIFT );
}

void x264_frame_expand_border_mod16( x264_t *h, x264_frame_t *frame )
{
    x264_frame_expand_border_mod16_rows( h, frame, 0, 16 * h->mb.i_mb_height );
}

/* Padding of luma rows [y0,y1) and the chroma rows they cover; y0 and y1 are
 * multiples of 16. The band ending at the frame bottom also pads below the
 * picture, copying from its last rows, so that band must hold them. */
void x264_frame_expand_border_mod16_rows( x264_t *h, x264_frame_t *frame, int y0, int y1 )
{
    for( int i = 0; i < frame->i_plane; i++ )
    {
        int i_width = h->param.i_width;
        int h_shift = i && CHROMA_H_SHIFT;
        int v_shift = i && CHROMA_V_SHIFT;
        int i_height = h->param.i_height >> v_shift;
        int i_padx = (h->mb.i_mb_width * 16 - h->param.i_width);
        int i_pady = (h->mb.i_mb_height * 16 - h->param.i_height) >> v_shift;

        if( i_padx )
        {
            int row_end = X264_MIN( y1 >> v_shift, i_height );
            for( int y = y0 >> v_shift; y < row_end; y++ )
                pixel_memset( &frame->plane[i][y*frame->i_stride[i] + i_width],
                              &frame->plane[i][y*frame->i_stride[i] + i_width - 1-h_shift],
                              i_padx>>h_shift, sizeof(pixel)<<h_shift );
        }
        if( i_pady && y1 == 16 * h->mb.i_mb_height )
        {
            for( int y = i_height; y < i_height + i_pady; y++ )
                memcpy( &frame->plane[i][y*frame->i_stride[i]],
                        &frame->plane[i][(i_height-(~y&PARAM_INTERLACED)-1)*frame->i_stride[i]],
                        (i_width + i_padx) * sizeof(pixel) );
        }
    }
}

/* The padding below the picture is per field, and x264_expand_border_mbpair
 * makes it per frame under frame mbpairs. With weightp and frame threads the
 * lookahead may read this frame's source as a reference meanwhile, so the
 * bottom mbpair row (and the 2 rows above it, for intra prediction from the
 * source) is copied to fenc_bot and padded there. */
void x264_fenc_bot_copy( x264_t *h )
{
    for( int i = 0; i < h->fenc->i_plane; i++ )
    {
        int height = 16 >> (i && CHROMA_V_SHIFT);
        int stride = h->fenc->i_stride[i];
        int y0 = height*(h->mb.i_mb_height-2) - 2;
        for( int y = 0; y < 2*height+2; y++ )
            memcpy( h->mb.fenc_bot[i] + PADH + y*stride, h->fenc->plane[i] + (y0+y)*stride,
                    16*h->mb.i_mb_width*sizeof(pixel) );
    }
    h->mb.b_fenc_bot = 1;
}

void x264_expand_border_mbpair( x264_t *h, int mb_x, int mb_y )
{
    for( int i = 0; i < h->fenc->i_plane; i++ )
    {
        int v_shift = i && CHROMA_V_SHIFT;
        int stride = h->fenc->i_stride[i];
        int height = h->param.i_height >> v_shift;
        int pady = (h->mb.i_mb_height * 16 - h->param.i_height) >> v_shift;
        pixel *fenc = h->fenc->plane[i] + 16*mb_x + height*stride;
        if( h->mb.b_fenc_bot )
            fenc = h->mb.fenc_bot[i] + PADH + 16*mb_x + (height - ((16 >> v_shift)*(h->mb.i_mb_height-2) - 2))*stride;
        for( int y = 0; y < pady; y++ )
            memcpy( fenc + y*stride, fenc - stride, 16*sizeof(pixel) );
    }
}

/* threading */
void x264_frame_cond_broadcast( x264_frame_t *frame, int i_lines_completed )
{
    x264_pthread_mutex_lock( &frame->mutex );
#if X264_FRAME_LINES_ATOMIC
    __atomic_store_n( &frame->i_lines_completed, i_lines_completed, __ATOMIC_RELAXED );
#else
    frame->i_lines_completed = i_lines_completed;
#endif
    x264_pthread_cond_broadcast( &frame->cv );
    x264_pthread_mutex_unlock( &frame->mutex );
}

int x264_frame_cond_wait( x264_frame_t *frame, int i_lines_completed )
{
    int completed;
    x264_pthread_mutex_lock( &frame->mutex );
    while( (completed = frame->i_lines_completed) < i_lines_completed && i_lines_completed >= 0 )
        x264_pthread_cond_wait( &frame->cv, &frame->mutex );
    x264_pthread_mutex_unlock( &frame->mutex );
    return completed;
}

void x264_threadslice_cond_broadcast( x264_t *h, int pass )
{
    x264_pthread_mutex_lock( &h->mutex );
    h->i_threadslice_pass = pass;
    if( pass > 0 )
        x264_pthread_cond_broadcast( &h->cv );
    x264_pthread_mutex_unlock( &h->mutex );
}

void x264_threadslice_cond_wait( x264_t *h, int pass )
{
    x264_pthread_mutex_lock( &h->mutex );
    while( h->i_threadslice_pass < pass )
        x264_pthread_cond_wait( &h->cv, &h->mutex );
    x264_pthread_mutex_unlock( &h->mutex );
}

int x264_frame_new_slice( x264_t *h, x264_frame_t *frame )
{
    if( h->param.i_slice_count_max )
    {
        int slice_count;
        if( h->param.b_sliced_threads )
            slice_count = x264_pthread_fetch_and_add( &frame->i_slice_count, 1, &frame->mutex );
        else
            slice_count = frame->i_slice_count++;
        if( slice_count >= h->param.i_slice_count_max )
            return -1;
    }
    return 0;
}

/* list operators */

void x264_frame_push( x264_frame_t **list, x264_frame_t *frame )
{
    int i = 0;
    while( list[i] ) i++;
    list[i] = frame;
}

x264_frame_t *x264_frame_pop( x264_frame_t **list )
{
    x264_frame_t *frame;
    int i = 0;
    assert( list[0] );
    while( list[i+1] ) i++;
    frame = list[i];
    list[i] = NULL;
    return frame;
}

void x264_frame_unshift( x264_frame_t **list, x264_frame_t *frame )
{
    int i = 0;
    while( list[i] ) i++;
    while( i-- )
        list[i+1] = list[i];
    list[0] = frame;
}

x264_frame_t *x264_frame_shift( x264_frame_t **list )
{
    x264_frame_t *frame = list[0];
    int i;
    for( i = 0; list[i]; i++ )
        list[i] = list[i+1];
    assert(frame);
    return frame;
}

void x264_frame_push_unused( x264_t *h, x264_frame_t *frame )
{
    assert( frame->i_reference_count > 0 );
    frame->i_reference_count--;
    if( frame->i_reference_count == 0 )
        x264_frame_push( h->frames.unused[frame->b_fdec], frame );
}

x264_frame_t *x264_frame_pop_unused( x264_t *h, int b_fdec )
{
    x264_frame_t *frame;
    if( h->frames.unused[b_fdec][0] )
    {
        frame = x264_frame_pop( h->frames.unused[b_fdec] );
        if( frame->hpel_cnt_tile[0] )
            hpel_cnt_flush( frame );
    }
    else
        frame = x264_frame_new( h, b_fdec, 0 );
    if( !frame )
        return NULL;
    frame->b_last_minigop_bframe = 0;
    frame->i_reference_count = 1;
    frame->b_intra_calculated = 0;
    frame->b_unweighted_cut = 0;
    frame->b_weight_csum = 0;
    frame->b_scenecut = 1;
    frame->b_keyframe = 0;
    frame->b_corrupt = 0;
    frame->i_slice_count = h->param.b_sliced_threads ? h->param.i_threads : 1;

    memset( frame->weight, 0, sizeof(frame->weight) );
    memset( frame->f_weighted_cost_delta, 0, sizeof(frame->f_weighted_cost_delta) );
    memset( frame->f_offset_weight_ratio, 0, sizeof(frame->f_offset_weight_ratio) );

    return frame;
}

/* Fill the unused pool with i_frames frames, their pages faulted in, so that
 * x264_frame_pop_unused takes them instead of allocating on first use. */
int x264_frame_prealloc_unused( x264_t *h, int b_fdec, int i_frames )
{
    for( int i = 0; i < i_frames; i++ )
    {
        x264_frame_t *frame = x264_frame_new( h, b_fdec, 1 );
        if( !frame )
            return -1;
        x264_frame_push( h->frames.unused[b_fdec], frame );
    }
    return 0;
}

void x264_frame_push_blank_unused( x264_t *h, x264_frame_t *frame )
{
    assert( frame->i_reference_count > 0 );
    frame->i_reference_count--;
    if( frame->i_reference_count == 0 )
        x264_frame_push( h->frames.blank_unused, frame );
}

x264_frame_t *x264_frame_pop_blank_unused( x264_t *h )
{
    x264_frame_t *frame;
    if( h->frames.blank_unused[0] )
        frame = x264_frame_pop( h->frames.blank_unused );
    else
        frame = x264_malloc( sizeof(x264_frame_t) );
    if( !frame )
        return NULL;
    frame->b_duplicate = 1;
    frame->i_reference_count = 1;
    return frame;
}

void x264_weight_scale_plane( x264_t *h, pixel *dst, intptr_t i_dst_stride, pixel *src, intptr_t i_src_stride,
                              int i_width, int i_height, x264_weight_t *w )
{
    if( h->mc.weight_plane && h->mc.weight_plane( dst, i_dst_stride, src, i_src_stride, w, i_width, i_height ) )
        return;
    /* Weight horizontal strips of height 16. This was found to be the optimal height
     * in terms of the cache loads. */
    while( i_height > 0 )
    {
        int x;
        for( x = 0; x < i_width-8; x += 16 )
            w->weightfn[16>>2]( dst+x, i_dst_stride, src+x, i_src_stride, w, X264_MIN( i_height, 16 ) );
        if( x < i_width )
            w->weightfn[ 8>>2]( dst+x, i_dst_stride, src+x, i_src_stride, w, X264_MIN( i_height, 16 ) );
        i_height -= 16;
        dst += 16 * i_dst_stride;
        src += 16 * i_src_stride;
    }
}

void x264_frame_delete_list( x264_frame_t **list )
{
    int i = 0;
    if( !list )
        return;
    while( list[i] )
        x264_frame_delete( list[i++] );
    x264_free( list );
}

int x264_sync_frame_list_init( x264_sync_frame_list_t *slist, int max_size )
{
    if( max_size < 0 )
        return -1;
    slist->i_max_size = max_size;
    slist->i_size = 0;
    CHECKED_MALLOCZERO( slist->list, (max_size+1) * sizeof(x264_frame_t*) );
    if( x264_pthread_mutex_init( &slist->mutex, NULL ) ||
        x264_pthread_cond_init( &slist->cv_fill, NULL ) ||
        x264_pthread_cond_init( &slist->cv_empty, NULL ) )
        return -1;
    return 0;
fail:
    return -1;
}

void x264_sync_frame_list_delete( x264_sync_frame_list_t *slist )
{
    x264_pthread_mutex_destroy( &slist->mutex );
    x264_pthread_cond_destroy( &slist->cv_fill );
    x264_pthread_cond_destroy( &slist->cv_empty );
    x264_frame_delete_list( slist->list );
}

void x264_sync_frame_list_push( x264_sync_frame_list_t *slist, x264_frame_t *frame )
{
    x264_pthread_mutex_lock( &slist->mutex );
    while( slist->i_size == slist->i_max_size )
        x264_pthread_cond_wait( &slist->cv_empty, &slist->mutex );
    slist->list[ slist->i_size++ ] = frame;
    x264_pthread_mutex_unlock( &slist->mutex );
    x264_pthread_cond_broadcast( &slist->cv_fill );
}

x264_frame_t *x264_sync_frame_list_pop( x264_sync_frame_list_t *slist )
{
    x264_frame_t *frame;
    x264_pthread_mutex_lock( &slist->mutex );
    while( !slist->i_size )
        x264_pthread_cond_wait( &slist->cv_fill, &slist->mutex );
    frame = slist->list[ --slist->i_size ];
    slist->list[ slist->i_size ] = NULL;
    x264_pthread_cond_broadcast( &slist->cv_empty );
    x264_pthread_mutex_unlock( &slist->mutex );
    return frame;
}
