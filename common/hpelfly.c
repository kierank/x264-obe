/*****************************************************************************
 * hpelfly.c: subpel interpolation on the fly, without stored hpel planes
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

#include "common.h"

x264_fly_ofs_t x264_fly_box_search_tab[FLY_HMAX+1][FLY_QMAX+1][16];

/* the reads of every mv refine_subpel can visit from a start of residue (rx,ry):
 * hpel diamond steps keep to start + 2*(i,j), |i|+|j| <= hpel_iters (the satd
 * re-cost is at one of them), then qpel steps add (a,b), |a|+|b| <= qpel_iters */
void x264_fly_tables_init( void )
{
    for( int hi = 0; hi <= FLY_HMAX; hi++ )
        for( int qi = 0; qi <= FLY_QMAX; qi++ )
            for( int r = 0; r < 16; r++ )
            {
                int rx = r&3, ry = r>>2;
                int x0[4], x1[4], y0[4], y1[4], mask = 0;
                for( int k = 0; k < 4; k++ )
                {
                    x0[k] = y0[k] = 127;
                    x1[k] = y1[k] = -128;
                }
                for( int i = -hi; i <= hi; i++ )
                    for( int j = -hi; j <= hi; j++ )
                    {
                        if( abs(i) + abs(j) > hi )
                            continue;
                        for( int a = -qi; a <= qi; a++ )
                            for( int b = -qi; b <= qi; b++ )
                            {
                                if( abs(a) + abs(b) > qi )
                                    continue;
                                x264_fly_box_t c;
                                /* bw = bh = 0: x1, y1 hold the last row and column start */
                                x264_fly_box_mv( &c, rx + 2*i + a, ry + 2*j + b, 0, 0 );
                                mask |= c.mask;
                                for( int k = 0; k < 4; k++ )
                                    if( c.mask & (1 << k) )
                                    {
                                        x0[k] = X264_MIN( x0[k], c.x0[k] );
                                        x1[k] = X264_MAX( x1[k], c.x1[k] );
                                        y0[k] = X264_MIN( y0[k], c.y0[k] );
                                        y1[k] = X264_MAX( y1[k], c.y1[k] );
                                    }
                            }
                    }
                x264_fly_ofs_t *o = &x264_fly_box_search_tab[hi][qi][r];
                o->mask = mask;
                o->ry0 = 0;
                o->ry1 = 0;
                for( int k = 1, any = 0; k < 4; k++ )
                    if( mask & (1 << k) )
                    {
                        o->ry0 = any ? X264_MIN( o->ry0, y0[k] ) : y0[k];
                        o->ry1 = any ? X264_MAX( o->ry1, y1[k] ) : y1[k];
                        any = 1;
                    }
                for( int k = 0; k < 4; k++ )
                {
                    o->x0[k] = mask & (1 << k) ? x0[k] : 0;
                    o->x1[k] = mask & (1 << k) ? x1[k] : 0;
                    o->y0[k] = mask & (1 << k) ? y0[k] : 0;
                    o->y1[k] = mask & (1 << k) ? y1[k] : 0;
                }
            }
}

static ALWAYS_INLINE uint64_t fly_rows( int r0, int r1 )
{
    return (r1 - r0 >= 64 ? ~0ULL : (1ULL << (r1 - r0)) - 1) << r0;
}

static ALWAYS_INLINE int fly_ctz64( uint64_t x )
{
    return __builtin_ctzll( x );
}

static ALWAYS_INLINE int fly_clz64( uint64_t x )
{
    return __builtin_clzll( x );
}

/* plane k of window w over window rows [y0,y1), columns [x0,x1); f0 is F at the window origin */
static ALWAYS_INLINE void fly_ensure( x264_t *h, x264_fly_win_t *w, int k, int x0, int x1, int y0, int y1,
                                      pixel *f0, intptr_t stride )
{
    uint64_t rows = fly_rows( y0, y1 );
    int g0 = x0 >> 4, g1 = (x1 + 15) >> 4;
    uint64_t miss = 0;
    int gl = FLY_NG, gr = -1;
    for( int g = g0; g < g1; g++ )
    {
        uint64_t m = rows & ~w->valid[k][g];
        if( m )
        {
            miss |= m;
            gl = X264_MIN( gl, g );
            gr = g;
        }
    }
    if( !miss )
        return;
    int r0 = fly_ctz64( miss );
    int r1 = 64 - fly_clz64( miss );
    h->mc.hpel_fly[k]( w->plane[k] + r0*FLY_WS + 16*gl, FLY_WS, f0 + r0*stride + 16*gl, stride,
                       16*(gr-gl+1), r1-r0 );
    uint64_t span = fly_rows( r0, r1 );
    for( int g = gl; g <= gr; g++ )
        w->valid[k][g] |= span;
#if HPELFLY_STATS
    h->fly->st_px[k] += 16*(gr-gl+1)*(r1-r0);
    h->fly->st_calls[k]++;
#endif
}

