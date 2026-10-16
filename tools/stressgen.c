/*****************************************************************************
 * stressgen.c: adversarial y4m test content generator
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

/* Streams y4m to stdout:  gcc -O2 -o stressgen tools/stressgen.c -lm  (-O3 is 10-40% faster)
 *
 * Samples are built at 16-bit precision and rounded once on output, so
 * 10-bit output carries real 10-bit detail.  Interlaced output renders each
 * field at its own instant and weaves them. */

#ifdef __linux__
#define _GNU_SOURCE
#include <fcntl.h>
#endif
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
#ifdef _WIN32
#include <io.h>
#include <fcntl.h>
#endif

#define PI 3.14159265358979323846
#define DEG (PI / 180.0)

/* 16-bit code values; output = v >> (16 - depth) with rounding */
#define YBLK  4096
#define YWHT  60160
#define YMID  ((YBLK + YWHT) / 2)
#define YRNG  (YWHT - YBLK)
#define CMIN  4096
#define CMAX  61440
#define CMID  32768
#define CRNG  (CMAX - CMIN)

enum
{
    T_NAT0, T_NAT1, T_NAT2, T_NAT3, T_SMOOTH, T_NATS, T_CHECK, T_VLINE, T_VLINE3, T_HLINE,
    T_EXT, T_ZONE, T_TICKER, T_CREDITS, T_THIN, T_LOGO, T_SUB, T_L3, T_COUNT
};

typedef struct
{
    int w, h, lw;           /* powers of two, wrapped; lw = log2( w ) */
    uint16_t *p[4];         /* Y, U, V, alpha; all at full resolution */
} tex_t;

typedef struct
{
    uint16_t *p[3];
} img_t;

typedef struct
{
    int x0, y0, x1, y1;     /* luma coordinates, half-open */
} rect_t;

typedef struct
{
    int n;                  /* frame number */
    int tick;               /* picture number: frame, or field in temporal order */
    int ftick;              /* field number; progressive splits a frame into 2n, 2n+1 */
    int field;              /* -1 progressive, 0 top, 1 bottom */
    int y0, ys;             /* rows of every plane drawn by this picture */
    double ft;              /* capture time in frame periods */
} pic_t;

typedef struct
{
    int w, h, csp, depth, interlaced, tff, frames;
    int fps_num, fps_den;
    double fps;
    uint64_t seed;
    int pw[3], ph[3];
    img_t img, tmp;
    uint16_t *ra, *rb;
    float *colw;
    tex_t *tex[T_COUNT];
} gen_t;

static void die( const char *msg )
{
    fprintf( stderr, "stressgen: %s\n", msg );
    exit( 1 );
}

static void *xmalloc( size_t n )
{
    void *p = malloc( n );
    if( !p )
        die( "out of memory" );
    return p;
}

/****************************************************************************
 * Random numbers
 ****************************************************************************/

static inline uint64_t mix64( uint64_t x )
{
    x += 0x9e3779b97f4a7c15ULL;
    x = (x ^ (x >> 30)) * 0xbf58476d1ce4e5b9ULL;
    x = (x ^ (x >> 27)) * 0x94d049bb133111ebULL;
    return x ^ (x >> 31);
}

static inline uint64_t hash4( uint64_t a, uint64_t b, uint64_t c, uint64_t d )
{
    return mix64( a ^ mix64( b ^ mix64( c ^ mix64( d ) ) ) );
}

static inline uint64_t rnd( uint64_t *s )
{
    uint64_t x = *s;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    *s = x;
    return x * 0x2545f4914f6cdd1dULL;
}

static inline double rndf( uint64_t *s )
{
    return (rnd( s ) >> 11) * (1.0 / 9007199254740992.0);
}

/* deterministic [0,1) from (seed, a, b) */
static double hr( const gen_t *g, uint64_t a, uint64_t b )
{
    return (hash4( g->seed, a, b, 0x5eed ) >> 11) * (1.0 / 9007199254740992.0);
}

static inline int clip16( int v )
{
    return v < 0 ? 0 : v > 65535 ? 65535 : v;
}

/****************************************************************************
 * Textures
 ****************************************************************************/

static tex_t *tex_alloc( int w, int h, int alpha )
{
    tex_t *t = xmalloc( sizeof(tex_t) );
    memset( t, 0, sizeof(tex_t) );
    t->w = w;
    t->h = h;
    while( (1 << t->lw) < w )
        t->lw++;
    for( int i = 0; i < 3 + alpha; i++ )
    {
        t->p[i] = xmalloc( (size_t)w * h * sizeof(uint16_t) );
        memset( t->p[i], 0, (size_t)w * h * sizeof(uint16_t) );
    }
    return t;
}

typedef struct
{
    int y[2], u, v, a;      /* y[1] used where (x+y)&1 when checker is set */
    int checker;
} pen_t;

static void tex_put( tex_t *t, int x, int y, const pen_t *pen )
{
    x &= t->w - 1;
    y &= t->h - 1;
    size_t i = (size_t)y * t->w + x;
    t->p[0][i] = pen->y[pen->checker ? (x + y) & 1 : 0];
    t->p[1][i] = pen->u;
    t->p[2][i] = pen->v;
    if( t->p[3] )
        t->p[3][i] = pen->a;
}

static void tex_rect( tex_t *t, int x0, int y0, int x1, int y1, const pen_t *pen )
{
    for( int y = y0; y < y1; y++ )
        for( int x = x0; x < x1; x++ )
            tex_put( t, x, y, pen );
}

/* 1/f-ish value noise on wrapped lattices, normalised to [0,1] */
static void fbm( float *f, int w, int h, uint64_t seed, int cmin, int cmax, double slope )
{
    float *grid = xmalloc( (size_t)(w / cmin) * (h / cmin) * sizeof(float) );
    float *wt = xmalloc( cmax * sizeof(float) );
    memset( f, 0, (size_t)w * h * sizeof(float) );
    for( int c = cmax; c >= cmin; c >>= 1 )
    {
        int gw = w / c, gh = h / c, lc = 0;
        while( (1 << lc) < c )
            lc++;
        uint64_t s = mix64( seed * 131 + c ) | 1;
        for( int i = 0; i < gw * gh; i++ )
            grid[i] = (float)(rndf( &s ) * 2 - 1);
        for( int i = 0; i < c; i++ )
        {
            float t = (i + 0.5f) / c;
            wt[i] = t * t * (3 - 2 * t);
        }
        float amp = (float)pow( c, slope );
        for( int y = 0; y < h; y++ )
        {
            int gy = y >> lc;
            float ty = wt[y & (c - 1)];
            const float *g0 = grid + (size_t)(gy % gh) * gw, *g1 = grid + (size_t)((gy + 1) % gh) * gw;
            float *row = f + (size_t)y * w;
            for( int x = 0; x < w; x++ )
            {
                int gx = x >> lc, gx1 = (gx + 1) % gw;
                float tx = wt[x & (c - 1)];
                float a = g0[gx] + (g0[gx1] - g0[gx]) * tx;
                float b = g1[gx] + (g1[gx1] - g1[gx]) * tx;
                row[x] += amp * (a + (b - a) * ty);
            }
        }
    }
    float lo = f[0], hi = f[0];
    for( size_t i = 0; i < (size_t)w * h; i++ )
    {
        lo = f[i] < lo ? f[i] : lo;
        hi = f[i] > hi ? f[i] : hi;
    }
    for( size_t i = 0; i < (size_t)w * h; i++ )
        f[i] = (f[i] - lo) / (hi - lo + 1e-9f);
    free( grid );
    free( wt );
}

/* camera-like texture: 1/f background, textured hard-edged objects, gratings, fine grain */
static tex_t *tex_natural( uint64_t seed, int smooth, int size )
{
    int w = size, h = size;
    size_t n = (size_t)w * h;
    tex_t *t = tex_alloc( w, h, 0 );
    float *f = xmalloc( n * sizeof(float) );
    uint64_t s = mix64( seed ) | 1;

    fbm( f, w, h, seed * 3 + 1, smooth ? 64 : 2, 1024, smooth ? 1.0 : 0.4 );
    for( size_t i = 0; i < n; i++ )
        t->p[0][i] = YBLK + (int)((0.06 + 0.88 * f[i]) * YRNG);
    for( int pl = 1; pl < 3; pl++ )
    {
        fbm( f, w, h, seed * 3 + 1 + pl, smooth ? 64 : 8, 1024, 1.0 );
        for( size_t i = 0; i < n; i++ )
            t->p[pl][i] = CMID + (int)((f[i] - 0.5f) * 0.6f * CRNG);
    }
    free( f );
    if( smooth )
        return t;

    for( int k = 0; k < 700 * size / 2048 * size / 2048; k++ )
    {
        int sw = (int)exp( log( 6.0 ) + rndf( &s ) * (log( 320.0 ) - log( 6.0 )) );
        int sh = (int)(sw * (0.4 + 1.2 * rndf( &s ))) + 1;
        int x0 = rnd( &s ) & (w - 1), y0 = rnd( &s ) & (h - 1), kind = rnd( &s ) % 4;
        int cy = YBLK + (int)(rndf( &s ) * YRNG);
        int cu = CMID + (int)((rndf( &s ) - 0.5) * 0.7 * CRNG);
        int cv = CMID + (int)((rndf( &s ) - 0.5) * 0.7 * CRNG);
        double ang = rndf( &s ) * PI, per = 2 + rndf( &s ) * 10;
        double ca = cos( ang ), sa = sin( ang );
        for( int dy = 0; dy < sh; dy++ )
            for( int dx = 0; dx < sw; dx++ )
            {
                double ex = (dx + 0.5) / sw * 2 - 1, ey = (dy + 0.5) / sh * 2 - 1, r2 = ex * ex + ey * ey;
                if( (kind == 1 && r2 > 1) || (kind == 3 && (r2 > 1 || r2 < 0.36)) )
                    continue;
                size_t i = (size_t)((y0 + dy) & (h - 1)) * w + ((x0 + dx) & (w - 1));
                int yv = cy + (t->p[0][i] - YMID) * 3 / 10;
                if( kind == 2 )
                    yv += fmod( fabs( dx * ca + dy * sa ), per ) < per * 0.5 ? YRNG / 5 : -YRNG / 5;
                t->p[0][i] = clip16( yv );
                t->p[1][i] = clip16( cu + (t->p[1][i] - CMID) * 3 / 10 );
                t->p[2][i] = clip16( cv + (t->p[2][i] - CMID) * 3 / 10 );
            }
    }
    /* keep camera content inside the legal range; only extremes goes outside it */
    for( size_t i = 0; i < n; i++ )
    {
        int v = t->p[0][i] + (int)((rndf( &s ) - 0.5) * 1100);
        t->p[0][i] = v < YBLK ? YBLK : v > YWHT ? YWHT : v;
        for( int pl = 1; pl < 3; pl++ )
            t->p[pl][i] = t->p[pl][i] < CMIN ? CMIN : t->p[pl][i] > CMAX ? CMAX : t->p[pl][i];
    }
    return t;
}

