/*****************************************************************************
 * wavgdrv.c: fixed-input A/B timing of the weighted MC kernels
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

/* Links the asm of libx264.a (--bit-depth=all) directly. Every cell: fixed
 * weight cache (as x264_weight_cache_* writes it), fixed pointers, ABAB
 * blocks of K calls timed with lfence/rdtsc .. rdtscp/lfence, median of N
 * repetitions; outputs of both arms and of a C reference compared bytewise
 * over the whole destination area. Times are TSC ticks per call. */

#define _GNU_SOURCE
#include <cpuid.h>
#include <getopt.h>
#include <math.h>
#include <sched.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#ifndef WAVG_REV
#define WAVG_REV "unknown"
#endif

/* common/mc.h x264_weight_t */
typedef struct
{
    int16_t cachea[8] __attribute__((aligned(16)));
    int16_t cacheb[8];
    int32_t i_denom;
    int32_t i_scale;
    int32_t i_offset;
    void *weightfn;
    void *weightavgfn;
} __attribute__((aligned(16))) wt_t;

/* ( dst, i_dst, src1, i_src, weight, h, src2 ) */
typedef void (*avg_fn)( void *, intptr_t, void *, intptr_t, const wt_t *, int, void * );
/* ( dst, i_dst, src, i_src, weight, h ) */
typedef void (*wt_fn)( void *, intptr_t, void *, intptr_t, const wt_t *, int );
/* ( dst, i_dst, src, i_src, weight, width, height ) */
typedef void (*pl_fn)( void *, intptr_t, void *, intptr_t, const wt_t *, int, int );

#define DECL_AVG(n) void n( void *, intptr_t, void *, intptr_t, const wt_t *, int, void * );
#define DECL_WT(n)  void n( void *, intptr_t, void *, intptr_t, const wt_t *, int );
#define DECL_PL(n)  void n( void *, intptr_t, void *, intptr_t, const wt_t *, int, int );
DECL_AVG( x264_10_mc_offsetadd_avg_w4_avx2 )
DECL_AVG( x264_10_mc_offsetadd_avg_w8_avx2 )
DECL_AVG( x264_10_mc_offsetadd_avg_w12_avx2 )
DECL_AVG( x264_10_mc_offsetadd_avg_w16_avx2 )
DECL_AVG( x264_10_mc_offsetadd_avg_w20_avx2 )
DECL_AVG( x264_10_mc_offsetadd_avg_w8_avx512icl )
DECL_AVG( x264_10_mc_offsetadd_avg_w16_avx512icl )
DECL_AVG( x264_8_mc_offsetadd_avg_w20_avx2 )
DECL_AVG( x264_8_mc_offsetsub_avg_w20_avx2 )
DECL_AVG( x264_8_mc_offsetadd_avg_w20_avx512icl )
DECL_AVG( x264_8_mc_offsetsub_avg_w20_avx512icl )
DECL_WT( x264_10_mc_weight_w12_avx2 )
DECL_WT( x264_10_mc_weight_w12_avx512 )
DECL_WT( x264_10_mc_weight_ns_w12_avx2 )
DECL_WT( x264_10_mc_weight_ns_w12_avx512 )
DECL_PL( x264_10_mc_offsetadd_plane_avx2 )
DECL_PL( x264_10_mc_offsetsub_plane_avx2 )
DECL_PL( x264_10_mc_offsetadd_plane_avx512 )
DECL_PL( x264_10_mc_offsetsub_plane_avx512 )

enum { K_AVG, K_WT, K_PLANE };
enum { OP_ADD, OP_SUB, OP_WEIGHT, OP_WEIGHT_NS };
enum { L_AVX2, L_AVX512, L_ICL };
enum { G_ENC, G_GRID };
enum { M_WARM, M_COLD, M_WHOLE };
static const char *grp_name[] = { "enc", "grid" };
static const char *mode_name[] = { "warm", "cold", "whole" };

typedef struct
{
    const char *id;
    int depth, kind, op, w;
    void *fa, *fb;
    const char *na, *nb;
    int level; /* of arm A */
} pair_t;