static ALWAYS_INLINE int fly_contains( x264_fly_win_t *w, int x0, int x1, int y0, int y1 )
{
    return x0 >= w->x0 && x1 <= w->x0 + FLY_W && y0 >= w->y0 && y1 <= w->y0 + FLY_H;
}

typedef unsigned __int128 fly_u128;

static ALWAYS_INLINE fly_u128 fly_band_valid( x264_fly_band_t *bd )
{
    return (fly_u128)bd->valid[1] << 64 | bd->valid[0];
}

static ALWAYS_INLINE void fly_band_set_valid( x264_fly_band_t *bd, fly_u128 v )
{
    bd->valid[0] = (uint64_t)v;
    bd->valid[1] = (uint64_t)(v >> 64);
}

/* band rows [p0, p1) */
static ALWAYS_INLINE fly_u128 fly_band_rows( int p0, int p1 )
{
    return (((fly_u128)1 << (p1 - p0)) - 1) << p0;
}

/* the band at fref (stride, F at the block, (ax,ay) of the plane) for H, V, C rows
 * [ry0, ry1): 0 if they are outside it, else its planes and stride in dst */
static int fly_band_planes( x264_t *h, x264_fly_band_t *bd, pixel **fref, intptr_t stride, int ax, int ay,
                            int ry0, int ry1, pixel *dst[4] )
{
    x264_fly_t *fly = h->fly;
    /* the mb row (pair row for MBAFF frame mbs) +- 24 */
    int pair = SLICE_MBAFF && !MB_INTERLACED;
    int base = 16*(h->mb.i_mb_y >> (MB_INTERLACED|pair)) << pair;
    int lo = base - 24, hi = base + (16 << pair) + 24;
    if( bd->gen != fly->gen )
    {
        bd->gen = fly->gen;
        bd->org = lo;
        bd->valid[0] = bd->valid[1] = 0;
    }
    else if( lo < bd->org || hi > bd->org + FLY_BR )
    {
        /* move the computed rows from lo on to the top */
        int d = lo - bd->org;
        fly_u128 v = d > 0 && d < FLY_BR ? fly_band_valid( bd ) >> d : 0;
        for( int p = 0; p < FLY_BR - d && v; p++ )
            if( (v >> p) & 1 )
            {
                for( int k = 1; k < 4; k++ )
                    memcpy( bd->plane[k] + p*bd->stride - PADH, bd->plane[k] + (p+d)*bd->stride - PADH,
                            (fly->width + 2*PADH) * sizeof(pixel) );
#if HPELFLY_STATS
                fly->st_band_moved++;
#endif
            }
        fly_band_set_valid( bd, v );
        bd->org = lo;
    }
    if( ry0 < bd->org || ry1 > bd->org + FLY_BR )
        return 0;
    if( ry1 > ry0 )
    {
        fly_u128 need = fly_band_rows( ry0 - bd->org, ry1 - bd->org );
        fly_u128 valid = fly_band_valid( bd );
        fly_u128 miss = need & ~valid;
        if( miss )
        {
            /* the missing rows, whole, in runs */
            pixel *f0 = fref[0] - ax - PADH + (bd->org - ay) * stride;
            for( int p = ry0 - bd->org; p < ry1 - bd->org; )
            {
                if( !((miss >> p) & 1) )
                {
                    p++;
                    continue;
                }
                int q = p + 1;
                while( q < ry1 - bd->org && ((miss >> q) & 1) )
                    q++;
                for( int k = 1; k < 4; k++ )
                    h->mc.hpel_fly[k]( bd->plane[k] + p*bd->stride - PADH, bd->stride, f0 + p*stride, stride,
                                       fly->width + 2*PADH, q - p );
#if HPELFLY_STATS
                fly->st_band_rows += q - p;
#endif
                p = q;
            }
            fly_band_set_valid( bd, valid | need );
        }
    }
#if HPELFLY_STATS
    fly->st_band_req++;
#endif
    dst[0] = fref[0];
    intptr_t off = (ay - bd->org) * bd->stride + ax;
    for( int k = 1; k < 4; k++ )
        dst[k] = bd->plane[k] + off;
    return bd->stride;
}