static uint8_t glyphs[64][7];

static void init_glyphs( uint64_t seed )
{
    uint64_t s = mix64( seed ^ 0x676c797068ULL ) | 1;
    for( int i = 0; i < 64; i++ )
    {
        int bits;
        do
        {
            bits = 0;
            for( int r = 0; r < 7; r++ )
            {
                glyphs[i][r] = rnd( &s ) & 31;
                for( int b = 0; b < 5; b++ )
                    bits += glyphs[i][r] >> b & 1;
            }
        } while( bits < 12 || bits > 26 );
    }
}

/* pseudo text: nch glyph cells of 6x8 units at scale px, some cells blank */
static void text_line( tex_t *t, int x, int y, int scale, int nch, uint64_t *s, const pen_t *pen )
{
    for( int c = 0; c < nch; c++, x += 6 * scale )
    {
        if( rnd( s ) % 6 == 0 )
            continue;
        const uint8_t *gl = glyphs[rnd( s ) & 63];
        for( int gy = 0; gy < 7; gy++ )
            for( int gx = 0; gx < 5; gx++ )
                if( gl[gy] >> (4 - gx) & 1 )
                    tex_rect( t, x + gx * scale, y + gy * scale, x + (gx + 1) * scale, y + (gy + 1) * scale, pen );
    }
}

static void text_centred( tex_t *t, int cx, int y, int scale, int nch, uint64_t *s, const pen_t *pen )
{
    text_line( t, cx - nch * 6 * scale / 2, y, scale, nch, s, pen );
}

static tex_t *tex_build( gen_t *g, int id )
{
    uint64_t s = mix64( g->seed * 977 + id ) | 1;
    int lo = YBLK + 1024, hi = YWHT - 1024;
    tex_t *t;
    switch( id )
    {
        case T_NAT0: case T_NAT1: case T_NAT2: case T_NAT3:
            return tex_natural( g->seed * 7919 + id, 0, 2048 );
        case T_SMOOTH:
            return tex_natural( g->seed * 7919 + id, 1, 2048 );
        case T_NATS:
            return tex_natural( g->seed * 7919 + id, 0, 1024 );
        case T_CHECK: case T_VLINE: case T_VLINE3: case T_HLINE: case T_EXT:
            t = tex_alloc( 1024, 1024, 0 );
            for( int y = 0; y < 1024; y++ )
                for( int x = 0; x < 1024; x++ )
                {
                    size_t i = (size_t)y * 1024 + x;
                    int on = id == T_CHECK ? (x + y) & 1 : id == T_VLINE ? x & 1 :
                             id == T_VLINE3 ? x % 3 == 0 : id == T_HLINE ? y & 1 : ((x >> 3) + (y >> 3)) & 1;
                    int con = ((x >> 1) + (y >> 1)) & 1;
                    if( id == T_EXT )
                    {
                        con = ((x >> 4) + (y >> 4)) & 1;
                        t->p[0][i] = on ? 65535 : 0;
                        t->p[1][i] = con ? 65535 : 0;
                        t->p[2][i] = con ? 0 : 65535;
                    }
                    else
                    {
                        t->p[0][i] = on ? hi : lo;
                        t->p[1][i] = id == T_CHECK ? (con ? CMID + 8000 : CMID - 8000) : CMID;
                        t->p[2][i] = id == T_CHECK ? (con ? CMID - 8000 : CMID + 8000) : CMID;
                    }
                }
            return t;
        case T_ZONE:
            /* luma chirp reaches luma Nyquist at r = 1024, chroma chirps reach chroma Nyquist */
            t = tex_alloc( 2048, 2048, 0 );
            for( int y = 0; y < 2048; y++ )
                for( int x = 0; x < 2048; x++ )
                {
                    double dx = x - 1024, dy = y - 1024;
                    size_t i = (size_t)y * 2048 + x;
                    t->p[0][i] = YMID + (int)(0.45 * YRNG * cos( PI * (dx * dx + dy * dy) / 2048 ));
                    t->p[1][i] = CMID + (int)(0.3 * CRNG * cos( PI * dx * dx / 4096 ));
                    t->p[2][i] = CMID + (int)(0.3 * CRNG * cos( PI * dy * dy / 4096 ));
                }
            return t;
        case T_TICKER:
        {
            t = tex_alloc( 8192, 64, 0 );
            pen_t bg = { { YBLK + YRNG / 5 }, CMID + 6000, CMID - 2000 };
            pen_t ac = { { YBLK + YRNG * 4 / 5 }, CMID - 14000, CMID + 4000 };
            pen_t fg = { { YWHT }, CMID, CMID };
            tex_rect( t, 0, 0, 8192, 64, &bg );
            tex_rect( t, 0, 0, 8192, 3, &ac );
            tex_rect( t, 0, 61, 8192, 64, &ac );
            for( int x = 16; x + 36 * 30 < 8192; x += 36 * 32 )
            {
                text_line( t, x, 11, 6, 28, &s, &fg );
                tex_rect( t, x + 36 * 29, 18, x + 36 * 29 + 24, 46, &ac );
            }
            return t;
        }
        case T_CREDITS:
        {
            t = tex_alloc( 2048, 4096, 0 );
            pen_t bg = { { YBLK }, CMID, CMID }, fg = { { YWHT }, CMID, CMID };
            tex_rect( t, 0, 0, 2048, 4096, &bg );
            for( int y = 40; y < 4096 - 80; y += 64 )
            {
                if( rnd( &s ) % 7 == 0 )
                    continue;
                int sc = rnd( &s ) % 4 ? 5 : 3;
                text_centred( t, 1024, y, sc, 8 + rnd( &s ) % 22, &s, &fg );
            }
            return t;
        }
        case T_THIN:
        {
            /* 1-px checker text: identical 2x2 means everywhere, so the 2:1 lowres is flat grey */
            int d = YRNG * 35 / 100;
            t = tex_alloc( 2048, 2048, 0 );
            pen_t bg = { { YMID }, CMID, CMID }, ck = { { YMID - d, YMID + d }, CMID, CMID, 0, 1 };
            pen_t ckinv = { { YMID + d, YMID - d }, CMID, CMID, 0, 1 };
            tex_rect( t, 0, 0, 1024, 2048, &bg );
            tex_rect( t, 1024, 0, 2048, 2048, &ckinv );
            for( int y = 24; y < 2048 - 40; y += 48 )
            {
                text_centred( t, 512, y, 4, 10 + rnd( &s ) % 30, &s, &ck );
                text_centred( t, 1536, y, 4, 10 + rnd( &s ) % 30, &s, &ck );
            }
            return t;
        }
        case T_LOGO:
        {
            t = tex_alloc( 256, 128, 1 );
            pen_t ring = { { YWHT }, CMID, CMID, 39321 }, core = { { YMID }, CMID - 16000, CMID - 4000, 65535 };
            pen_t fg = { { YWHT }, CMID, CMID, 65535 };
            for( int y = 0; y < 128; y++ )
                for( int x = 0; x < 128; x++ )
                {
                    double r = hypot( x - 63.5, y - 63.5 );
                    if( r >= 44 && r < 58 )
                        tex_put( t, x, y, &ring );
                    else if( r < 30 )
                        tex_put( t, x, y, &core );
                }
            text_line( t, 128, 43, 6, 3, &s, &fg );
            return t;
        }
        case T_SUB:
        {
            t = tex_alloc( 2048, 1024, 1 );
            pen_t bg = { { YBLK }, CMID, CMID, 0 }, fg = { { YWHT - 2048 }, CMID, CMID, 65535 };
            tex_rect( t, 0, 0, 2048, 1024, &bg );
            for( int c = 0; c < 8; c++ )
            {
                text_centred( t, 1024, c * 128 + 24, 4, 20 + rnd( &s ) % 20, &s, &fg );
                text_centred( t, 1024, c * 128 + 72, 4, 20 + rnd( &s ) % 20, &s, &fg );
            }
            return t;
        }
        case T_L3:
        {
            t = tex_alloc( 2048, 256, 1 );
            pen_t ac = { { YBLK + YRNG * 4 / 5 }, CMID - 14000, CMID + 4000, 65535 };
            pen_t fg = { { YWHT }, CMID, CMID, 65535 }, fg2 = { { YBLK + YRNG * 3 / 4 }, CMID, CMID, 65535 };
            for( int x = 0; x < 1400; x++ )
            {
                pen_t band = { { YBLK + (int)((0.15 + 0.2 * x / 1400.0) * YRNG) }, CMID + 5000, CMID - 3000, 57671 };
                tex_rect( t, x, 60, x + 1, 200, &band );
            }
            tex_rect( t, 0, 60, 1400, 68, &ac );
            text_line( t, 40, 80, 7, 24, &s, &fg );
            text_line( t, 40, 150, 4, 50, &s, &fg2 );
            return t;
        }
    }
    die( "bad texture" );
    return NULL;
}

