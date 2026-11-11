/* loop-of-N harness: per-call tsc of small 8-bit kernels on block sets, throughput and latency.
 * Copyright (C) 2026 Open Broadcast Systems Ltd */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <x86intrin.h>

typedef int (*f1)( int16_t * );
typedef void (*fpcd)( uint8_t *, intptr_t, uint8_t *, intptr_t, uint8_t *, intptr_t, int, int );

#define D(n) extern int x264_8_##n( int16_t * );
D(coeff_last15_sse2_lzcnt) D(coeff_last16_sse2_lzcnt) D(coeff_last15_avx2_lzcnt) D(coeff_last16_avx2_lzcnt)
D(coeff_last15_avx512) D(coeff_last16_avx512)
D(decimate_score15_ssse3) D(decimate_score16_ssse3) D(decimate_score15_avx2) D(decimate_score16_avx2)
D(decimate_score15_xmm_avx2) D(decimate_score16_xmm_avx2) D(decimate_score15_avx512) D(decimate_score16_avx512)
#define P(n) extern void x264_8_##n( uint8_t *, intptr_t, uint8_t *, intptr_t, uint8_t *, intptr_t, int, int );
P(plane_copy_deinterleave_ssse3) P(plane_copy_deinterleave_avx2) P(plane_copy_deinterleave_avx512icl)
P(plane_copy_deinterleave_zmm_avx512icl)

__attribute__((noinline)) static int nopf( int16_t *p ) { __asm__ volatile( "" :: "r"(p) ); return 0; }

#define N 4096
static int16_t blk[N][16] __attribute__((aligned(64)));
static uint64_t rng = 88172645463325252ull;
static uint32_t rnd( void ) { rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17; return (uint32_t)rng; }

/* dist 0 sparse (high qp, +-1, short last), 1 mid, 2 dense with large levels */
static void gen( int dist, int ac )
{
    for( int b = 0; b < N; b++ )
    {
        int nz = 0;
        for( int i = 0; i < 16; i++ )
        {
            int pct = dist == 0 ? 30 - 2*i : dist == 1 ? 70 - 4*i : 95 - 2*i;
            int v = 0;
            if( (int)(rnd() % 100) < pct )
            {
                int r = rnd() % 100;
                v = dist == 0 ? (r < 92 ? 1 : 2) : dist == 1 ? (r < 70 ? 1 : r < 90 ? 2 : 1 + r%9) : 1 + (rnd() % 40);
                if( rnd() & 1 ) v = -v;
            }
            if( i < ac ) v = (rnd() & 0x3ff) - 0x200;
            blk[b][i] = v;
            nz |= i >= ac && v;
        }
        if( !nz ) blk[b][ac] = 1;
    }
}

static volatile f1 vf;
static double run( f1 f, int ac, int lat )
{
    vf = f;
    f1 g = vf;
    int R = 64, s = 0;
    double best = 1e30;
    for( int t = 0; t < 7; t++ )
    {
        uint64_t t0 = __rdtsc();
        if( lat )
        {
            int idx = 0;
            for( int r = 0; r < R*N; r++ )
            {
                int v = g( blk[idx] + ac );
                idx = (idx + 1 + (v >> 30)) & (N-1);
                s += v;
            }
        }
        else
            for( int r = 0; r < R; r++ )
                for( int i = 0; i < N; i++ )
                    s += g( blk[i] + ac );
        uint64_t t1 = __rdtsc();
        double d = (double)(t1 - t0) / ((double)R*N);
        if( d < best ) best = d;
    }
    if( s == 0x7fffffff ) printf( "." );
    return best;
}

static int no512;
static void row( const char *name, f1 *fs, const char **names, int nf, int ac )
{
    static const char *dn[3] = { "sparse", "mid", "dense" };
    for( int d = 0; d < 3; d++ )
    {
        gen( d, ac );
        double nt = run( nopf, ac, 0 ), nl = run( nopf, ac, 1 );
        printf( "%-16s %-6s nop thr %.2f lat %.2f |", name, dn[d], nt, nl );
        for( int k = 0; k < nf; k++ )
        {
            if( no512 && strstr( names[k], "avx512" ) ) continue;
            /* same output as the first kernel */
            for( int b = 0; b < N; b++ )
            {
                int a = fs[0]( blk[b] + ac ), c = fs[k]( blk[b] + ac );
                if( strstr( name, "decimate" ) ) { a = a < 7 ? a : 7; c = c < 7 ? c : 7; }
                if( a != c ) { printf( " MISMATCH %s blk %d (%d vs %d)\n", names[k], b, a, c ); exit( 1 ); }
            }
            printf( " %s thr %.2f lat %.2f |", names[k], run( fs[k], ac, 0 ) - nt, run( fs[k], ac, 1 ) - nl );
        }
        printf( "\n" );
    }
}