intptr_t x264_fly_planes( x264_t *h, pixel **fref, intptr_t stride, int bx, int by, const x264_fly_box_t *b, pixel *dst[4] )
{
    x264_fly_t *fly = h->fly;
    x264_fly_slot_t *sl = &fly->slot[x264_fly_ref( fref )];
    if( sl->band )
    {
        int ax = 16*h->mb.i_mb_x + bx;
        int ay = 16*(h->mb.i_mb_y >> MB_INTERLACED) + by;
        int ry0 = INT_MAX, ry1 = INT_MIN;
        for( int k = 1; k < 4; k++ )
            if( b->mask & (1 << k) )
            {
                ry0 = X264_MIN( ry0, b->y0[k] );
                ry1 = X264_MAX( ry1, b->y1[k] );
            }
        if( ry1 < ry0 )
            ry0 = ry1 = 0;
        if( fly_band_planes( h, sl->band, fref, stride, ax, ay, ry0 + ay, ry1 + ay, dst ) )
            return stride;
    }
    if( sl->gen != fly->gen )
    {
        sl->gen = fly->gen;
        sl->win[0].x0 = sl->win[1].x0 = INT_MIN;
    }
    /* the block in px of the reference plane (field rows for a field mb) */
    int ax = 16*h->mb.i_mb_x + bx;
    int ay = 16*(h->mb.i_mb_y >> MB_INTERLACED) + by;
    int ux0 = INT_MAX, ux1 = INT_MIN, uy0 = INT_MAX, uy1 = INT_MIN;
    for( int k = 0; k < 4; k++ )
        if( b->mask & (1 << k) )
        {
            ux0 = X264_MIN( ux0, b->x0[k] );
            ux1 = X264_MAX( ux1, b->x1[k] );
            uy0 = X264_MIN( uy0, b->y0[k] );
            uy1 = X264_MAX( uy1, b->y1[k] );
        }
    ux0 += ax; ux1 += ax;
    uy0 += ay; uy1 += ay;
#if HPELFLY_STATS
    fly->st_req++;
#endif
    int wi = sl->last;
    x264_fly_win_t *w = &sl->win[wi];
    if( !fly_contains( w, ux0, ux1, uy0, uy1 ) )
    {
        wi ^= 1;
        w = &sl->win[wi];
        if( !fly_contains( w, ux0, ux1, uy0, uy1 ) )
        {
            /* the least recently used window, the request near its left: mbs go right */
            int gx0 = ux0 & ~15;
            int free = FLY_W - (((ux1 + 15) & ~15) - gx0);
            w->x0 = gx0 - (free >= 32 ? 16 : 0);
            w->y0 = uy0 - ((FLY_H - (uy1 - uy0)) >> 1);
            memset( w->valid, 0, sizeof(w->valid) );
#if HPELFLY_STATS
            fly->st_place++;
#endif
        }
        sl->last = wi;
    }
    pixel *f0 = fref[0] + (w->x0 - ax) + (w->y0 - ay) * stride;
    int ox = ax - w->x0, oy = ay - w->y0;
    for( int k = 0; k < 4; k++ )
        if( b->mask & (1 << k) )
            fly_ensure( h, w, k, b->x0[k] + ox, b->x1[k] + ox, b->y0[k] + oy, b->y1[k] + oy, f0, stride );
    intptr_t off = oy * FLY_WS + ox;
    for( int k = 0; k < 4; k++ )
        dst[k] = w->plane[k] + off;
    return FLY_WS;
}

pixel *x264_fly_get_ref( x264_t *h, pixel *dst, intptr_t *i_dst_stride, pixel **src, intptr_t i_src_stride,
                         int mvx, int mvy, int i_width, int i_height, const x264_weight_t *weight, int bx, int by )
{
    pixel *p[4];
    intptr_t ws = x264_fly_planes_mv( h, src, i_src_stride, bx, by, mvx, mvy, i_width, i_height, p );
    return h->mc.get_ref( dst, i_dst_stride, p, ws, mvx, mvy, i_width, i_height, weight );
}

pixel *x264_fly_get_ref_copy( x264_t *h, pixel *dst, intptr_t *i_dst_stride, pixel **src, intptr_t i_src_stride,
                              int mvx, int mvy, int i_width, int i_height, const x264_weight_t *weight, int bx, int by )
{
    intptr_t s = *i_dst_stride;
    pixel *r = x264_fly_get_ref( h, dst, i_dst_stride, src, i_src_stride, mvx, mvy, i_width, i_height, weight, bx, by );
    if( r != dst )
        for( int y = 0; y < i_height; y++ )
            memcpy( dst + y*s, r + y * *i_dst_stride, i_width * sizeof(pixel) );
    *i_dst_stride = s;
    return dst;
}