static tex_t *gettex( gen_t *g, int id )
{
    if( !g->tex[id] )
        g->tex[id] = tex_build( g, id );
    return g->tex[id];
}

/* round( x * 65536 ) without a libm call; valid for x > -2^24 */
static inline uint32_t fix16( double x )
{
    return (uint32_t)((int64_t)(x * 65536.0 + 0.5 + 1099511627776.0) - 1099511627776LL);
}

/* bilinear row fetch, coordinates in texels with 1/256 px precision.  16.16
 * coordinates wrap in uint32: 2^32 is a multiple of every texture size << 16 */
static void tex_row( const tex_t *t, int pl, uint16_t *restrict dst, int n, double u, double v, double du, double dv )
{
    const uint16_t *restrict src = t->p[pl];
    uint32_t wm = t->w - 1, hm = t->h - 1, fu = fix16( u ), fv = fix16( v ), fdu = fix16( du ), fdv = fix16( dv );
    int lw = t->lw;
    if( !fdv )
    {
        uint32_t iv = fv >> 16, fy = (fv >> 8) & 255;
        const uint16_t *r0 = src + ((size_t)(iv & hm) << lw), *r1 = src + ((size_t)((iv + 1) & hm) << lw);
        if( !(fdu & 0xffff) )
        {
            /* whole-texel step: constant weights, same rounding as below */
            uint32_t k = fu >> 16, st = fdu >> 16, fx = (fu >> 8) & 255;
            if( !fx && !fy )
                for( int i = 0; i < n; i++, k += st )
                    dst[i] = r0[k & wm];
            else if( !fy )
                for( int i = 0; i < n; i++, k += st )
                    dst[i] = (r0[k & wm] * (256 - fx) + r0[(k + 1) & wm] * fx + 128) >> 8;
            else
                for( int i = 0; i < n; i++, k += st )
                {
                    uint32_t a = r0[k & wm] * (256 - fx) + r0[(k + 1) & wm] * fx;
                    uint32_t b = r1[k & wm] * (256 - fx) + r1[(k + 1) & wm] * fx;
                    dst[i] = (a * (256 - fy) + b * fy + 32768) >> 16;
                }
            return;
        }
        for( int i = 0; i < n; i++, fu += fdu )
        {
            uint32_t iu = fu >> 16, fx = (fu >> 8) & 255, x0 = iu & wm, x1 = (iu + 1) & wm;
            uint32_t a = r0[x0] * (256 - fx) + r0[x1] * fx;
            uint32_t b = r1[x0] * (256 - fx) + r1[x1] * fx;
            dst[i] = (a * (256 - fy) + b * fy + 32768) >> 16;
        }
        return;
    }
    for( int i = 0; i < n; i++, fu += fdu, fv += fdv )
    {
        uint32_t iu = fu >> 16, fx = (fu >> 8) & 255, x0 = iu & wm, x1 = (iu + 1) & wm;
        uint32_t iv = fv >> 16, fy = (fv >> 8) & 255;
        const uint16_t *r0 = src + ((size_t)(iv & hm) << lw), *r1 = src + ((size_t)((iv + 1) & hm) << lw);
        uint32_t a = r0[x0] * (256 - fx) + r0[x1] * fx;
        uint32_t b = r1[x0] * (256 - fx) + r1[x1] * fx;
        dst[i] = (a * (256 - fy) + b * fy + 32768) >> 16;
    }
}

/****************************************************************************
 * Drawing: every op touches only the rows of the current picture
 ****************************************************************************/

#define ROWS( g, p, pl, y ) for( int y = (p)->y0; y < (g)->ph[pl]; y += (p)->ys )
#define ALL 7

static rect_t R( int x0, int y0, int x1, int y1 )
{
    rect_t r = { x0, y0, x1, y1 };
    return r;
}

static rect_t full( const gen_t *g )
{
    return R( 0, 0, g->w, g->h );
}

/* vertical sample position of a plane row in luma frame lines */
static double ypos( const gen_t *g, int pl, int y )
{
    if( !pl || g->csp == 422 )
        return y;
    if( g->interlaced )
        return (y & 1) + 4 * (y >> 1) + 1;
    return 2 * y + 0.5;
}

/* plane columns of a row inside r; chroma sample cx sits at luma 2*cx */
static int span( const gen_t *g, int pl, int y, rect_t r, int *x0, int *x1, double *yl )
{
    int sx = pl ? 2 : 1;
    int a = r.x0 < 0 ? 0 : r.x0, b = r.x1 > g->w ? g->w : r.x1;
    *yl = ypos( g, pl, y );
    if( *yl < r.y0 || *yl >= r.y1 )
        return 0;
    *x0 = (a + sx - 1) / sx;
    *x1 = (b + sx - 1) / sx;
    return *x1 > *x0;
}

#define SPANS( g, p, r, planes ) \
    for( int pl = 0; pl < 3; pl++ ) \
        if( (planes) >> pl & 1 ) \
            ROWS( g, p, pl, y ) \
                for( int x0, x1, once_ = 1; once_; once_ = 0 ) \
                    for( double yl; once_ && span( g, pl, y, r, &x0, &x1, &yl ); once_ = 0 )

#define ROWPTR( g, img, pl, y ) ((img)->p[pl] + (size_t)(y) * (g)->pw[pl])

static void draw_tex( gen_t *g, const pic_t *p, img_t *dst, int id, const double *A, rect_t r )
{
    const tex_t *t = gettex( g, id );
    SPANS( g, p, r, ALL )
    {
        int sx = pl ? 2 : 1;
        double xl = x0 * sx;
        tex_row( t, pl, ROWPTR( g, dst, pl, y ) + x0, x1 - x0, A[0] * xl + A[1] * yl + A[2],
                 A[3] * xl + A[4] * yl + A[5], A[0] * sx, A[3] * sx );
    }
}

static void draw_tex_alpha( gen_t *g, const pic_t *p, img_t *dst, int id, const double *A, rect_t r )
{
    const tex_t *t = gettex( g, id );
    SPANS( g, p, r, ALL )
    {
        int sx = pl ? 2 : 1, n = x1 - x0;
        double xl = x0 * sx, u = A[0] * xl + A[1] * yl + A[2], v = A[3] * xl + A[4] * yl + A[5];
        uint16_t *d = ROWPTR( g, dst, pl, y ) + x0;
        tex_row( t, 3, g->ra, n, u, v, A[0] * sx, A[3] * sx );
        tex_row( t, pl, g->rb, n, u, v, A[0] * sx, A[3] * sx );
        for( int i = 0; i < n; i++ )
            d[i] += (int)(((int64_t)(g->rb[i] - d[i]) * g->ra[i] + 32767) / 65535);
    }
}

static void draw_fill( gen_t *g, const pic_t *p, img_t *dst, rect_t r, const int *c )
{
    SPANS( g, p, r, ALL )
    {
        uint16_t *d = ROWPTR( g, dst, pl, y );
        for( int x = x0; x < x1; x++ )
            d[x] = c[pl];
    }
}

/* uniform noise mean +- amp (added to the picture when mean is NULL), fresh for every field */
static void draw_noise( gen_t *g, const pic_t *p, img_t *dst, rect_t r, int planes, const int *mean, const int *amp,
                        uint64_t salt )
{
    SPANS( g, p, r, planes )
    {
        uint16_t *d = ROWPTR( g, dst, pl, y );
        uint64_t s = hash4( g->seed, salt, p->ftick, (uint64_t)pl << 32 | y ) | 1, v = 0;
        for( int x = x0; x < x1; x++ )
        {
            if( !((x - x0) & 3) )
                v = rnd( &s );
            int u = (int)(v & 0xffff) - 32768;
            v >>= 16;
            d[x] = clip16( (mean ? mean[pl] : d[x]) + (u * amp[pl] >> 15) );
        }
    }
}

static int16_t gauss[4096];     /* N(0,1) * 1024 */

static void init_gauss( void )
{
    uint64_t s = 0x9a055 | 1;
    for( int i = 0; i < 4096; i++ )
    {
        double z = sqrt( -2 * log( 1 - rndf( &s ) ) ) * cos( 2 * PI * rndf( &s ) ) * 1024;
        gauss[i] = (int16_t)(z > 32767 ? 32767 : z < -32767 ? -32767 : floor( z + 0.5 ));
    }
}

/* additive gaussian grain */
static void draw_grain( gen_t *g, const pic_t *p, img_t *dst, rect_t r, int planes, const int *sigma, uint64_t salt )
{
    SPANS( g, p, r, planes )
    {
        uint16_t *d = ROWPTR( g, dst, pl, y );
        uint64_t s = hash4( g->seed, salt ^ 0x6772, p->ftick, (uint64_t)pl << 32 | y ) | 1, v = 0;
        for( int x = x0; x < x1; x++ )
        {
            if( !((x - x0) % 5) )
                v = rnd( &s );
            d[x] = clip16( d[x] + (gauss[v & 4095] * sigma[pl] >> 10) );
            v >>= 12;
        }
    }
}

/* luma (v - pivot) * gy + pivot + off, chroma around mid by cg */
static void adjust( gen_t *g, const pic_t *p, img_t *dst, rect_t r, double gy, int pivot, int off, double cg )
{
    int qy = (int)floor( gy * 65536 + 0.5 ), qc = (int)floor( cg * 65536 + 0.5 );
    SPANS( g, p, r, ALL )
    {
        uint16_t *d = ROWPTR( g, dst, pl, y );
        int q = pl ? qc : qy, piv = pl ? CMID : pivot, o = pl ? 0 : off;
        for( int x = x0; x < x1; x++ )
            d[x] = clip16( piv + o + (int)(((int64_t)(d[x] - piv) * q + 32768) >> 16) );
    }
}