#define F(x) (void*)x
static const pair_t pairs[] =
{
    { "10b_offsetadd_avg_w8",     10, K_AVG, OP_ADD,  8, F(x264_10_mc_offsetadd_avg_w8_avx512icl),  F(x264_10_mc_offsetadd_avg_w8_avx2),  "avx512icl", "avx2", L_ICL },
    { "10b_offsetadd_avg_w16",    10, K_AVG, OP_ADD, 16, F(x264_10_mc_offsetadd_avg_w16_avx512icl), F(x264_10_mc_offsetadd_avg_w16_avx2), "avx512icl", "avx2", L_ICL },
    /* A/A controls: one function in both arms, the harness's own ratio */
    { "10b_offsetadd_avg_w8_AA",  10, K_AVG, OP_ADD,  8, F(x264_10_mc_offsetadd_avg_w8_avx2),  F(x264_10_mc_offsetadd_avg_w8_avx2),  "avx2", "avx2", L_AVX2 },
    { "10b_offsetadd_avg_w4_AA",  10, K_AVG, OP_ADD,  4, F(x264_10_mc_offsetadd_avg_w4_avx2),  F(x264_10_mc_offsetadd_avg_w4_avx2),  "avx2", "avx2", L_AVX2 },
    { "10b_offsetadd_avg_w12_AA", 10, K_AVG, OP_ADD, 12, F(x264_10_mc_offsetadd_avg_w12_avx2), F(x264_10_mc_offsetadd_avg_w12_avx2), "avx2", "avx2", L_AVX2 },
    { "10b_offsetadd_avg_w20_AA", 10, K_AVG, OP_ADD, 20, F(x264_10_mc_offsetadd_avg_w20_avx2), F(x264_10_mc_offsetadd_avg_w20_avx2), "avx2", "avx2", L_AVX2 },
    /* 8-bit control pairs (dispatched in c7dc060a) */
    { "8b_offsetadd_avg_w20",      8, K_AVG, OP_ADD, 20, F(x264_8_mc_offsetadd_avg_w20_avx512icl), F(x264_8_mc_offsetadd_avg_w20_avx2), "avx512icl", "avx2", L_ICL },
    { "8b_offsetsub_avg_w20",      8, K_AVG, OP_SUB, 20, F(x264_8_mc_offsetsub_avg_w20_avx512icl), F(x264_8_mc_offsetsub_avg_w20_avx2), "avx512icl", "avx2", L_ICL },
    /* stage 2 zen4 prunes on checkasm numbers */
    { "10b_weight_w12",           10, K_WT, OP_WEIGHT, 12, F(x264_10_mc_weight_w12_avx512), F(x264_10_mc_weight_w12_avx2), "avx512", "avx2", L_AVX512 },
    /* dispatched; most of what checkasm benches as weight_w12 */
    { "10b_weight_ns_w12",        10, K_WT, OP_WEIGHT_NS, 12, F(x264_10_mc_weight_ns_w12_avx512), F(x264_10_mc_weight_ns_w12_avx2), "avx512", "avx2", L_AVX512 },
    { "10b_offsetadd_plane",      10, K_PLANE, OP_ADD, 1984, F(x264_10_mc_offsetadd_plane_avx512), F(x264_10_mc_offsetadd_plane_avx2), "avx512", "avx2", L_AVX512 },
    { "10b_offsetsub_plane",      10, K_PLANE, OP_SUB, 1984, F(x264_10_mc_offsetsub_plane_avx512), F(x264_10_mc_offsetsub_plane_avx2), "avx512", "avx2", L_AVX512 },
};
#define NPAIRS (int)(sizeof(pairs)/sizeof(pairs[0]))

/* scale, denom, offset: offset-only weights are scale == 1<<denom */
static const int wsets[4][2][3] =
{
    [OP_ADD]    = { { 64, 6,   3 }, { 64, 6,  100 } },
    [OP_SUB]    = { { 64, 6,  -3 }, { 64, 6, -100 } },
    [OP_WEIGHT] = { { 72, 6,   4 }, { 120, 6, -30 } },
    [OP_WEIGHT_NS] = { { 40, 6, 5 }, { 56, 6, -20 } },
};

/* the callers' sizes: mc_luma into fdec (FDEC_STRIDE 32, x of the 4x4/8x8
 * block within the MB), get_ref into pix[16*16] (stride 16), get_ref of the
 * hpel refine (bw x bh+1, bw+4 x bh, stride 64) */
typedef struct { int w, h, ds, nd, dpx[4]; } site_t;
static const site_t avg_sites[] =
{
    { 16, 16, 32, 1, {0} }, { 16, 8, 32, 1, {0} },
    {  8, 16, 32, 2, {0,8} }, { 8, 8, 32, 2, {0,8} }, { 8, 4, 32, 2, {0,8} },
    {  4,  8, 32, 4, {0,4,8,12} }, { 4, 4, 32, 4, {0,4,8,12} },
    { 16, 16, 16, 1, {0} }, { 16, 8, 16, 1, {0} },
    {  8, 16, 16, 1, {0} }, { 8, 8, 16, 1, {0} }, { 8, 4, 16, 1, {0} },
    {  4,  8, 16, 1, {0} }, { 4, 4, 16, 1, {0} },
    { 16, 17, 64, 1, {0} }, { 16, 9, 64, 1, {0} },
    {  8, 17, 64, 1, {0} }, { 8, 9, 64, 1, {0} }, { 8, 5, 64, 1, {0} },
    {  4,  9, 64, 1, {0} }, { 4, 5, 64, 1, {0} },
    { 20, 16, 64, 1, {0} }, { 20, 8, 64, 1, {0} },
    { 12, 16, 64, 1, {0} }, { 12, 8, 64, 1, {0} }, { 12, 4, 64, 1, {0} },
    {  8,  8, 64, 1, {0} }, { 8, 4, 64, 1, {0} },
};
#define NSITES (int)(sizeof(avg_sites)/sizeof(avg_sites[0]))
/* the grid's one size per width */
static const site_t grid_sites[] =
{
    { 4, 8, 32, 1, {0} }, { 8, 8, 32, 1, {0} }, { 12, 8, 64, 1, {0} }, { 16, 16, 32, 1, {0} }, { 20, 16, 64, 1, {0} },
};

/* frame geometry of common/frame.c at 1920x1080 (1088 coded), avx512 align */
#define F_WIDTH   1984 /* 1920 + 2*PADH */
#define F_STRIDE  1984
#define F_ROWS    1152 /* 1088 + 2*PADV */

typedef struct
{
    const pair_t *p;
    int grp, mode, wi;
    int w, h, ds;          /* ds: dst stride (px); plane: w = width */
    int s1b, s2b, db;      /* byte offsets from 64-aligned bases */
} cell_t;