void x264_fly_mc_luma( x264_t *h, pixel *dst, intptr_t i_dst_stride, pixel **src, intptr_t i_src_stride,
                       int mvx, int mvy, int i_width, int i_height, const x264_weight_t *weight, int bx, int by )
{
    pixel *p[4];
    intptr_t ws = x264_fly_planes_mv( h, src, i_src_stride, bx, by, mvx, mvy, i_width, i_height, p );
    h->mc.mc_luma( dst, i_dst_stride, p, ws, mvx, mvy, i_width, i_height, weight );
}

int x264_fly_alloc( x264_t *h, intptr_t stride, int width )
{
    x264_fly_t *fly;
    CHECKED_MALLOCZERO( fly, sizeof(x264_fly_t) );
    h->fly = fly;
    fly->width = width;
    /* + 2 weightp duplicates in list 0 */
    fly->nref[0] = X264_MIN( h->frames.i_max_ref0 + 2, X264_REF_MAX );
    fly->nref[1] = h->param.i_bframe ? X264_MIN( h->frames.i_max_ref1 + 2, X264_REF_MAX ) : 0;
    fly->nslot = (fly->nref[0] + fly->nref[1]) * (PARAM_INTERLACED ? 3 : 1);
    CHECKED_MALLOCZERO( fly->slot, fly->nslot * sizeof(x264_fly_slot_t) );
    /* windows: slack rows, and a group of columns past the last plane for over-reads */
    size_t win_size = 4 * FLY_PLANE + 64;
    CHECKED_MALLOC( fly->buf, (2 * fly->nslot * win_size + 64) * sizeof(pixel) );
    for( int i = 0; i < fly->nslot; i++ )
        for( int j = 0; j < 2; j++ )
        {
            x264_fly_win_t *w = &fly->slot[i].win[j];
            pixel *base = fly->buf + (2*i + j) * win_size;
            for( int k = 0; k < 4; k++ )
                w->plane[k] = base + k*FLY_PLANE + FLY_WS;
            w->x0 = INT_MIN;
        }
    /* bands for references 0 and 1 of each list, frame and (both parities in one
     * buffer at the field stride) field */
    CHECKED_MALLOCZERO( fly->bands, 12 * sizeof(x264_fly_band_t) );
    for( int field = 0; field <= PARAM_INTERLACED; field++ )
        for( int l = 0; l < 2; l++ )
            for( int r = 0; r < X264_MIN( fly->nref[l], 2 ); r++ )
            {
                intptr_t bs = stride << field;
                size_t plane = (FLY_BR + 2) * bs;
                pixel *buf;
                CHECKED_MALLOC( buf, (3*plane + 64) * sizeof(pixel) );
                fly->band_buf[fly->nband++] = buf;
                for( int p = 0; p <= field; p++ )
                {
                    x264_fly_band_t *bd = &fly->bands[field ? 4 + 4*l + 2*r + p : 2*l + r];
                    bd->stride = bs;
                    for( int k = 1; k < 4; k++ )
                        bd->plane[k] = buf + (k-1)*plane + bs + p*stride + PADH;
                    fly->slot[x264_fly_slot_idx( fly, l, field ? 2*r + p : r, field )].band = bd;
                }
            }
#if HPELFLY_STATS
    {
        /* frame.c's luma buffers: the stride at most 16*mb_width + 2*PADH + its alignment slack */
        size_t lstride = 16*h->mb.i_mb_width + 2*PADH + 1024;
        size_t plane = lstride * (16*h->mb.i_mb_height + 2*(PADV << PARAM_INTERLACED)) + 2*4096;
        size_t lines = (4*plane + 64) * sizeof(pixel) / 64 + 1;
        fly->led_words = (lines + 63) / 64;
        CHECKED_MALLOC( fly->led_buf, 2*X264_REF_MAX * 2 * fly->led_words * sizeof(uint64_t) );
    }
#endif
    fly->gen = 1;
    return 0;
fail:
    return -1;
}

void x264_fly_free( x264_t *h )
{
    if( !h->fly )
        return;
    x264_free( h->fly->buf );
    for( int i = 0; i < h->fly->nband; i++ )
        x264_free( h->fly->band_buf[i] );
    x264_free( h->fly->bands );
#if HPELFLY_STATS
    x264_free( h->fly->led_buf );
#endif
    x264_free( h->fly->slot );
    x264_free( h->fly );
    h->fly = NULL;
}