/* move towards colour c by a (times colw[x] if given) */
static void mix_to( gen_t *g, const pic_t *p, img_t *dst, rect_t r, const int *c, double a, const float *colw )
{
    SPANS( g, p, r, ALL )
    {
        uint16_t *d = ROWPTR( g, dst, pl, y );
        int sx = pl ? 2 : 1;
        for( int x = x0; x < x1; x++ )
        {
            double k = colw ? a * colw[x * sx] : a;
            d[x] = clip16( d[x] + (int)floor( (c[pl] - d[x]) * k + 0.5 ) );
        }
    }
}

static void blend( gen_t *g, const pic_t *p, img_t *dst, const img_t *src, rect_t r, double a )
{
    int q = (int)floor( a * 65536 + 0.5 );
    SPANS( g, p, r, ALL )
    {
        uint16_t *d = ROWPTR( g, dst, pl, y );
        const uint16_t *s = ROWPTR( g, src, pl, y );
        for( int x = x0; x < x1; x++ )
            d[x] += (int)(((int64_t)(s[x] - d[x]) * q + 32768) >> 16);
    }
}

/* horizontal ramp v0..v1 across r, wrapping, shifted by sh luma px */
static void draw_ramp( gen_t *g, const pic_t *p, img_t *dst, rect_t r, int planes, const int *v0, const int *v1,
                       double sh )
{
    double rw = r.x1 - r.x0;
    SPANS( g, p, r, planes )
    {
        uint16_t *d = ROWPTR( g, dst, pl, y );
        int sx = pl ? 2 : 1;
        for( int x = x0; x < x1; x++ )
        {
            double f = fmod( x * sx - r.x0 + sh, rw ) / rw;
            f += f < 0;
            d[x] = clip16( v0[pl] + (int)floor( (v1[pl] - v0[pl]) * f + 0.5 ) );
        }
    }
}

static const int BARS75[8][3]  = { { 721, 512, 512 }, { 674, 176, 543 }, { 581, 589, 176 }, { 534, 253, 207 },
                                   { 251, 771, 817 }, { 204, 435, 848 }, { 111, 848, 481 }, { 64, 512, 512 } };
static const int BARS100[8][3] = { { 940, 512, 512 }, { 877, 64, 553 }, { 754, 615, 64 }, { 691, 167, 105 },
                                   { 313, 857, 919 }, { 250, 409, 960 }, { 127, 960, 471 }, { 64, 512, 512 } };

static void draw_bars( gen_t *g, const pic_t *p, img_t *dst, rect_t r, const int (*bars)[3], const int *order, int nb )
{
    for( int i = 0; i < nb; i++ )
    {
        const int *b = bars[order ? order[i] : i];
        int c[3] = { b[0] << 6, b[1] << 6, b[2] << 6 };
        draw_fill( g, p, dst, R( r.x0 + (r.x1 - r.x0) * i / nb, r.y0, r.x0 + (r.x1 - r.x0) * (i + 1) / nb, r.y1 ), c );
    }
}

/****************************************************************************
 * Helpers for motion
 ****************************************************************************/

/* frame -> texture: scale and rotate about the frame centre, then translate */
static void aff( const gen_t *g, double *A, double scale, double ang, double tx, double ty )
{
    double c = cos( ang ) / scale, s = sin( ang ) / scale, cx = g->w * 0.5, cy = g->h * 0.5;
    A[0] = c;
    A[1] = -s;
    A[2] = cx + tx - c * cx + s * cy;
    A[3] = s;
    A[4] = c;
    A[5] = cy + ty - s * cx - c * cy;
}

static void draw_pan( gen_t *g, const pic_t *p, int id, double tx, double ty, rect_t r )
{
    double A[6];
    aff( g, A, 1, 0, tx, ty );
    draw_tex( g, p, &g->img, id, A, r );
}

static double bounce( double x, double range )
{
    if( range <= 0 )
        return 0;
    x = fmod( x, 2 * range );
    x += x < 0 ? 2 * range : 0;
    return x < range ? x : 2 * range - x;
}

static double pwl( const double *tv, int n, double t )
{
    if( t <= tv[0] )
        return tv[1];
    for( int i = 1; i < n; i++ )
        if( t < tv[2 * i] )
            return tv[2 * i - 1] + (t - tv[2 * i - 2]) / (tv[2 * i] - tv[2 * i - 2]) * (tv[2 * i + 1] - tv[2 * i - 1]);
    return tv[2 * n - 1];
}

static int fsec( const gen_t *g, double s )
{
    int f = (int)(s * g->fps + 0.5);
    return f > 0 ? f : 1;
}

static double secs( const gen_t *g, const pic_t *p )
{
    return p->ft / g->fps;
}

/* the pictures of a field-structured scene: interlaced = this field,
 * progressive = even and odd rows of the frame as two pseudo fields */
static int fields_of( const gen_t *g, const pic_t *p, pic_t *f )
{
    f[0] = *p;
    if( g->interlaced )
        return 1;
    f[1] = *p;
    f[0].y0 = 0;
    f[1].y0 = 1;
    f[0].ys = f[1].ys = 2;
    f[0].field = 0;
    f[1].field = 1;
    f[0].ftick = 2 * p->n;
    f[1].ftick = 2 * p->n + 1;
    return 2;
}

static const int GREY[3]  = { YMID, CMID, CMID };
static const int BLACK[3] = { YBLK, CMID, CMID };
static const int WHITE[3] = { YWHT, CMID, CMID };
static const int NMEAN[3] = { YMID, CMID, CMID };
static const int NAMP[3]  = { YRNG / 2, CRNG / 2, CRNG / 2 };

static void full_noise( gen_t *g, const pic_t *p, rect_t r )
{
    draw_noise( g, p, &g->img, r, ALL, NMEAN, NAMP, 1 );
}

/****************************************************************************
 * Scenarios: CPU worst case
 ****************************************************************************/

static void sc_noise( gen_t *g, const pic_t *p )
{
    full_noise( g, p, full( g ) );
}

static void sc_chroma_noise( gen_t *g, const pic_t *p )
{
    double t = secs( g, p ) < 5 ? 0 : p->ft - 5 * g->fps;
    draw_pan( g, p, T_NAT0, 2.5 * t, 0, full( g ) );
    draw_noise( g, p, &g->img, full( g ), 6, NMEAN, NAMP, 2 );
}

static void sc_lsb_noise( gen_t *g, const pic_t *p )
{
    static const int amp[3] = { 128, 128, 128 };
    draw_pan( g, p, T_SMOOTH, 0.5 * p->ft, 0.2 * p->ft, full( g ) );
    draw_noise( g, p, &g->img, full( g ), ALL, NULL, amp, 3 );
}

static void sc_nyquist( gen_t *g, const pic_t *p )
{
    static const double sp[4] = { 0.25, 0.5, 1.0 / 3, 0.75 };
    int w = g->w, h = g->h, c1 = w / 3, c2 = 2 * w / 3, hm = h / 2;
    double t = p->ft, v = sp[(int)(secs( g, p ) / 4) % 4] * t;
    draw_pan( g, p, T_CHECK, 0, 0, R( 0, 0, c1, hm ) );
    draw_pan( g, p, T_CHECK, v, v * 0.5, R( c1, 0, c2, hm ) );
    draw_pan( g, p, T_ZONE, 1024 - (c2 + w) / 2 + 0.37 * t, 1024 - hm / 2 + 0.21 * t, R( c2, 0, w, hm ) );
    draw_pan( g, p, T_VLINE, v, 0, R( 0, hm, c1, h ) );
    draw_pan( g, p, T_HLINE, 0, v, R( c1, hm, c2, h ) );
    draw_pan( g, p, T_VLINE3, 0, 0, R( c2, hm, w, h ) );
}

static void sc_tile_chaos( gen_t *g, const pic_t *p )
{
    static double *mv;
    static int last = -1;
    int ntx = (g->w + 15) / 16, nty = (g->h + 15) / 16;
    if( !mv )
    {
        mv = xmalloc( (size_t)ntx * nty * 2 * sizeof(double) );
        for( int i = 0; i < ntx * nty * 2; i++ )
            mv[i] = floor( hr( g, 5, i ) * 1024 );
    }
    if( p->tick != last )
    {
        last = p->tick;
        uint64_t s = hash4( g->seed, 5, p->tick, 0 ) | 1;
        for( int i = 0; i < ntx * nty * 2; i++ )
            mv[i] = fmod( mv[i] + floor( (rndf( &s ) * 2 - 1) * 256 ) / 4 + 1024, 1024 );
    }
    const tex_t *t = gettex( g, T_NATS );    /* small enough to stay in cache */
    for( int pl = 0; pl < 3; pl++ )
        ROWS( g, p, pl, y )
        {
            int sx = pl ? 2 : 1, ty = (int)ypos( g, pl, y ) >> 4;
            double yl = ypos( g, pl, y );
            for( int tx = 0; tx < ntx; tx++ )
            {
                int x0, x1;
                const double *m = mv + 2 * (ty * ntx + tx);
                if( span( g, pl, y, R( tx * 16, 0, tx * 16 + 16, g->h ), &x0, &x1, &yl ) )
                    tex_row( t, pl, ROWPTR( g, &g->img, pl, y ) + x0, x1 - x0, x0 * sx + m[0], yl + m[1], sx, 0 );
            }
        }
}