typedef struct
{
    cell_t c;
    double *ratio;         /* per repetition A/B */
    double ca, cb, r, lo, hi;
    int ok, xu;
} res_t;

static int reps = 51;
static double target = 40000.;
static int quiet = 0;

static uint8_t *ref_buf[2], *ref_base[2][2]; /* [depth8/10][plane] */
static uint8_t *dpl_buf, *dpl_base;          /* 10-bit plane dst */
static uint8_t *arena, *arena_c, *arena_s;
#define ARENA 32768
#define ARENA_OFF 4096
static intptr_t plane_bytes[2];
static intptr_t *cold_pos[2];
static int cold_n[2];
static intptr_t plane_pos[F_ROWS/16];
static int plane_npos;
static uint8_t *pl_save;
static int have_xinuse;

static inline uint64_t tsc_start( void )
{
    uint32_t lo, hi;
    __asm__ volatile( "lfence\n\trdtsc\n\tlfence" : "=a"(lo), "=d"(hi) :: "memory" );
    return (uint64_t)hi << 32 | lo;
}

static inline uint64_t tsc_stop( void )
{
    uint32_t lo, hi, aux;
    __asm__ volatile( "rdtscp\n\tlfence" : "=a"(lo), "=d"(hi), "=c"(aux) :: "memory" );
    return (uint64_t)hi << 32 | lo;
}

/* XINUSE: bit 2 ymm0-15 upper, bit 6 zmm0-15 upper; both clear after vzeroupper */
static inline uint64_t xinuse( void )
{
    uint32_t lo, hi;
    __asm__ volatile( "xgetbv" : "=a"(lo), "=d"(hi) : "c"(1) );
    return (uint64_t)hi << 32 | lo;
}

static int cpu_level( char *brand )
{
    uint32_t a = 0, b = 0, c = 0, d = 0;
    brand[0] = 0;
    if( __get_cpuid( 0x80000000, &a, &b, &c, &d ) && a >= 0x80000004 )
    {
        uint32_t *p = (uint32_t*)brand;
        for( uint32_t i = 0; i < 3; i++ )
            __get_cpuid( 0x80000002+i, p+4*i, p+4*i+1, p+4*i+2, p+4*i+3 );
        brand[48] = 0;
    }
    __get_cpuid( 1, &a, &b, &c, &d );
    if( !(c & (1<<27)) )
        return -1;
    uint32_t xlo, xhi;
    __asm__ volatile( "xgetbv" : "=a"(xlo), "=d"(xhi) : "c"(0) );
    __cpuid_count( 0xd, 1, a, b, c, d );
    have_xinuse = !!(a & 4);
    __cpuid_count( 7, 0, a, b, c, d );
    if( (xlo & 6) != 6 || !(b & 0x20) )
        return -1;
    int lvl = L_AVX2;
    if( (xlo & 0xe0) == 0xe0 )
    {
        if( (b & 0xD0030000) == 0xD0030000 )
            lvl = L_AVX512;
        if( (b & 0xD0230000) == 0xD0230000 && (c & 0x00005F42) == 0x00005F42 )
            lvl = L_ICL;
    }
    return lvl;
}

static uint32_t rng = 1;
static inline uint32_t rnd( void )
{
    rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5;
    return rng;
}

static void fill_pixels( uint8_t *p, intptr_t bytes, int depth )
{
    int pmax = (1 << depth) - 1;
    if( depth == 8 )
        for( intptr_t i = 0; i < bytes; i++ )
        {
            uint32_t r = rnd();
            p[i] = r&8 ? (r&1 ? pmax : 0) : r&4 ? (r&1 ? pmax-1 : 1) : (int)(r >> 8) & pmax;
        }
    else
        for( intptr_t i = 0; i < bytes/2; i++ )
        {
            uint32_t r = rnd();
            ((uint16_t*)p)[i] = r&8 ? (r&1 ? pmax : 0) : r&4 ? (r&1 ? pmax-1 : 1) : (int)(r >> 8) & pmax;
        }
}

static void fill_sentinel( uint8_t *p, intptr_t bytes )
{
    uint32_t s = 0x9e3779b9u;
    for( intptr_t i = 0; i < bytes; i++ )
    {
        s = s * 1664525u + 1013904223u;
        p[i] = s >> 24;
    }
}

/* huge-page buffers as x264_malloc */
static uint8_t *big_alloc( size_t size )
{
    size_t hp = 2 << 20;
    size = (size + hp - 1) & ~(hp - 1);
    void *p = NULL;
    if( posix_memalign( &p, hp, size ) )
        return NULL;
    madvise( p, size, MADV_HUGEPAGE );
    memset( p, 0, size );
    return p;
}