int main( int argc, char **argv )
{
    no512 = argc > 1 && !strcmp( argv[1], "noavx512" ); /* AVX2-only machines */
    {
        f1 f[] = { x264_8_coeff_last16_sse2_lzcnt, x264_8_coeff_last16_avx2_lzcnt, x264_8_coeff_last16_avx512 };
        const char *n[] = { "sse2_lzcnt", "avx2_lzcnt", "avx512" };
        row( "coeff_last16", f, n, 3, 0 );
    }
    {
        f1 f[] = { x264_8_coeff_last15_sse2_lzcnt, x264_8_coeff_last15_avx2_lzcnt, x264_8_coeff_last15_avx512 };
        const char *n[] = { "sse2_lzcnt", "avx2_lzcnt", "avx512" };
        row( "coeff_last15", f, n, 3, 1 );
    }
    {
        f1 f[] = { x264_8_decimate_score16_ssse3, x264_8_decimate_score16_avx2, x264_8_decimate_score16_xmm_avx2, x264_8_decimate_score16_avx512 };
        const char *n[] = { "ssse3", "avx2", "xmm_avx2", "avx512" };
        row( "decimate16", f, n, 4, 0 );
    }
    {
        f1 f[] = { x264_8_decimate_score15_ssse3, x264_8_decimate_score15_avx2, x264_8_decimate_score15_xmm_avx2, x264_8_decimate_score15_avx512 };
        const char *n[] = { "ssse3", "avx2", "xmm_avx2", "avx512" };
        /* 15 takes the whole 16-coef block; the DC is ignored */
        static int16_t dummy;
        (void)dummy;
        row( "decimate15", f, n, 4, 0 );
    }
    /* 1080i field chroma plane: 960x270 NV12 rows, and 1080p 960x540 */
    {
        fpcd f[] = { x264_8_plane_copy_deinterleave_ssse3, x264_8_plane_copy_deinterleave_avx2,
                     x264_8_plane_copy_deinterleave_avx512icl, x264_8_plane_copy_deinterleave_zmm_avx512icl };
        const char *n[] = { "ssse3", "avx2", "avx512icl", "zmm_avx512icl" };
        int hs[3] = { 4, 270, 540 };
        intptr_t is = 1920 + 128, os = 1024;
        uint8_t *src = aligned_alloc( 64, is*540 + 64 ), *du = aligned_alloc( 64, os*540 + 64 ), *dv = aligned_alloc( 64, os*540 + 64 );
        uint8_t *ru = aligned_alloc( 64, os*540 + 64 ), *rv = aligned_alloc( 64, os*540 + 64 );
        for( intptr_t i = 0; i < is*540; i++ ) src[i] = rnd();
        /* cold: 960x8 bands (the weightp call) walking a 64 MB source, so it comes from DRAM */
        size_t bigsz = (size_t)64 << 20;
        uint8_t *big = aligned_alloc( 64, bigsz );
        for( size_t i = 0; i < bigsz; i += 64 ) big[i] = rnd();
        int nb = (int)(bigsz / (is*8)) - 1;
        static const int hs2[4] = { 4, 8, 270, 540 };
        for( int pass = 0; pass < 2; pass++ )
        for( int hh = 0; hh < 5; hh++ )
        {
            int cold = hh == 4;
            int h = cold ? 8 : hs2[hh];
            printf( "plane_deint 960x%-3d%s pass %d |", h, cold ? " cold" : "     ", pass );
            memset( ru, 0, os*540 ); memset( rv, 0, os*540 );
            f[0]( ru, os, rv, os, src, is, 960, h );
            for( int kk = 0; kk < 4; kk++ )
            {
                int k = pass ? 3 - kk : kk;
                if( no512 && strstr( n[k], "avx512" ) ) continue;
                memset( du, 0, os*540 ); memset( dv, 0, os*540 );
                f[k]( du, os, dv, os, src, is, 960, h );
                for( int y = 0; y < h; y++ )
                    if( memcmp( du+y*os, ru+y*os, 960 ) || memcmp( dv+y*os, rv+y*os, 960 ) ) { printf( " MISMATCH %s\n", n[k] ); exit( 1 ); }
                int R = h <= 8 ? 20000 : 200;
                if( cold ) R = nb;
                double best = 1e30;
                for( int t = 0; t < 5; t++ )
                {
                    uint64_t t0 = __rdtsc();
                    for( int r = 0; r < R; r++ )
                        f[k]( du, os, dv, os, cold ? big + (size_t)r*is*8 : src, is, 960, h );
                    uint64_t t1 = __rdtsc();
                    double d = (double)(t1 - t0) / R;
                    if( d < best ) best = d;
                }
                printf( " %s %.0f |", n[k], best );
            }
            printf( "\n" );
        }
    }
    return 0;
}