static void sc_pan_fast( gen_t *g, const pic_t *p )
{
    double seg = 2 * g->fps, A[6];
    int k = (int)(p->ft / seg), ph = k % 8;
    double lt = p->ft - k * seg, z;
    switch( ph )
    {
        case 0: aff( g, A, 1, 0, 96 * lt, 0 ); break;
        case 1: aff( g, A, 1, 0, 160 * lt, 0 ); break;
        case 2: aff( g, A, 1, 0, 250 * lt, 0 ); break;
        case 3: aff( g, A, 1, 0, -120 * lt, 68 * lt ); break;
        case 4: aff( g, A, 1, 0, 0, 64 * lt ); break;
        case 5: z = bounce( lt, 20 ); aff( g, A, exp( 0.04 * z ), 0, 0, 0 ); break;
        case 6: aff( g, A, 1, 30 * DEG * sin( PI * lt / seg ), 0, 0 ); break;
        default: aff( g, A, 1 + 0.3 * sin( 2 * PI * lt / 50 ), 20 * DEG * sin( 2 * PI * lt / seg ), 40 * lt, 0 ); break;
    }
    draw_tex( g, p, &g->img, ph & 1 ? T_NAT1 : T_NAT0, A, full( g ) );
}

static void sc_cut_storm( gen_t *g, const pic_t *p )
{
    double A[6];
    int n = p->n;
    aff( g, A, 0.6 + 1.2 * hr( g, 7, n * 8 + 1 ), 0,
         2048 * hr( g, 7, n * 8 + 3 ) + 3 * (p->ft - n), 2048 * hr( g, 7, n * 8 + 4 ) );
    /* random mirror and flip; no rotation, which is slow to sample */
    if( hash4( g->seed, 7, n, 1 ) & 1 )
    {
        A[2] += A[0] * g->w;
        A[0] = -A[0];
    }
    if( hash4( g->seed, 7, n, 1 ) & 2 )
    {
        A[5] += A[4] * g->h;
        A[4] = -A[4];
    }
    draw_tex( g, p, &g->img, T_NAT0 + (int)(hash4( g->seed, 7, n, 0 ) % 4), A, full( g ) );
    adjust( g, p, &g->img, full( g ), 0.7 + 0.5 * hr( g, 7, n * 8 + 5 ), YBLK,
            (int)((hr( g, 7, n * 8 + 6 ) - 0.5) * 6000), 0.4 + 1.2 * hr( g, 7, n * 8 + 7 ) );
}

static void sc_strobe( gen_t *g, const pic_t *p )
{
    double s = secs( g, p ), lt = fmod( s, 4 ), gy, cg = 1;
    int k = (int)(s / 4) % 3;
    if( k == 2 )
    {
        double A[6];
        aff( g, A, 1 + 0.002 * lt * g->fps, 0, 6 * p->ft, 2 * p->ft );
        draw_tex( g, p, &g->img, T_NAT0, A, full( g ) );
        gy = cg = fabs( cos( PI * lt / 2 ) );
    }
    else
    {
        draw_pan( g, p, T_NAT0, 3 * p->ft, p->ft, full( g ) );
        gy = k == 0 ? (p->n & 1 ? 0.45 : 1.0) : 0.4 + 0.8 * hr( g, 8, p->n );
    }
    adjust( g, p, &g->img, full( g ), gy, YBLK, 0, cg );
}

static void sc_band_hop( gen_t *g, const pic_t *p )
{
    static const int pos[7] = { 0, 6, 2, 4, 1, 5, -1 };
    static const int sigma[3] = { 2500, 1500, 1500 };
    int k = (int)secs( g, p ) % 7, bh = g->h / 4, top;
    if( pos[k] >= 0 )
        top = pos[k] * g->h / 8;
    else    /* sweep down and back up within the second */
        top = (int)bounce( 2 * (secs( g, p ) - floor( secs( g, p ) )) * (g->h - bh), g->h - bh );
    rect_t band = R( 0, top, g->w, top + bh );
    draw_pan( g, p, T_NAT1, 0, 0, full( g ) );
    draw_pan( g, p, T_NAT2, 37 * p->ft, 11 * p->ft, band );
    draw_grain( g, p, &g->img, band, ALL, sigma, 9 );
}

static void sc_grain( gen_t *g, const pic_t *p )
{
    static const int s1[3] = { 900, 500, 500 }, s2[3] = { 2000, 1100, 1100 };
    draw_pan( g, p, T_NAT1, 1.3 * p->ft, 0.4 * p->ft, full( g ) );
    draw_grain( g, p, &g->img, full( g ), ALL, (int)(secs( g, p ) / 4) & 1 ? s2 : s1, 27 );
}

/****************************************************************************
 * Scenarios: rate control and VBV
 ****************************************************************************/

static void sc_flat_noise( gen_t *g, const pic_t *p )
{
    static const char *pat[4] = { "FN", "FFN", "NNF", "FNNF" };
    int seg = fsec( g, 4 ), k = p->n / seg, i = p->n % seg;
    const char *s = pat[k % 4];
    if( s[i % strlen( s )] == 'N' )
        full_noise( g, p, full( g ) );
    else
        draw_fill( g, p, &g->img, full( g ), GREY );
}

static void draw_test_card( gen_t *g, const pic_t *p )
{
    static const int rev[7] = { 6, 7, 4, 7, 2, 7, 0 };
    int w = g->w, h = g->h, y1 = h * 2 / 3, y2 = h * 3 / 4;
    draw_bars( g, p, &g->img, R( 0, 0, w, y1 ), BARS75, NULL, 7 );
    draw_bars( g, p, &g->img, R( 0, y1, w, y2 ), BARS75, rev, 7 );
    int r0[3] = { 64 << 6, CMID, CMID }, r1[3] = { 940 << 6, CMID, CMID };
    draw_ramp( g, p, &g->img, R( 0, y2, w * 3 / 4, h ), ALL, r0, r1, 0 );
    for( int i = 0; i < 4; i++ )
    {
        int c[3] = { (64 + (i - 1) * 18) << 6, CMID, CMID };
        draw_fill( g, p, &g->img, R( w * 3 / 4 + w * i / 16, y2, w * 3 / 4 + w * (i + 1) / 16, h ), c );
    }
}

static void sc_bars_cut( gen_t *g, const pic_t *p )
{
    static const int sigma[3] = { 600, 300, 300 };
    double s = fmod( p->n / g->fps, 16 );
    if( s >= 5 && s < 7 )
        full_noise( g, p, full( g ) );
    else if( s >= 12 && s < 14 )
    {
        draw_pan( g, p, T_NAT0, 8 * p->ft, 0, full( g ) );
        draw_grain( g, p, &g->img, full( g ), ALL, sigma, 11 );
    }
    else
        draw_test_card( g, p );
}

static void sc_spikes( gen_t *g, const pic_t *p )
{
    static const int per[3] = { 3, 7, 13 };
    int seg = fsec( g, 6 ), N = per[(p->n / seg) % 3];
    if( p->n % seg % N == N - 1 )
        full_noise( g, p, full( g ) );
    else
        draw_pan( g, p, T_NAT1, 0, 0, full( g ) );
}

static void sc_lowres( gen_t *g, const pic_t *p )
{
    int w = g->w, h = g->h, h1 = h / 3, h2 = 2 * h / 3, d = YRNG * 35 / 100, dc = CRNG / 4;
    const tex_t *m = gettex( g, T_NAT3 );
    draw_pan( g, p, T_THIN, 1024 - w / 2, 3 * p->ft, R( 0, 0, w, h1 ) );
    draw_pan( g, p, T_HLINE, 0, p->ft, R( 0, h1, w / 2, h2 ) );
    draw_pan( g, p, T_CHECK, p->ft, 0, R( w / 2, h1, w, h2 ) );
    /* checker whose phase flips inside moving blobs: edges at full res, flat at half res */
    SPANS( g, p, R( 0, h2, w, h ), ALL )
    {
        int sx = pl ? 2 : 1;
        uint16_t *dst = ROWPTR( g, &g->img, pl, y );
        tex_row( m, 0, g->ra, x1 - x0, x0 * sx + 5 * p->ft, yl + 2 * p->ft, sx, 0 );
        for( int x = x0; x < x1; x++ )
        {
            int ph = ((x + y) & 1) ^ (g->ra[x - x0] > YMID);
            dst[x] = pl == 0 ? (ph ? YMID + d : YMID - d) : pl == 1 ? (ph ? CMID + dc : CMID - dc) : CMID;
        }
    }
}

static void sc_dissolve( gen_t *g, const pic_t *p )
{
    static const double tv[] = { 0, 0, 1, 0, 3, 1, 4, 1, 4.5, 0.5, 5.5, 0.5, 6, 0, 7, 0, 7.4, 1, 8, 1 };
    double a = pwl( tv, 10, fmod( secs( g, p ), 8 ) ), A[6], B[6];
    aff( g, A, 1 + 0.1 * sin( p->ft / 40 ), 0, 5 * p->ft, p->ft );
    aff( g, B, 1 + 0.15 * sin( p->ft / 45 ), 0, -3 * p->ft, 4 * p->ft );
    if( a < 1 )
        draw_tex( g, p, &g->img, T_NAT0, A, full( g ) );
    if( a >= 1 )
        draw_tex( g, p, &g->img, T_NAT2, B, full( g ) );
    else if( a > 0 )
    {
        draw_tex( g, p, &g->tmp, T_NAT2, B, full( g ) );
        blend( g, p, &g->img, &g->tmp, full( g ), a );
    }
}