static int setup( void )
{
    for( int di = 0; di < 2; di++ )
    {
        int px = di ? 2 : 1;
        intptr_t sb = F_STRIDE * px;
        intptr_t ppx = F_STRIDE * F_ROWS;
        if( !(ppx & 1023) )
            ppx += 128; /* align_plane_size */
        plane_bytes[di] = ppx * px;
        ref_buf[di] = big_alloc( 2*plane_bytes[di] + 8192 );
        if( !ref_buf[di] )
            return -1;
        fill_pixels( ref_buf[di], 2*plane_bytes[di] + 8192, di ? 10 : 8 );
        /* two hpel planes of one frame buffer; MB-like origin, 64-byte aligned */
        for( int pl = 0; pl < 2; pl++ )
            ref_base[di][pl] = ref_buf[di] + pl*plane_bytes[di] + 64*sb + 128*px;
        /* cold: 64-byte column steps along 16-row bands over the plane */
        int nx = (sb - 256*px - 128) / 64;
        int ny = (F_ROWS - 64 - 24) / 16;
        cold_n[di] = nx * ny;
        cold_pos[di] = malloc( cold_n[di] * sizeof(intptr_t) );
        if( !cold_pos[di] )
            return -1;
        for( int k = 0; k < cold_n[di]; k++ )
            cold_pos[di][k] = (intptr_t)(k % nx) * 64 + (intptr_t)(k / nx) * 16 * sb;
    }
    dpl_buf = big_alloc( plane_bytes[1] + 4*F_STRIDE*2 + 8192 );
    pl_save = big_alloc( plane_bytes[1] + 4*F_STRIDE*2 + 8192 );
    if( !dpl_buf || !pl_save )
        return -1;
    dpl_base = dpl_buf;
    plane_npos = F_ROWS / 16;
    for( int k = 0; k < plane_npos; k++ )
        plane_pos[k] = (intptr_t)k * 16 * F_STRIDE * 2;
    if( posix_memalign( (void**)&arena, 4096, ARENA ) || posix_memalign( (void**)&arena_c, 4096, ARENA ) ||
        posix_memalign( (void**)&arena_s, 4096, ARENA ) )
        return -1;
    fill_sentinel( arena_s, ARENA );
    memcpy( arena, arena_s, ARENA );
    return 0;
}

static void weight_fill( wt_t *w, int depth, int s, int d, int o )
{
    memset( w, 0, sizeof(*w) );
    w->i_scale = s;
    w->i_denom = d;
    w->i_offset = o;
    if( s == 1<<d )
    {
        /* x264_weight_cache_mmx2 (high bit depth) / _ssse3 (8-bit) offset path */
        if( depth == 10 )
            for( int i = 0; i < 8; i++ )
                w->cachea[i] = abs(o) << 2;
        else
            memset( w->cachea, abs(o), sizeof(w->cachea) );
    }
    else
    {
        /* weight_cache_mulhrs: scale > 1<<denom (mc_weight_wtab), scale < 1<<denom (ns) */
        int mul = s << (s < 1<<d ? 15 - d : depth - d);
        int off = o * (1 << (depth-8)) + 0x7fff - ((1 << depth) - 1);
        for( int i = 0; i < 8; i++ )
        {
            w->cachea[i] = mul;
            w->cacheb[i] = off;
        }
    }
}

static inline int clipp( int v, int pmax ) { return v < 0 ? 0 : v > pmax ? pmax : v; }

static inline int op_px( int v, const wt_t *w, int depth )
{
    int pmax = (1 << depth) - 1;
    int o = w->i_offset * (1 << (depth-8));
    if( w->i_scale == 1<<w->i_denom )
        return clipp( v + o, pmax );
    int d = w->i_denom;
    return clipp( (d ? (v * w->i_scale + (1 << (d-1))) >> d : v * w->i_scale) + o, pmax );
}

#define PX(p,i) (depth == 8 ? ((uint8_t*)(p))[i] : ((uint16_t*)(p))[i])
#define SETPX(p,i,v) do { if( depth == 8 ) ((uint8_t*)(p))[i] = v; else ((uint16_t*)(p))[i] = v; } while(0)

/* C references of common/mc.c over what the asm writes: even rows */
static void ref_avg( int depth, uint8_t *dst, int ds, uint8_t *s1, uint8_t *s2, int ss, const wt_t *w, int width, int h )
{
    int rows = (h + 1) & ~1;
    for( int y = 0; y < rows; y++ )
        for( int x = 0; x < width; x++ )
        {
            int v = (PX(s1, y*ss+x) + PX(s2, y*ss+x) + 1) >> 1;
            SETPX( dst, y*ds+x, op_px( v, w, depth ) );
        }
}

static void ref_wt( int depth, uint8_t *dst, int ds, uint8_t *src, int ss, const wt_t *w, int width, int h )
{
    for( int y = 0; y < h; y++ )
        for( int x = 0; x < width; x++ )
            SETPX( dst, y*ds+x, op_px( PX(src, y*ss+x), w, depth ) );
}

static __attribute__((noinline)) uint64_t time_avg( avg_fn f, uint8_t *dst, intptr_t ds, uint8_t *s1, uint8_t *s2,
                                                    intptr_t ss, const wt_t *w, int h, const intptr_t *pos,
                                                    int npos, int *cur, int k )
{
    int c = *cur;
    uint64_t t0 = tsc_start();
    for( int i = 0; i < k; i++ )
    {
        intptr_t p = pos[c];
        f( dst, ds, s1 + p, ss, w, h, s2 + p );
        if( ++c == npos )
            c = 0;
    }
    uint64_t t1 = tsc_stop();
    *cur = c;
    return t1 - t0;
}

static __attribute__((noinline)) uint64_t time_wt( wt_fn f, uint8_t *dst, intptr_t ds, uint8_t *src,
                                                   intptr_t ss, const wt_t *w, int h, const intptr_t *pos,
                                                   int npos, int *cur, int k )
{
    int c = *cur;
    uint64_t t0 = tsc_start();
    for( int i = 0; i < k; i++ )
    {
        f( dst, ds, src + pos[c], ss, w, h );
        if( ++c == npos )
            c = 0;
    }
    uint64_t t1 = tsc_stop();
    *cur = c;
    return t1 - t0;
}