#if HPELFLY_STATS
/* a reference frame's luma buffers, as frame.c allocates them */
static size_t fly_led_lines( x264_t *h, x264_frame_t *f )
{
    size_t plane = (size_t)f->i_stride[0] * (f->i_lines[0] + 2*(PADV << PARAM_INTERLACED)) + 2*4096;
    return (4*plane + 64) * sizeof(pixel) / 64 + 1;
}

void x264_fly_ledger( x264_t *h, pixel **src, intptr_t stride, int bx, int by, const x264_fly_box_t *b )
{
    x264_fly_t *fly = h->fly;
    for( int k = 1; k < 4; k++ )
    {
        if( !(b->mask & (1 << k)) )
            continue;
        uintptr_t p = (uintptr_t)(src[k] + b->y0[k]*stride + b->x0[k]);
        int e, half = 0;
        uintptr_t base = 0;
        for( e = 0; e < fly->nled; e++ )
        {
            x264_frame_t *f = fly->led[e].frame;
            size_t n = fly_led_lines( h, f ) * 64;
            if( p - (uintptr_t)f->buffer[0] < n )
            {
                base = (uintptr_t)f->buffer[0];
                break;
            }
            if( PARAM_INTERLACED && p - (uintptr_t)f->buffer_fld[0] < n )
            {
                base = (uintptr_t)f->buffer_fld[0];
                half = 1;
                break;
            }
        }
        if( e == fly->nled )
        {
            /* a reference of the slice not seen yet */
            x264_frame_t *f = NULL;
            for( int l = 0; l < 2 && !f; l++ )
                for( int j = 0; j < h->i_ref[l] && !f; j++ )
                {
                    x264_frame_t *r = h->fref[l][j];
                    size_t n = fly_led_lines( h, r ) * 64;
                    if( p - (uintptr_t)r->buffer[0] < n )
                        f = r, base = (uintptr_t)r->buffer[0];
                    else if( PARAM_INTERLACED && p - (uintptr_t)r->buffer_fld[0] < n )
                        f = r, base = (uintptr_t)r->buffer_fld[0], half = 1;
                }
            if( !f || fly->nled == 2*X264_REF_MAX || fly_led_lines( h, f ) > fly->led_words*64 )
                continue;
            fly->led[e].frame = f;
            fly->led[e].bits[0] = fly->led_buf + 2*e*fly->led_words;
            fly->led[e].bits[1] = fly->led[e].bits[0] + fly->led_words;
            memset( fly->led[e].bits[0], 0, 2*fly->led_words*sizeof(uint64_t) );
            fly->nled++;
        }
        uint64_t *bits = fly->led[e].bits[half];
        for( int y = b->y0[k]; y < b->y1[k]; y++ )
        {
            uintptr_t a = (uintptr_t)(src[k] + y*stride);
            size_t l0 = ((a + b->x0[k]*sizeof(pixel)) >> 6) - (base >> 6);
            size_t l1 = ((a + (b->x1[k]-1)*sizeof(pixel)) >> 6) - (base >> 6);
            for( size_t l = l0; l <= l1; l++ )
                bits[l >> 6] |= 1ULL << (l & 63);
        }
    }
}

void x264_fly_ledger_flush( x264_t *h )
{
    x264_fly_t *fly = h->fly;
    if( !fly )
        return;
    for( int e = 0; e < fly->nled; e++ )
        for( size_t i = 0; i < 2*fly->led_words; i++ )
            fly->st_rd_lines += __builtin_popcountll( fly->led[e].bits[0][i] );
    fly->nled = 0;
    fly->st_slices++;
}
#endif

void x264_fly_report( x264_t *h )
{
#if HPELFLY_STATS
    x264_fly_t *f = h->fly;
    if( !f )
        return;
    x264_fly_ledger_flush( h );
    x264_log( h, X264_LOG_INFO, "hpelfly %s: slices %"PRId64" | stored H/V/C: written %"PRId64" B, read %"PRId64" B (distinct lines per slice)"
              " | bands: requests %"PRId64" rows %"PRId64" moved %"PRId64" | windows: requests %"PRId64" placements %"PRId64" computed px F %"PRId64" H %"PRId64" V %"PRId64" C %"PRId64
              " calls %"PRId64" %"PRId64" %"PRId64" %"PRId64"\n", h->b_hpel_fly ? "on" : "off", f->st_slices,
              f->st_wr_bytes, f->st_rd_lines*64, f->st_band_req, f->st_band_rows, f->st_band_moved, f->st_req, f->st_place,
              f->st_px[0], f->st_px[1], f->st_px[2], f->st_px[3], f->st_calls[0], f->st_calls[1], f->st_calls[2], f->st_calls[3] );
#endif
}