static void sc_fades( gen_t *g, const pic_t *p )
{
    static const double black[] = { 0, 1, 1, 1, 2, 0, 2.4, 0, 3.4, 1 };
    static const double white[] = { 4.4, 0, 5.4, 1, 5.8, 1, 6.8, 0 };
    static const double sat[]   = { 9.5, 1, 10.5, 0, 11, 0, 11.5, 1 };
    int cyc = fsec( g, 12 ), f0 = fsec( g, 7.8 ), i = p->n % cyc;
    double t = (i + p->ft - p->n) / g->fps;
    double gy = pwl( black, 5, t ), wm = pwl( white, 4, t ), cg = pwl( sat, 4, t ), fr = i + p->ft - p->n - f0;
    int inv = i == f0 || i == f0 + 3 || i == f0 + 4;
    if( i == f0 + 10 )
        wm = 1;
    if( fr >= 20 && fr < 30 )
        gy = fabs( fr - 25 ) / 5;
    draw_pan( g, p, T_NAT1, 2 * p->ft, 0.5 * p->ft, full( g ) );
    adjust( g, p, &g->img, full( g ), gy, YBLK, 0, cg * gy );
    if( wm > 0 )
        mix_to( g, p, &g->img, full( g ), WHITE, wm, NULL );
    if( inv )
        adjust( g, p, &g->img, full( g ), -1, YMID, 0, 1 );
}

/* event of frame n: 0 full, 1 partial, 2 decaying, 3 single field, 4 burst; else none */
static int flash_event( const gen_t *g, int n )
{
    return n < 0 ? -1 : (int)(hash4( g->seed, 28, n, 0 ) % 40);
}

static void sc_flash( gen_t *g, const pic_t *p )
{
    int n = p->n, w = g->w, h = g->h;
    int e0 = flash_event( g, n ), e1 = flash_event( g, n - 1 ), e2 = flash_event( g, n - 2 ), e4 = flash_event( g, n - 4 );
    double a = 0;
    float *colw = NULL;
    draw_pan( g, p, T_NAT0, 4 * p->ft, 0, full( g ) );
    int ox = (int)bounce( 11 * p->ft, w - w / 3 ), oy = (int)bounce( 6 * p->ft, h - h / 3 );
    draw_pan( g, p, T_NAT2, -ox + 3 * p->ft, -oy, R( ox, oy, ox + w / 3, oy + h / 3 ) );
    if( e0 == 0 )
        a = 0.85;
    else if( e0 == 1 )
    {
        double cx = w * (0.2 + 0.6 * hr( g, 28, n ));
        for( int x = 0; x < w; x++ )
            g->colw[x] = (float)fmax( 0, 1 - fabs( x - cx ) / (0.4 * w) );
        colw = g->colw;
        a = 0.9;
    }
    else if( e0 == 2 )
        a = 0.9;
    else if( e0 == 3 )
        a = g->interlaced ? (p->tick & 1 ? 0 : 0.9) : 0.45;
    if( e1 == 2 )
        a = fmax( a, 0.45 );
    if( e0 == 4 || e2 == 4 || e4 == 4 )
        a = fmax( a, 0.8 );
    if( a > 0 )
        mix_to( g, p, &g->img, full( g ), WHITE, a, colw );
}

static void sc_dark( gen_t *g, const pic_t *p )
{
    static const int sigma[3] = { 40, 30, 30 };
    int w = g->w, h = g->h, ox = (int)bounce( 9 * p->ft, w - 160 ), oy = (int)bounce( 5 * p->ft, h - 90 );
    draw_pan( g, p, T_SMOOTH, 0.3 * p->ft, 0.1 * p->ft, full( g ) );
    adjust( g, p, &g->img, full( g ), 0.12, YBLK, 0, 0.3 );
    draw_grain( g, p, &g->img, R( w / 2, 0, w, h ), ALL, sigma, 29 );
    draw_pan( g, p, T_NAT0, -ox, -oy, R( ox, oy, ox + 160, oy + 90 ) );
}

/****************************************************************************
 * Scenarios: interlace
 ****************************************************************************/

static void sc_field_split( gen_t *g, const pic_t *p )
{
    pic_t f[2];
    double A[6];
    for( int i = 0, nf = fields_of( g, p, f ); i < nf; i++ )
    {
        if( f[i].field == 0 )
            aff( g, A, 1, 0, 6 * p->ft, 0 );
        else
            aff( g, A, 1 + 0.05 * sin( p->ft / 20 ), 0, -4 * p->ft, 2 * p->ft );
        draw_tex( g, &f[i], &g->img, f[i].field ? T_NAT3 : T_NAT0, A, full( g ) );
    }
}

static void sc_field_cut( gen_t *g, const pic_t *p )
{
    pic_t f[2];
    int L = fsec( g, 1.5 );
    for( int i = 0, nf = fields_of( g, p, f ); i < nf; i++ )
    {
        /* cut k lands on the second field of frame k*L, every third on the first */
        int k = f[i].ftick / (2 * L);
        int sc = f[i].ftick >= 2 * k * L + (k % 3 == 2 ? 0 : 1) ? k : k - 1;
        uint64_t s = hash4( g->seed, 17, sc + 1000, 0 ) | 1;
        double bx = rndf( &s ) * 2048, by = rndf( &s ) * 2048, vx = rndf( &s ) * 16 - 8, vy = rndf( &s ) * 16 - 8;
        draw_pan( g, &f[i], T_NAT0 + ((sc % 4) + 4) % 4, bx + vx * p->ft, by + vy * p->ft, full( g ) );
    }
}

static void sc_pulldown( gen_t *g, const pic_t *p )
{
    static const int cad[10] = { 0, 0, 1, 1, 1, 2, 2, 3, 3, 3 };
    pic_t f[2];
    int seg = 2 * fsec( g, 8 ), w = g->w, h = g->h;
    for( int i = 0, nf = fields_of( g, p, f ); i < nf; i++ )
    {
        /* each 8 s segment restarts the cadence at a new phase: a bad edit */
        int k = f[i].ftick / seg, j = f[i].ftick % seg, ph = (k * 3) % 10;
        double fi = k * (seg * 2 / 5) + ((j + ph) / 10) * 4 + cad[(j + ph) % 10];
        int ox = 100 + (int)bounce( 14 * fi, w - 680 ), oy = 100 + (int)bounce( 5 * fi, h - 520 );
        draw_pan( g, &f[i], T_NAT2, 8 * fi, 0.5 * fi, full( g ) );
        draw_pan( g, &f[i], T_NAT3, -ox - 3 * fi, -oy, R( ox, oy, ox + 480, oy + 320 ) );
        if( j >= seg / 2 )  /* video-rate crawl over film: mixed cadence */
            draw_pan( g, &f[i], T_TICKER, 4 * f[i].ftick, -(h - 112), R( 0, h - 112, w, h - 48 ) );
    }
}

static void sc_ticker( gen_t *g, const pic_t *p )
{
    double A[6], fl = 2 * p->ft;   /* field periods */
    int h = g->h, w = g->w, y1 = h * 85 / 100, y2 = h * 7 / 100, y3 = h * 70 / 100;
    aff( g, A, 1 + 0.03 * sin( 2 * PI * p->ft / 150 ), 0, 3.3 * p->ft, 0.7 * p->ft );
    draw_tex( g, p, &g->img, T_NAT0, A, full( g ) );
    draw_pan( g, p, T_TICKER, 3.37 * fl, -y1, R( 0, y1, w, y1 + 64 ) );
    draw_pan( g, p, T_TICKER, 4096 + 6.5 * fl, -y2, R( 0, y2, w, y2 + 64 ) );
    draw_pan( g, p, T_TICKER, 2000 + 0.77 * fl, -y3, R( 0, y3, w, y3 + 64 ) );
}

static void sc_credits( gen_t *g, const pic_t *p )
{
    static const double sp[11] = { 1, 2, 3, 4, 5, 6, 7, 1.5, 2.5, 3, 3 };
    static double pos, last;
    int ph = (int)(secs( g, p ) / 3) % 11;
    double v = ph == 10 ? 3 + 2.5 * sin( 2 * PI * p->ft / 12 ) : sp[ph], jx = 0, jy = 0;
    pos += v * (p->ft - last);
    last = p->ft;
    if( ph == 9 )
    {
        jx = (hr( g, 20, 2 * p->tick ) - 0.5) * 1.4;
        jy = (hr( g, 20, 2 * p->tick + 1 ) - 0.5) * 1.4;
    }
    draw_pan( g, p, T_CREDITS, 1024 - g->w / 2 + jx, pos + jy, full( g ) );
}

static void sc_comb( gen_t *g, const pic_t *p )
{
    int w = g->w, h = g->h;
    draw_pan( g, p, T_NAT1, 24 * p->ft, 0, R( 0, 0, w, h / 2 ) );
    for( int b = 0; b < 4; b++ )
    {
        rect_t r = R( 0, h / 2 + b * h / 8, w, h / 2 + (b + 1) * h / 8 );
        if( b & 1 )
            draw_pan( g, p, T_CREDITS, -18 * p->ft, b * 300, r );
        else
            draw_pan( g, p, T_NAT3, 30 * p->ft, b * 400, r );
    }
}

static void sc_field_frame( gen_t *g, const pic_t *p )
{
    int w = g->w, h = g->h, xb = (int)bounce( 2 * p->ft, w );
    for( int ty = 0; ty < h / 2; ty += 64 )
        for( int tx = 0; tx < w; tx += 64 )
        {
            rect_t r = R( tx, ty, tx + 64, ty + 64 < h / 2 ? ty + 64 : h / 2 );
            if( ((tx + ty) >> 6) & 1 )
                draw_pan( g, p, T_NAT2, 20 * p->ft, 0, r );
            else
                draw_pan( g, p, T_NAT0, 0, 0, r );
        }
    draw_pan( g, p, T_NAT0, 0, 0, R( 0, h / 2, xb, h ) );
    draw_pan( g, p, T_NAT2, -16 * p->ft, 0, R( xb, h / 2, w, h ) );
}

/****************************************************************************
 * Scenarios: graphics and broadcast oddities
 ****************************************************************************/