static __attribute__((noinline)) uint64_t time_pl( pl_fn f, uint8_t *dst, intptr_t ds, uint8_t *src,
                                                   intptr_t ss, const wt_t *w, int width, int height,
                                                   const intptr_t *pos, int npos, int *cur, int k )
{
    int c = *cur;
    uint64_t t0 = tsc_start();
    for( int i = 0; i < k; i++ )
    {
        f( dst + pos[c], ds, src + pos[c], ss, w, width, height );
        if( ++c == npos )
            c = 0;
    }
    uint64_t t1 = tsc_stop();
    *cur = c;
    return t1 - t0;
}

typedef struct
{
    const cell_t *c;
    int depth, px;
    wt_t w;
    uint8_t *dst, *s1, *s2;
    intptr_t ds, ss;
    const intptr_t *pos;
    int npos, cur;
} ctx_t;

static const intptr_t pos0[1] = { 0 };

static uint64_t run_arm( ctx_t *x, void *f, int k )
{
    const cell_t *c = x->c;
    switch( c->p->kind )
    {
        case K_AVG:
            return time_avg( (avg_fn)f, x->dst, x->ds, x->s1, x->s2, x->ss, &x->w, c->h, x->pos, x->npos, &x->cur, k );
        case K_WT:
            return time_wt( (wt_fn)f, x->dst, x->ds, x->s1, x->ss, &x->w, c->h, x->pos, x->npos, &x->cur, k );
        default:
            return time_pl( (pl_fn)f, x->dst, x->ds, x->s1, x->ss, &x->w, c->w, c->h, x->pos, x->npos, &x->cur, k );
    }
}

/* one call at the base position on a sentinel area; 0 if it differs from want */
static int verify_arm( ctx_t *x, void *f, uint8_t *area, const uint8_t *want, intptr_t bytes, int *xu )
{
    const cell_t *c = x->c;
    uint64_t st = 0;
    if( c->p->kind == K_PLANE )
        fill_sentinel( area, bytes );
    else
        memcpy( area, arena_s, bytes );
    switch( c->p->kind )
    {
        case K_AVG:
            ((avg_fn)f)( x->dst, x->ds, x->s1, x->ss, &x->w, c->h, x->s2 );
            break;
        case K_WT:
            ((wt_fn)f)( x->dst, x->ds, x->s1, x->ss, &x->w, c->h );
            break;
        default:
            ((pl_fn)f)( x->dst, x->ds, x->s1, x->ss, &x->w, c->w, c->h );
            break;
    }
    if( have_xinuse )
        st = xinuse();
    if( st & ((1<<2) | (1<<6)) )
        *xu = 1;
    return !memcmp( area, want, bytes );
}

static int cmp_dbl( const void *a, const void *b )
{
    double x = *(const double*)a, y = *(const double*)b;
    return x < y ? -1 : x > y;
}

static double median( double *v, int n )
{
    qsort( v, n, sizeof(double), cmp_dbl );
    return n & 1 ? v[n/2] : 0.5 * (v[n/2-1] + v[n/2]);
}

/* 1-based rank pair of the ~95% order-statistic interval of a median */
static void ci_ranks( int n, int *lo, int *hi )
{
    int k = (int)floor( (n - 1.96 * sqrt( n )) / 2 );
    if( k < 1 )
        k = 1;
    *lo = k;
    *hi = n + 1 - k;
}

static void wlabel( char *s, const pair_t *p, int wi )
{
    const int *ws = wsets[p->op][wi];
    if( p->op >= OP_WEIGHT )
        sprintf( s, "%d/%d%+d", ws[0], 1 << ws[1], ws[2] );
    else
        sprintf( s, "%+d", ws[2] );
}