static void sc_logo_noise( gen_t *g, const pic_t *p )
{
    double A[6], s = fmod( secs( g, p ), 10 ), e;
    int w = g->w, h = g->h, ly = h * 70 / 100, n12 = 12, lx;
    full_noise( g, p, full( g ) );
    aff( g, A, 1, 0, -(w - 352), -54 );
    draw_tex_alpha( g, p, &g->img, T_LOGO, A, R( w - 352, 54, w - 96, 182 ) );
    if( s >= 2 && s < 9 )
    {
        double fi = (s - 2) * g->fps, fo = (s - 7) * g->fps;
        e = fi < n12 ? fi / n12 : fo > 0 ? 1 - fo / n12 : 1;
        if( e > 0 )
        {
            e = e > 1 ? 1 : e;
            lx = 96 - (int)floor( 1500 * (1 - e) * (1 - e) );
            aff( g, A, 1, 0, -lx, -ly );
            draw_tex_alpha( g, p, &g->img, T_L3, A, R( lx, ly, lx + 1400, ly + 256 ) );
        }
    }
}

static void sc_letterbox( gen_t *g, const pic_t *p )
{
    static const int sigma[3] = { 400, 200, 200 };
    int w = g->w, h = g->h, ph = (int)(secs( g, p ) / 4) % 6, ev = (int)(secs( g, p ) / 1.7);
    int lb = (h - (int)(w / 2.39)) / 2, lb2 = (h - (int)(w / 1.85)) / 2, pb = (w - h * 4 / 3) / 2;
    rect_t a[6] = { R( 0, lb, w, h - lb ), R( pb, 0, w - pb, h ), R( pb, lb, w - pb, h - lb ), full( g ),
                    R( 0, lb2, w, h - lb2 ), R( 0, lb - 38, w, h - lb - 38 ) };
    rect_t r = a[ph];
    draw_fill( g, p, &g->img, full( g ), BLACK );
    draw_pan( g, p, T_NAT2, 4 * p->ft, p->ft, r );
    draw_grain( g, p, &g->img, r, ALL, sigma, 23 );
    if( fmod( secs( g, p ), 1.7 ) < 1.2 )
    {
        /* subtitles centred in the bottom bar when it is tall enough, else over the picture */
        double A[6];
        int bar = h - r.y1, sy = bar >= 128 ? r.y1 + (bar - 128) / 2 : h - 160;
        aff( g, A, 1, 0, 1024 - w / 2, (ev % 8) * 128 - sy );
        draw_tex_alpha( g, p, &g->img, T_SUB, A, R( 0, sy, w, sy + 128 ) );
    }
}

static void sc_extremes( gen_t *g, const pic_t *p )
{
    static const int ext[8][3] = { { 0, 0, 0 }, { 65535, 65535, 65535 }, { 0, 65535, 0 }, { 65535, 0, 65535 },
                                   { 0, 0, 65535 }, { 65535, 65535, 0 }, { 32768, 0, 0 }, { 32768, 65535, 65535 } };
    int w = g->w, h = g->h, w2 = w / 2, h2 = h / 2, h4 = h / 4;
    int r0[3] = { 0, 0, 65535 }, r1[3] = { 65535, 65535, 65535 };
    draw_pan( g, p, T_EXT, p->ft, 0, R( 0, 0, w2, h2 ) );
    for( int i = 0; i < 8; i++ )
        draw_fill( g, p, &g->img, R( w2 + w2 * i / 8, 0, w2 + w2 * (i + 1) / 8, h4 ), ext[i] );
    draw_bars( g, p, &g->img, R( w2, h4, w, h2 ), BARS100, NULL, 8 );
    draw_ramp( g, p, &g->img, R( 0, h2, w2, h ), ALL, r0, r1, p->ft );
    draw_pan( g, p, T_NAT0, 5 * p->ft, 3 * p->ft, R( w2, h2, w, h ) );
    adjust( g, p, &g->img, R( w2, h2, w, h ), 2.5, YMID, 0, 3.0 );
}

static void sc_repeats( gen_t *g, const pic_t *p )
{
    static const int hold[12] = { 1, 2, 1, 3, 1, 4, 2, 2, 3, 3, 4, 4 };
    static const int sigma[3] = { 150, 100, 100 };
    static int last = -1, src = -1, left = 0, idx = 0;
    if( p->n != last )
    {
        last = p->n;
        if( !left )
        {
            src++;
            left = hold[idx++ % 12];
        }
        left--;
    }
    double ts = src + (p->ft - p->n);
    int ox = (int)bounce( 13 * ts, g->w - 400 ), oy = (int)bounce( 7 * ts, g->h - 300 );
    draw_pan( g, p, T_NAT0, 7 * ts, 2 * ts, full( g ) );
    draw_pan( g, p, T_NAT3, -ox, -oy - 4 * ts, R( ox, oy, ox + 400, oy + 300 ) );
    if( fmod( secs( g, p ), 10 ) >= 5 )
        draw_grain( g, p, &g->img, full( g ), ALL, sigma, 25 );
}

static void sc_split_pip( gen_t *g, const pic_t *p )
{
    int w = g->w, h = g->h, xs = w / 2 + 5, ph = (int)(secs( g, p ) / 5) % 3;
    double lt = p->ft - floor( secs( g, p ) / 5 ) * 5 * g->fps;
    if( ph < 2 )
    {
        draw_pan( g, p, T_NAT1, 0, 0, R( 0, 0, xs, h ) );
        if( ph == 0 )
            full_noise( g, p, R( xs, 0, w, h ) );
        else
        {
            double A[6];
            aff( g, A, 1 + 0.2 * sin( 2 * PI * lt / (2.5 * g->fps) ), 0, 20 * lt, 0 );
            draw_tex( g, p, &g->img, T_NAT2, A, R( xs, 0, w, h ) );
        }
        return;
    }
    int ww = w / 4, wh = h / 4;
    int px = 4 + (int)floor( bounce( 7.3 * p->ft, w - ww - 8 ) ), py = 4 + (int)floor( bounce( 4.1 * p->ft, h - wh - 8 ) );
    draw_pan( g, p, T_NAT1, 0, 0, full( g ) );
    draw_fill( g, p, &g->img, R( px - 4, py - 4, px + ww + 4, py + wh + 4 ), WHITE );
    draw_pan( g, p, T_NAT3, -px + 6 * p->ft, -py - 3 * p->ft, R( px, py, px + ww, py + wh ) );
}

/****************************************************************************
 * Scenario table, output, main
 ****************************************************************************/

typedef struct
{
    const char *name;
    int group, ilace;
    void (*render)( gen_t *g, const pic_t *p );
    const char *purpose;
    unsigned tex;           /* textures to build before the first frame */
} scenario_t;

#define TX( t ) (1u << T_##t)

static const char *groups[4] = { "CPU worst case", "Rate control / VBV / quality", "Interlace", "Graphics and broadcast oddities" };

static const scenario_t scenarios[] =
{
    { "noise",          0, 0, sc_noise,        "full-range white noise in all planes, new every field",
      0 },
    { "chroma-noise",   0, 0, sc_chroma_noise, "clean luma (static 5 s, then 2.5 px/frame pan), full-range chroma noise",
      TX( NAT0 ) },
    { "lsb-noise",      0, 0, sc_lsb_noise,    "smooth 10-bit gradients plus +-2 LSB 10-bit noise (vanishes at 8 bits)",
      TX( SMOOTH ) },
    { "nyquist",        0, 0, sc_nyquist,      "1-px checker, 1-px gratings, zone plate; static and subpixel motion",
      TX( CHECK ) | TX( ZONE ) | TX( VLINE ) | TX( HLINE ) | TX( VLINE3 ) },
    { "tile-chaos",     0, 0, sc_tile_chaos,   "16x16 tiles each random-walking up to +-64 px (qpel) per picture",
      TX( NATS ) },
    { "pan-fast",       0, 0, sc_pan_fast,     "2 s each: pan 96/160/250 px/frame, diagonal, vertical 64, zoom, rotate, all",
      TX( NAT0 ) | TX( NAT1 ) },
    { "cut-storm",      0, 0, sc_cut_storm,    "hard cut every frame: random texture, scale, mirror, flip, level, saturation",
      TX( NAT0 ) | TX( NAT1 ) | TX( NAT2 ) | TX( NAT3 ) },
    { "strobe",         0, 0, sc_strobe,       "4 s each: luma strobe every frame, random flicker, moving fade to black",
      TX( NAT0 ) },
    { "band-hop",       0, 0, sc_band_hop,     "all complexity in a h/4 band hopping between slice bands every second",
      TX( NAT1 ) | TX( NAT2 ) },
    { "grain",          0, 0, sc_grain,        "slow pan under heavy temporal film grain, sigma doubling every 4 s",
      TX( NAT1 ) },
    { "flat-noise-alt", 1, 0, sc_flat_noise,   "flat grey vs full noise frames in patterns FN, FFN, NNF, FNNF (4 s each)",
      0 },
    { "bars-cut",       1, 0, sc_bars_cut,     "5 s static bars, 2 s noise, 5 s bars, 2 s moving grain, 2 s bars",
      TX( NAT0 ) },
    { "spikes",         1, 0, sc_spikes,       "static picture with a noise frame every 3, 7, 13 frames (6 s each)",
      TX( NAT1 ) },
    { "lowres-deceptive",1, 0, sc_lowres,      "1-px checker text/gratings/phase blobs that are flat at half resolution",
      TX( NAT3 ) | TX( THIN ) | TX( HLINE ) | TX( CHECK ) },
    { "dissolve",       1, 0, sc_dissolve,     "slow, half-held and fast dissolves between two unrelated moving shots",
      TX( NAT0 ) | TX( NAT2 ) },
    { "fades",          1, 0, sc_fades,        "fades to black/white, inverted-luma flashes, white flash, desaturation",
      TX( NAT1 ) },
    { "flash",          1, 0, sc_flash,        "random camera flashes: full, partial, decaying, single-field, bursts",
      TX( NAT0 ) | TX( NAT2 ) },
    { "dark-gradient",  1, 0, sc_dark,         "dark 10-bit shadow gradients (8-bit 16..42), faint dither, small bright object",
      TX( SMOOTH ) | TX( NAT0 ) },
    { "field-split",    2, 1, sc_field_split,  "top and bottom fields from unrelated content moving opposite ways",
      TX( NAT0 ) | TX( NAT3 ) },
    { "field-cut",      2, 1, sc_field_cut,    "scene cuts every 1.5 s landing on the second field (every third on the first)",
      TX( NAT0 ) | TX( NAT1 ) | TX( NAT2 ) | TX( NAT3 ) },
    { "pulldown",       2, 1, sc_pulldown,     "3:2 film in 29.97i, cadence broken every 8 s, video-rate crawl half the time",
      TX( NAT2 ) | TX( NAT3 ) | TX( TICKER ) },
    { "ticker",         2, 1, sc_ticker,       "crawls at 3.37, 6.5, 0.77 px/field over zooming, panning video",
      TX( NAT0 ) | TX( TICKER ) },
    { "credits",        2, 1, sc_credits,      "rigid vertical scroll 1..7, 1.5, 2.5 px/frame, then jittered and wobbling",
      TX( CREDITS ) },
    { "comb",           2, 1, sc_comb,         "fast horizontal motion (24-30 px/frame) of high detail and text",
      TX( NAT1 ) | TX( NAT3 ) | TX( CREDITS ) },
    { "field-frame-mix",2, 1, sc_field_frame,  "64x64 static/moving checker plus a sweeping static|moving boundary",
      TX( NAT0 ) | TX( NAT2 ) },
    { "logo-noise",     3, 0, sc_logo_noise,   "semi-transparent DOG and sliding lower third over full-frame noise",
      TX( LOGO ) | TX( L3 ) },
    { "letterbox",      3, 0, sc_letterbox,    "2.39, 4:3, windowbox, full, 1.85, offset bars; subtitles in the bars",
      TX( NAT2 ) | TX( SUB ) },
    { "extremes",       3, 0, sc_extremes,     "code values 0 and max, clipped chroma, 100% bars, full ramps, overdriven video",
      TX( EXT ) | TX( NAT0 ) },
    { "repeats",        3, 0, sc_repeats,      "frames held 1-4 times; second half of every 10 s adds fresh grain",
      TX( NAT0 ) | TX( NAT3 ) },
    { "split-pip",      3, 0, sc_split_pip,    "5 s each: static|noise, static|moving split, bouncing picture-in-picture",
      TX( NAT1 ) | TX( NAT2 ) | TX( NAT3 ) },
};