static int run_cell( const cell_t *c, res_t *r )
{
    const pair_t *p = c->p;
    ctx_t x = { .c = c, .depth = p->depth, .px = p->depth == 8 ? 1 : 2 };
    int di = p->depth == 10;
    const int *ws = wsets[p->op][c->wi];
    weight_fill( &x.w, p->depth, ws[0], ws[1], ws[2] );
    x.ss = F_STRIDE;
    x.cur = 0;
    uint8_t *area;
    intptr_t bytes;
    if( p->kind == K_PLANE )
    {
        x.ds = F_STRIDE;
        x.s1 = ref_buf[1] + c->s1b; /* plane start: buffer + padh_align (0 at 10-bit) */
        x.dst = dpl_base + c->db;
        x.pos = c->mode == M_COLD ? plane_pos : pos0;
        x.npos = c->mode == M_COLD ? plane_npos : 1;
        area = dpl_buf;
        bytes = (intptr_t)(c->h + 2) * F_STRIDE * 2 + 4096;
    }
    else
    {
        x.ds = c->ds;
        x.s1 = ref_base[di][0] + c->s1b;
        x.s2 = ref_base[di][1] + c->s2b;
        x.dst = arena + ARENA_OFF + c->db;
        x.pos = c->mode == M_COLD ? cold_pos[di] : pos0;
        x.npos = c->mode == M_COLD ? cold_n[di] : 1;
        area = arena;
        bytes = ARENA;
    }

    /* C reference on the sentinel area */
    uint8_t *want = p->kind == K_PLANE ? pl_save : arena_c;
    if( p->kind == K_PLANE )
        fill_sentinel( want, bytes );
    else
        memcpy( want, arena_s, bytes );
    uint8_t *wdst = want + (x.dst - area);
    if( p->kind == K_AVG )
        ref_avg( p->depth, wdst, x.ds, x.s1, x.s2, x.ss, &x.w, c->w, c->h );
    else
        ref_wt( p->depth, wdst, x.ds, x.s1, x.ss, &x.w, c->w, c->h );
    int xu = 0;
    int ok = verify_arm( &x, p->fa, area, want, bytes, &xu );
    ok &= verify_arm( &x, p->fb, area, want, bytes, &xu );

    /* K from arm B: a block of ~target ticks */
    int k;
    run_arm( &x, p->fb, 1 );
    uint64_t t = run_arm( &x, p->fb, 4 );
    double per = t / 4.;
    k = per > 0 ? (int)(target / per) : 4096;
    if( k < 1 )
        k = 1;
    if( k > 8192 )
        k = 8192;
    if( c->mode == M_WHOLE && k > 4 )
        k = 4;

    for( int i = 0; i < 2; i++ )
    {
        run_arm( &x, p->fa, k );
        run_arm( &x, p->fb, k );
    }
    double *ta = malloc( reps * sizeof(double) );
    double *tb = malloc( reps * sizeof(double) );
    double *rr = malloc( reps * sizeof(double) );
    double *tmp = malloc( reps * sizeof(double) );
    if( !ta || !tb || !rr || !tmp )
        return -1;
    for( int i = 0; i < reps; i++ )
    {
        ta[i] = (double)run_arm( &x, p->fa, k ) / k;
        tb[i] = (double)run_arm( &x, p->fb, k ) / k;
        rr[i] = ta[i] / tb[i];
    }
    r->c = *c;
    r->ratio = rr;
    r->ca = median( ta, reps );
    r->cb = median( tb, reps );
    memcpy( tmp, rr, reps * sizeof(double) );
    r->r = median( tmp, reps );
    int lo, hi;
    ci_ranks( reps, &lo, &hi );
    r->lo = tmp[lo-1];
    r->hi = tmp[hi-1];
    r->ok = ok;
    r->xu = xu;
    free( ta );
    free( tb );
    free( tmp );

    if( !quiet || !ok )
    {
        char wl[32];
        wlabel( wl, p, c->wi );
        int s2a = p->kind == K_AVG ? (int)((uintptr_t)x.s2 & 63) : -1;
        printf( "CELL %2d %-16s %4d %4d %2d %-4s %-5s %-8s %2d %2d %2d %-9s %-4s %9.2f %9.2f %.4f %.4f %.4f %d %s%s\n",
                p->depth, p->id, c->w, c->h, (int)x.ds, grp_name[c->grp], mode_name[c->mode], wl,
                (int)((uintptr_t)x.s1 & 63), s2a, (int)((uintptr_t)x.dst & 63),
                p->na, p->nb, r->ca, r->cb, r->r, r->lo, r->hi, k, ok ? "ok" : "MISMATCH", xu ? " XINUSE" : "" );
    }
    return ok ? 0 : 1;
}

/* M_j = median over cells of the repetition-j ratio; median and ~95% CI over j */
static void summary( const char *tag, res_t *res, int *idx, int n )
{
    if( !n )
        return;
    double *m = malloc( reps * sizeof(double) );
    double *v = malloc( (n > reps ? n : reps) * sizeof(double) );
    if( !m || !v )
        return;
    for( int j = 0; j < reps; j++ )
    {
        for( int i = 0; i < n; i++ )
            v[i] = res[idx[i]].ratio[j];
        m[j] = median( v, n );
    }
    double mm = median( m, reps );
    int lo, hi;
    ci_ranks( reps, &lo, &hi );
    int wins = 0, bad = 0;
    for( int i = 0; i < n; i++ )
    {
        wins += res[idx[i]].r < 1.;
        bad += !res[idx[i]].ok;
    }
    for( int i = 0; i < n; i++ )
        v[i] = res[idx[i]].ca;
    double ca = median( v, n );
    for( int i = 0; i < n; i++ )
        v[i] = res[idx[i]].cb;
    double cb = median( v, n );
    for( int i = 0; i < n; i++ )
        v[i] = res[idx[i]].r;
    double cm = median( v, n );
    printf( "SUM  %-26s %-40s cells %5d  A %9.2f  B %9.2f  ratio %.4f  ci [%.4f %.4f]  cellmed %.4f  Afaster %5.1f%%%s\n",
            res[idx[0]].c.p->id, tag, n, ca, cb, mm, m[lo-1], m[hi-1], cm, 100. * wins / n,
            bad ? "  MISMATCH" : "" );
    free( m );
    free( v );
}

static res_t *res;
static int nres, cres;

static int add_cell( const cell_t *c )
{
    if( nres == cres )
    {
        cres = cres ? 2*cres : 1024;
        res = realloc( res, cres * sizeof(res_t) );
        if( !res )
            return -1;
    }
    return run_cell( c, &res[nres++] );
}

static int run_pair( const pair_t *p, int gmask, int mmask )
{
    int px = p->depth == 8 ? 1 : 2;
    int fails = 0;
    nres = 0;
    const int aln[7] = { 0, 2, 8, 16, 32, 48, 3*px }; /* bytes; the last an odd pixel */
    cell_t c = { .p = p };
    if( p->kind == K_PLANE )
    {
        c.w = F_WIDTH;
        if( gmask & 1 )
        {
            c.grp = G_ENC;
            for( int wi = 0; wi < 2; wi++ )
                for( int m = 0; m < 3; m++ )
                {
                    if( !(mmask & (1 << (m == M_WHOLE ? M_COLD : m))) )
                        continue;
                    c.mode = m; c.wi = wi;
                    c.h = m == M_WHOLE ? F_ROWS : 16;
                    c.s1b = c.db = 0;
                    fails += add_cell( &c );
                }
        }
        if( (gmask & 2) && (mmask & 1) )
        {
            c.grp = G_GRID; c.mode = M_WARM; c.wi = 0; c.h = 16;
            for( int a = 0; a < 7; a++ )
                for( int b = 0; b < 7; b++ )
                {
                    if( aln[a] % px || aln[b] % px )
                        continue;
                    c.s1b = aln[a]; c.db = aln[b];
                    fails += add_cell( &c );
                }
        }
    }
    else
    {
        if( gmask & 1 )
        {
            c.grp = G_ENC;
            for( int m = 0; m < 2; m++ )
            {
                if( !(mmask & (1 << m)) )
                    continue;
                c.mode = m;
                for( int si = 0; si < NSITES; si++ )
                {
                    const site_t *s = &avg_sites[si];
                    if( s->w != p->w || (p->kind == K_WT && (s->ds != 64 || s->h & 1)) )
                        continue;
                    c.w = s->w; c.h = s->h; c.ds = s->ds;
                    for( int wi = 0; wi < 2; wi++ )
                        for( int di = 0; di < s->nd; di++ )
                            for( int s1 = 0; s1 < 64; s1 += px )
                                for( int s2 = 0; s2 < (p->kind == K_AVG ? 2 : 1); s2++ )
                                {
                                    c.wi = wi;
                                    c.db = s->dpx[di] * px;
                                    c.s1b = s1;
                                    c.s2b = s1 + s2 * px; /* src2 at src1, or src1+1 px (mvx&3 == 3) */
                                    fails += add_cell( &c );
                                }
                }
            }
        }
        if( (gmask & 2) && (mmask & 1) )
        {
            static const site_t wt_grid = { 12, 16, 64, 1, {0} };
            const site_t *s = &wt_grid;
            for( int i = 0; p->kind == K_AVG && i < 5; i++ )
                if( grid_sites[i].w == p->w )
                    s = &grid_sites[i];
            c.grp = G_GRID; c.mode = M_WARM; c.wi = 0;
            c.w = s->w; c.h = s->h; c.ds = s->ds;
            for( int a = 0; a < 7; a++ )
                for( int b = 0; b < (p->kind == K_AVG ? 7 : 1); b++ )
                    for( int d = 0; d < 7; d++ )
                    {
                        if( aln[a] % px || aln[b] % px || aln[d] % px )
                            continue;
                        c.s1b = aln[a]; c.s2b = aln[b]; c.db = aln[d];
                        fails += add_cell( &c );
                    }
        }
    }

    /* summaries */
    int *idx = malloc( (nres ? nres : 1) * sizeof(int) );
    if( !idx )
        return fails + 1;
    char tag[96];
    for( int g = 0; g < 2; g++ )
        for( int m = 0; m < 3; m++ )
        {
            int n = 0;
            for( int i = 0; i < nres; i++ )
                if( res[i].c.grp == g && res[i].c.mode == m )
                    idx[n++] = i;
            if( !n )
                continue;
            sprintf( tag, "%s/%s/all", grp_name[g], mode_name[m] );
            summary( tag, res, idx, n );
            if( g == G_ENC && p->kind != K_PLANE )
            {
                for( int si = 0; si < NSITES; si++ )
                {
                    const site_t *s = &avg_sites[si];
                    n = 0;
                    for( int i = 0; i < nres; i++ )
                        if( res[i].c.grp == g && res[i].c.mode == m && res[i].c.w == s->w &&
                            res[i].c.h == s->h && res[i].c.ds == s->ds )
                            idx[n++] = i;
                    sprintf( tag, "%s/%s/%dx%d/ds%d", grp_name[g], mode_name[m], s->w, s->h, s->ds );
                    summary( tag, res, idx, n );
                }
                /* by src1 alignment class: rows inside a 64-byte line or split */
                for( int split = 0; split < 2; split++ )
                {
                    n = 0;
                    for( int i = 0; i < nres; i++ )
                        if( res[i].c.grp == g && res[i].c.mode == m &&
                            ((res[i].c.s1b + res[i].c.w * px > 64) == split) )
                            idx[n++] = i;
                    sprintf( tag, "%s/%s/src1-%s", grp_name[g], mode_name[m], split ? "splitline" : "inline" );
                    summary( tag, res, idx, n );
                }
            }
            if( g == G_GRID )
            {
                static const char *an[3] = { "src1", "src2", "dst" };
                for( int which = 0; which < 3; which++ )
                {
                    if( which == 1 && p->kind != K_AVG )
                        continue;
                    if( which == 1 && p->kind == K_PLANE )
                        continue;
                    for( int a = 0; a < 7; a++ )
                    {
                        n = 0;
                        for( int i = 0; i < nres; i++ )
                        {
                            const cell_t *rc = &res[i].c;
                            int v = which == 0 ? rc->s1b : which == 1 ? rc->s2b : rc->db;
                            if( rc->grp == g && rc->mode == m && v == aln[a] )
                                idx[n++] = i;
                        }
                        sprintf( tag, "%s/%s/%s=%d", grp_name[g], mode_name[m], an[which], aln[a] );
                        summary( tag, res, idx, n );
                    }
                }
            }
        }
    /* verdict: the encoder cells; A faster/slower only when the CI excludes 1 */
    for( int m = 0; m < 3; m++ )
    {
        int n = 0;
        for( int i = 0; i < nres; i++ )
            if( res[i].c.grp == G_ENC && res[i].c.mode == m )
                idx[n++] = i;
        if( !n )
            continue;
        double *mv = malloc( reps * sizeof(double) );
        double *v = malloc( n * sizeof(double) );
        if( !mv || !v )
            return fails + 1;
        for( int j = 0; j < reps; j++ )
        {
            for( int i = 0; i < n; i++ )
                v[i] = res[idx[i]].ratio[j];
            mv[j] = median( v, n );
        }
        double mm = median( mv, reps );
        int lo, hi;
        ci_ranks( reps, &lo, &hi );
        printf( "VERDICT %-26s %-5s %s/%s ratio %.4f ci [%.4f %.4f] -> %s\n", p->id, mode_name[m], p->na, p->nb,
                mm, mv[lo-1], mv[hi-1],
                mv[hi-1] < 1. ? "A FASTER" : mv[lo-1] > 1. ? "A SLOWER" : "NOT RESOLVED" );
        free( mv );
        free( v );
    }
    fflush( stdout );
    for( int i = 0; i < nres; i++ )
        free( res[i].ratio );
    free( idx );
    return fails;
}