#define NSCEN (int)(sizeof(scenarios) / sizeof(scenarios[0]))

static void list( void )
{
    for( int gr = 0; gr < 4; gr++ )
    {
        printf( "%s:\n", groups[gr] );
        for( int i = 0; i < NSCEN; i++ )
            if( scenarios[i].group == gr )
                printf( "  %-17s %s\n", scenarios[i].name, scenarios[i].purpose );
    }
}

static void usage( void )
{
    fprintf( stderr,
             "usage: stressgen --scenario NAME [--w 1920] [--h 1080] [--fps 25|50|30000/1001|60000/1001]\n"
             "                 [--depth 8|10] [--csp 420|422] [--interlaced tff|bff|none]\n"
             "                 [--frames N (0 = endless)] [--seed S] > out.y4m\n"
             "       stressgen --list\n" );
    exit( 1 );
}

static void write_frame( gen_t *g, uint8_t *buf, size_t size )
{
    uint8_t *o = buf;
    memcpy( o, "FRAME\n", 6 );
    o += 6;
    for( int pl = 0; pl < 3; pl++ )
    {
        const uint16_t *s = g->img.p[pl];
        size_t n = (size_t)g->pw[pl] * g->ph[pl];
        if( g->depth == 8 )
            for( size_t i = 0; i < n; i++ )
            {
                int v = (s[i] + 128) >> 8;
                *o++ = v > 255 ? 255 : v;
            }
        else
            for( size_t i = 0; i < n; i++ )
            {
                int v = (s[i] + 32) >> 6;
                v = v > 1023 ? 1023 : v;
                *o++ = v & 255;
                *o++ = v >> 8;
            }
    }
    if( fwrite( buf, 1, size, stdout ) != size )
        exit( 0 );  /* reader went away */
}

int main( int argc, char **argv )
{
    gen_t g;
    const scenario_t *sc = NULL;
    const char *name = NULL;
    memset( &g, 0, sizeof(g) );
    g.w = 1920;
    g.h = 1080;
    g.fps_num = 25;
    g.fps_den = 1;
    g.depth = 8;
    g.csp = 420;
    g.frames = 250;
    g.seed = 1;

    for( int i = 1; i < argc; i++ )
    {
        const char *a = argv[i], *v = i + 1 < argc ? argv[i + 1] : NULL;
        if( !strcmp( a, "--list" ) )
        {
            list();
            return 0;
        }
        if( !v )
            usage();
        i++;
        if( !strcmp( a, "--scenario" ) )
            name = v;
        else if( !strcmp( a, "--w" ) )
            g.w = atoi( v );
        else if( !strcmp( a, "--h" ) )
            g.h = atoi( v );
        else if( !strcmp( a, "--depth" ) )
            g.depth = atoi( v );
        else if( !strcmp( a, "--csp" ) )
            g.csp = atoi( v );
        else if( !strcmp( a, "--frames" ) )
            g.frames = atoi( v );
        else if( !strcmp( a, "--seed" ) )
            g.seed = strtoull( v, NULL, 0 );
        else if( !strcmp( a, "--fps" ) )
        {
            if( sscanf( v, "%d/%d", &g.fps_num, &g.fps_den ) != 2 && sscanf( v, "%d:%d", &g.fps_num, &g.fps_den ) != 2 )
            {
                g.fps_num = atoi( v );
                g.fps_den = 1;
            }
        }
        else if( !strcmp( a, "--interlaced" ) )
        {
            g.interlaced = strcmp( v, "none" ) != 0;
            g.tff = !strcmp( v, "tff" );
            if( g.interlaced && !g.tff && strcmp( v, "bff" ) )
                usage();
        }
        else
            usage();
    }
    for( int i = 0; name && i < NSCEN; i++ )
        if( !strcmp( name, scenarios[i].name ) )
            sc = &scenarios[i];
    if( !sc )
    {
        fprintf( stderr, "stressgen: unknown or missing --scenario; see --list\n" );
        return 1;
    }
    if( g.w < 64 || g.h < 64 || g.w > 8192 || g.h > 8192 || (g.w & 1) || (g.h & (g.csp == 420 && g.interlaced ? 3 : 1)) )
        die( "width/height must be 64..8192, even (multiple of 4 for interlaced 4:2:0)" );
    if( (g.depth != 8 && g.depth != 10) || (g.csp != 420 && g.csp != 422) || g.fps_num <= 0 || g.fps_den <= 0 || g.frames < 0 )
        die( "bad --depth, --csp, --fps or --frames" );
    if( sc->ilace && !g.interlaced )
        fprintf( stderr, "stressgen: note: %s is built for --interlaced; progressive output interleaves its fields by row\n", sc->name );
    g.fps = (double)g.fps_num / g.fps_den;

    g.pw[0] = g.w;
    g.ph[0] = g.h;
    g.pw[1] = g.pw[2] = g.w / 2;
    g.ph[1] = g.ph[2] = g.csp == 420 ? g.h / 2 : g.h;
    size_t fsize = 6;
    for( int pl = 0; pl < 3; pl++ )
    {
        size_t n = (size_t)g.pw[pl] * g.ph[pl];
        g.img.p[pl] = xmalloc( n * sizeof(uint16_t) );
        g.tmp.p[pl] = xmalloc( n * sizeof(uint16_t) );
        memset( g.img.p[pl], 0, n * sizeof(uint16_t) );
        memset( g.tmp.p[pl], 0, n * sizeof(uint16_t) );
        fsize += n * (g.depth > 8 ? 2 : 1);
    }
    g.ra = xmalloc( g.w * sizeof(uint16_t) );
    g.rb = xmalloc( g.w * sizeof(uint16_t) );
    g.colw = xmalloc( g.w * sizeof(float) );
    uint8_t *buf = xmalloc( fsize );
    init_glyphs( g.seed );
    init_gauss();
    for( int i = 0; i < T_COUNT; i++ )
        if( sc->tex >> i & 1 )
            gettex( &g, i );

#ifdef _WIN32
    _setmode( _fileno( stdout ), _O_BINARY );
#endif
#ifdef F_SETPIPE_SZ
    fcntl( 1, F_SETPIPE_SZ, 1 << 20 );     /* fewer reader wakeups; harmless if not a pipe */
#endif
    setvbuf( stdout, NULL, _IOFBF, 1 << 20 );
    printf( "YUV4MPEG2 W%d H%d F%d:%d I%c A1:1 C%s%s\n", g.w, g.h, g.fps_num, g.fps_den,
            g.interlaced ? (g.tff ? 't' : 'b') : 'p', g.csp == 420 ? "420" : "422",
            g.depth > 8 ? "p10" : g.csp == 420 ? "jpeg" : "" );

    for( int n = 0; !g.frames || n < g.frames; n++ )
    {
        pic_t p = { n, n, 2 * n, -1, 0, 1, n };
        if( g.interlaced )
            for( int k = 0; k < 2; k++ )
            {
                p.field = g.tff ? k : !k;
                p.y0 = p.field;
                p.ys = 2;
                p.tick = p.ftick = 2 * n + k;
                p.ft = n + 0.5 * k;
                sc->render( &g, &p );
            }
        else
            sc->render( &g, &p );
        write_frame( &g, buf, fsize );
    }
    fflush( stdout );
    return 0;
}