static void usage( void )
{
    fprintf( stderr,
             "wavgdrv [-c cpu] [-n reps] [-t ticks per block] [-f pair substring] [-g enc|grid|all]\n"
             "        [-m warm|cold|all] [-s seed] [-q] [-l]\n"
             "  -l lists the pairs; -q prints only SUM/VERDICT lines (and mismatches)\n" );
}

int main( int argc, char **argv )
{
    int cpu = -1, gmask = 3, mmask = 3, list = 0;
    const char *filter = NULL;
    int opt;
    while( (opt = getopt( argc, argv, "c:n:t:f:g:m:s:qlh" )) != -1 )
    {
        switch( opt )
        {
            case 'c': cpu = atoi( optarg ); break;
            case 'n': reps = atoi( optarg ); break;
            case 't': target = atof( optarg ); break;
            case 'f': filter = optarg; break;
            case 'g': gmask = !strcmp( optarg, "enc" ) ? 1 : !strcmp( optarg, "grid" ) ? 2 : 3; break;
            case 'm': mmask = !strcmp( optarg, "warm" ) ? 1 : !strcmp( optarg, "cold" ) ? 2 : 3; break;
            case 's': rng = strtoul( optarg, NULL, 0 ) | 1; break;
            case 'q': quiet = 1; break;
            case 'l': list = 1; break;
            default: usage(); return 1;
        }
    }
    if( reps < 5 )
        reps = 5;
    if( list )
    {
        for( int i = 0; i < NPAIRS; i++ )
            printf( "%s  %s vs %s\n", pairs[i].id, pairs[i].na, pairs[i].nb );
        return 0;
    }
    if( cpu >= 0 )
    {
        cpu_set_t set;
        CPU_ZERO( &set );
        CPU_SET( cpu, &set );
        if( sched_setaffinity( 0, sizeof(set), &set ) )
        {
            perror( "sched_setaffinity" );
            return 1;
        }
    }
    char brand[64];
    int lvl = cpu_level( brand );
    if( lvl < 0 )
    {
        fprintf( stderr, "no AVX2\n" );
        return 1;
    }
    if( setup() )
    {
        fprintf( stderr, "allocation failed\n" );
        return 1;
    }
    printf( "# wavgdrv rev %s  cpu %s  pinned %d (on %d)  level %s  reps %d  block %.0f ticks  xinuse %d\n",
            WAVG_REV, brand, cpu, sched_getcpu(), lvl == L_ICL ? "avx512icl" : lvl == L_AVX512 ? "avx512" : "avx2",
            reps, target, have_xinuse );
    printf( "# times: TSC ticks per call (median of reps); ratio = A/B per repetition, median and ~95%% order-statistic CI\n" );
    printf( "# frame: stride %d px, %d rows, two hpel planes one plane apart; cold = 64-byte steps over 16-row bands\n",
            F_STRIDE, F_ROWS );
    printf( "# CELL depth pair w h dst_stride grp mode weight src1%%64 src2%%64 dst%%64 A B A_ticks B_ticks ratio lo hi K check\n" );
    int fails = 0, ran = 0;
    for( int i = 0; i < NPAIRS; i++ )
    {
        const pair_t *p = &pairs[i];
        if( filter && !strstr( p->id, filter ) )
            continue;
        if( p->level > lvl )
        {
            printf( "SKIP %s: needs %s\n", p->id, p->na );
            continue;
        }
        fails += run_pair( p, gmask, mmask );
        ran++;
    }
    printf( "# done: %d pairs, %d mismatching cells\n", ran, fails );
    return fails ? 2 : 0;
}
