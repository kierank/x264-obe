/*****************************************************************************
 * checkasm.c: assembly check tool
 *****************************************************************************
 * Copyright (C) 2003-2014 x264 project
 *
 * Authors: Loren Merritt <lorenm@u.washington.edu>
 *          Laurent Aimar <fenrir@via.ecp.fr>
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

#include <ctype.h>
#include "common/common.h"
#if SYS_LINUX
#include <sys/mman.h>
#include <unistd.h>
#endif

// GCC doesn't align stack variables on ARM, so use .bss
#if ARCH_ARM
#undef ALIGNED_16
#define ALIGNED_16( var ) DECLARE_ALIGNED( static var, 16 )
#endif

/* buf1, buf2: initialised to random data and shouldn't write into them */
uint8_t *buf1, *buf2;
/* buf3, buf4: used to store output */
uint8_t *buf3, *buf4;
/* pbuf1, pbuf2: initialised to random pixel data and shouldn't write into them. */
pixel *pbuf1, *pbuf2;
/* pbuf3, pbuf4: point to buf3, buf4, just for type convenience */
pixel *pbuf3, *pbuf4;

int quiet = 0;

#define report( name ) { \
    if( used_asm && !quiet ) \
        fprintf( stderr, " - %-21s [%s]\n", name, ok ? "OK" : "FAILED" ); \
    if( !ok ) ret = -1; \
}

#define BENCH_RUNS 100  // tradeoff between accuracy and speed
#define MAX_FUNCS 1000  // just has to be big enough to hold all the existing functions
#define MAX_CPUS 30     // number of different combinations of cpu flags

// RAND_MAX is guaranteed to be at least 32767, to get 30 bits of random data, we'll call rand() twice
#define rand30() (((rand() & 0x7fff) << 15) + (rand() & 0x7fff))

typedef struct
{
    void *pointer; // just for detecting duplicates
    uint32_t cpu;
    uint64_t cycles;
    uint32_t den;
} bench_t;

typedef struct
{
    char *name;
    bench_t vers[MAX_CPUS];
} bench_func_t;

int do_bench = 0;
int bench_pattern_len = 0;
const char *bench_pattern = "";
static int bench_seed;
char func_name[100];
static bench_func_t benchs[MAX_FUNCS];

static const char *pixel_names[12] = { "16x16", "16x8", "8x16", "8x8", "8x4", "4x8", "4x4", "4x16", "4x2", "2x8", "2x4", "2x2" };
static const char *intra_predict_16x16_names[7] = { "v", "h", "dc", "p", "dcl", "dct", "dc8" };
static const char *intra_predict_8x8c_names[7] = { "dc", "h", "v", "p", "dcl", "dct", "dc8" };
static const char *intra_predict_4x4_names[12] = { "v", "h", "dc", "ddl", "ddr", "vr", "hd", "vl", "hu", "dcl", "dct", "dc8" };
static const char **intra_predict_8x8_names = intra_predict_4x4_names;
static const char **intra_predict_8x16c_names = intra_predict_8x8c_names;

#define set_func_name(...) snprintf( func_name, sizeof(func_name), __VA_ARGS__ )

/* bench inputs: a private xorshift, not rand(), so they are the same at every
 * cpu level, seed and --bench filter */
static uint32_t bench_rng;
static void bench_srand( uint32_t s )
{
    bench_rng = s * 2654435761u | 1;
}
static int bench_rand( void )
{
    bench_rng ^= bench_rng << 13;
    bench_rng ^= bench_rng >> 17;
    bench_rng ^= bench_rng << 5;
    return bench_rng >> 1;
}

static inline uint32_t read_time(void)
{
    uint32_t a = 0;
#if HAVE_X86_INLINE_ASM
    asm volatile( "rdtsc" :"=a"(a) ::"edx" );
#elif ARCH_PPC
    asm volatile( "mftb %0" : "=r" (a) );
#elif ARCH_ARM     // ARMv7 only
    asm volatile( "mrc p15, 0, %0, c9, c13, 0" : "=r"(a) );
#endif
    return a;
}

static bench_t* get_bench( const char *name, int cpu )
{
    int i, j;
    for( i = 0; benchs[i].name && strcmp(name, benchs[i].name); i++ )
        assert( i < MAX_FUNCS );
    if( !benchs[i].name )
        benchs[i].name = strdup( name );
    if( !cpu )
        return &benchs[i].vers[0];
    for( j = 1; benchs[i].vers[j].cpu && benchs[i].vers[j].cpu != cpu; j++ )
        assert( j < MAX_CPUS );
    benchs[i].vers[j].cpu = cpu;
    return &benchs[i].vers[j];
}

static int cmp_nop( const void *a, const void *b )
{
    return *(uint16_t*)a - *(uint16_t*)b;
}

static int cmp_bench( const void *a, const void *b )
{
    // asciibetical sort except preserving numbers
    const char *sa = ((bench_func_t*)a)->name;
    const char *sb = ((bench_func_t*)b)->name;
    for( ;; sa++, sb++ )
    {
        if( !*sa && !*sb )
            return 0;
        if( isdigit( *sa ) && isdigit( *sb ) && isdigit( sa[1] ) != isdigit( sb[1] ) )
            return isdigit( sa[1] ) - isdigit( sb[1] );
        if( *sa != *sb )
            return *sa - *sb;
    }
}

static void print_bench(void)
{
    uint16_t nops[10000];
    int nfuncs, nop_time=0;

    for( int i = 0; i < 10000; i++ )
    {
        uint32_t t = read_time();
        nops[i] = read_time() - t;
    }
    qsort( nops, 10000, sizeof(uint16_t), cmp_nop );
    for( int i = 500; i < 9500; i++ )
        nop_time += nops[i];
    nop_time /= 900;
    printf( "nop: %d\n", nop_time );

    for( nfuncs = 0; nfuncs < MAX_FUNCS && benchs[nfuncs].name; nfuncs++ );
    qsort( benchs, nfuncs, sizeof(bench_func_t), cmp_bench );
    for( int i = 0; i < nfuncs; i++ )
        for( int j = 0; j < MAX_CPUS && (!j || benchs[i].vers[j].cpu); j++ )
        {
            int k;
            bench_t *b = &benchs[i].vers[j];
            if( !b->den )
                continue;
            for( k = 0; k < j && benchs[i].vers[k].pointer != b->pointer; k++ );
            if( k < j )
                continue;
            printf( "%s_%s%s: %"PRId64"\n", benchs[i].name,
#if HAVE_MMX
                    b->cpu&X264_CPU_AVX512ICL ? "avx512icl" :
                    b->cpu&X264_CPU_AVX512 ? "avx512" :
                    b->cpu&X264_CPU_AVX2 && b->cpu&X264_CPU_FMA3 ? "avx2_fma3" :
                    b->cpu&X264_CPU_AVX2 ? "avx2" :
                    b->cpu&X264_CPU_FMA3 ? "fma3" :
                    b->cpu&X264_CPU_FMA4 ? "fma4" :
                    b->cpu&X264_CPU_XOP ? "xop" :
                    b->cpu&X264_CPU_AVX ? "avx" :
                    b->cpu&X264_CPU_SSE4 ? "sse4" :
                    b->cpu&X264_CPU_SSSE3 ? "ssse3" :
                    b->cpu&X264_CPU_SSE3 ? "sse3" :
                    /* print sse2slow only if there's also a sse2fast version of the same func */
                    b->cpu&X264_CPU_SSE2_IS_SLOW && j<MAX_CPUS-1 && b[1].cpu&X264_CPU_SSE2_IS_FAST && !(b[1].cpu&X264_CPU_SSE3) ? "sse2slow" :
                    b->cpu&X264_CPU_SSE2 ? "sse2" :
                    b->cpu&X264_CPU_SSE ? "sse" :
                    b->cpu&X264_CPU_MMX ? "mmx" :
#elif ARCH_PPC
                    b->cpu&X264_CPU_ALTIVEC ? "altivec" :
#elif ARCH_ARM
                    b->cpu&X264_CPU_NEON ? "neon" :
                    b->cpu&X264_CPU_ARMV6 ? "armv6" :
#endif
                    "c",
#if HAVE_MMX
                    b->cpu&X264_CPU_CACHELINE_32 ? "_c32" :
                    b->cpu&X264_CPU_SLOW_ATOM && b->cpu&X264_CPU_CACHELINE_64 ? "_c64_atom" :
                    b->cpu&X264_CPU_CACHELINE_64 ? "_c64" :
                    b->cpu&X264_CPU_SLOW_SHUFFLE ? "_slowshuffle" :
                    b->cpu&X264_CPU_LZCNT ? "_lzcnt" :
                    b->cpu&X264_CPU_BMI2 ? "_bmi2" :
                    b->cpu&X264_CPU_BMI1 ? "_bmi1" :
                    b->cpu&X264_CPU_SLOW_ATOM ? "_atom" :
#elif ARCH_ARM
                    b->cpu&X264_CPU_FAST_NEON_MRC ? "_fast_mrc" :
#endif
                    "",
                    (int64_t)(10*b->cycles/b->den - nop_time)/4 );
        }
}

#if ARCH_X86 || ARCH_X86_64
int x264_stack_pagealign( int (*func)(), int align );

/* detect when callee-saved regs aren't saved
 * needs an explicit asm check because it only sometimes crashes in normal use. */
intptr_t x264_checkasm_call( intptr_t (*func)(), int *ok, ... );
#else
#define x264_stack_pagealign( func, align ) func()
#endif

#define call_c1(func,...) func(__VA_ARGS__)

#if ARCH_X86_64
/* Evil hack: detect incorrect assumptions that 32-bit ints are zero-extended to 64-bit.
 * This is done by clobbering the stack with junk around the stack pointer and calling the
 * assembly function through x264_checkasm_call with added dummy arguments which forces all
 * real arguments to be passed on the stack and not in registers. For 32-bit argument the
 * upper half of the 64-bit register location on the stack will now contain junk. Note that
 * this is dependant on compiler behaviour and that interrupts etc. at the wrong time may
 * overwrite the junk written to the stack so there's no guarantee that it will always
 * detect all functions that assumes zero-extension.
 */
void x264_checkasm_stack_clobber( uint64_t clobber, ... );
/* nonzero (avx-512 cpus): x264_checkasm_call loads k0-k7 from it */
uint64_t x264_checkasm_kmask;
#define call_a1(func,...) ({ \
    uint64_t r = (rand() & 0xffff) * 0x0001000100010001ULL; \
    x264_checkasm_stack_clobber( r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r ); /* max_args+6 */ \
    x264_checkasm_call(( intptr_t(*)())func, &ok, 0, 0, 0, 0, __VA_ARGS__ ); })
#elif ARCH_X86
#define call_a1(func,...) x264_checkasm_call( (intptr_t(*)())func, &ok, __VA_ARGS__ )
#else
#define call_a1 call_c1
#endif

#define call_bench(func,cpu,...)\
    if( do_bench && !strncmp(func_name, bench_pattern, bench_pattern_len) )\
    {\
        uint64_t tsum = 0;\
        int tcount = 0;\
        call_a1(func, __VA_ARGS__);\
        for( int ti = 0; ti < (cpu?BENCH_RUNS:BENCH_RUNS/4); ti++ )\
        {\
            uint32_t t = read_time();\
            func(__VA_ARGS__);\
            func(__VA_ARGS__);\
            func(__VA_ARGS__);\
            func(__VA_ARGS__);\
            t = read_time() - t;\
            if( (uint64_t)t*tcount <= tsum*4 && ti > 0 )\
            {\
                tsum += t;\
                tcount++;\
            }\
        }\
        bench_t *b = get_bench( func_name, cpu );\
        b->cycles += tsum;\
        b->den += tcount;\
        b->pointer = func;\
    }

/* for most functions, run benchmark and correctness test at the same time.
 * for those that modify their inputs, run the above macros separately */
#define call_a(func,...) ({ call_a2(func,__VA_ARGS__); call_a1(func,__VA_ARGS__); })
#define call_c(func,...) ({ call_c2(func,__VA_ARGS__); call_c1(func,__VA_ARGS__); })
#define call_a2(func,...) ({ call_bench(func,cpu_new,__VA_ARGS__); })
#define call_c2(func,...) ({ call_bench(func,0,__VA_ARGS__); })

#if !HIGH_BIT_DEPTH
/* me.c's dia / hex search through sad_x3 / sad_x4 and sad_sq_min_c, as me.c does them without the
 * search kernels. st: 0 no move, 1 the walk ended without a move, 2 iteration limit, 3 out of range,
 * 4 four or more moves, 5.. square idx 0-8 (dia: the dir of each move, 1 3 4 12) */
static uint64_t fpel_search_model( int hex, int i_pixel, pixel *p_fenc, pixel *p_fref_w, intptr_t stride,
                                   const uint16_t *p_cost_mvx, const uint16_t *p_cost_mvy, int bmx, int bmy, int bcost,
                                   int i_me_range, uint32_t mv_min, uint32_t mv_max, int *st,
                                   x264_pixel_cmp_x3_t sad_x3, x264_pixel_cmp_x4_t sad_x4 )
{
    static const uint8_t mod6m1[8] = {5,0,1,2,3,4,5,0};
    static const int8_t hex2[8][2] = {{-1,-2}, {-2,0}, {-1,2}, {1,2}, {2,0}, {1,-2}, {-1,-2}, {-2,0}};
    static const int8_t square1[9][2] = {{0,0}, {0,-1}, {0,1}, {-1,0}, {1,0}, {-1,-1}, {-1,1}, {1,-1}, {1,1}};
#define BITS_MVD( mx, my ) (p_cost_mvx[(mx)*4] + p_cost_mvy[(my)*4])
#define pack16to32_mask2(mx,my) (((uint32_t)(mx)<<16)|((my)&0x7FFF))
#define CHECK_MVRANGE(mx,my) (!(((pack16to32_mask2(mx,my) + mv_min) | (mv_max - pack16to32_mask2(mx,my))) & 0x80004000))
    int32_t pt_bias[12];
    int costs[4];
#define MIN1( key ) { int k_ = key; if( k_ < bcost ) bcost = k_; }
    int moves = 0;
    if( !hex )
    {
        bcost <<= 4;
        int i = i_me_range;
        do
        {
            pixel *pb = p_fref_w + bmx + bmy*stride;
            sad_x4( p_fenc, pb - stride, pb + stride, pb - 1, pb + 1, stride, costs );
            MIN1( ((costs[0] + BITS_MVD( bmx, bmy-1 )) << 4) + 1 );
            MIN1( ((costs[1] + BITS_MVD( bmx, bmy+1 )) << 4) + 3 );
            MIN1( ((costs[2] + BITS_MVD( bmx-1, bmy )) << 4) + 4 );
            MIN1( ((costs[3] + BITS_MVD( bmx+1, bmy )) << 4) + 12 );
            if( !(bcost&15) )
            {
                st[0]++;
                break;
            }
            st[5 + ((bcost&15) == 3) + 2*((bcost&15) == 4) + 3*((bcost&15) == 12)]++;
            moves++;
            bmx -= (bcost<<28)>>30;
            bmy -= (bcost<<30)>>30;
            bcost &= ~15;
            if( i == 1 )
                st[2]++;
            else if( !CHECK_MVRANGE(bmx, bmy) )
                st[3]++;
        } while( --i && CHECK_MVRANGE(bmx, bmy) );
        bcost >>= 4;
    }
    else
    {
        bcost <<= 6;
        for( int g = 0; g < 2; g++ )
        {
            pixel *pb = p_fref_w + bmx + bmy*stride;
            sad_x3( p_fenc, pb + hex2[3*g+1][0] + hex2[3*g+1][1]*stride, pb + hex2[3*g+2][0] + hex2[3*g+2][1]*stride,
                    pb + hex2[3*g+3][0] + hex2[3*g+3][1]*stride, stride, costs );
            for( int j = 0; j < 3; j++ )
                MIN1( ((costs[j] + BITS_MVD( bmx+hex2[3*g+j+1][0], bmy+hex2[3*g+j+1][1] )) << 6) + 3*g+j+2 );
        }
        if( bcost&63 )
        {
            int dir = (bcost&63)-2;
            int i = (i_me_range>>1) - 1;
            bmx += hex2[dir+1][0];
            bmy += hex2[dir+1][1];
            moves++;
            for( ; i > 0 && CHECK_MVRANGE(bmx, bmy); i-- )
            {
                bcost &= ~63;
                pixel *pb = p_fref_w + bmx + bmy*stride;
                sad_x3( p_fenc, pb + hex2[dir][0] + hex2[dir][1]*stride, pb + hex2[dir+1][0] + hex2[dir+1][1]*stride,
                        pb + hex2[dir+2][0] + hex2[dir+2][1]*stride, stride, costs );
                for( int j = 0; j < 3; j++ )
                    MIN1( ((costs[j] + BITS_MVD( bmx+hex2[dir+j][0], bmy+hex2[dir+j][1] )) << 6) + j+1 );
                if( !(bcost&63) )
                {
                    st[1]++;
                    break;
                }
                dir += (bcost&63)-2;
                dir = mod6m1[dir+1];
                bmx += hex2[dir+1][0];
                bmy += hex2[dir+1][1];
                moves++;
            }
            if( i <= 0 )
                st[2]++;
            else if( !CHECK_MVRANGE(bmx, bmy) )
                st[3]++;
        }
        else
            st[0]++;
        bcost >>= 6;
        bcost <<= 6;
        int cx0 = p_cost_mvx[(bmx-1)*4], cx1 = p_cost_mvx[bmx*4], cx2 = p_cost_mvx[(bmx+1)*4];
        int cy0 = p_cost_mvy[(bmy-1)*4], cy1 = p_cost_mvy[bmy*4], cy2 = p_cost_mvy[(bmy+1)*4];
        pt_bias[ 0] = ((cx0 + cy0) << 6) + 5;
        pt_bias[ 1] = ((cx1 + cy0) << 6) + 1;
        pt_bias[ 2] = ((cx2 + cy0) << 6) + 7;
        pt_bias[ 3] = 1 << 30;
        pt_bias[ 4] = ((cx0 + cy2) << 6) + 6;
        pt_bias[ 5] = ((cx1 + cy2) << 6) + 2;
        pt_bias[ 6] = ((cx2 + cy2) << 6) + 8;
        pt_bias[ 7] = 1 << 30;
        pt_bias[ 8] = ((cx0 + cy1) << 6) + 3;
        pt_bias[ 9] = 1 << 30;
        pt_bias[10] = ((cx2 + cy1) << 6) + 4;
        pt_bias[11] = 1 << 30;
        bcost = x264_pixel_sad_sq_min_c( i_pixel, p_fenc, p_fref_w + bmx + bmy*stride, stride, pt_bias, bcost );
        st[5 + (bcost&63)]++;
        bmx += square1[bcost&63][0];
        bmy += square1[bcost&63][1];
        bcost >>= 6;
    }
    if( moves >= 4 )
        st[4]++;
#undef BITS_MVD
#undef pack16to32_mask2
#undef CHECK_MVRANGE
#undef MIN1
    return (uint32_t)bcost | (uint64_t)pack16to32_mask( bmx, bmy ) << 32;
}
#endif

/* reference of the asm only weightp_satd8_search: x264_weights_analyse's luma pass */
static void wp_weight8x8( pixel *dst, pixel *src, intptr_t i_src, int scale, int denom, int offset )
{
    int round = (1 << denom) >> 1;
    for( int y = 0; y < 8; y++ )
        for( int x = 0; x < 8; x++ )
            dst[x+8*y] = x264_clip_pixel( ((src[x+y*i_src] * scale + round) >> denom) + offset );
}

/* An offset changes every weighted pixel by the same amount while nothing clips (per
 * block, from the min and max of r, as the weighting is monotonic), so only the DC of
 * each 4x4 Hadamard, the sum D of the 4x4 differences, changes: by 16 * the offset
 * difference. satd_8x8 is half the sum of |coefficients| of its 4 4x4 transforms (each
 * even: all of a transform's coefficients have the parity of D), so it changes by the
 * sum of ( |D + 16*d| - |D| ) / 2, exactly. */
static void weightp_satd8_search_ref( x264_pixel_function_t *pf, uint32_t (*cost)[4], pixel *r, pixel *f,
                                      intptr_t i_stride, int n, uint16_t *icost, const int16_t (*wp)[4], int nk )
{
    ALIGNED_ARRAY_16( pixel, buf,[8*8] );
    for( int i = 0; i < n; i++, r += 8, f += 8 )
    {
        int ic = icost[i] << (BIT_DEPTH-8);
        int mn = PIXEL_MAX, mx = 0;
        for( int y = 0; y < 8; y++ )
            for( int x = 0; x < 8; x++ )
            {
                mn = X264_MIN( mn, r[x+y*i_stride] );
                mx = X264_MAX( mx, r[x+y*i_stride] );
            }
        for( int k = 0; k < nk; k++ )
        {
            int scale = wp[k][0], denom = wp[k][1], o0 = wp[k][2];
            int round = (1 << denom) >> 1;
            int lo = ((mn * scale + round) >> denom) + o0;
            int hi = ((mx * scale + round) >> denom) + o0;
            int32_t dc[4];
            wp_weight8x8( buf, r, i_stride, scale, denom, o0 );
            int base = pf->satd[PIXEL_8x8]( buf, 8, f, i_stride );
            cost[k][0] += X264_MIN( base, ic );
            if( wp[k][3] > 1 && lo >= 0 )
                pf->weightp_dc8x8( dc, buf, 8, f, i_stride );
            for( int j = 1; j < wp[k][3]; j++ )
            {
                int d = j << (BIT_DEPTH-8);
                int cj;
                if( lo >= 0 && hi + d <= PIXEL_MAX )
                    cj = base + ( abs( dc[0] + 16*d ) - abs( dc[0] ) + abs( dc[1] + 16*d ) - abs( dc[1] )
                                + abs( dc[2] + 16*d ) - abs( dc[2] ) + abs( dc[3] + 16*d ) - abs( dc[3] ) ) / 2;
                else
                {
                    wp_weight8x8( buf, r, i_stride, scale, denom, o0 + d );
                    cj = pf->satd[PIXEL_8x8]( buf, 8, f, i_stride );
                }
                cost[k][j] += X264_MIN( cj, ic );
            }
        }
    }
}

static int check_pixel( int cpu_ref, int cpu_new )
{
    x264_pixel_function_t pixel_c;
    x264_pixel_function_t pixel_ref;
    x264_pixel_function_t pixel_asm;
    x264_predict_t predict_4x4[12];
    x264_predict_t predict_8x8c[7];
    x264_predict8x8_t predict_8x8[12];
    x264_predict_8x8_filter_t predict_8x8_filter;
    ALIGNED_16( pixel edge[36] );
    uint16_t cost_mv[32];
    int ret = 0, ok, used_asm;

    x264_pixel_init( 0, &pixel_c );
    x264_pixel_init( cpu_ref, &pixel_ref );
    x264_pixel_init( cpu_new, &pixel_asm );
    x264_predict_4x4_init( 0, predict_4x4 );
    x264_predict_8x8c_init( 0, predict_8x8c );
    x264_predict_8x8_init( 0, predict_8x8, &predict_8x8_filter );
    predict_8x8_filter( pbuf2+40, edge, ALL_NEIGHBORS, ALL_NEIGHBORS );

    // maximize sum
    for( int i = 0; i < 256; i++ )
    {
        int z = i|(i>>4);
        z ^= z>>2;
        z ^= z>>1;
        pbuf4[i] = -(z&1) & PIXEL_MAX;
        pbuf3[i] = ~pbuf4[i] & PIXEL_MAX;
    }
    // random pattern made of maxed pixel differences, in case an intermediate value overflows
    for( int i = 256; i < 0x1000; i++ )
    {
        pbuf4[i] = -(pbuf1[i&~0x88]&1) & PIXEL_MAX;
        pbuf3[i] = ~(pbuf4[i]) & PIXEL_MAX;
    }
    // maxed differences, negated in one column of the top 8x8s: puts most of the sa8d sum in one word
    for( int i = 256; i < 512; i++ )
    {
        pbuf4[i] = i&0x80 ? 0 : -!(i&7) & PIXEL_MAX;
        pbuf3[i] = i&0x80 ? 0 : ~pbuf4[i] & PIXEL_MAX;
    }

#define TEST_PIXEL( name, align ) \
    ok = 1, used_asm = 0; \
    for( int i = 0; i < ARRAY_ELEMS(pixel_c.name); i++ ) \
    { \
        int res_c, res_asm; \
        if( pixel_asm.name[i] != pixel_ref.name[i] ) \
        { \
            set_func_name( "%s_%s", #name, pixel_names[i] ); \
            used_asm = 1; \
            for( int j = 0; j < 64; j++ ) \
            { \
                intptr_t stride1 = (j&31) == 31 ? 32 : FENC_STRIDE; \
                res_c   = call_c( pixel_c.name[i],   pbuf1, stride1, pbuf2+j*!align, (intptr_t)64 ); \
                res_asm = call_a( pixel_asm.name[i], pbuf1, stride1, pbuf2+j*!align, (intptr_t)64 ); \
                if( res_c != res_asm ) \
                { \
                    ok = 0; \
                    fprintf( stderr, #name "[%d]: %d != %d [FAILED]\n", i, res_c, res_asm ); \
                    break; \
                } \
            } \
            for( int j = 0; j < 0x1000 && ok; j += 256 ) \
            { \
                res_c   = pixel_c  .name[i]( pbuf3+j, 16, pbuf4+j, 16 ); \
                res_asm = pixel_asm.name[i]( pbuf3+j, 16, pbuf4+j, 16 ); \
                if( res_c != res_asm ) \
                { \
                    ok = 0; \
                    fprintf( stderr, #name "[%d]: overflow %d != %d\n", i, res_c, res_asm ); \
                } \
            } \
        } \
    } \
    report( "pixel " #name " :" );

    TEST_PIXEL( sad, 0 );
    TEST_PIXEL( sad_aligned, 1 );
    TEST_PIXEL( ssd, 1 );
    TEST_PIXEL( satd, 0 );

#define TEST_PIXEL_AVG2( name, cmp ) \
    ok = 1, used_asm = 0; \
    for( int i = 0; i < ARRAY_ELEMS(pixel_asm.name); i++ ) \
    { \
        if( pixel_asm.name[i] && pixel_asm.name[i] != pixel_ref.name[i] ) \
        { \
            int w = x264_pixel_size[i].w, hgt = x264_pixel_size[i].h; \
            ALIGNED_16( pixel avg[16*16] ); \
            int res_c, res_asm; \
            set_func_name( "%s_%s", #name, pixel_names[i] ); \
            used_asm = 1; \
            for( int j = 0; j < 64 && ok; j++ ) \
            { \
                pixel *src1 = pbuf2 + j; \
                pixel *src2 = pbuf2 + 1280 + (j^5); \
                for( int y = 0; y < hgt; y++ ) \
                    for( int x = 0; x < w; x++ ) \
                        avg[y*16+x] = (src1[y*64+x] + src2[y*64+x] + 1) >> 1; \
                res_c   = pixel_c.cmp[i]( pbuf1, FENC_STRIDE, avg, 16 ); \
                res_asm = call_a( pixel_asm.name[i], pbuf1, src1, src2, (intptr_t)64 ); \
                if( res_c != res_asm ) \
                { \
                    ok = 0; \
                    fprintf( stderr, #name "[%d]: %d != %d [FAILED]\n", i, res_c, res_asm ); \
                } \
            } \
            for( int j = 0; j < 0x1000 && ok; j += 256 ) \
            { \
                res_c   = pixel_c.cmp[i]( pbuf3+j, 16, pbuf4+j, 16 ); \
                res_asm = pixel_asm.name[i]( pbuf3+j, pbuf4+j, pbuf4+j, 16 ); \
                if( res_c != res_asm ) \
                { \
                    ok = 0; \
                    fprintf( stderr, #name "[%d]: overflow %d != %d\n", i, res_c, res_asm ); \
                } \
            } \
        } \
    } \
    report( "pixel " #name " :" );

    TEST_PIXEL_AVG2( satd_avg2, satd );
    TEST_PIXEL_AVG2( sad_avg2, sad );

    ok = 1, used_asm = 0;
    if( pixel_asm.satd_mcc && pixel_asm.satd_mcc != pixel_ref.satd_mcc )
    {
        /* width, height, satd size of the u and v blocks */
        static const int mcc_sizes[6][3] = { {8, 16, PIXEL_8x16}, {8, 8, PIXEL_8x8}, {8, 4, PIXEL_8x4},
                                             {4, 16, PIXEL_4x16}, {4, 8, PIXEL_4x8}, {4, 4, PIXEL_4x4} };
        x264_mc_functions_t mc_c;
        x264_mc_init( 0, &mc_c, 0 );
        used_asm = 1;
#if !HIGH_BIT_DEPTH
        ALIGNED_ARRAY_32( int16_t, mcc_pre,[512] );
#endif
        for( int s = 0; s < 6; s++ )
        {
            int w = mcc_sizes[s][0], hgt = mcc_sizes[s][1], size = mcc_sizes[s][2];
            ALIGNED_16( pixel dstu[16*16] );
            ALIGNED_16( pixel dstv[16*16] );
            /* the reference satd takes fenc deinterleaved */
            ALIGNED_16( pixel fenc_c[16*FENC_STRIDE] );
            int res_c[2], res_asm[2];
            /* k = 0: random, every fraction pair, varied integer parts;
             * k = 1: dx = dy = 0, pbuf3 = ~pbuf4: every difference is +-PIXEL_MAX */
            for( int k = 0; k < 2; k++ )
                for( int j = 0; j < (k ? 0xc00 : 64) && ok; j += k ? 256 : 1 )
                {
                    int dx = k ? 0 : (j&7) | ((j*5)&24);
                    int dy = k ? 0 : (j>>3) | ((j*3+s)&24);
                    pixel *src = k ? pbuf4+j : pbuf2 + 64 + 2*j;
                    pixel *fenc = k ? pbuf3+j : pbuf1 + 2*(j&7);
                    intptr_t stride = k ? 16 : 64;
                    x264_mcc_fenc_t *fenc_mcc;
                    mc_c.mc_chroma( dstu, dstv, 16, src, stride, dx, dy, w, hgt );
#if HIGH_BIT_DEPTH
                    /* fenc is interleaved uv with the stride of src */
                    int x = 0, y = 0;
                    mc_c.load_deinterleave_chroma_fenc( fenc_c, fenc, stride, hgt );
                    fenc_mcc = fenc;
#else
                    /* satd_mcc_fenc_pre of an mb's chroma fenc 8 or 16 high, the block at x, y;
                     * 4x4 only at height 8 (4:2:0) */
                    int ch = hgt == 4 ? 8 : k || hgt == 16 || (j&1) ? 16 : 8;
                    int x = w == 4 ? 4*((j>>1)&1) : 0;
                    int y = hgt * ((j>>2) % (ch/hgt));
                    mc_c.load_deinterleave_chroma_fenc( fenc_c, fenc, stride, ch );
                    set_func_name( "satd_mcc_fenc_pre" );
                    call_a( pixel_asm.satd_mcc_fenc_pre, mcc_pre, fenc_c, ch );
                    for( int yy = 0; yy < ch && ok; yy++ )
                        for( int xx = 0; xx < 16; xx++ )
                        {
                            int e = 64*fenc_c[yy*FENC_STRIDE + (xx&1)*8 + (xx>>1)] - 32;
                            if( mcc_pre[16*yy+xx] != e ||
                                mcc_pre[256 + 128*(xx>>3) + 64*(yy>>3) + 16*(yy&3) + 8*((yy>>2)&1) + (xx&7)] != e ||
                                (ch == 8 && mcc_pre[128 + 32*(xx>>3) + 64*((yy>>2)&1) + 8*((yy>>1)&1) + 16*(yy&1) + (xx&7)] != e) )
                            {
                                ok = 0;
                                fprintf( stderr, "satd_mcc_fenc_pre height %d: row %d word %d [FAILED]\n", ch, yy, xx );
                                break;
                            }
                        }
                    fenc_mcc = mcc_pre + (w == 8 ? 16*y : hgt == 4 ? 128 + 8*x + 16*y : 256 + 32*x + 8*y);
#endif
                    res_c[0] = pixel_c.satd[size]( fenc_c+x+y*FENC_STRIDE,   FENC_STRIDE, dstu, 16 );
                    res_c[1] = pixel_c.satd[size]( fenc_c+8+x+y*FENC_STRIDE, FENC_STRIDE, dstv, 16 );
                    res_asm[0] = res_asm[1] = -1;
                    set_func_name( "satd_mcc" );
                    call_a( pixel_asm.satd_mcc, fenc_mcc, res_asm, src, stride, dx, dy, w, hgt );
                    if( res_c[0] != res_asm[0] || res_c[1] != res_asm[1] )
                    {
                        ok = 0;
                        fprintf( stderr, "satd_mcc %dx%d at %d,%d dx %d dy %d%s: %d,%d != %d,%d [FAILED]\n",
                                 w, hgt, x, y, dx, dy, k ? " overflow" : "", res_c[0], res_c[1], res_asm[0], res_asm[1] );
                    }
                }
        }
    }
    report( "pixel satd_mcc :" );

    ok = 1, used_asm = 0;
    if( pixel_asm.satd_pre[PIXEL_16x16] && pixel_asm.satd_pre[PIXEL_16x16] != pixel_ref.satd_pre[PIXEL_16x16] )
    {
        /* size, x, y of every partition of a 16x16 fenc */
        static const uint8_t pre_parts[9][3] = { {PIXEL_16x16, 0, 0}, {PIXEL_16x8, 0, 0}, {PIXEL_16x8, 0, 8},
                                                 {PIXEL_8x16, 0, 0}, {PIXEL_8x16, 8, 0}, {PIXEL_8x8, 0, 0},
                                                 {PIXEL_8x8, 8, 0}, {PIXEL_8x8, 0, 8}, {PIXEL_8x8, 8, 8} };
        ALIGNED_ARRAY_32( int16_t, fenc_pre,[512] );
        ALIGNED_16( pixel avg[16*16] );
        used_asm = 1;
        /* k = 0: random, k = 1: maxed differences (pbuf3 = ~pbuf4) */
        for( int k = 0; k < 2 && ok; k++ )
            for( int j = 0; j < (k ? 0x1000 : 64) && ok; j += k ? 256 : 1 )
            {
                pixel *fenc = k ? pbuf3+j : pbuf1;
                pixel *src1 = k ? pbuf4+j : pbuf2+j;
                pixel *src2 = k ? pbuf4+j : pbuf2+1280+(j^5);
                intptr_t stride = k ? 16 : 64;
                set_func_name( "satd_fenc_pre_16x16" );
                call_a( pixel_asm.satd_fenc_pre[0], fenc_pre, fenc );
                set_func_name( "satd_fenc_pre_8x8" );
                for( int b = 0; b < 4; b++ )
                    call_a( pixel_asm.satd_fenc_pre[1], fenc_pre+256+64*b, fenc+8*(b>>1)+8*FENC_STRIDE*(b&1) );
                for( int p = 0; p < 9 && ok; p++ )
                {
                    int i = pre_parts[p][0], x = pre_parts[p][1], y = pre_parts[p][2];
                    int w = x264_pixel_size[i].w, hgt = x264_pixel_size[i].h;
                    int16_t *pre = i <= PIXEL_16x8 ? fenc_pre+16*y : fenc_pre+256+64*(2*(x>>3)+(y>>3));
                    pixel *f = fenc + x + y*FENC_STRIDE;
                    pixel *s1 = src1 + x + y*stride, *s2 = src2 + x + y*stride;
                    int res_c, res_asm;
                    set_func_name( "satd_pre_%s", pixel_names[i] );
                    res_c   = pixel_c.satd[i]( f, FENC_STRIDE, s1, stride );
                    res_asm = call_a( pixel_asm.satd_pre[i], pre, s1, stride );
                    if( res_c != res_asm )
                    {
                        ok = 0;
                        fprintf( stderr, "satd_pre[%d] %d,%d %s: %d != %d [FAILED]\n", i, x, y, k ? "overflow" : "random", res_c, res_asm );
                    }
                    for( int yy = 0; yy < hgt; yy++ )
                        for( int xx = 0; xx < w; xx++ )
                            avg[yy*16+xx] = (s1[yy*stride+xx] + s2[yy*stride+xx] + 1) >> 1;
                    set_func_name( "satd_avg2_pre_%s", pixel_names[i] );
                    res_c   = pixel_c.satd[i]( f, FENC_STRIDE, avg, 16 );
                    res_asm = call_a( pixel_asm.satd_avg2_pre[i], pre, s1, s2, stride );
                    if( res_c != res_asm )
                    {
                        ok = 0;
                        fprintf( stderr, "satd_avg2_pre[%d] %d,%d %s: %d != %d [FAILED]\n", i, x, y, k ? "overflow" : "random", res_c, res_asm );
                    }
                }
            }
    }
    report( "pixel satd_pre :" );

    ok = 1, used_asm = 0;
    if( pixel_asm.satd_bi[PIXEL_16x16] && pixel_asm.satd_bi[PIXEL_16x16] != pixel_ref.satd_bi[PIXEL_16x16] )
    {
        /* size, x, y of every partition of a 16x16 fenc */
        static const uint8_t bi_parts[9][3] = { {PIXEL_16x16, 0, 0}, {PIXEL_16x8, 0, 0}, {PIXEL_16x8, 0, 8},
                                                {PIXEL_8x16, 0, 0}, {PIXEL_8x16, 8, 0}, {PIXEL_8x8, 0, 0},
                                                {PIXEL_8x8, 8, 0}, {PIXEL_8x8, 0, 8}, {PIXEL_8x8, 8, 8} };
        static const int8_t bi_weights[9] = { 32, -63, -1, 0, 1, 63, 64, 65, 127 };
        x264_mc_functions_t mc_c;
        x264_mc_init( 0, &mc_c, 0 );
#if !HIGH_BIT_DEPTH
        ALIGNED_ARRAY_32( int16_t, fenc_pre,[512] );
#endif
        ALIGNED_16( pixel avg[16*16] );
        ALIGNED_16( pixel ref0[16*16] );
        ALIGNED_16( pixel ref1[16*16] );
        used_asm = 1;
        /* k = 0: random, every weight, every qpel fraction;
         * k = 1: src0 = src1 = ~fenc, maxed differences;
         * k = 2: src0 = ~src1 maxed, clipped at the extreme weights */
        for( int k = 0; k < 3 && ok; k++ )
            for( int j = 0; j < (k ? 0x1000 : 64) && ok; j += k ? 256 : 1 )
            {
                pixel *fenc = k == 1 ? pbuf3+j : k ? pbuf1+j : pbuf2+0xa00+j;
                /* satd_bi: src0 (stride0), src1 (stride1) */
                pixel *src0 = k ? pbuf4+j : pbuf2+j;
                pixel *src1 = k == 2 ? pbuf3+j : k ? pbuf4+j : pbuf2+1280+(j^5);
                intptr_t stride0 = k ? 16 : 64, stride1 = k ? 16 : 32;
                /* satd_bi4: hpel planes and mvs of the two lists, get_ref's sources */
                pixel *planes[2][4];
                intptr_t pstride = k ? 16 : 64;
                int mv[2][2];
                for( int q = 0; q < 4; q++ )
                {
                    planes[0][q] = k ? pbuf4+j : pbuf1+2*64+2+q*600+j;
                    planes[1][q] = k == 2 ? pbuf3+j : k ? pbuf4+j : pbuf1+3400+q*600+(j^9);
                }
                if( k )
                {
                    /* fractions 0 or 1: get_ref averages identical planes */
                    mv[0][0] = (j>>8)&1;
                    mv[0][1] = (j>>9)&1;
                    mv[1][0] = (j>>10)&1;
                    mv[1][1] = (j>>11)&1;
                }
                else
                {
                    mv[0][0] = 4*(j%3-1) + (j&3);
                    mv[0][1] = 4*(j/3%3-1) + ((j>>2)&3);
                    mv[1][0] = 4*(j/9%3-1) + ((j>>4)&3);
                    mv[1][1] = 4*(j/27%3-1) + (((j>>1)^j)&3);
                }
#if !HIGH_BIT_DEPTH
                set_func_name( "satd_fenc_pre_16x16" );
                call_a( pixel_asm.satd_fenc_pre[0], fenc_pre, fenc );
                set_func_name( "satd_fenc_pre_8x8" );
                for( int b = 0; b < 4; b++ )
                    call_a( pixel_asm.satd_fenc_pre[1], fenc_pre+256+64*b, fenc+8*(b>>1)+8*FENC_STRIDE*(b&1) );
#endif
                for( int p = 0; p < 9 && ok; p++ )
                {
                    int i = bi_parts[p][0], x = bi_parts[p][1], y = bi_parts[p][2];
                    int w = x264_pixel_size[i].w, hgt = x264_pixel_size[i].h;
                    pixel *f = fenc + x + y*FENC_STRIDE;
#if HIGH_BIT_DEPTH
                    x264_bi_fenc_t *bf = f;
#else
                    x264_bi_fenc_t *bf = i <= PIXEL_16x8 ? fenc_pre+16*y : fenc_pre+256+64*(2*(x>>3)+(y>>3));
#endif
                    pixel *s0 = src0 + x + y*stride0, *s1 = src1 + x + y*stride1;
                    pixel *pl[2][4], *hp[2][2], *r[2];
                    intptr_t rstride[2] = { 16, 16 };
                    for( int l = 0; l < 2; l++ )
                    {
                        for( int q = 0; q < 4; q++ )
                            pl[l][q] = planes[l][q] + x + y*pstride;
                        r[l] = mc_c.get_ref( l ? ref1 : ref0, &rstride[l], pl[l], pstride, mv[l][0], mv[l][1], w, hgt, x264_weight_none );
                        x264_mc_hpel_pair( hp[l], pl[l], pstride, mv[l][0], mv[l][1] );
                    }
                    for( int wi = 0; wi < (k ? 9 : 191) && ok; wi++ )
                    {
                        int weight = k ? bi_weights[wi] : wi - 63;
                        int bench = weight == 32 || weight == 65;
                        int res_c, res_asm;
                        mc_c.avg[i]( avg, 16, s0, stride0, s1, stride1, weight );
                        res_c = pixel_c.satd[i]( f, FENC_STRIDE, avg, 16 );
                        if( bench )
                        {
                            set_func_name( "satd_bi%s_%s", weight == 32 ? "" : "w", pixel_names[i] );
                            res_asm = call_a( pixel_asm.satd_bi[i], bf, s0, stride0, s1, stride1, weight );
                        }
                        else
                            res_asm = pixel_asm.satd_bi[i]( bf, s0, stride0, s1, stride1, weight );
                        if( res_c != res_asm )
                        {
                            ok = 0;
                            fprintf( stderr, "satd_bi[%d] %d,%d weight %d k %d: %d != %d [FAILED]\n", i, x, y, weight, k, res_c, res_asm );
                        }
                        mc_c.avg[i]( avg, 16, r[0], rstride[0], r[1], rstride[1], weight );
                        res_c = pixel_c.satd[i]( f, FENC_STRIDE, avg, 16 );
                        if( bench )
                        {
                            set_func_name( "satd_bi4%s_%s", weight == 32 ? "" : "w", pixel_names[i] );
                            res_asm = call_a( pixel_asm.satd_bi4[i], bf, hp[0][0], hp[0][1], hp[1][0], hp[1][1], pstride, weight );
                        }
                        else
                            res_asm = pixel_asm.satd_bi4[i]( bf, hp[0][0], hp[0][1], hp[1][0], hp[1][1], pstride, weight );
                        if( res_c != res_asm )
                        {
                            ok = 0;
                            fprintf( stderr, "satd_bi4[%d] %d,%d mv %d,%d %d,%d weight %d k %d: %d != %d [FAILED]\n", i, x, y,
                                     mv[0][0], mv[0][1], mv[1][0], mv[1][1], weight, k, res_c, res_asm );
                        }
                    }
                }
            }
    }
    report( "pixel satd_bi :" );

    TEST_PIXEL( sa8d, 1 );

    ok = 1, used_asm = 0;
    if( pixel_asm.sa8d_satd[PIXEL_16x16] != pixel_ref.sa8d_satd[PIXEL_16x16] )
    {
        set_func_name( "sa8d_satd_%s", pixel_names[PIXEL_16x16] );
        used_asm = 1;
        for( int j = 0; j < 64; j++ )
        {
            uint32_t cost8_c = pixel_c.sa8d[PIXEL_16x16]( pbuf1, 16, pbuf2+16*j, 64 );
            uint32_t cost4_c = pixel_c.satd[PIXEL_16x16]( pbuf1, 16, pbuf2+16*j, 64 );
            uint64_t res_a = call_a( pixel_asm.sa8d_satd[PIXEL_16x16], pbuf1, (intptr_t)16, pbuf2+16*j, (intptr_t)64 );
            uint32_t cost8_a = res_a;
            uint32_t cost4_a = res_a >> 32;
            if( cost8_a != cost8_c || cost4_a != cost4_c )
            {
                ok = 0;
                fprintf( stderr, "sa8d_satd [%d]: (%d,%d) != (%d,%d) [FAILED]\n", PIXEL_16x16,
                         cost8_c, cost4_c, cost8_a, cost4_a );
                break;
            }
        }
        for( int j = 0; j < 0x1000 && ok; j += 256 ) \
        {
            uint32_t cost8_c = pixel_c.sa8d[PIXEL_16x16]( pbuf3+j, 16, pbuf4+j, 16 );
            uint32_t cost4_c = pixel_c.satd[PIXEL_16x16]( pbuf3+j, 16, pbuf4+j, 16 );
            uint64_t res_a = pixel_asm.sa8d_satd[PIXEL_16x16]( pbuf3+j, 16, pbuf4+j, 16 );
            uint32_t cost8_a = res_a;
            uint32_t cost4_a = res_a >> 32;
            if( cost8_a != cost8_c || cost4_a != cost4_c )
            {
                ok = 0;
                fprintf( stderr, "sa8d_satd [%d]: overflow (%d,%d) != (%d,%d) [FAILED]\n", PIXEL_16x16,
                         cost8_c, cost4_c, cost8_a, cost4_a );
            }
        }
    }
    report( "pixel sa8d_satd :" );

    // maxed differences negated on a coset of each 8x8 (3 of its 6 coordinate bits fixed), the same in
    // all four 8x8s of a 16x16: puts most of every 8x8's sa8d in one word, whatever the lane layout
    ok = 1, used_asm = 0;
    if( pixel_asm.sa8d[PIXEL_8x8] != pixel_ref.sa8d[PIXEL_8x8] ||
        pixel_asm.sa8d[PIXEL_16x16] != pixel_ref.sa8d[PIXEL_16x16] ||
        pixel_asm.sa8d_satd[PIXEL_16x16] != pixel_ref.sa8d_satd[PIXEL_16x16] )
    {
        static const int sa8d_sizes[2] = { PIXEL_16x16, PIXEL_8x8 };
        ALIGNED_ARRAY_64( pixel, pa,[16*16] );
        ALIGNED_ARRAY_64( pixel, pb,[16*16] );
        set_func_name( "sa8d_coset" );
        used_asm = 1;
        for( int m = 0; m < 64 && ok; m++ )
        {
            int bits = 0;
            for( int b = m; b; b &= b-1 )
                bits++;
            if( bits != 3 )
                continue;
            for( int t = 0; t < 64 && ok; t++ )
            {
                if( t & ~m )
                    continue;
                for( int inv = 0; inv < 2 && ok; inv++ )
                {
                    for( int i = 0; i < 256; i++ )
                    {
                        int k = (i>>4&7)<<3 | (i&7);
                        int neg = ((k & m) == t) ^ inv;
                        pa[i] = neg ? 0 : PIXEL_MAX;
                        pb[i] = neg ? PIXEL_MAX : 0;
                    }
                    for( int s = 0; s < 2; s++ )
                    {
                        int sz = sa8d_sizes[s];
                        if( pixel_asm.sa8d[sz] == pixel_ref.sa8d[sz] )
                            continue;
                        int res_c   = pixel_c.sa8d[sz]( pa, 16, pb, 16 );
                        int res_asm = pixel_asm.sa8d[sz]( pa, 16, pb, 16 );
                        if( res_c != res_asm )
                        {
                            ok = 0;
                            fprintf( stderr, "sa8d[%d]: coset %02o/%02o%s %d != %d [FAILED]\n",
                                     sz, m, t, inv ? " inverted" : "", res_c, res_asm );
                        }
                    }
                    if( pixel_asm.sa8d_satd[PIXEL_16x16] != pixel_ref.sa8d_satd[PIXEL_16x16] )
                    {
                        uint32_t cost8_c = pixel_c.sa8d[PIXEL_16x16]( pa, 16, pb, 16 );
                        uint32_t cost4_c = pixel_c.satd[PIXEL_16x16]( pa, 16, pb, 16 );
                        uint64_t res_a = pixel_asm.sa8d_satd[PIXEL_16x16]( pa, 16, pb, 16 );
                        uint32_t cost8_a = res_a;
                        uint32_t cost4_a = res_a >> 32;
                        if( cost8_a != cost8_c || cost4_a != cost4_c )
                        {
                            ok = 0;
                            fprintf( stderr, "sa8d_satd [%d]: coset %02o/%02o%s (%d,%d) != (%d,%d) [FAILED]\n",
                                     PIXEL_16x16, m, t, inv ? " inverted" : "", cost8_c, cost4_c, cost8_a, cost4_a );
                        }
                    }
                }
            }
        }
    }
    report( "pixel sa8d coset :" );

#define TEST_PIXEL_X( N ) \
    ok = 1; used_asm = 0; \
    for( int i = 0; i < 7; i++ ) \
    { \
        ALIGNED_16( int res_c[4] ) = {0}; \
        ALIGNED_16( int res_asm[4] ) = {0}; \
        if( pixel_asm.sad_x##N[i] && pixel_asm.sad_x##N[i] != pixel_ref.sad_x##N[i] ) \
        { \
            set_func_name( "sad_x%d_%s", N, pixel_names[i] ); \
            used_asm = 1; \
            for( int j = 0; j < 64; j++ ) \
            { \
                pixel *pix2 = pbuf2+j; \
                res_c[0] = pixel_c.sad[i]( pbuf1, 16, pix2,   64 ); \
                res_c[1] = pixel_c.sad[i]( pbuf1, 16, pix2+6, 64 ); \
                res_c[2] = pixel_c.sad[i]( pbuf1, 16, pix2+1, 64 ); \
                if( N == 4 ) \
                { \
                    res_c[3] = pixel_c.sad[i]( pbuf1, 16, pix2+10, 64 ); \
                    call_a( pixel_asm.sad_x4[i], pbuf1, pix2, pix2+6, pix2+1, pix2+10, (intptr_t)64, res_asm ); \
                } \
                else \
                    call_a( pixel_asm.sad_x3[i], pbuf1, pix2, pix2+6, pix2+1, (intptr_t)64, res_asm ); \
                if( memcmp(res_c, res_asm, N*sizeof(int)) ) \
                { \
                    ok = 0; \
                    fprintf( stderr, "sad_x"#N"[%d]: %d,%d,%d,%d != %d,%d,%d,%d [FAILED]\n", \
                             i, res_c[0], res_c[1], res_c[2], res_c[3], \
                             res_asm[0], res_asm[1], res_asm[2], res_asm[3] ); \
                } \
                if( N == 4 ) \
                    call_c2( pixel_c.sad_x4[i], pbuf1, pix2, pix2+6, pix2+1, pix2+10, (intptr_t)64, res_asm ); \
                else \
                    call_c2( pixel_c.sad_x3[i], pbuf1, pix2, pix2+6, pix2+1, (intptr_t)64, res_asm ); \
            } \
            /* candidate k at k*256 past the complement of fenc (pbuf3 = ~pbuf4): maxed differences in the first, \
             * every 256-pixel offset of the 4096 */ \
            for( int j = 0; j < 0x1000 && ok; j += 256 ) \
            { \
                pixel *pix[4]; \
                for( int k = 0; k < 4; k++ ) \
                { \
                    pix[k] = pbuf4 + ((j + 256*k) & 0xfff); \
                    res_c[k] = pixel_c.sad[i]( pbuf3+j, 16, pix[k], 16 ); \
                } \
                if( N == 4 ) \
                    pixel_asm.sad_x4[i]( pbuf3+j, pix[0], pix[1], pix[2], pix[3], (intptr_t)16, res_asm ); \
                else \
                    pixel_asm.sad_x3[i]( pbuf3+j, pix[0], pix[1], pix[2], (intptr_t)16, res_asm ); \
                if( memcmp(res_c, res_asm, N*sizeof(int)) ) \
                { \
                    ok = 0; \
                    fprintf( stderr, "sad_x"#N"[%d]: overflow %d,%d,%d,%d != %d,%d,%d,%d [FAILED]\n", \
                             i, res_c[0], res_c[1], res_c[2], res_c[3], \
                             res_asm[0], res_asm[1], res_asm[2], res_asm[3] ); \
                } \
            } \
        } \
    } \
    report( "pixel sad_x"#N" :" );

    TEST_PIXEL_X(3);
    TEST_PIXEL_X(4);

    /* against the sequential strict < selection over best then the candidates in order;
     * j>>6: 0 random costs, 1 equal costs (ties go by idx), 2 extreme mv costs and best,
     * 3 maximal sads */
#define TEST_PIXEL_X_MIN( N ) \
    ok = 1; used_asm = 0; \
    for( int i = 0; i < 7; i++ ) \
    { \
        if( pixel_asm.sad_x##N##_min[i] && pixel_asm.sad_x##N##_min[i] != pixel_ref.sad_x##N##_min[i] ) \
        { \
            static const int offs[4] = { 0, 6, 1, 10 }; \
            int wins[5] = {0}; \
            set_func_name( "sad_x%d_min_%s", N, pixel_names[i] ); \
            used_asm = 1; \
            for( int j = 0; j < 256 && ok; j++ ) \
            { \
                int mode = j>>6; \
                pixel *fenc = mode == 3 ? pbuf3 : pbuf1; \
                intptr_t stride = mode == 3 ? FENC_STRIDE : 64; \
                pixel *pix[4]; \
                int sad[4], bias[4], mvc[4], idx[4], best = 0, res_c, res_a; \
                int tmin = INT_MAX, tmax = 0; \
                for( int k = 0; k < 4; k++ ) \
                { \
                    pix[k] = mode == 3 ? pbuf4 : pbuf2 + (j&63) + offs[k]; \
                    sad[k] = pixel_c.sad[i]( fenc, FENC_STRIDE, pix[k], stride ); \
                    tmax = X264_MAX( tmax, sad[k] ); \
                    idx[k] = rand()&63; \
                    mvc[k] = rand()%131071; \
                } \
                if( mode == 1 ) \
                { \
                    int t = tmax + (rand()&7); \
                    for( int k = 0; k < 4; k++ ) \
                    { \
                        mvc[k] = t - sad[k]; \
                        idx[k] = 1 + ((k + j) & 3); \
                    } \
                    best = (t << 6) + (rand()%3 ? (int)(rand()&63) : 0); \
                } \
                else if( mode == 2 ) \
                { \
                    for( int k = 0; k < 4; k++ ) \
                    { \
                        mvc[k] = ((j>>k)&1) * 131070; \
                        idx[k] = ((j>>(k+2))&1) * 63; \
                    } \
                    best = (j&3) == 0 ? 0 : (j&3) == 1 ? (1<<30)-1 : ((sad[0] + mvc[0]) << 6) + idx[0]; \
                } \
                for( int k = 0; k < 4; k++ ) \
                { \
                    bias[k] = (mvc[k] << 6) + idx[k]; \
                    tmin = X264_MIN( tmin, sad[k] + mvc[k] ); \
                } \
                if( mode == 0 || mode == 3 ) \
                    best = (X264_MAX( tmin + (rand()&255) - 128, 0 ) << 6) + (rand()&63); \
                int win = 0; \
                res_c = best; \
                for( int k = 0; k < N; k++ ) \
                    if( (sad[k] << 6) + bias[k] < res_c ) \
                    { \
                        res_c = (sad[k] << 6) + bias[k]; \
                        win = k+1; \
                    } \
                wins[win]++; \
                if( N == 4 ) \
                    res_a = call_a( pixel_asm.sad_x4_min[i], fenc, pix[0], pix[1], pix[2], pix[3], stride, \
                                    (uint32_t)bias[0] | (uint64_t)(uint32_t)bias[1] << 32, \
                                    (uint32_t)bias[2] | (uint64_t)(uint32_t)bias[3] << 32, best ); \
                else \
                    res_a = call_a( pixel_asm.sad_x3_min[i], fenc, pix[0], pix[1], pix[2], stride, \
                                    (uint32_t)bias[0] | (uint64_t)(uint32_t)bias[1] << 32, \
                                    (uint32_t)bias[2] | (uint64_t)(uint32_t)best << 32 ); \
                if( res_c != res_a ) \
                { \
                    ok = 0; \
                    fprintf( stderr, "sad_x"#N"_min[%d]: mode %d %d != %d [FAILED]\n", i, mode, res_c, res_a ); \
                } \
            } \
            /* every lane of the reduction, and best, must have been the result */ \
            for( int k = 0; k <= N && ok; k++ ) \
                if( !wins[k] ) \
                { \
                    ok = 0; \
                    fprintf( stderr, "sad_x"#N"_min[%d]: %s %d never selected [FAILED]\n", i, k ? "candidate" : "best", k-1 ); \
                } \
        } \
    } \
    report( "pixel sad_x"#N"_min :" );

    TEST_PIXEL_X_MIN(3);
    TEST_PIXEL_X_MIN(4);

    /* j>>6: 0 random costs, 1 equal costs (ties go by idx), 2 extreme mv costs and best,
     * me.c's 1<<30 in unused slots, 3 a maximal sad (~fenc) in slot j%12, winning */
    ok = 1; used_asm = 0;
    for( int i = 0; i < 7; i++ )
    {
        if( pixel_asm.sad_sq_min[i] && pixel_asm.sad_sq_min[i] != pixel_ref.sad_sq_min[i] )
        {
            static const int dys[3] = { -1, 1, 0 };
            ALIGNED_16( pixel refm[20*48] );
            int wins[13] = {0};
            set_func_name( "sad_sq_min_%s", pixel_names[i] );
            used_asm = 1;
            for( int j = 0; j < 256 && ok; j++ )
            {
                int mode = j>>6;
                pixel *fenc = mode == 3 ? pbuf3 : pbuf1;
                intptr_t stride = mode == 3 ? 48 : (j&1) ? 64 : 40 + (j&15);
                pixel *pix = mode == 3 ? refm + 2*48 + 2 : pbuf2 + (j&31) + stride + 1;
                ALIGNED_16( int32_t bias[12] );
                int sad[12], best, tmin = INT_MAX, tmax = 0, res_c, res_a, win = 0;
                if( mode == 3 )
                {
                    int k = j%12;
                    for( int l = 0; l < 20*48; l++ )
                        refm[l] = rand() & PIXEL_MAX;
                    for( int y = 0; y < 16; y++ )
                        memcpy( pix + (k&3) - 1 + (dys[k>>2] + y)*stride, pbuf4 + 16*y, 16*sizeof(pixel) );
                }
                for( int k = 0; k < 12; k++ )
                {
                    sad[k] = pixel_c.sad[i]( fenc, FENC_STRIDE, pix + (k&3) - 1 + dys[k>>2]*stride, stride );
                    tmax = X264_MAX( tmax, sad[k] );
                }
                for( int k = 0; k < 12; k++ )
                {
                    if( mode == 1 )
                        bias[k] = ((tmax - sad[k]) << 6) + 1 + (k + j) % 12;
                    else if( mode == 2 )
                        bias[k] = (j&4) && (k&3) == 3 ? 1 << 30
                                : ((((j>>(k%6))&1) * 131070) << 6) + ((j>>(k%5))&1) * 63;
                    else if( mode == 3 )
                        bias[k] = k == j%12 ? rand()&63 : 1 << 24;
                    else
                        bias[k] = ((rand()%4096) << 6) + (rand()&63);
                    tmin = X264_MIN( tmin, (sad[k] << 6) + bias[k] );
                }
                if( mode == 1 )
                    best = (tmax << 6) + (rand()%3 ? (int)(rand()&63) : 0);
                else if( mode == 2 )
                    best = (j&3) == 0 ? 0 : (j&3) == 1 ? INT_MAX : tmin;
                else if( mode == 3 )
                    best = INT_MAX;
                else
                    best = tmin + ((rand()&255) - 128) * 64 + (rand()&63);
                res_c = best;
                for( int k = 0; k < 12; k++ )
                    if( (sad[k] << 6) + bias[k] < res_c )
                    {
                        res_c = (sad[k] << 6) + bias[k];
                        win = k+1;
                    }
                wins[win]++;
                if( x264_pixel_sad_sq_min_c( i, fenc, pix, stride, bias, best ) != res_c )
                {
                    ok = 0;
                    fprintf( stderr, "sad_sq_min[%d]: C reference mismatch [FAILED]\n", i );
                }
                res_a = call_a( pixel_asm.sad_sq_min[i], fenc, pix, stride, bias, best );
                if( res_c != res_a )
                {
                    ok = 0;
                    fprintf( stderr, "sad_sq_min[%d]: mode %d %d != %d [FAILED]\n", i, mode, res_c, res_a );
                }
            }
            /* every slot, and best, must have been the result */
            for( int k = 0; k <= 12 && ok; k++ )
                if( !wins[k] )
                {
                    ok = 0;
                    fprintf( stderr, "sad_sq_min[%d]: %s %d never selected [FAILED]\n", i, k ? "slot" : "best", k-1 );
                }
        }
    }
    report( "pixel sad_sq_min :" );

    /* dia, oct, ring (s 4), hex (s 6). j>>7: 0 random costs, 1 equal costs (ties go by idx),
     * 2 extreme mv costs and best, 3 a maximal sad (~fenc) in slot j%n, winning */
    ok = 1; used_asm = 0;
    for( int kind = 0; kind < 4; kind++ )
        for( int i = 0; i < 7; i++ )
        {
            static const int8_t dia_pt[4][2] = {{0,-1}, {0,1}, {-1,0}, {1,0}};
            static const int8_t hex_pt[6][2] = {{-2,0}, {-1,2}, {1,2}, {2,0}, {1,-2}, {-1,-2}};
            static const int8_t oct_pt[8][2] = {{0,-2}, {-1,-1}, {1,-1}, {-2,0}, {2,0}, {-1,1}, {1,1}, {0,2}};
            static const int8_t ring_pt[8][2] = {{-1,-2}, {1,-2}, {-2,-1}, {2,-1}, {-2,1}, {2,1}, {-1,2}, {1,2}};
            static const char *kind_names[4] = { "dia", "hex", "oct", "ring" };
            static int (* const pt_c[4])( int, pixel *, pixel *, intptr_t, const int32_t *, int ) =
            {
                x264_pixel_sad_dia_min_c, x264_pixel_sad_hex_min_c, x264_pixel_sad_oct_min_c, x264_pixel_sad_ring_min_c
            };
            x264_pixel_cmp_pt_min_t pt_asm = (kind == 0 ? pixel_asm.sad_dia_min : kind == 1 ? pixel_asm.sad_hex_min
                                            : kind == 2 ? pixel_asm.sad_oct_min : pixel_asm.sad_ring_min)[i];
            x264_pixel_cmp_pt_min_t pt_ref = (kind == 0 ? pixel_ref.sad_dia_min : kind == 1 ? pixel_ref.sad_hex_min
                                            : kind == 2 ? pixel_ref.sad_oct_min : pixel_ref.sad_ring_min)[i];
            const int8_t (*pt)[2] = kind == 0 ? dia_pt : kind == 1 ? hex_pt : kind == 2 ? oct_pt : ring_pt;
            int n = kind == 0 ? 4 : kind == 1 ? 6 : 8;
            int s = kind == 1 ? 6 : 4;
            if( !pt_asm || pt_asm == pt_ref )
                continue;
            int bw = x264_pixel_size[i].w, bh = x264_pixel_size[i].h;
            ALIGNED_16( pixel refm[24*48] );
            int wins[9] = {0};
            set_func_name( "sad_%s_min_%s", kind_names[kind], pixel_names[i] );
            used_asm = 1;
            for( int j = 0; j < 512 && ok; j++ )
            {
                int mode = j>>7;
                pixel *fenc = mode == 3 ? pbuf3 : pbuf1;
                intptr_t stride = mode == 3 ? 48 : (j&1) ? 64 : 40 + (j&15);
                pixel *pix = mode == 3 ? refm + 4*48 + 8 : pbuf2 + (j&31) + 2*stride + 4;
                ALIGNED_16( int32_t bias[8] );
                int sad[8], best, tmin = INT_MAX, tmax = 0, res_c, res_a, win = 0;
                if( mode == 3 )
                {
                    int k = j%n;
                    for( int l = 0; l < 24*48; l++ )
                        refm[l] = rand() & PIXEL_MAX;
                    for( int y = 0; y < bh; y++ )
                        memcpy( pix + pt[k][0] + (pt[k][1] + y)*stride, pbuf4 + 16*y, bw*sizeof(pixel) );
                }
                for( int k = 0; k < n; k++ )
                {
                    sad[k] = pixel_c.sad[i]( fenc, FENC_STRIDE, pix + pt[k][0] + pt[k][1]*stride, stride );
                    tmax = X264_MAX( tmax, sad[k] );
                }
                for( int k = 0; k < n; k++ )
                {
                    if( mode == 1 )
                        bias[k] = ((tmax - sad[k]) << s) + 1 + (k + j) % n;
                    else if( mode == 2 )
                        bias[k] = ((((j>>(k%5))&1) * 131070) << s) + ((j>>(k%4))&1) * ((1<<s)-1);
                    else if( mode == 3 )
                        bias[k] = k == j%n ? rand()&((1<<s)-1) : 1 << 24;
                    else
                        bias[k] = ((rand()%4096) << s) + (rand()&((1<<s)-1));
                    tmin = X264_MIN( tmin, (sad[k] << s) + bias[k] );
                }
                if( mode == 1 )
                    best = (tmax << s) + (rand()%3 ? (int)(rand()&((1<<s)-1)) : 0);
                else if( mode == 2 )
                    best = (j&3) == 0 ? 0 : (j&3) == 1 ? INT_MAX : tmin;
                else if( mode == 3 )
                    best = INT_MAX;
                else
                    best = tmin + ((rand()&255) - 128) * (1<<s) + (rand()&((1<<s)-1));
                res_c = best;
                for( int k = 0; k < n; k++ )
                    if( (sad[k] << s) + bias[k] < res_c )
                    {
                        res_c = (sad[k] << s) + bias[k];
                        win = k+1;
                    }
                wins[win]++;
                int res_r = pt_c[kind]( i, fenc, pix, stride, bias, best );
                if( res_r != res_c )
                {
                    ok = 0;
                    fprintf( stderr, "sad_%s_min[%d]: C reference mismatch [FAILED]\n", kind_names[kind], i );
                }
                res_a = call_a( pt_asm, fenc, pix, stride, bias, best );
                if( res_c != res_a )
                {
                    ok = 0;
                    fprintf( stderr, "sad_%s_min[%d]: mode %d %d != %d [FAILED]\n", kind_names[kind], i, mode, res_c, res_a );
                }
            }
            /* every slot, and best, must have been the result */
            for( int k = 0; k <= n && ok; k++ )
                if( !wins[k] )
                {
                    ok = 0;
                    fprintf( stderr, "sad_%s_min[%d]: %s %d never selected [FAILED]\n", kind_names[kind], i, k ? "slot" : "best", k-1 );
                }
        }
    report( "pixel sad_pt_min :" );

    /* j>>6: 0 random costs, 1 equal costs (ties go by idx), 2 extreme mv costs and best,
     * 3 a maximal sad (~fenc) in slot j&3, winning */
    ok = 1; used_asm = 0;
    for( int i = 0; i < 7; i++ )
    {
        if( pixel_asm.sad_hpel_min[i] && pixel_asm.sad_hpel_min[i] != pixel_ref.sad_hpel_min[i] )
        {
            ALIGNED_16( pixel refm[40*48] );
            int wins[5] = {0};
            set_func_name( "sad_hpel_min_%s", pixel_names[i] );
            used_asm = 1;
            for( int j = 0; j < 256 && ok; j++ )
            {
                int mode = j>>6;
                pixel *fenc = mode == 3 ? pbuf3 : pbuf1;
                intptr_t stride = mode == 3 ? 48 : (j&1) ? 64 : 40 + (j&15);
                pixel *pixv = mode == 3 ? refm + 1 : pbuf2 + (j&31) + 1;
                pixel *pixh = mode == 3 ? refm + 19*48 + 2 : pbuf2 + 18*stride + ((j*7)&31);
                pixel *pix[4];
                int sad[4], bias[4], best, tmin = INT_MAX, tmax = 0, res_c, res_a, win = 0;
                pix[0] = pixv;
                pix[1] = pixv + stride;
                pix[2] = pixh;
                pix[3] = pixh + 1;
                if( mode == 3 )
                {
                    int k = j&3;
                    for( int l = 0; l < 40*48; l++ )
                        refm[l] = rand() & PIXEL_MAX;
                    for( int y = 0; y < 16; y++ )
                        memcpy( pix[k] + y*stride, pbuf4 + 16*y, 16*sizeof(pixel) );
                }
                for( int k = 0; k < 4; k++ )
                {
                    sad[k] = pixel_c.sad[i]( fenc, FENC_STRIDE, pix[k], stride );
                    tmax = X264_MAX( tmax, sad[k] );
                }
                for( int k = 0; k < 4; k++ )
                {
                    if( mode == 1 )
                        bias[k] = ((tmax - sad[k]) << 6) + 1 + ((k + j) & 3);
                    else if( mode == 2 )
                        bias[k] = ((((j>>k)&1) * 131070) << 6) + ((j>>(k+2))&1) * 63;
                    else if( mode == 3 )
                        bias[k] = k == (j&3) ? rand()&63 : 1 << 24;
                    else
                        bias[k] = ((rand()%4096) << 6) + (rand()&63);
                    tmin = X264_MIN( tmin, (sad[k] << 6) + bias[k] );
                }
                if( mode == 1 )
                    best = (tmax << 6) + (rand()%3 ? (int)(rand()&63) : 0);
                else if( mode == 2 )
                    best = (j&3) == 0 ? 0 : (j&3) == 1 ? INT_MAX : tmin;
                else if( mode == 3 )
                    best = INT_MAX;
                else
                    best = tmin + ((rand()&255) - 128) * 64 + (rand()&63);
                uint64_t bias01 = (uint32_t)bias[0] | (uint64_t)(uint32_t)bias[1] << 32;
                uint64_t bias23 = (uint32_t)bias[2] | (uint64_t)(uint32_t)bias[3] << 32;
                res_c = best;
                for( int k = 0; k < 4; k++ )
                    if( (sad[k] << 6) + bias[k] < res_c )
                    {
                        res_c = (sad[k] << 6) + bias[k];
                        win = k+1;
                    }
                wins[win]++;
                if( x264_pixel_sad_hpel_min_c( i, fenc, pixv, pixh, stride, bias01, bias23, best ) != res_c )
                {
                    ok = 0;
                    fprintf( stderr, "sad_hpel_min[%d]: C reference mismatch [FAILED]\n", i );
                }
                res_a = call_a( pixel_asm.sad_hpel_min[i], fenc, pixv, pixh, stride, bias01, bias23, best );
                if( res_c != res_a )
                {
                    ok = 0;
                    fprintf( stderr, "sad_hpel_min[%d]: mode %d %d != %d [FAILED]\n", i, mode, res_c, res_a );
                }
            }
            /* every slot, and best, must have been the result */
            for( int k = 0; k <= 4 && ok; k++ )
                if( !wins[k] )
                {
                    ok = 0;
                    fprintf( stderr, "sad_hpel_min[%d]: %s %d never selected [FAILED]\n", i, k ? "slot" : "best", k-1 );
                }
        }
    }
    report( "pixel sad_hpel_min :" );

    /* in fenc_buf/fdec_buf layouts at the luma, 4:2:0/4:2:2 u and v, and 4:4:4 offsets,
     * pixels outside the block different: equal, then one pixel changed at every
     * position (by 1, or to 0/PIXEL_MAX), then pixels outside the block changed */
    ok = 1; used_asm = 0;
    for( int i = 0; i < 7; i++ )
    {
        if( pixel_asm.fenc_eq[i] && pixel_asm.fenc_eq[i] != pixel_ref.fenc_eq[i] )
        {
            static const int fenc_off[4] = { 0, 16*FENC_STRIDE, 16*FENC_STRIDE+8, 32*FENC_STRIDE };
            static const int fdec_off[4] = { 2*FDEC_STRIDE, 20*FDEC_STRIDE, 20*FDEC_STRIDE+16, 38*FDEC_STRIDE };
            ALIGNED_64( pixel fenc_b[48*FENC_STRIDE] );
            ALIGNED_64( pixel fdec_b[54*FDEC_STRIDE] );
            int w = x264_pixel_size[i].w, bh = x264_pixel_size[i].h;
            set_func_name( "fenc_eq_%s", pixel_names[i] );
            used_asm = 1;
            for( int o = 0; o < 4 && ok; o++ )
            {
                if( (w == 16) != (o == 0 || o == 3) )
                    continue;
                pixel *fenc = fenc_b + fenc_off[o];
                pixel *fdec = fdec_b + fdec_off[o];
                for( int j = 0; j < 2*w*bh + 64 && ok; j++ )
                {
                    for( int l = 0; l < 48*FENC_STRIDE; l++ )
                        fenc_b[l] = rand() & PIXEL_MAX;
                    for( int l = 0; l < 54*FDEC_STRIDE; l++ )
                        fdec_b[l] = rand() & PIXEL_MAX;
                    if( j&1 )
                        for( int y = 0; y < bh; y++ )
                            for( int x = 0; x < w; x++ )
                                fenc[x+y*FENC_STRIDE] = (j&2) ? PIXEL_MAX : 0;
                    for( int y = 0; y < bh; y++ )
                        memcpy( fdec + y*FDEC_STRIDE, fenc + y*FENC_STRIDE, w*sizeof(pixel) );
                    if( j < 2*w*bh )
                    {
                        /* pixel j>>1 of the block */
                        pixel *p = fdec + ((j>>1)%w) + ((j>>1)/w)*FDEC_STRIDE;
                        *p = (j&1) ? PIXEL_MAX - *p : (*p + 1) & PIXEL_MAX;
                    }
                    else
                    {
                        /* outside the block: the rest of a row, a row below (4:4:4 v: above),
                         * a column left */
                        int k = j - 2*w*bh;
                        int yo = o == 3 ? -1 : bh;
                        fdec[w + (k&15) + (k%bh)*FDEC_STRIDE] ^= 1;
                        if( w == 8 )
                            fenc[w + (k&7) + (k%bh)*FENC_STRIDE] ^= 1;
                        else
                            fenc[(k&15) + yo*FENC_STRIDE] ^= 1;
                        fdec[(k&7) + yo*FDEC_STRIDE] ^= 1;
                        fdec[-1 + (k%bh)*FDEC_STRIDE] ^= 1;
                    }
                    int res_c = x264_pixel_fenc_eq_c( i, fenc, fdec );
                    if( res_c != (j >= 2*w*bh) )
                    {
                        ok = 0;
                        fprintf( stderr, "fenc_eq[%d]: C reference %d at %d [FAILED]\n", i, res_c, j );
                    }
                    int res_a = call_a1( pixel_asm.fenc_eq[i], fenc, fdec );
                    if( res_c != res_a )
                    {
                        ok = 0;
                        fprintf( stderr, "fenc_eq[%d]: offset %d case %d %d != %d [FAILED]\n", i, o, j, res_c, res_a );
                    }
                }
                /* bench: equal (every row read), and the first row different */
                for( int y = 0; y < bh; y++ )
                    memcpy( fdec + y*FDEC_STRIDE, fenc + y*FENC_STRIDE, w*sizeof(pixel) );
                set_func_name( "fenc_eq_%s_same", pixel_names[i] );
                call_a2( pixel_asm.fenc_eq[i], fenc, fdec );
                fdec[w-1] ^= 1;
                set_func_name( "fenc_eq_%s_diff", pixel_names[i] );
                call_a2( pixel_asm.fenc_eq[i], fenc, fdec );
                set_func_name( "fenc_eq_%s", pixel_names[i] );
            }
        }
    }
    report( "pixel fenc_eq :" );

    /* box8_mask. j>>7: 0 random; 1 box near fsum, small costs, thresh near the bounds, so
     * every point both passes and fails; 2 extremes: 0 or the maximal sums, costs and thresh */
    ok = 1; used_asm = 0;
    if( pixel_asm.box8_mask_16x16 != pixel_ref.box8_mask_16x16 )
    {
        ALIGNED_ARRAY_64( uint16_t, box,[13*64] );
        ALIGNED_16( uint16_t costx[24] );
        ALIGNED_16( uint16_t costy[24] );
        int fsum[4], pass[25] = {0}, fail[25] = {0};
        const int maxsum = 64*PIXEL_MAX;
        set_func_name( "box8_mask_16x16" );
        used_asm = 1;
        for( int j = 0; j < 384 && ok; j++ )
        {
            int mode = j>>7;
            intptr_t stride = (j&3) == 0 ? 16 : (j&3) == 1 ? 24 : (j&3) == 2 ? 40 : 64;
            int r = mode == 1 ? 1 + (rand() % 64) : 0;
            int thresh;
            for( int k = 0; k < 4; k++ )
                fsum[k] = mode == 2 ? (rand()&1) * maxsum : rand() % (maxsum+1);
            for( int k = 0; k < 13*64; k++ )
            {
                int q = ((k%stride) >= 8) + 2*((k/stride) >= 8);
                if( mode == 0 )
                    box[k] = rand() % (maxsum+1);
                else if( mode == 1 )
                    box[k] = x264_clip3( fsum[q] + rand() % (2*r+1) - r, 0, maxsum );
                else
                    box[k] = (rand()&1) * maxsum;
            }
            for( int k = 0; k < 24; k++ )
            {
                costx[k] = mode == 0 ? rand() >> (rand()&15) : mode == 1 ? rand() % (r+1) : (rand()&1) * 0xffff;
                costy[k] = mode == 0 ? rand() >> (rand()&15) : mode == 1 ? rand() % (r+1) : (rand()&1) * 0xffff;
            }
            if( mode == 0 )
                thresh = rand() & 0xffff;
            else if( mode == 1 )
                thresh = rand() % (6*r+1);
            else
                thresh = (j&4) ? rand() & 0xffff : (j&8) ? 0xffff : 0;
            uint64_t res_c = call_c1( pixel_c.box8_mask_16x16, box, stride, fsum, costx, costy, thresh );
            uint64_t res_a = call_a1( pixel_asm.box8_mask_16x16, box, stride, fsum, costx, costy, thresh );
            if( res_c != res_a )
            {
                ok = 0;
                fprintf( stderr, "box8_mask: mode %d stride %d %"PRIx64" != %"PRIx64" [FAILED]\n",
                         mode, (int)stride, res_c, res_a );
            }
            for( int k = 0; k < 25; k++ )
            {
                pass[k] += (res_c >> (8*(k/5) + k%5)) & 1;
                fail[k] += !((res_c >> (8*(k/5) + k%5)) & 1);
            }
            call_c2( pixel_c.box8_mask_16x16, box, stride, fsum, costx, costy, thresh );
            call_a2( pixel_asm.box8_mask_16x16, box, stride, fsum, costx, costy, thresh );
        }
        for( int k = 0; k < 25 && ok; k++ )
            if( !pass[k] || !fail[k] )
            {
                ok = 0;
                fprintf( stderr, "box8_mask: point %d never %s [FAILED]\n", k, pass[k] ? "fails" : "passes" );
            }
    }
    report( "pixel box8_mask :" );

#if !HIGH_BIT_DEPTH
    /* sad_dia_search, sad_hex_search: whole searches from a random start inside random mv limits
     * (0-40 each side), i_me_range 1-40, against the C reference and me.c's per-step path.
     * j&3: 0 smooth ref with fenc cut from it near the start (walks), 1 flat ref and fenc (sad 0,
     * the mv costs decide; ties), 2 noise, 3 extreme sads. (j>>2)&3 mv costs: x264's log2 shape,
     * zero (ties), random, 0/65535. Every exit, 4+ moves and every square idx (dia: dir) must occur */
    ok = 1; used_asm = 0;
    for( int hex = 0; hex < 2; hex++ )
        for( int i = 0; i < 7; i++ )
        {
            x264_pixel_fpel_search_t fn_asm = (hex ? pixel_asm.sad_hex_search : pixel_asm.sad_dia_search)[i];
            x264_pixel_fpel_search_t fn_ref = (hex ? pixel_ref.sad_hex_search : pixel_ref.sad_dia_search)[i];
            if( !fn_asm || fn_asm == fn_ref )
                continue;
            ALIGNED_16( static pixel planes[4][176*256] );
            ALIGNED_16( pixel fenc[16*FENC_STRIDE] );
            static uint16_t cost_tab[2][2*8192+1];
            int flat[4] = {0};
            int bw = x264_pixel_size[i].w, bh = x264_pixel_size[i].h;
            int st[16] = {0};
            set_func_name( "sad_%s_search_%s", hex ? "hex" : "dia", pixel_names[i] );
            used_asm = 1;
            for( int j = 0; j < 4096 && ok; j++ )
            {
                int mode = j&3, cmode = (j>>2)&3;
                intptr_t stride = 192 + (rand()&63);
                int xmin = -(rand()%41), xmax = rand()%41, ymin = -(rand()%41), ymax = rand()%41;
                if( j&16 )
                    xmin = -(rand()&3), xmax = rand()&3;
                if( j&32 )
                    ymin = -(rand()&3), ymax = rand()&3;
                int bmx = xmin + rand()%(xmax-xmin+1), bmy = ymin + rand()%(ymax-ymin+1);
                /* mv 0 at (96, 80): reads stay inside the plane. A new plane per mode every 64 */
                pixel *plane = planes[mode];
                pixel *ref = plane + 96 + 80*stride;
                if( !(j&60) )
                {
                    flat[mode] = rand() & PIXEL_MAX;
                    for( int k = 0; k < 176*256; k++ )
                        plane[k] = mode == 1 ? flat[mode] : mode == 3 ? ((rand()&7) ? 0 : PIXEL_MAX) : rand() & PIXEL_MAX;
                    for( int pass = 0; pass < 3*(mode == 0); pass++ )
                        for( int k = 0; k < 176*256 - 2*256; k++ )
                            plane[k] = (plane[k] + plane[k+1] + plane[k+256] + plane[k+257] + 2) >> 2;
                }
                if( mode == 0 )
                {
                    int tx = bmx + rand()%17 - 8, ty = bmy + rand()%17 - 8;
                    for( int y = 0; y < bh; y++ )
                        for( int x = 0; x < bw; x++ )
                            fenc[y*FENC_STRIDE+x] = x264_clip_pixel( ref[tx+x + (ty+y)*stride] + (rand()%5) - 2 );
                }
                else
                    for( int k = 0; k < 16*FENC_STRIDE; k++ )
                        fenc[k] = mode == 1 ? flat[mode] : mode == 2 ? rand() & PIXEL_MAX : (rand()&7) ? PIXEL_MAX : 0;
                int lambda = 1 + rand()%40;
                for( int t = 0; t < 2; t++ )
                    for( int k = -512; k <= 512; k++ ) /* the part read: |4*mv - mvp| < 400 */
                    {
                        int v = cmode == 0 ? (int)(lambda * (2*log2f( abs(k)+1 ) + 1) + .5f)
                              : cmode == 1 ? 0 : cmode == 2 ? rand()%4096 : (rand()&1) * 65535;
                        cost_tab[t][k+8192] = X264_MIN( v, 65535 );
                    }
                int mvpx = rand()%321 - 160, mvpy = rand()%321 - 160;
                const uint16_t *cmx = cost_tab[0] + 8192 - mvpx, *cmy = cost_tab[1] + 8192 - mvpy;
                uint32_t mv_min = (((uint32_t)-xmin)<<16) | (-ymin&0x7FFF);
                uint32_t mv_max = (((uint32_t)xmax<<16) | (ymax&0x7FFF)) | 0x8000;
                uint64_t range = mv_min | (uint64_t)mv_max << 32;
                int iters = (j&64) ? 1 + rand()%40 : 4 + rand()%13;
                int bcost = pixel_c.sad[i]( fenc, FENC_STRIDE, ref + bmx + bmy*stride, stride ) + cmx[bmx*4] + cmy[bmy*4];
                if( (j&0x380) == 0x380 )
                    bcost = rand()%3 ? 0 : rand()%(bcost+1);
                uint32_t bmv = pack16to32_mask( bmx, bmy );
                uint64_t res_m = fpel_search_model( hex, i, fenc, ref, stride, cmx, cmy, bmx, bmy, bcost, iters, mv_min, mv_max, st, pixel_c.sad_x3[i], pixel_c.sad_x4[i] );
                uint64_t res_c = (hex ? x264_pixel_sad_hex_search_c : x264_pixel_sad_dia_search_c)( i, fenc, ref, stride, cmx, cmy, bmv, bcost, iters, range );
                uint64_t res_a = call_a( fn_asm, fenc, ref, stride, cmx, cmy, bmv, bcost, iters, range );
                if( res_c != res_m )
                {
                    ok = 0;
                    fprintf( stderr, "sad_%s_search[%d]: C reference mismatch [FAILED]\n", hex ? "hex" : "dia", i );
                }
                if( res_c != res_a )
                {
                    ok = 0;
                    fprintf( stderr, "sad_%s_search[%d]: mode %d %d: %d (%d,%d) != %d (%d,%d) [FAILED]\n", hex ? "hex" : "dia", i, mode, cmode,
                             (int)(uint32_t)res_c, (int16_t)(res_c>>32), (int16_t)(res_c>>48),
                             (int)(uint32_t)res_a, (int16_t)(res_a>>32), (int16_t)(res_a>>48) );
                }
            }
            for( int k = 0; k < (hex ? 14 : 9) && ok; k++ )
                if( !st[k] && (hex || k != 1) )
                {
                    ok = 0;
                    fprintf( stderr, "sad_%s_search[%d]: case %d never occurred [FAILED]\n", hex ? "hex" : "dia", i, k );
                }
        }
    report( "pixel fpel_search :" );
#endif

    ALIGNED_16( pixel var_max[256] );
    ALIGNED_16( pixel var_zero[256] );
#define TEST_PIXEL_VAR( i ) \
    if( pixel_asm.var[i] != pixel_ref.var[i] ) \
    { \
        set_func_name( "%s_%s", "var", pixel_names[i] ); \
        used_asm = 1; \
        /* abi-check wrapper can't return uint64_t, so separate it from return value check */ \
        call_c1( pixel_c.var[i],   pbuf1,           16 ); \
        call_a1( pixel_asm.var[i], pbuf1, (intptr_t)16 ); \
        /* random, maxed differences, all PIXEL_MAX, all 0 */ \
        for( int j = 0; j < 5; j++ ) \
        { \
            pixel *pix = j == 0 ? pbuf1 : j == 1 ? pbuf3 : j == 2 ? pbuf4 : var_max; \
            for( int k = 0; k < 256; k++ ) \
                var_max[k] = j == 3 ? PIXEL_MAX : 0; \
            uint64_t res_c   = pixel_c.var[i]( pix, 16 ); \
            uint64_t res_asm = pixel_asm.var[i]( pix, 16 ); \
            if( res_c != res_asm ) \
            { \
                ok = 0; \
                fprintf( stderr, "var[%d] %d: %d %d != %d %d [FAILED]\n", i, j, (int)res_c, (int)(res_c>>32), (int)res_asm, (int)(res_asm>>32) ); \
            } \
        } \
        call_c2( pixel_c.var[i],   pbuf1, (intptr_t)16 ); \
        call_a2( pixel_asm.var[i], pbuf1, (intptr_t)16 ); \
    }

    ok = 1; used_asm = 0;
    TEST_PIXEL_VAR( PIXEL_16x16 );
    TEST_PIXEL_VAR( PIXEL_8x16 );
    TEST_PIXEL_VAR( PIXEL_8x8 );
    report( "pixel var :" );

#define TEST_PIXEL_VAR2( i ) \
    if( pixel_asm.var2[i] != pixel_ref.var2[i] ) \
    { \
        int res_c, res_asm, ssd_c, ssd_asm; \
        set_func_name( "%s_%s", "var2", pixel_names[i] ); \
        used_asm = 1; \
        res_c   = call_c( pixel_c.var2[i],   pbuf1, (intptr_t)16, pbuf2, (intptr_t)16, &ssd_c   ); \
        res_asm = call_a( pixel_asm.var2[i], pbuf1, (intptr_t)16, pbuf2, (intptr_t)16, &ssd_asm ); \
        if( res_c != res_asm || ssd_c != ssd_asm ) \
        { \
            ok = 0; \
            fprintf( stderr, "var2[%d]: %d != %d or %d != %d [FAILED]\n", i, res_c, res_asm, ssd_c, ssd_asm ); \
        } \
        /* maxed differences of both signs, and all +-PIXEL_MAX (the largest |sum|) */ \
        for( int j = 0; j < 4; j++ ) \
        { \
            for( int k = 0; k < 256; k++ ) \
            { \
                var_max[k] = PIXEL_MAX; \
                var_zero[k] = 0; \
            } \
            pixel *p1 = j == 0 ? pbuf3 : j == 1 ? pbuf4 : j == 2 ? var_max : var_zero; \
            pixel *p2 = j == 0 ? pbuf4 : j == 1 ? pbuf3 : j == 2 ? var_zero : var_max; \
            res_c   = pixel_c.var2[i]( p1, 16, p2, 16, &ssd_c ); \
            res_asm = pixel_asm.var2[i]( p1, 16, p2, 16, &ssd_asm ); \
            if( res_c != res_asm || ssd_c != ssd_asm ) \
            { \
                ok = 0; \
                fprintf( stderr, "var2[%d] %d: %d != %d or %d != %d [FAILED]\n", i, j, res_c, res_asm, ssd_c, ssd_asm ); \
            } \
        } \
    }

    ok = 1; used_asm = 0;
    TEST_PIXEL_VAR2( PIXEL_8x16 );
    TEST_PIXEL_VAR2( PIXEL_8x8 );
    report( "pixel var2 :" );

    ok = 1; used_asm = 0;
    for( int i = 0; i < 4; i++ )
        if( pixel_asm.hadamard_ac[i] != pixel_ref.hadamard_ac[i] )
        {
            set_func_name( "hadamard_ac_%s", pixel_names[i] );
            used_asm = 1;
            for( int j = 0; j < 32; j++ )
            {
                pixel *pix = (j&16 ? pbuf1 : pbuf3) + (j&15)*256;
                call_c1( pixel_c.hadamard_ac[i],   pbuf1, (intptr_t)16 );
                call_a1( pixel_asm.hadamard_ac[i], pbuf1, (intptr_t)16 );
                uint64_t rc = pixel_c.hadamard_ac[i]( pix, 16 );
                uint64_t ra = pixel_asm.hadamard_ac[i]( pix, 16 );
                if( rc != ra )
                {
                    ok = 0;
                    fprintf( stderr, "hadamard_ac[%d]: %d,%d != %d,%d\n", i, (int)rc, (int)(rc>>32), (int)ra, (int)(ra>>32) );
                    break;
                }
            }
            call_c2( pixel_c.hadamard_ac[i],   pbuf1, (intptr_t)16 );
            call_a2( pixel_asm.hadamard_ac[i], pbuf1, (intptr_t)16 );
        }
    report( "pixel hadamard_ac :" );

    ok = 1; used_asm = 0;
    for( int c = 0; c < 2; c++ )
        if( pixel_asm.ssd_psy_mb[c] && pixel_asm.ssd_psy_mb[c] != pixel_ref.ssd_psy_mb[c] )
        {
            /* reference: the C ssd and hadamard_ac of rdo.c's old path */
            int csize = c ? PIXEL_8x16 : PIXEL_8x8;
            /* the MB cache: fenc luma then u|v; fdec luma at row 2, u|v at row 20 */
            ALIGNED_ARRAY_64( pixel, fenc,[48*FENC_STRIDE] );
            ALIGNED_ARRAY_64( pixel, fdec,[54*FDEC_STRIDE] );
            pixel *fenc_uv = fenc + 16*FENC_STRIDE, *fdec_y = fdec + 2*FDEC_STRIDE, *fdec_uv = fdec + 20*FDEC_STRIDE;
            set_func_name( "ssd_psy_mb_%s", c ? "422" : "420" );
            used_asm = 1;
            /* k&3 = 0: random; 1: maxed differences; 2: fdec the maxed hadamard patterns of pbuf3,
             * fenc its complement; 3: fdec PIXEL_MAX, fenc 0 */
            for( int k = 0; k < 64 && ok; k++ )
            {
                for( int i = 0; i < 54*FDEC_STRIDE; i++ )
                {
                    int x = i%FDEC_STRIDE, y = i/FDEC_STRIDE;
                    fdec[i] = (k&3) == 0 ? pbuf2[(i+131*k)%0xf00]
                            : (k&3) == 1 ? -(pbuf2[(i+131*k)%0xf00]&1) & PIXEL_MAX
                            : (k&3) == 2 ? pbuf3[((x&15)+16*y+256*(k>>2))&0xfff]
                            : PIXEL_MAX;
                }
                for( int i = 0; i < 48*FENC_STRIDE; i++ )
                {
                    int x = i%FENC_STRIDE, y = i/FENC_STRIDE;
                    pixel *d = y < 16 ? fdec_y + y*FDEC_STRIDE + x : fdec_uv + (y-16)*FDEC_STRIDE + x + (x&8);
                    fenc[i] = (k&3) == 0 ? pbuf1[(i+67*k)%0x1e00]
                            : (k&3) == 3 ? 0
                            : ~*d & PIXEL_MAX;
                }
                int res_c[4], res_a[4];
                uint64_t ac = pixel_c.hadamard_ac[PIXEL_16x16]( fdec_y, FDEC_STRIDE );
                res_c[0] = pixel_c.ssd[PIXEL_16x16]( fenc, FENC_STRIDE, fdec_y, FDEC_STRIDE );
                res_c[1] = pixel_c.ssd[csize]( fenc_uv, FENC_STRIDE, fdec_uv, FDEC_STRIDE )
                         + pixel_c.ssd[csize]( fenc_uv+8, FENC_STRIDE, fdec_uv+16, FDEC_STRIDE );
                res_c[2] = (uint32_t)ac;
                res_c[3] = ac >> 32;
                call_a1( pixel_asm.ssd_psy_mb[c], res_a, fenc, fdec_y, fenc_uv, fdec_uv );
                if( memcmp( res_c, res_a, sizeof(res_c) ) )
                {
                    ok = 0;
                    fprintf( stderr, "ssd_psy_mb[%d] k %d: %d %d %d %d != %d %d %d %d\n", c, k, res_c[0], res_c[1],
                             res_c[2], res_c[3], res_a[0], res_a[1], res_a[2], res_a[3] );
                }
            }
            int res[4];
            call_a2( pixel_asm.ssd_psy_mb[c], res, fenc, fdec_y, fenc_uv, fdec_uv );
        }
    report( "pixel ssd_psy_mb :" );

    // maximize sum
    for( int i = 0; i < 32; i++ )
        for( int j = 0; j < 16; j++ )
            pbuf4[16*i+j] = -((i+j)&1) & PIXEL_MAX;
    ok = 1; used_asm = 0;
    if( pixel_asm.vsad != pixel_ref.vsad )
    {
        for( int h = 2; h <= 32; h += 2 )
        {
            int res_c, res_asm;
            set_func_name( "vsad" );
            used_asm = 1;
            for( int j = 0; j < 2 && ok; j++ )
            {
                pixel *p = j ? pbuf4 : pbuf1;
                res_c   = call_c( pixel_c.vsad,   p, (intptr_t)16, h );
                res_asm = call_a( pixel_asm.vsad, p, (intptr_t)16, h );
                if( res_c != res_asm )
                {
                    ok = 0;
                    fprintf( stderr, "vsad: height=%d, %d != %d\n", h, res_c, res_asm );
                    break;
                }
            }
        }
    }
    report( "pixel vsad :" );

    ok = 1; used_asm = 0;
    if( pixel_asm.asd8 != pixel_ref.asd8 )
    {
        set_func_name( "asd8" );
        used_asm = 1;
        int res_c = call_c( pixel_c.asd8,   pbuf1, (intptr_t)8, pbuf2, (intptr_t)8, 16 );
        int res_a = call_a( pixel_asm.asd8, pbuf1, (intptr_t)8, pbuf2, (intptr_t)8, 16 );
        if( res_c != res_a )
        {
            ok = 0;
            fprintf( stderr, "asd: %d != %d\n", res_c, res_a );
        }
        /* the largest |sum| of both signs */
        for( int k = 0; k < 256; k++ )
        {
            var_max[k] = PIXEL_MAX;
            var_zero[k] = 0;
        }
        for( int j = 0; j < 2 && ok; j++ )
        {
            res_c = pixel_c.asd8( j ? var_max : var_zero, 8, j ? var_zero : var_max, 8, 16 );
            res_a = pixel_asm.asd8( j ? var_max : var_zero, 8, j ? var_zero : var_max, 8, 16 );
            if( res_c != res_a )
            {
                ok = 0;
                fprintf( stderr, "asd: extreme %d: %d != %d\n", j, res_c, res_a );
            }
        }
        /* every height: random, and PIXEL_MAX against 0 either way */
        ALIGNED_16( pixel hi[8*16] );
        ALIGNED_16( pixel lo[8*16] );
        for( int i = 0; i < 8*16; i++ )
        {
            hi[i] = PIXEL_MAX;
            lo[i] = 0;
        }
        for( int h = 4; h <= 16 && ok; h += 4 )
            for( int k = 0; k < 3 && ok; k++ )
            {
                pixel *p1 = k == 0 ? pbuf1 : k == 1 ? hi : lo;
                pixel *p2 = k == 0 ? pbuf2 : k == 1 ? lo : hi;
                res_c = pixel_c.asd8( p1, 8, p2, 8, h );
                res_a = pixel_asm.asd8( p1, 8, p2, 8, h );
                if( res_c != res_a )
                {
                    ok = 0;
                    fprintf( stderr, "asd: height %d %d: %d != %d\n", h, k, res_c, res_a );
                }
            }
    }
    report( "pixel asd :" );

    ok = 1; used_asm = 0;
    if( pixel_asm.weightp_stats8 != pixel_ref.weightp_stats8 ||
        pixel_asm.weightp_sum8 != pixel_ref.weightp_sum8 ||
        pixel_asm.weightp_sum8_clip != pixel_ref.weightp_sum8_clip ||
        pixel_asm.weightp_sum8_nv != pixel_ref.weightp_sum8_nv )
    {
        /* random and near PIXEL_MAX; outputs compared up to n, as the asm may do n
         * rounded up to 16 (src and outputs have room for that) */
        intptr_t stride = 16*48 + 64;
        pixel *src = x264_malloc( 16*stride*sizeof(pixel) );
        int32_t *out = x264_malloc( 4*64*sizeof(int32_t) );
        int32_t *outc[2] = { out, out+64 };
        int32_t *outa[2] = { out+128, out+192 };
        ok = src && out;
        for( int k = 0; k < 2 && ok; k++ )
        {
            for( int i = 0; i < 16*stride; i++ )
                src[i] = k ? PIXEL_MAX - (rand()&3) : rand() & PIXEL_MAX;
            for( int height = 8; height <= 16 && ok; height += 8 )
                for( int n = 1; n <= 40 && ok; n += 3 )
                {
                    if( pixel_asm.weightp_stats8 != pixel_ref.weightp_stats8 )
                    {
                        set_func_name( "weightp_stats8" );
                        used_asm = 1;
                        memset( out, 0, 4*64*sizeof(int32_t) );
                        call_c( pixel_c.weightp_stats8, outc[0], (uint32_t*)outc[1], src, stride, n, height );
                        call_a( pixel_asm.weightp_stats8, outa[0], (uint32_t*)outa[1], src, stride, n, height );
                        if( memcmp( outc[0], outa[0], n*sizeof(int32_t) ) || memcmp( outc[1], outa[1], n*sizeof(int32_t) ) )
                        {
                            ok = 0;
                            fprintf( stderr, "weightp_stats8 FAILED: src %d n %d height %d\n", k, n, height );
                        }
                    }
                    if( pixel_asm.weightp_sum8 != pixel_ref.weightp_sum8 )
                    {
                        set_func_name( "weightp_sum8" );
                        used_asm = 1;
                        for( int denom = 0; denom <= 7 && ok; denom++ )
                        {
                            int scale = denom == 7 ? 127 : denom == 6 ? 0 : rand() & 127;
                            memset( out, 0, 4*64*sizeof(int32_t) );
                            call_c( pixel_c.weightp_sum8, outc[0], src, stride, n, height, scale, denom );
                            call_a( pixel_asm.weightp_sum8, outa[0], src, stride, n, height, scale, denom );
                            if( memcmp( outc[0], outa[0], n*sizeof(int32_t) ) )
                            {
                                ok = 0;
                                fprintf( stderr, "weightp_sum8 FAILED: src %d n %d height %d scale %d denom %d\n",
                                         k, n, height, scale, denom );
                            }
                        }
                    }
                    if( pixel_asm.weightp_sum8_clip != pixel_ref.weightp_sum8_clip )
                    {
                        set_func_name( "weightp_sum8_clip" );
                        used_asm = 1;
                        /* the extreme offsets, 0 and a random one */
                        for( int denom = 0; denom <= 7 && ok; denom++ )
                            for( int o = 0; o < 4 && ok; o++ )
                            {
                                int scale = denom == 7 ? 127 : denom == 6 ? 0 : rand() & 127;
                                int offset = (o == 0 ? -128 : o == 1 ? 127 : o == 2 ? 0 : (rand() & 255) - 128) << (BIT_DEPTH-8);
                                memset( out, 0, 4*64*sizeof(int32_t) );
                                call_c( pixel_c.weightp_sum8_clip, outc[0], src, stride, n, height, scale, denom, offset );
                                call_a( pixel_asm.weightp_sum8_clip, outa[0], src, stride, n, height, scale, denom, offset );
                                if( memcmp( outc[0], outa[0], n*sizeof(int32_t) ) )
                                {
                                    ok = 0;
                                    fprintf( stderr, "weightp_sum8_clip FAILED: src %d n %d height %d scale %d denom %d offset %d\n",
                                             k, n, height, scale, denom, offset );
                                }
                            }
                    }
                    if( pixel_asm.weightp_sum8_nv != pixel_ref.weightp_sum8_nv )
                    {
                        set_func_name( "weightp_sum8_nv" );
                        used_asm = 1;
                        memset( out, 0, 4*64*sizeof(int32_t) );
                        call_c( pixel_c.weightp_sum8_nv, outc[0], outc[1], src, stride, n, height );
                        call_a( pixel_asm.weightp_sum8_nv, outa[0], outa[1], src, stride, n, height );
                        if( memcmp( outc[0], outa[0], n*sizeof(int32_t) ) || memcmp( outc[1], outa[1], n*sizeof(int32_t) ) )
                        {
                            ok = 0;
                            fprintf( stderr, "weightp_sum8_nv FAILED: src %d n %d height %d\n", k, n, height );
                        }
                    }
                }
        }
        x264_free( src );
        x264_free( out );
    }
    report( "weightp stats :" );

    ok = 1; used_asm = 0;
    if( pixel_asm.weightp_dc8x8 != pixel_ref.weightp_dc8x8 )
    {
        ALIGNED_16( pixel lo[8*64] );
        ALIGNED_16( pixel hi[8*64] );
        for( int i = 0; i < 8*64; i++ )
        {
            lo[i] = rand() & 1;
            hi[i] = PIXEL_MAX - (rand() & 1);
        }
        set_func_name( "weightp_dc8x8" );
        used_asm = 1;
        /* k = 0: random, k = 1, 2: differences near +-PIXEL_MAX; misaligned too */
        for( int k = 0; k < 3 && ok; k++ )
            for( int s = 0; s < 4 && ok; s++ )
                for( int j = 0; j < 3 && ok; j++ )
                {
                    intptr_t i1 = s&1 ? 64 : 8;
                    intptr_t i2 = s&2 ? 64 : 8;
                    pixel *pix1 = (k == 0 ? pbuf1 : k == 1 ? hi : lo) + j;
                    pixel *pix2 = (k == 0 ? pbuf2 : k == 1 ? lo : hi) + 3*j;
                    int32_t dc_c[4], dc_a[4];
                    call_c( pixel_c.weightp_dc8x8, dc_c, pix1, i1, pix2, i2 );
                    call_a( pixel_asm.weightp_dc8x8, dc_a, pix1, i1, pix2, i2 );
                    if( memcmp( dc_c, dc_a, sizeof(dc_c) ) )
                    {
                        ok = 0;
                        fprintf( stderr, "weightp_dc8x8 FAILED: k %d i1 %d i2 %d j %d\n", k, (int)i1, (int)i2, j );
                    }
                }
    }
    report( "weightp dc :" );

    ok = 1; used_asm = 0;
    {
        /* random, near 0 and PIXEL_MAX (clipping at either end), flat; the identity, scale 0,
         * scale 127 at denom 0, extreme offsets; each output checked against the definition */
        intptr_t stride = 8*40 + 64;
        pixel *wref = x264_malloc( 8*stride*sizeof(pixel) );
        pixel *wfenc = x264_malloc( 8*stride*sizeof(pixel) );
        uint16_t *icost = x264_malloc( 40*sizeof(uint16_t) );
        ok = wref && wfenc && icost;
        for( int wt = 0; wt < 24 && ok; wt++ )
        {
            int kind = wt & 3;
            for( int i = 0; i < 8*stride; i++ )
            {
                int v = rand() & PIXEL_MAX;
                wref[i] = kind == 0 ? v : kind == 1 ? v >> (BIT_DEPTH-2) : kind == 2 ? PIXEL_MAX - (v >> (BIT_DEPTH-2)) : (wt*37) & PIXEL_MAX;
                wfenc[i] = kind == 3 ? (pixel)(rand() & PIXEL_MAX) : wt & 4 ? (pixel)(PIXEL_MAX - wref[i]) : (pixel)(rand() & PIXEL_MAX);
            }
            for( int i = 0; i < 40; i++ )
                icost[i] = wt & 8 ? rand() & 0x3fff : rand() & 0x1ff;
            int16_t wp[10][4];
            int nk = 1 + (wt % 10);
            for( int k = 0; k < nk; k++ )
            {
                int c = (wt + k) % 7;
                int denom = c == 0 || c == 1 ? 0 : c == 2 ? 1 : c == 3 ? 7 : rand() & 7;
                int scale = c == 0 ? 1 : c == 1 ? 127 : c == 2 ? 64 + (rand() & 63) : c == 3 ? 127 : c == 4 ? 0
                          : (1 << denom) + (rand() & 15) - 8;
                int offset = c == 0 ? 0 : c == 5 ? -128 : c == 6 ? 124 : (rand() & 255) - 128;
                wp[k][0] = x264_clip3( scale, 0, 127 );
                wp[k][1] = denom;
                wp[k][2] = offset << (BIT_DEPTH-8);
                wp[k][3] = c == 0 ? 1 : 1 + (rand() & 3);
            }
            int n = wt < 12 ? 1 + 3*wt : 38 + (wt&1);
            ALIGNED_16( uint32_t cost_c[10][4] );
            ALIGNED_16( uint32_t cost_a[10][4] );
            if( pixel_asm.weightp_satd8_search && pixel_asm.weightp_satd8_search != pixel_ref.weightp_satd8_search )
            {
                set_func_name( "weightp_satd8_search" );
                used_asm = 1;
                for( int k = 0; k < 10; k++ )
                    for( int j = 0; j < 4; j++ )
                        cost_c[k][j] = cost_a[k][j] = k*j;
                call_c1( weightp_satd8_search_ref, &pixel_c, cost_c, wref, wfenc, stride, n, icost, (const int16_t (*)[4])wp, nk );
                call_a1( pixel_asm.weightp_satd8_search, cost_a, wref, wfenc, stride, n, icost, (const int16_t (*)[4])wp, nk );
                for( int k = 0; k < nk; k++ )
                    for( int j = 0; j < wp[k][3]; j++ )
                        if( cost_c[k][j] != cost_a[k][j] )
                        {
                            ok = 0;
                            fprintf( stderr, "weightp_satd8_search FAILED: wt %d n %d k %d j %d { %d %d %d %d }: %u != %u\n",
                                     wt, n, k, j, wp[k][0], wp[k][1], wp[k][2], wp[k][3], cost_c[k][j], cost_a[k][j] );
                            k = nk;
                            break;
                        }
            }
            else
            {
                for( int k = 0; k < 10; k++ )
                    for( int j = 0; j < 4; j++ )
                        cost_c[k][j] = k*j;
                weightp_satd8_search_ref( &pixel_c, cost_c, wref, wfenc, stride, n, icost, (const int16_t (*)[4])wp, nk );
            }
            /* the definition, per block and weight */
            for( int k = 0; k < nk && ok; k++ )
                for( int j = 0; j < wp[k][3] && ok; j++ )
                {
                    uint32_t sum = k*j;
                    int round = (1 << wp[k][1]) >> 1;
                    for( int i = 0; i < n; i++ )
                    {
                        ALIGNED_16( pixel w[64] );
                        for( int y = 0; y < 8; y++ )
                            for( int x = 0; x < 8; x++ )
                                w[x+8*y] = x264_clip3( ((wref[8*i+x+y*stride] * wp[k][0] + round) >> wp[k][1])
                                                       + wp[k][2] + (j << (BIT_DEPTH-8)), 0, PIXEL_MAX );
                        int satd = pixel_c.satd[PIXEL_8x8]( w, 8, wfenc + 8*i, stride );
                        sum += X264_MIN( satd, icost[i] << (BIT_DEPTH-8) );
                    }
                    if( sum != cost_c[k][j] )
                    {
                        ok = 0;
                        fprintf( stderr, "weightp_satd8_search C FAILED: wt %d n %d k %d j %d: %u != %u\n",
                                 wt, n, k, j, cost_c[k][j], sum );
                    }
                }
        }
        /* bench: a row of 40 blocks, no clipping, from a private generator: the unweighted
         * ref and one scale of 3 offsets (lowlat, subme 2), and of three scales of 3 (subme 7) */
        for( int bk = 0; bk < 2 && ok && do_bench && pixel_asm.weightp_satd8_search && pixel_asm.weightp_satd8_search != pixel_ref.weightp_satd8_search; bk++ )
        {
            static const int16_t bench_wp[4][4] = { { 1, 0, 0, 1 }, { 110, 7, 3, 3 }, { 111, 7, 3, 3 }, { 112, 7, 2, 3 } };
            int16_t wp[4][4];
            ALIGNED_64( uint32_t cost[4][4] );
            bench_srand( 700 );
            for( int i = 0; i < 8*stride; i++ )
            {
                wref[i] = (PIXEL_MAX/4) + (bench_rand() & (PIXEL_MAX/4));
                wfenc[i] = (PIXEL_MAX/4) + (bench_rand() & (PIXEL_MAX/4));
            }
            for( int i = 0; i < 40; i++ )
                icost[i] = 0x3fff;
            for( int k = 0; k < 4; k++ )
                for( int j = 0; j < 4; j++ )
                    wp[k][j] = j == 2 ? bench_wp[k][j] << (BIT_DEPTH-8) : bench_wp[k][j];
            memset( cost, 0, sizeof(cost) );
            set_func_name( "weightp_satd8_search_k%d", bk ? 4 : 2 );
            call_c2( weightp_satd8_search_ref, &pixel_c, cost, wref, wfenc, stride, 40, icost, (const int16_t (*)[4])wp, bk ? 4 : 2 );
            call_a2( pixel_asm.weightp_satd8_search, cost, wref, wfenc, stride, 40, icost, (const int16_t (*)[4])wp, bk ? 4 : 2 );
        }
        x264_free( wref );
        x264_free( wfenc );
        x264_free( icost );
    }
    report( "weightp satd8 search :" );

#define TEST_INTRA_X3( name, i8x8, ... ) \
    if( pixel_asm.name && pixel_asm.name != pixel_ref.name ) \
    { \
        ALIGNED_16( int res_c[4] ); \
        ALIGNED_16( int res_asm[4] ); \
        set_func_name( #name ); \
        used_asm = 1; \
        call_c( pixel_c.name, x9_fenc+48, i8x8 ? edge : pbuf3+48, res_c ); \
        call_a( pixel_asm.name, x9_fenc+48, i8x8 ? edge : pbuf3+48, res_asm ); \
        if( memcmp(res_c, res_asm, 3 * sizeof(*res_c)) ) \
        { \
            ok = 0; \
            fprintf( stderr, #name": %d,%d,%d != %d,%d,%d [FAILED]\n", \
                     res_c[0], res_c[1], res_c[2], \
                     res_asm[0], res_asm[1], res_asm[2] ); \
        } \
    }

#define TEST_INTRA_X9( name, cmp ) \
    if( pixel_asm.name && pixel_asm.name != pixel_ref.name ) \
    { \
        set_func_name( #name ); \
        used_asm = 1; \
        ALIGNED_ARRAY_64( uint16_t, bitcosts,[17] ); \
        for( int i=0; i<17; i++ ) \
            bitcosts[i] = 9*(i!=8); \
        memcpy( pbuf3, x9_dec, 20*FDEC_STRIDE*sizeof(pixel) ); \
        memcpy( pbuf4, x9_dec, 20*FDEC_STRIDE*sizeof(pixel) ); \
        for( int i=0; i<32; i++ ) \
        { \
            pixel *fenc = x9_fenc+48+i*12; \
            pixel *fdec1 = pbuf3+48+i*12; \
            pixel *fdec2 = pbuf4+48+i*12; \
            int pred_mode = i%9; \
            int res_c = INT_MAX; \
            for( int j=0; j<9; j++ ) \
            { \
                predict_4x4[j]( fdec1 ); \
                int cost = pixel_c.cmp[PIXEL_4x4]( fenc, FENC_STRIDE, fdec1, FDEC_STRIDE ) + 9*(j!=pred_mode); \
                if( cost < (uint16_t)res_c ) \
                    res_c = cost + (j<<16); \
            } \
            predict_4x4[res_c>>16]( fdec1 ); \
            int res_a = call_a( pixel_asm.name, fenc, fdec2, bitcosts+8-pred_mode ); \
            if( res_c != res_a ) \
            { \
                ok = 0; \
                fprintf( stderr, #name": %d,%d != %d,%d [FAILED]\n", res_c>>16, res_c&0xffff, res_a>>16, res_a&0xffff ); \
                break; \
            } \
            if( memcmp(fdec1, fdec2, 4*FDEC_STRIDE*sizeof(pixel)) ) \
            { \
                ok = 0; \
                fprintf( stderr, #name" [FAILED]\n" ); \
                for( int j=0; j<16; j++ ) \
                    fprintf( stderr, "%02x ", fdec1[(j&3)+(j>>2)*FDEC_STRIDE] ); \
                fprintf( stderr, "\n" ); \
                for( int j=0; j<16; j++ ) \
                    fprintf( stderr, "%02x ", fdec2[(j&3)+(j>>2)*FDEC_STRIDE] ); \
                fprintf( stderr, "\n" ); \
                break; \
            } \
        } \
    }

#define TEST_INTRA8_X9( name, cmp ) \
    if( pixel_asm.name && pixel_asm.name != pixel_ref.name ) \
    { \
        set_func_name( #name ); \
        used_asm = 1; \
        ALIGNED_ARRAY_64( uint16_t, bitcosts,[17] ); \
        ALIGNED_ARRAY_16( uint16_t, satds_c,[16] ); \
        ALIGNED_ARRAY_16( uint16_t, satds_a,[16] ); \
        memset( satds_c, 0, 16 * sizeof(*satds_c) ); \
        memset( satds_a, 0, 16 * sizeof(*satds_a) ); \
        for( int i=0; i<17; i++ ) \
            bitcosts[i] = 9*(i!=8); \
        memcpy( pbuf3, x9_dec, 20*FDEC_STRIDE*sizeof(pixel) ); \
        memcpy( pbuf4, x9_dec, 20*FDEC_STRIDE*sizeof(pixel) ); \
        for( int i=0; i<32; i++ ) \
        { \
            pixel *fenc = x9_fenc+48+i*12; \
            pixel *fdec1 = pbuf3+48+i*12; \
            pixel *fdec2 = pbuf4+48+i*12; \
            int pred_mode = i%9; \
            int res_c = INT_MAX; \
            predict_8x8_filter( fdec1, edge, ALL_NEIGHBORS, ALL_NEIGHBORS ); \
            for( int j=0; j<9; j++ ) \
            { \
                predict_8x8[j]( fdec1, edge ); \
                satds_c[j] = X264_MIN( pixel_c.cmp[PIXEL_8x8]( fenc, FENC_STRIDE, fdec1, FDEC_STRIDE ) + 9*(j!=pred_mode), 0xffff ); \
                if( satds_c[j] < (uint16_t)res_c ) \
                    res_c = satds_c[j] + (j<<16); \
            } \
            predict_8x8[res_c>>16]( fdec1, edge ); \
            int res_a = call_a( pixel_asm.name, fenc, fdec2, edge, bitcosts+8-pred_mode, satds_a ); \
            if( res_c != res_a || memcmp(satds_c, satds_a, sizeof(satds_c)) ) \
            { \
                ok = 0; \
                fprintf( stderr, #name": %d,%d != %d,%d [FAILED]\n", res_c>>16, res_c&0xffff, res_a>>16, res_a&0xffff ); \
                for( int j = 0; j < 9; j++ ) \
                    fprintf( stderr, "%5d ", satds_c[j]); \
                fprintf( stderr, "\n" ); \
                for( int j = 0; j < 9; j++ ) \
                    fprintf( stderr, "%5d ", satds_a[j]); \
                fprintf( stderr, "\n" ); \
                break; \
            } \
            for( int j=0; j<8; j++ ) \
                if( memcmp(fdec1+j*FDEC_STRIDE, fdec2+j*FDEC_STRIDE, 8*sizeof(pixel)) ) \
                    ok = 0; \
            if( !ok ) \
            { \
                fprintf( stderr, #name" [FAILED]\n" ); \
                for( int j=0; j<8; j++ ) \
                { \
                    for( int k=0; k<8; k++ ) \
                        fprintf( stderr, "%02x ", fdec1[k+j*FDEC_STRIDE] ); \
                    fprintf( stderr, "\n" ); \
                } \
                fprintf( stderr, "\n" ); \
                for( int j=0; j<8; j++ ) \
                { \
                    for( int k=0; k<8; k++ ) \
                        fprintf( stderr, "%02x ", fdec2[k+j*FDEC_STRIDE] ); \
                    fprintf( stderr, "\n" ); \
                } \
                fprintf( stderr, "\n" ); \
                break; \
            } \
        } \
    }

    /* pat = 0: random fenc and neighbours; 1: fenc PIXEL_MAX, neighbours 0;
     * 2: fenc 0, neighbours PIXEL_MAX; 3: both a random mix of 0 and PIXEL_MAX */
    pixel *x9_fenc, *x9_dec;
    ALIGNED_ARRAY_64( pixel, x9_buf,[0x800] );
#define INTRA_X_SOURCES( pat ) \
    x9_fenc = pbuf1; \
    x9_dec = pbuf2; \
    if( pat ) \
    { \
        x9_fenc = x9_buf; \
        x9_dec = x9_buf+0x400; \
        for( int i = 0; i < 0x400; i++ ) \
        { \
            x9_fenc[i] = pat == 1 ? PIXEL_MAX : pat == 2 ? 0 : (rand()&1)*PIXEL_MAX; \
            x9_dec[i]  = pat == 1 ? 0 : pat == 2 ? PIXEL_MAX : (rand()&1)*PIXEL_MAX; \
        } \
    } \
    predict_8x8_filter( x9_dec+40, edge, ALL_NEIGHBORS, ALL_NEIGHBORS ); \
    memcpy( pbuf3, x9_dec, 20*FDEC_STRIDE*sizeof(pixel) );

    ok = 1; used_asm = 0;
    for( int pat = 0; pat < (do_bench ? 1 : 4) && ok; pat++ )
    {
        INTRA_X_SOURCES( pat );
        TEST_INTRA_X3( intra_satd_x3_16x16, 0 );
        TEST_INTRA_X3( intra_satd_x3_8x16c, 0 );
        TEST_INTRA_X3( intra_satd_x3_8x8c, 0 );
        TEST_INTRA_X3( intra_sa8d_x3_8x8, 1, edge );
        TEST_INTRA_X3( intra_satd_x3_4x4, 0 );
    }
    report( "intra satd_x3 :" );
    ok = 1; used_asm = 0;
    for( int pat = 0; pat < (do_bench ? 1 : 4) && ok; pat++ )
    {
        INTRA_X_SOURCES( pat );
        /* several aligned block positions: other neighbours and DC roundings */
        for( int o = 0; o < (do_bench ? 1 : 7) && ok; o++ )
        {
            pixel *fenc0 = x9_fenc, *fdec0 = pbuf3;
            x9_fenc += 16*o;
            pbuf3 += 16*o;
            TEST_INTRA_X3( intra_sad_x3_16x16, 0 );
            TEST_INTRA_X3( intra_sad_x3_8x16c, 0 );
            TEST_INTRA_X3( intra_sad_x3_8x8c, 0 );
            TEST_INTRA_X3( intra_sad_x3_8x8, 1, edge );
            TEST_INTRA_X3( intra_sad_x3_4x4, 0 );
            x9_fenc = fenc0;
            pbuf3 = fdec0;
        }
    }
    report( "intra sad_x3 :" );
    ok = 1; used_asm = 0;
    for( int pat = 0; pat < (do_bench ? 1 : 4) && ok; pat++ )
    {
        INTRA_X_SOURCES( pat );
        TEST_INTRA_X9( intra_satd_x9_4x4, satd );
        TEST_INTRA8_X9( intra_sa8d_x9_8x8, sa8d );
    }
    report( "intra satd_x9 :" );
    ok = 1; used_asm = 0;
    for( int pat = 0; pat < (do_bench ? 1 : 4) && ok; pat++ )
    {
        INTRA_X_SOURCES( pat );
        TEST_INTRA_X9( intra_sad_x9_4x4, sad );
        TEST_INTRA8_X9( intra_sad_x9_8x8, sad );
    }
    report( "intra sad_x9 :" );

    ok = 1; used_asm = 0;
    if( pixel_asm.intra_satd_lowres && pixel_asm.intra_satd_lowres != pixel_ref.intra_satd_lowres )
    {
        /* against slicetype's C path: neighbours copied to pix, x3, P, filter, DDL..HU */
        ALIGNED_ARRAY_64( pixel, plane,[10*64] );
        ALIGNED_ARRAY_64( pixel, fenc,[8*FENC_STRIDE] );
        ALIGNED_ARRAY_64( pixel, pixbuf,[9*FDEC_STRIDE] );
        ALIGNED_16( pixel edge8[36] );
        intptr_t stride = 64;
        pixel *src = plane + stride + 16;
        pixel *pix = pixbuf + FDEC_STRIDE + 8;
        int pixoff = 4 / sizeof(pixel);
        used_asm = 1;
        set_func_name( "intra_satd_lowres" );
        /* k = 0: random; 1: random 0/max, every difference +-max; 2, 3: the neighbour
         * segments lt, t0-3, t4-7, t8-15, l0-3, l4-7 each 0 or max by the bits of j,
         * fenc random (2) or a 0/max checkerboard (3) */
        for( int k = 0; k < 4 && ok; k++ )
            for( int j = 0; j < 64 && ok; j++ )
            {
                for( int i = 0; i < 10*64; i++ )
                    plane[i] = k == 1 ? -(pbuf1[i+3*j]&1) & PIXEL_MAX : pbuf2[i+7*j];
                if( k >= 2 )
                {
                    src[-stride-1] = -(j&1) & PIXEL_MAX;
                    for( int x = 0; x < 16; x++ )
                        src[x-stride] = -((j >> (1 + X264_MIN( x>>2, 2 ))) & 1) & PIXEL_MAX;
                    for( int y = 0; y < 8; y++ )
                        src[y*stride-1] = -((j >> (4 + (y>>2))) & 1) & PIXEL_MAX;
                }
                for( int y = 0; y < 8; y++ )
                    for( int x = 0; x < 8; x++ )
                        fenc[y*FENC_STRIDE+x] = k == 1 ? PIXEL_MAX - src[y*stride+x]
                                              : k == 3 ? -((x^y^j)&1) & PIXEL_MAX
                                              : pbuf1[y*16+x+5*j];

                int satds[3];
                memcpy( pix-FDEC_STRIDE, src-stride, 16 * sizeof(pixel) );
                for( int i = -1; i < 8; i++ )
                    M32( &pix[i*FDEC_STRIDE-pixoff] ) = M32( &src[i*stride-pixoff] );
                pixel_c.intra_satd_x3_8x8c( fenc, pix, satds );
                int res_c = X264_MIN3( satds[0], satds[1], satds[2] );
                predict_8x8c[I_PRED_CHROMA_P]( pix );
                res_c = X264_MIN( res_c, pixel_c.satd[PIXEL_8x8]( pix, FDEC_STRIDE, fenc, FENC_STRIDE ) );
                predict_8x8_filter( pix, edge8, ALL_NEIGHBORS, ALL_NEIGHBORS );
                for( int i = 3; i < 9; i++ )
                {
                    predict_8x8[i]( pix, edge8 );
                    res_c = X264_MIN( res_c, pixel_c.satd[PIXEL_8x8]( pix, FDEC_STRIDE, fenc, FENC_STRIDE ) );
                }

                void *f = fenc;
#if !HIGH_BIT_DEPTH
                ALIGNED_ARRAY_64( int16_t, fenc_pre,[64] );
                pixel_asm.satd_fenc_pre[1]( fenc_pre, fenc );
                f = fenc_pre;
#endif
                int res_a = call_a( pixel_asm.intra_satd_lowres, f, src, stride );
                if( res_c != res_a )
                {
                    ok = 0;
                    fprintf( stderr, "intra_satd_lowres k=%d j=%d: %d != %d [FAILED]\n", k, j, res_c, res_a );
                }
            }
    }
    report( "intra satd_lowres :" );

    ok = 1; used_asm = 0;
    if( pixel_asm.ssd_nv12_core != pixel_ref.ssd_nv12_core )
    {
        used_asm = 1;
        set_func_name( "ssd_nv12" );
        uint64_t res_u_c, res_v_c, res_u_a, res_v_a;
        pixel_c.ssd_nv12_core(   pbuf1, 368, pbuf2, 368, 360, 8, &res_u_c, &res_v_c );
        pixel_asm.ssd_nv12_core( pbuf1, 368, pbuf2, 368, 360, 8, &res_u_a, &res_v_a );
        if( res_u_c != res_u_a || res_v_c != res_v_a )
        {
            ok = 0;
            fprintf( stderr, "ssd_nv12: %"PRIu64",%"PRIu64" != %"PRIu64",%"PRIu64"\n",
                     res_u_c, res_v_c, res_u_a, res_v_a );
        }
        /* every difference +-PIXEL_MAX, the 16-pixel tail, odd heights */
        for( int i = 0; i < 0x1000; i++ )
        {
            pbuf3[i] = -(pbuf1[i]&1) & PIXEL_MAX;
            pbuf4[i] = PIXEL_MAX - pbuf3[i];
        }
        for( int k = 0; k < 4 && ok; k++ )
        {
            int w = k&1 ? 360 : 352, hgt = k&2 ? 9 : 8;
            pixel_c.ssd_nv12_core(   pbuf3, 368, pbuf4, 368, w, hgt, &res_u_c, &res_v_c );
            pixel_asm.ssd_nv12_core( pbuf3, 368, pbuf4, 368, w, hgt, &res_u_a, &res_v_a );
            if( res_u_c != res_u_a || res_v_c != res_v_a )
            {
                ok = 0;
                fprintf( stderr, "ssd_nv12 %dx%d maxed: %"PRIu64",%"PRIu64" != %"PRIu64",%"PRIu64"\n",
                         w, hgt, res_u_c, res_v_c, res_u_a, res_v_a );
            }
        }
        call_c( pixel_c.ssd_nv12_core,   pbuf1, (intptr_t)368, pbuf2, (intptr_t)368, 360, 8, &res_u_c, &res_v_c );
        call_a( pixel_asm.ssd_nv12_core, pbuf1, (intptr_t)368, pbuf2, (intptr_t)368, 360, 8, &res_u_a, &res_v_a );
    }
    report( "ssd_nv12 :" );

    if( pixel_asm.ssim_4x4x2_core != pixel_ref.ssim_4x4x2_core ||
        pixel_asm.ssim_end4 != pixel_ref.ssim_end4 )
    {
        int cnt;
        float res_c, res_a;
        ALIGNED_16( int sums[5][4] ) = {{0}};
        used_asm = ok = 1;
        x264_emms();
        res_c = x264_pixel_ssim_wxh( &pixel_c,   pbuf1+2, 32, pbuf2+2, 32, 32, 28, pbuf3, &cnt );
        res_a = x264_pixel_ssim_wxh( &pixel_asm, pbuf1+2, 32, pbuf2+2, 32, 32, 28, pbuf3, &cnt );
        if( fabs( res_c - res_a ) > 1e-6 )
        {
            ok = 0;
            fprintf( stderr, "ssim: %.7f != %.7f [FAILED]\n", res_c, res_a );
        }
        /* the core's sums exactly: random, and 0/PIXEL_MAX (pbuf3 against its complement and itself) */
        for( int i = 0; i < 256; i++ )
        {
            pbuf3[i] = -(pbuf1[i]&1) & PIXEL_MAX;
            pbuf4[i] = PIXEL_MAX - pbuf3[i];
        }
        if( pixel_asm.ssim_4x4x2_core != pixel_ref.ssim_4x4x2_core )
        {
            for( int k = 0; k < 3 && ok; k++ )
                for( int j = 0; j < 8 && ok; j++ )
                {
                    pixel *p1 = (k ? pbuf3 : pbuf1) + 4*j + 2;
                    pixel *p2 = (k == 1 ? pbuf4 : k ? pbuf3 : pbuf2) + 4*j + 2;
                    int sums_c[2][4], sums_a[2][4];
                    memset( sums_c, 0x5a, sizeof(sums_c) );
                    memset( sums_a, 0x5a, sizeof(sums_a) );
                    pixel_c.ssim_4x4x2_core( p1, 32, p2, 32, sums_c );
                    pixel_asm.ssim_4x4x2_core( p1, 32, p2, 32, sums_a );
                    if( memcmp( sums_c, sums_a, sizeof(sums_c) ) )
                    {
                        ok = 0;
                        fprintf( stderr, "ssim_4x4x2_core k %d x %d: %d,%d,%d,%d %d,%d,%d,%d != %d,%d,%d,%d %d,%d,%d,%d [FAILED]\n", k, 4*j+2,
                                 sums_c[0][0], sums_c[0][1], sums_c[0][2], sums_c[0][3], sums_c[1][0], sums_c[1][1], sums_c[1][2], sums_c[1][3],
                                 sums_a[0][0], sums_a[0][1], sums_a[0][2], sums_a[0][3], sums_a[1][0], sums_a[1][1], sums_a[1][2], sums_a[1][3] );
                    }
                }
            /* odd alignment, random maxed differences, PIXEL_MAX against 0 and itself */
            for( int j = 0; j < 4 && ok; j++ )
            {
                ALIGNED_16( int sc[2][4] );
                ALIGNED_16( int sa[2][4] );
                pixel *p1 = j == 0 ? pbuf1+5 : pbuf3;
                pixel *p2 = j == 0 ? pbuf2+3 : j == 1 ? pbuf4 : pbuf3;
                for( int k = 0; k < 4*32 && j; k++ )
                {
                    pbuf3[k] = j == 1 ? -(rand()&1) & PIXEL_MAX : PIXEL_MAX;
                    pbuf4[k] = j == 1 ? PIXEL_MAX - pbuf3[k] : 0;
                }
                if( j == 2 )
                    p2 = pbuf4;
                memset( sc, 0x5a, sizeof(sc) );
                memset( sa, 0x5a, sizeof(sa) );
                pixel_c.ssim_4x4x2_core( p1, 32, p2, 32, sc );
                pixel_asm.ssim_4x4x2_core( p1, 32, p2, 32, sa );
                if( memcmp( sc, sa, sizeof(sc) ) )
                {
                    ok = 0;
                    fprintf( stderr, "ssim_4x4x2_core %d [FAILED]\n", j );
                }
            }
        }
        /* ssim_end4 at every width: the blocks past it must not count */
        for( int w = 1; w <= 4 && ok; w++ )
        {
            ALIGNED_16( int s[2][6][4] );
            for( int z = 0; z < 2; z++ )
                for( int i = 0; i < 3; i++ )
                    pixel_c.ssim_4x4x2_core( pbuf1+8*i+4*z*32, 32, pbuf2+8*i+4*z*32, 32, s[z]+2*i );
            float e_c = pixel_c.ssim_end4( s[0], s[1], w );
            float e_a = pixel_asm.ssim_end4( s[0], s[1], w );
            if( fabs( e_c - e_a ) > 1e-6 )
            {
                ok = 0;
                fprintf( stderr, "ssim_end4 width %d: %.7f != %.7f [FAILED]\n", w, e_c, e_a );
            }
        }
        set_func_name( "ssim_core" );
        call_c2( pixel_c.ssim_4x4x2_core,   pbuf1+2, (intptr_t)32, pbuf2+2, (intptr_t)32, sums );
        call_a2( pixel_asm.ssim_4x4x2_core, pbuf1+2, (intptr_t)32, pbuf2+2, (intptr_t)32, sums );
        set_func_name( "ssim_end" );
        call_c2( pixel_c.ssim_end4,   sums, sums, 4 );
        call_a2( pixel_asm.ssim_end4, sums, sums, 4 );
        report( "ssim :" );
    }

    ok = 1; used_asm = 0;
    for( int i = 0; i < 32; i++ )
        cost_mv[i] = rand30() & 0xffff;
    for( int i = 0; i < 200 && ok; i++ )
        if( pixel_asm.ads[i&3] != pixel_ref.ads[i&3] )
        {
            /* widths: one partial chunk, whole chunks, several chunks plus a tail;
             * thresholds: random, then 0, the 0xffff / 0x10000 boundaries, all pass, negative */
            static const int ads_width[5] = { 28, 4, 64, 100, 36 };
            static const int ads_thresh[7] = { 0, 1, 0xffff, 0x10000, 0x10001, 0x20000, -5 };
            ALIGNED_16( uint16_t sums[192] );
            ALIGNED_16( uint16_t cost[192] );
            ALIGNED_16( int dc[4] );
            ALIGNED_16( int16_t mvs_a[160] );
            ALIGNED_16( int16_t mvs_c[160] );
            int mvn_a, mvn_c;
            int width = i < 100 ? 28 : ads_width[(i>>2)%5];
            int thresh = (rand() % 257) * PIXEL_MAX + (rand30() & 0xffff);
            if( i >= 100 && i%3 == 2 )
                thresh = ads_thresh[(i>>2)%7];
            set_func_name( "esa_ads_%s", pixel_names[i&3] );
            if( i < 40 || (i >= 100 && i < 140) )
            {
                for( int j = 0; j < 192; j++ )
                    sums[j] = (rand() % 9) * 8 * PIXEL_MAX;
                for( int j = 0; j < 4; j++ )
                    dc[j]   = (rand() % 9) * 8 * PIXEL_MAX;
            }
            else
            {
#if BIT_DEPTH + 6 > 15
                for( int j = 0; j < 192; j++ )
                    sums[j] = rand30() & ((1 << (BIT_DEPTH + 6))-1);
                for( int j = 0; j < 4; j++ )
                    dc[j]   = rand30() & ((1 << (BIT_DEPTH + 6))-1);
#else
                for( int j = 0; j < 192; j++ )
                    sums[j] = rand() & ((1 << (BIT_DEPTH + 6))-1);
                for( int j = 0; j < 4; j++ )
                    dc[j]   = rand() & ((1 << (BIT_DEPTH + 6))-1);
#endif
            }
            for( int j = 0; j < 192; j++ )
                cost[j] = j < 32 && i < 100 ? cost_mv[j] : rand30() & 0xffff;
            if( i >= 100 && i%3 == 1 )
            {
                /* thresh equal to a candidate's cost */
                int k = rand() % width;
                int size = (i&3) == 0 ? 4 : (i&3) == 3 ? 1 : 2;
                thresh = abs( dc[0] - sums[k] ) + cost[k];
                if( size == 4 )
                    thresh += abs( dc[1] - sums[k+8] ) + abs( dc[2] - sums[k+32] ) + abs( dc[3] - sums[k+40] );
                else if( size == 2 )
                    thresh += abs( dc[1] - sums[k+32] );
            }
            used_asm = 1;
            mvn_c = call_c1( pixel_c.ads[i&3], dc, sums, 32, cost, mvs_c, width, thresh );
            mvn_a = call_a1( pixel_asm.ads[i&3], dc, sums, 32, cost, mvs_a, width, thresh );
            if( mvn_c != mvn_a || memcmp( mvs_c, mvs_a, mvn_c*sizeof(*mvs_c) ) )
            {
                ok = 0;
                printf( "width: %d thresh: %d\n", width, thresh );
                printf( "c%d: ", i&3 );
                for( int j = 0; j < mvn_c; j++ )
                    printf( "%d ", mvs_c[j] );
                printf( "\na%d: ", i&3 );
                for( int j = 0; j < mvn_a; j++ )
                    printf( "%d ", mvs_a[j] );
                printf( "\n\n" );
            }
        }
    /* bench: one fixed row per size, width 64, sums and dc clustered as in the check,
     * a fixed threshold */
    for( int i = 0; i < 4 && ok && do_bench; i++ )
        if( pixel_asm.ads[i] != pixel_ref.ads[i] )
        {
            ALIGNED_16( uint16_t sums[192] );
            ALIGNED_16( uint16_t cost[192] );
            ALIGNED_16( int dc[4] );
            ALIGNED_16( int16_t mvs[160] );
            bench_srand( 400 + i );
            for( int j = 0; j < 192; j++ )
            {
                sums[j] = (bench_rand() % 9) * 8 * PIXEL_MAX;
                cost[j] = bench_rand() & 0x3ff;
            }
            for( int j = 0; j < 4; j++ )
                dc[j] = 4 * 8 * PIXEL_MAX;
            set_func_name( "esa_ads_%s", pixel_names[i] );
            call_c2( pixel_c.ads[i], dc, sums, 32, cost, mvs, 64, 16 * PIXEL_MAX );
            call_a2( pixel_asm.ads[i], dc, sums, 32, cost, mvs, 64, 16 * PIXEL_MAX );
        }
    report( "esa ads:" );

    return ret;
}

static int check_dct( int cpu_ref, int cpu_new )
{
    x264_dct_function_t dct_c;
    x264_dct_function_t dct_ref;
    x264_dct_function_t dct_asm;
    x264_quant_function_t qf;
    int ret = 0, ok, used_asm, interlace = 0;
    ALIGNED_ARRAY_64( dctcoef, dct1, [16],[16] );
    ALIGNED_ARRAY_64( dctcoef, dct2, [16],[16] );
    ALIGNED_ARRAY_64( dctcoef, dct4, [16],[16] );
    ALIGNED_ARRAY_64( dctcoef, dct8, [4],[64] );
    ALIGNED_16( dctcoef dctdc[2][8] );
    x264_t h_buf;
    x264_t *h = &h_buf;

    x264_dct_init( 0, &dct_c );
    x264_dct_init( cpu_ref, &dct_ref);
    x264_dct_init( cpu_new, &dct_asm );

    memset( h, 0, sizeof(*h) );
    x264_param_default( &h->param );
    h->sps->i_chroma_format_idc = 1;
    h->chroma_qp_table = i_chroma_qp_table + 12;
    h->param.analyse.i_luma_deadzone[0] = 0;
    h->param.analyse.i_luma_deadzone[1] = 0;
    h->param.analyse.b_transform_8x8 = 1;
    for( int i = 0; i < 6; i++ )
        h->pps->scaling_list[i] = x264_cqm_flat16;
    x264_cqm_init( h );
    x264_quant_init( h, 0, &qf );

    /* overflow test cases */
    for( int i = 0; i < 5; i++ )
    {
        pixel *enc = &pbuf3[16*i*FENC_STRIDE];
        pixel *dec = &pbuf4[16*i*FDEC_STRIDE];

        for( int j = 0; j < 16; j++ )
        {
            int cond_a = (i < 2) ? 1 : ((j&3) == 0 || (j&3) == (i-1));
            int cond_b = (i == 0) ? 1 : !cond_a;
            enc[0] = enc[1] = enc[4] = enc[5] = enc[8] = enc[9] = enc[12] = enc[13] = cond_a ? PIXEL_MAX : 0;
            enc[2] = enc[3] = enc[6] = enc[7] = enc[10] = enc[11] = enc[14] = enc[15] = cond_b ? PIXEL_MAX : 0;

            /* every column: the 8x8 and 16x16 transforms read them all */
            for( int k = 0; k < 16; k++ )
                dec[k] = PIXEL_MAX - enc[k];

            enc += FENC_STRIDE;
            dec += FDEC_STRIDE;
        }
    }

#define TEST_DCT( name, t1, t2, size ) \
    if( dct_asm.name != dct_ref.name ) \
    { \
        set_func_name( #name ); \
        used_asm = 1; \
        pixel *enc = pbuf3; \
        pixel *dec = pbuf4; \
        for( int j = 0; j < 5; j++) \
        { \
            call_c( dct_c.name, t1, &pbuf1[j*64], &pbuf2[j*64] ); \
            call_a( dct_asm.name, t2, &pbuf1[j*64], &pbuf2[j*64] ); \
            if( memcmp( t1, t2, size*sizeof(dctcoef) ) ) \
            { \
                ok = 0; \
                fprintf( stderr, #name " [FAILED]\n" ); \
                for( int k = 0; k < size; k++ )\
                    printf( "%d ", ((dctcoef*)t1)[k] );\
                printf("\n");\
                for( int k = 0; k < size; k++ )\
                    printf( "%d ", ((dctcoef*)t2)[k] );\
                printf("\n");\
                break; \
            } \
            call_c( dct_c.name, t1, enc, dec ); \
            call_a( dct_asm.name, t2, enc, dec ); \
            if( memcmp( t1, t2, size*sizeof(dctcoef) ) ) \
            { \
                ok = 0; \
                fprintf( stderr, #name " [FAILED] (overflow)\n" ); \
                break; \
            } \
            enc += 16*FENC_STRIDE; \
            dec += 16*FDEC_STRIDE; \
        } \
    }
    ok = 1; used_asm = 0;
    TEST_DCT( sub4x4_dct, dct1[0], dct2[0], 16 );
    TEST_DCT( sub8x8_dct, dct1, dct2, 16*4 );
    TEST_DCT( sub8x8_dct_dc, dctdc[0], dctdc[1], 4 );
    TEST_DCT( sub8x16_dct_dc, dctdc[0], dctdc[1], 8 );
    TEST_DCT( sub16x16_dct, dct1, dct2, 16*16 );
    report( "sub_dct4 :" );

    ok = 1; used_asm = 0;
    TEST_DCT( sub8x8_dct8, (void*)dct1[0], (void*)dct2[0], 64 );
    TEST_DCT( sub16x16_dct8, (void*)dct1, (void*)dct2, 64*4 );
    report( "sub_dct8 :" );
#undef TEST_DCT

    // fdct and idct are denormalized by different factors, so quant/dequant
    // is needed to force the coefs into the right range.
    dct_c.sub16x16_dct( dct4, pbuf1, pbuf2 );
    dct_c.sub16x16_dct8( dct8, pbuf1, pbuf2 );
    for( int i = 0; i < 16; i++ )
    {
        qf.quant_4x4( dct4[i], h->quant4_mf[CQM_4IY][20], h->quant4_bias[CQM_4IY][20] );
        qf.dequant_4x4( dct4[i], h->dequant4_mf[CQM_4IY], 20 );
    }
    for( int i = 0; i < 4; i++ )
    {
        qf.quant_8x8( dct8[i], h->quant8_mf[CQM_8IY][20], h->quant8_bias[CQM_8IY][20] );
        qf.dequant_8x8( dct8[i], h->dequant8_mf[CQM_8IY], 20 );
    }
    x264_cqm_delete( h );

#define TEST_IDCT( name, src ) \
    if( dct_asm.name != dct_ref.name ) \
    { \
        set_func_name( #name ); \
        used_asm = 1; \
        /* dst random, near PIXEL_MAX and near 0: the clip at both ends */ \
        for( int d = 0; d < 3; d++ ) \
        { \
            for( int i = 0; i < 32*32; i++ ) \
                pbuf3[i] = pbuf4[i] = d == 0 ? pbuf1[i] : d == 1 ? PIXEL_MAX - (pbuf1[i]&3) : pbuf1[i]&3; \
            memcpy( dct1, src, 256 * sizeof(dctcoef) ); \
            memcpy( dct2, src, 256 * sizeof(dctcoef) ); \
            call_c1( dct_c.name, pbuf3, (void*)dct1 ); \
            call_a1( dct_asm.name, pbuf4, (void*)dct2 ); \
            if( memcmp( pbuf3, pbuf4, 32*32 * sizeof(pixel) ) ) \
            { \
                ok = 0; \
                fprintf( stderr, #name " dst %d [FAILED]\n", d ); \
            } \
        } \
        call_c2( dct_c.name, pbuf3, (void*)dct1 ); \
        call_a2( dct_asm.name, pbuf4, (void*)dct2 ); \
    }
    ok = 1; used_asm = 0;
    TEST_IDCT( add4x4_idct, dct4 );
    TEST_IDCT( add8x8_idct, dct4 );
    TEST_IDCT( add8x8_idct_dc, dct4 );
    TEST_IDCT( add16x16_idct, dct4 );
    TEST_IDCT( add16x16_idct_dc, dct4 );
    report( "add_idct4 :" );

    ok = 1; used_asm = 0;
    TEST_IDCT( add8x8_idct8, dct8 );
    TEST_IDCT( add16x16_idct8, dct8 );
    report( "add_idct8 :" );
#undef TEST_IDCT

#define TEST_DCTDC( name )\
    ok = 1; used_asm = 0;\
    if( dct_asm.name != dct_ref.name )\
    {\
        set_func_name( #name );\
        used_asm = 1;\
        uint16_t *p = (uint16_t*)buf1;\
        for( int i = 0; i < 16 && ok; i++ )\
        {\
            for( int j = 0; j < 16; j++ )\
                dct1[0][j] = !i ? (j^j>>1^j>>2^j>>3)&1 ? PIXEL_MAX*16 : -PIXEL_MAX*16 /* max dc */\
                           : i<8 ? (*p++)&1 ? PIXEL_MAX*16 : -PIXEL_MAX*16 /* max elements */\
                           : ((*p++)&0x1fff)-0x1000; /* general case */\
            memcpy( dct2, dct1, 16 * sizeof(dctcoef) );\
            call_c1( dct_c.name, dct1[0] );\
            call_a1( dct_asm.name, dct2[0] );\
            if( memcmp( dct1, dct2, 16 * sizeof(dctcoef) ) )\
                ok = 0;\
        }\
        call_c2( dct_c.name, dct1[0] );\
        call_a2( dct_asm.name, dct2[0] );\
    }\
    report( #name " :" );

    TEST_DCTDC(  dct4x4dc );
    TEST_DCTDC( idct4x4dc );
#undef TEST_DCTDC

#define TEST_DCTDC_CHROMA( name )\
    ok = 1; used_asm = 0;\
    if( dct_asm.name != dct_ref.name )\
    {\
        set_func_name( #name );\
        used_asm = 1;\
        uint16_t *p = (uint16_t*)buf1;\
        for( int i = 0; i < 16 && ok; i++ )\
        {\
            for( int j = 0; j < 8; j++ )\
                dct1[j][0] = !i ? (j^j>>1^j>>2)&1 ? PIXEL_MAX*16 : -PIXEL_MAX*16 /* max dc */\
                           : i<8 ? (*p++)&1 ? PIXEL_MAX*16 : -PIXEL_MAX*16 /* max elements */\
                           : ((*p++)&0x1fff)-0x1000; /* general case */\
            memcpy( dct2, dct1, 8*16 * sizeof(dctcoef) );\
            call_c1( dct_c.name, dctdc[0], dct1 );\
            call_a1( dct_asm.name, dctdc[1], dct2 );\
            if( memcmp( dctdc[0], dctdc[1], 8 * sizeof(dctcoef) ) || memcmp( dct1, dct2, 8*16 * sizeof(dctcoef) ) )\
            {\
                ok = 0;\
                fprintf( stderr, #name " [FAILED]\n" ); \
            }\
        }\
        call_c2( dct_c.name, dctdc[0], dct1 );\
        call_a2( dct_asm.name, dctdc[1], dct2 );\
    }\
    report( #name " :" );

    TEST_DCTDC_CHROMA( dct2x4dc );
#undef TEST_DCTDC_CHROMA

    x264_zigzag_function_t zigzag_c[2];
    x264_zigzag_function_t zigzag_ref[2];
    x264_zigzag_function_t zigzag_asm[2];

    ALIGNED_ARRAY_64( dctcoef, level1,[64] );
    ALIGNED_ARRAY_64( dctcoef, level2,[64] );
    ALIGNED_ARRAY_64( pixel, zsrc,[16*FENC_STRIDE] );

#define TEST_ZIGZAG_SCAN( name, t1, t2, dct, size ) \
    if( zigzag_asm[interlace].name != zigzag_ref[interlace].name ) \
    { \
        set_func_name( "zigzag_"#name"_%s", interlace?"field":"frame" ); \
        used_asm = 1; \
        /* distinct, both signs, the high bits of dctcoef set */ \
        for( int i = 0; i < size*size; i++ ) \
            dct[i] = (i&1 ? -1 : 1) * i * (sizeof(dctcoef) == 2 ? 509 : 0x10101); \
        call_c( zigzag_c[interlace].name, t1, dct ); \
        call_a( zigzag_asm[interlace].name, t2, dct ); \
        if( memcmp( t1, t2, size*size*sizeof(dctcoef) ) ) \
        { \
            ok = 0; \
            for( int i = 0; i < 2; i++ ) \
            { \
                dctcoef *d = (dctcoef*)(i ? t2 : t1); \
                for( int j = 0; j < size; j++ ) \
                { \
                    for( int k = 0; k < size; k++ ) \
                        fprintf( stderr, "%2d ", d[k+j*8] ); \
                    fprintf( stderr, "\n" ); \
                } \
                fprintf( stderr, "\n" ); \
            } \
            fprintf( stderr, #name " [FAILED]\n" ); \
        } \
    }

/* cases: random; dst == src (nz = 0); dst == src but one pixel; extremes
 * (src max, dst 0 and the reverse) */
#define TEST_ZIGZAG_SUB( name, t1, t2, size ) \
    if( zigzag_asm[interlace].name != zigzag_ref[interlace].name ) \
    { \
        int nz_a, nz_c, w = size == 16 ? 4 : 8; \
        set_func_name( "zigzag_"#name"_%s", interlace?"field":"frame" ); \
        used_asm = 1; \
        for( int i = 0; i < 6 && ok; i++ ) \
        { \
            memcpy( zsrc, pbuf2, 16*FENC_STRIDE * sizeof(pixel) ); \
            memcpy( pbuf3, pbuf1, 16*FDEC_STRIDE * sizeof(pixel) ); \
            for( int y = 0; y < w; y++ ) \
                for( int x = 0; x < w; x++ ) \
                { \
                    if( i == 1 || i == 2 || i == 3 ) \
                        pbuf3[y*FDEC_STRIDE+x] = zsrc[y*FENC_STRIDE+x]; \
                    else if( i == 4 ) \
                    { \
                        zsrc[y*FENC_STRIDE+x] = PIXEL_MAX; \
                        pbuf3[y*FDEC_STRIDE+x] = 0; \
                    } \
                    else if( i == 5 ) \
                    { \
                        zsrc[y*FENC_STRIDE+x] = 0; \
                        pbuf3[y*FDEC_STRIDE+x] = PIXEL_MAX; \
                    } \
                } \
            if( i == 2 ) \
                pbuf3[(w-1)*FDEC_STRIDE+w-1] ^= 1; \
            if( i == 3 ) \
                pbuf3[(rand()%w)*FDEC_STRIDE+rand()%w] ^= 1; \
            memcpy( pbuf4, pbuf3, 16*FDEC_STRIDE * sizeof(pixel) ); \
            nz_c = call_c1( zigzag_c[interlace].name, t1, zsrc, pbuf3 ); \
            nz_a = call_a1( zigzag_asm[interlace].name, t2, zsrc, pbuf4 ); \
            if( memcmp( t1, t2, size*sizeof(dctcoef) ) || memcmp( pbuf3, pbuf4, 16*FDEC_STRIDE*sizeof(pixel) ) || nz_c != nz_a ) \
            { \
                ok = 0; \
                fprintf( stderr, #name " [FAILED] case %d\n", i ); \
            } \
        } \
        call_c2( zigzag_c[interlace].name, t1, pbuf2, pbuf3 ); \
        call_a2( zigzag_asm[interlace].name, t2, pbuf2, pbuf4 ); \
    }

#define TEST_ZIGZAG_SUBAC( name, t1, t2 ) \
    if( zigzag_asm[interlace].name != zigzag_ref[interlace].name ) \
    { \
        int nz_a, nz_c; \
        dctcoef dc_a, dc_c; \
        set_func_name( "zigzag_"#name"_%s", interlace?"field":"frame" ); \
        used_asm = 1; \
        /* cases: dst == src; random; only the dc differs (nz = 0); src max, dst 0 */ \
        for( int i = 0; i < 4; i++ ) \
        { \
            memcpy( zsrc, pbuf2, 16*FENC_STRIDE * sizeof(pixel) ); \
            memcpy( pbuf3, pbuf2, 16*FDEC_STRIDE * sizeof(pixel) ); \
            for( int j = 0; j < 4; j++ ) \
            { \
                if( i == 3 ) \
                    for( int k = 0; k < 4; k++ ) \
                        zsrc[j*FENC_STRIDE+k] = PIXEL_MAX; \
                memcpy( pbuf3 + j*FDEC_STRIDE, (i==1?pbuf1:zsrc) + j*FENC_STRIDE, 4 * sizeof(pixel) ); \
                if( i == 3 ) \
                    memset( pbuf3 + j*FDEC_STRIDE, 0, 4 * sizeof(pixel) ); \
            } \
            if( i == 2 ) \
                pbuf3[0] ^= 1; \
            memcpy( pbuf4, pbuf3, 16*FDEC_STRIDE * sizeof(pixel) ); \
            nz_c = call_c1( zigzag_c[interlace].name, t1, zsrc, pbuf3, &dc_c ); \
            nz_a = call_a1( zigzag_asm[interlace].name, t2, zsrc, pbuf4, &dc_a ); \
            if( memcmp( t1, t2, 16*sizeof(dctcoef) ) || memcmp( pbuf3, pbuf4, 16*FDEC_STRIDE * sizeof(pixel) ) || nz_c != nz_a || dc_c != dc_a ) \
            { \
                ok = 0; \
                fprintf( stderr, #name " [FAILED] case %d\n", i ); \
                break; \
            } \
        } \
        call_c2( zigzag_c[interlace].name, t1, pbuf2, pbuf3, &dc_c ); \
        call_a2( zigzag_asm[interlace].name, t2, pbuf2, pbuf4, &dc_a ); \
    }

#define TEST_INTERLEAVE( name, t1, t2, dct, size ) \
    if( zigzag_asm[interlace].name != zigzag_ref[interlace].name ) \
    { \
        for( int j = 0; j < 100; j++ ) \
        { \
            set_func_name( "zigzag_"#name"_%s", interlace?"field":"frame" ); \
            used_asm = 1; \
            memcpy(dct, buf1, size*sizeof(dctcoef)); \
            for( int i = 0; i < size; i++ ) \
                dct[i] = rand()&0x1F ? 0 : dct[i]; \
            memcpy(buf3, buf4, 10); \
            call_c( zigzag_c[interlace].name, t1, dct, buf3 ); \
            call_a( zigzag_asm[interlace].name, t2, dct, buf4 ); \
            if( memcmp( t1, t2, size*sizeof(dctcoef) ) || memcmp( buf3, buf4, 10 ) ) \
            { \
                ok = 0; printf("%d: %d %d %d %d\n%d %d %d %d\n\n",memcmp( t1, t2, size*sizeof(dctcoef) ),buf3[0], buf3[1], buf3[8], buf3[9], buf4[0], buf4[1], buf4[8], buf4[9]);break;\
            } \
        } \
    }

    x264_zigzag_init( 0, &zigzag_c[0], &zigzag_c[1] );
    x264_zigzag_init( cpu_ref, &zigzag_ref[0], &zigzag_ref[1] );
    x264_zigzag_init( cpu_new, &zigzag_asm[0], &zigzag_asm[1] );

    ok = 1; used_asm = 0;
    TEST_INTERLEAVE( interleave_8x8_cavlc, level1, level2, dct8[0], 64 );
    report( "zigzag_interleave :" );

    for( interlace = 0; interlace <= 1; interlace++ )
    {
        ok = 1; used_asm = 0;
        TEST_ZIGZAG_SCAN( scan_8x8, level1, level2, dct8[0], 8 );
        TEST_ZIGZAG_SCAN( scan_4x4, level1, level2, dct1[0], 4 );
        TEST_ZIGZAG_SUB( sub_4x4, level1, level2, 16 );
        TEST_ZIGZAG_SUB( sub_8x8, level1, level2, 64 );
        TEST_ZIGZAG_SUBAC( sub_4x4ac, level1, level2 );
        report( interlace ? "zigzag_field :" : "zigzag_frame :" );
    }
#undef TEST_ZIGZAG_SCAN
#undef TEST_ZIGZAG_SUB

    return ret;
}

/* weight_plane references: the area x264_weight_scale_plane's strips write
 * (width up to a multiple of 8, height up to even), in C w8 columns, and the
 * strips themselves with the asm kernels of the weight (benchmark only) */
static weight_fn_t *wp_c_wtab;
static void weight_plane_c( pixel *dst, intptr_t i_dst, pixel *src, intptr_t i_src,
                            const x264_weight_t *w, int width, int height )
{
    for( int x = 0; x < width; x += 8 )
        wp_c_wtab[8>>2]( dst+x, i_dst, src+x, i_src, w, (height+1)&~1 );
}

static void weight_plane_strips( pixel *dst, intptr_t i_dst, pixel *src, intptr_t i_src,
                                 const x264_weight_t *w, int width, int height )
{
    for( ; height > 0; height -= 16, dst += 16*i_dst, src += 16*i_src )
    {
        int x;
        for( x = 0; x < width-8; x += 16 )
            w->weightfn[16>>2]( dst+x, i_dst, src+x, i_src, w, X264_MIN( height, 16 ) );
        if( x < width )
            w->weightfn[8>>2]( dst+x, i_dst, src+x, i_src, w, X264_MIN( height, 16 ) );
    }
}

static int check_mc( int cpu_ref, int cpu_new )
{
    x264_mc_functions_t mc_c;
    x264_mc_functions_t mc_ref;
    x264_mc_functions_t mc_a;
    x264_pixel_function_t pixf;

    pixel *src     = &(pbuf1)[2*64+2];
    pixel *src2[4] = { &(pbuf1)[3*64+2], &(pbuf1)[5*64+2],
                       &(pbuf1)[7*64+2], &(pbuf1)[9*64+2] };
    pixel *dst1    = pbuf3;
    pixel *dst2    = pbuf4;

    int ret = 0, ok, used_asm;

    x264_mc_init( 0, &mc_c, 0 );
    x264_mc_init( cpu_ref, &mc_ref, 0 );
    x264_mc_init( cpu_new, &mc_a, 0 );
    x264_pixel_init( 0, &pixf );

#define MC_TEST_LUMA( w, h ) \
        if( mc_a.mc_luma != mc_ref.mc_luma && !(w&(w-1)) && h<=16 ) \
        { \
            const x264_weight_t *weight = x264_weight_none; \
            set_func_name( "mc_luma_%dx%d", w, h ); \
            used_asm = 1; \
            for( int i = 0; i < 1024; i++ ) \
                pbuf3[i] = pbuf4[i] = 0xCD; \
            call_c1( mc_c.mc_luma, dst1, (intptr_t)32, src2, (intptr_t)64, dx, dy, w, h, weight ); \
            call_a1( mc_a.mc_luma, dst2, (intptr_t)32, src2, (intptr_t)64, dx, dy, w, h, weight ); \
            if( memcmp( pbuf3, pbuf4, 1024 * sizeof(pixel) ) ) \
            { \
                fprintf( stderr, "mc_luma[mv(%d,%d) %2dx%-2d]     [FAILED]\n", dx, dy, w, h ); \
                ok = 0; \
            } \
        } \
        if( mc_a.get_ref != mc_ref.get_ref ) \
        { \
            pixel *ref = dst2; \
            intptr_t ref_stride = 32; \
            int w_checked = ( ( sizeof(pixel) == 2 && (w == 12 || w == 20)) ? w-2 : w ); \
            const x264_weight_t *weight = x264_weight_none; \
            set_func_name( "get_ref_%dx%d", w_checked, h ); \
            used_asm = 1; \
            for( int i = 0; i < 1024; i++ ) \
                pbuf3[i] = pbuf4[i] = 0xCD; \
            call_c1( mc_c.mc_luma, dst1, (intptr_t)32, src2, (intptr_t)64, dx, dy, w, h, weight ); \
            ref = (pixel*)call_a1( mc_a.get_ref, ref, &ref_stride, src2, (intptr_t)64, dx, dy, w, h, weight ); \
            for( int i = 0; i < h; i++ ) \
                if( memcmp( dst1+i*32, ref+i*ref_stride, w_checked * sizeof(pixel) ) ) \
                { \
                    fprintf( stderr, "get_ref[mv(%d,%d) %2dx%-2d]     [FAILED]\n", dx, dy, w_checked, h ); \
                    ok = 0; \
                    break; \
                } \
        }

#define MC_TEST_CHROMA( w, h ) \
        if( mc_a.mc_chroma != mc_ref.mc_chroma ) \
        { \
            set_func_name( "mc_chroma_%dx%d", w, h ); \
            used_asm = 1; \
            for( int i = 0; i < 1024; i++ ) \
                pbuf3[i] = pbuf4[i] = 0xCD; \
            call_c1( mc_c.mc_chroma, dst1, dst1+8, (intptr_t)16, src, (intptr_t)64, dx, dy, w, h ); \
            call_a1( mc_a.mc_chroma, dst2, dst2+8, (intptr_t)16, src, (intptr_t)64, dx, dy, w, h ); \
            /* mc_chroma width=2 may write garbage to the right of dst. ignore that. */ \
            for( int j = 0; j < h; j++ ) \
                for( int i = w; i < 8; i++ ) \
                { \
                    dst2[i+j*16+8] = dst1[i+j*16+8]; \
                    dst2[i+j*16  ] = dst1[i+j*16  ]; \
                } \
            if( memcmp( pbuf3, pbuf4, 1024 * sizeof(pixel) ) ) \
            { \
                fprintf( stderr, "mc_chroma[mv(%d,%d) %2dx%-2d]     [FAILED]\n", dx, dy, w, h ); \
                ok = 0; \
            } \
        }
    ok = 1; used_asm = 0;
    for( int dy = -8; dy < 8; dy++ )
        for( int dx = -128; dx < 128; dx++ )
        {
            if( rand()&15 ) continue; // running all of them is too slow
            MC_TEST_LUMA( 20, 18 );
            MC_TEST_LUMA( 16, 16 );
            MC_TEST_LUMA( 16, 8 );
            MC_TEST_LUMA( 12, 10 );
            MC_TEST_LUMA( 8, 16 );
            MC_TEST_LUMA( 8, 8 );
            MC_TEST_LUMA( 8, 4 );
            MC_TEST_LUMA( 4, 8 );
            MC_TEST_LUMA( 4, 4 );
        }
    /* bench: 64-byte aligned planes of stride 64, one mv per class: fullpel
     * (copy), qpel (1,0), qpel3 (3,0: src2 one pixel on), diag (1,1); the
     * sizes of MC and of get_ref (bw x bh, bw x bh+1, bw+4 x bh) */
    {
        ALIGNED_ARRAY_64( pixel, lb_src, [4*64*24] );
        pixel *lb_ref[4] = { lb_src, lb_src+64*24, lb_src+2*64*24, lb_src+3*64*24 };
        static const int8_t lb_mv[4][2] = { {0,0}, {1,0}, {3,0}, {1,1} };
        static const char *lb_name[4] = { "fullpel", "qpel", "qpel3", "diag" };
        static const int8_t lb_size[19][2] = { {16,16}, {16,8}, {8,16}, {8,8}, {8,4}, {4,8}, {4,4},
                                               {16,17}, {16,9}, {8,17}, {8,9}, {8,5}, {4,9}, {4,5},
                                               {20,16}, {20,8}, {12,16}, {12,8}, {12,4} };
        memcpy( lb_src, pbuf1, 4*64*24*sizeof(pixel) );
        for( int k = 0; k < 4; k++ )
            for( int j = 0; j < 19; j++ )
            {
                int w = lb_size[j][0], h = lb_size[j][1], dx = lb_mv[k][0], dy = lb_mv[k][1];
                const x264_weight_t *weight = x264_weight_none;
                if( mc_a.mc_luma != mc_ref.mc_luma && j < 7 )
                {
                    set_func_name( "mc_luma_%s_%dx%d", lb_name[k], w, h );
                    call_c2( mc_c.mc_luma, dst1, (intptr_t)32, lb_ref, (intptr_t)64, dx, dy, w, h, weight );
                    call_a2( mc_a.mc_luma, dst2, (intptr_t)32, lb_ref, (intptr_t)64, dx, dy, w, h, weight );
                }
                /* fullpel and hpel get_ref return a plane pointer */
                if( mc_a.get_ref != mc_ref.get_ref && k )
                {
                    intptr_t ref_stride = 64;
                    set_func_name( "get_ref_%s_%dx%d", lb_name[k], w, h );
                    call_c2( mc_c.mc_luma, dst1, (intptr_t)64, lb_ref, (intptr_t)64, dx, dy, w, h, weight );
                    call_a2( mc_a.get_ref, dst2, &ref_stride, lb_ref, (intptr_t)64, dx, dy, w, h, weight );
                }
            }
    }
    report( "mc luma :" );

    /* weighted luma MC: mc_luma and get_ref with a weight against C at every
     * qpel fraction, the sizes of MC and of the subpel ME (bw+4 x bh, bw x bh+1);
     * the weights cover each kernel x264_weight_cache picks: weight, ns
     * (scale < 1<<denom), offsetadd, offsetsub, the SSE2 fallback (high bit
     * depth: scale<<(BIT_DEPTH-denom) > 0x7fff, scale < 0), the 8-bit fast path */
    static const int16_t luma_w[][3] = /* scale, denom, offset */
    {
        { 45, 5, 5 }, { 127, 7, -128 }, { 33, 5, 127 }, { 31, 5, -1 }, { 20, 5, 7 }, { 1, 7, -1 },
        { 0, 3, -128 }, { 32, 5, 9 }, { 1, 0, 127 }, { 4, 2, 0 }, { 1, 0, -9 }, { 16, 4, -128 },
        { 31, 0, -3 }, { 32, 0, 3 }, { 127, 0, 127 }, { 2, 0, -128 }, { -5, 3, 10 }, { -128, 7, 127 },
    };
    x264_t *hlc = x264_malloc( sizeof(x264_t) );
    x264_t *hla = x264_malloc( sizeof(x264_t) );
    if( !hlc || !hla )
        return -1;
    hlc->mc = mc_c;
    hla->mc = mc_a;
    int luma_w_new = mc_a.mc_luma != mc_ref.mc_luma || mc_a.get_ref != mc_ref.get_ref ||
                     mc_a.weight_cache != mc_ref.weight_cache || mc_a.weight != mc_ref.weight ||
                     mc_a.offsetadd != mc_ref.offsetadd || mc_a.offsetsub != mc_ref.offsetsub;
#define MC_TEST_LUMA_W( w, h ) \
        if( !(w&(w-1)) && h<=16 && !(h&1) ) \
        { \
            set_func_name( "mc_luma_w_%dx%d", w, h ); \
            for( int i = 0; i < 1024; i++ ) \
                pbuf3[i] = pbuf4[i] = 0xCD; \
            call_c1( mc_c.mc_luma, dst1, (intptr_t)32, src2, (intptr_t)64, dx, dy, w, h, &wc ); \
            call_a1( mc_a.mc_luma, dst2, (intptr_t)32, src2, (intptr_t)64, dx, dy, w, h, &wa ); \
            if( memcmp( pbuf3, pbuf4, 1024 * sizeof(pixel) ) ) \
            { \
                fprintf( stderr, "mc_luma[mv(%d,%d) %2dx%-2d] s:%d d:%d o:%d [FAILED]\n", dx, dy, w, h, \
                         wc.i_scale, wc.i_denom, wc.i_offset ); \
                ok = 0; \
            } \
        } \
        { \
            pixel *ref = dst2; \
            intptr_t ref_stride = 32; \
            int w_checked = ( ( sizeof(pixel) == 2 && (w == 12 || w == 20)) ? w-2 : w ); \
            set_func_name( "get_ref_w_%dx%d", w_checked, h ); \
            for( int i = 0; i < 1024; i++ ) \
                pbuf3[i] = pbuf4[i] = 0xCD; \
            call_c1( mc_c.mc_luma, dst1, (intptr_t)32, src2, (intptr_t)64, dx, dy, w, h, &wc ); \
            ref = (pixel*)call_a1( mc_a.get_ref, ref, &ref_stride, src2, (intptr_t)64, dx, dy, w, h, &wa ); \
            for( int i = 0; i < h; i++ ) \
                if( memcmp( dst1+i*32, ref+i*ref_stride, w_checked * sizeof(pixel) ) ) \
                { \
                    fprintf( stderr, "get_ref[mv(%d,%d) %2dx%-2d] s:%d d:%d o:%d [FAILED]\n", dx, dy, w_checked, h, \
                             wc.i_scale, wc.i_denom, wc.i_offset ); \
                    ok = 0; \
                    break; \
                } \
        }
    ok = 1; used_asm = 0;
    if( luma_w_new )
    {
        used_asm = 1;
        int wi = 0;
        for( int dy = -8; dy < 8; dy++ )
            for( int dx = -128; dx < 128; dx++ )
            {
                if( rand()&15 ) continue;
                if( !HIGH_BIT_DEPTH && luma_w[wi][0] < 0 )
                    wi = 0;
                x264_weight_t wc = { .i_scale = luma_w[wi][0], .i_denom = luma_w[wi][1], .i_offset = luma_w[wi][2] };
                x264_weight_t wa = wc;
                wi = (wi + 1) % ARRAY_ELEMS(luma_w);
                mc_c.weight_cache( hlc, &wc );
                mc_a.weight_cache( hla, &wa );
                MC_TEST_LUMA_W( 20, 16 );
                MC_TEST_LUMA_W( 20, 8 );
                MC_TEST_LUMA_W( 16, 17 );
                MC_TEST_LUMA_W( 16, 16 );
                MC_TEST_LUMA_W( 16, 9 );
                MC_TEST_LUMA_W( 16, 8 );
                MC_TEST_LUMA_W( 12, 16 );
                MC_TEST_LUMA_W( 12, 8 );
                MC_TEST_LUMA_W( 12, 4 );
                MC_TEST_LUMA_W( 8, 17 );
                MC_TEST_LUMA_W( 8, 16 );
                MC_TEST_LUMA_W( 8, 9 );
                MC_TEST_LUMA_W( 8, 8 );
                MC_TEST_LUMA_W( 8, 5 );
                MC_TEST_LUMA_W( 8, 4 );
                MC_TEST_LUMA_W( 4, 9 );
                MC_TEST_LUMA_W( 4, 8 );
                MC_TEST_LUMA_W( 4, 5 );
                MC_TEST_LUMA_W( 4, 4 );
            }
        /* benchmark: get_ref at a qpel mv (a two-plane average), per weight kind */
        static const int16_t bench_w[4][3] = { { 45, 5, 5 }, { 20, 5, 7 }, { 32, 5, 9 }, { 32, 5, -9 } };
        static const char *bench_name[4] = { "weight", "weight_ns", "offsetadd", "offsetsub" };
        static const int8_t bench_size[8][2] = { {16,16}, {16,17}, {20,16}, {8,8}, {8,9}, {12,8}, {4,4}, {4,5} };
        for( int k = 0; k < 4; k++ )
        {
            x264_weight_t wc = { .i_scale = bench_w[k][0], .i_denom = bench_w[k][1], .i_offset = bench_w[k][2] };
            x264_weight_t wa = wc;
            mc_c.weight_cache( hlc, &wc );
            mc_a.weight_cache( hla, &wa );
            for( int j = 0; j < 8; j++ )
            {
                int w = bench_size[j][0], h = bench_size[j][1];
                intptr_t ref_stride = 64;
                set_func_name( "get_ref_%s_%dx%d", bench_name[k], w, h );
                call_c2( mc_c.mc_luma, dst1, (intptr_t)64, src2, (intptr_t)64, 1, 3, w, h, &wc );
                call_a2( mc_a.get_ref, dst2, &ref_stride, src2, (intptr_t)64, 1, 3, w, h, &wa );
            }
        }
    }
    x264_free( hlc );
    x264_free( hla );
    report( "mc luma weighted :" );
#undef MC_TEST_LUMA_W

    ok = 1; used_asm = 0;
    for( int dy = -1; dy < 9; dy++ )
        for( int dx = -128; dx < 128; dx++ )
        {
            if( rand()&15 ) continue;
            MC_TEST_CHROMA( 8, 8 );
            MC_TEST_CHROMA( 8, 4 );
            MC_TEST_CHROMA( 4, 8 );
            MC_TEST_CHROMA( 4, 4 );
            MC_TEST_CHROMA( 4, 2 );
            MC_TEST_CHROMA( 2, 4 );
            MC_TEST_CHROMA( 2, 2 );
        }
    /* bench: a 64-byte aligned interleaved plane of stride 64, one mv (1/8 pel)
     * per class: full (0,0), h (4,0), v (0,4), hv (3,5); the 4:2:0 and 4:2:2 sizes */
    if( mc_a.mc_chroma != mc_ref.mc_chroma )
    {
        ALIGNED_ARRAY_64( pixel, cb_src, [64*20] );
        static const int8_t cb_mv[4][2] = { {0,0}, {4,0}, {0,4}, {3,5} };
        static const char *cb_name[4] = { "full", "h", "v", "hv" };
        static const int8_t cb_size[10][2] = { {8,16}, {8,8}, {8,4}, {4,16}, {4,8}, {4,4}, {4,2}, {2,8}, {2,4}, {2,2} };
        memcpy( cb_src, pbuf1, 64*20*sizeof(pixel) );
        for( int k = 0; k < 4; k++ )
            for( int j = 0; j < 10; j++ )
            {
                int w = cb_size[j][0], h = cb_size[j][1], dx = cb_mv[k][0], dy = cb_mv[k][1];
                set_func_name( "mc_chroma_%s_%dx%d", cb_name[k], w, h );
                call_c2( mc_c.mc_chroma, dst1, dst1+8, (intptr_t)16, cb_src, (intptr_t)64, dx, dy, w, h );
                call_a2( mc_a.mc_chroma, dst2, dst2+8, (intptr_t)16, cb_src, (intptr_t)64, dx, dy, w, h );
            }
    }
    report( "mc chroma :" );
#undef MC_TEST_LUMA
#undef MC_TEST_CHROMA

#define MC_TEST_AVG( name, weight ) \
{ \
    for( int i = 0; i < 12; i++ ) \
    { \
        memcpy( pbuf3, pbuf1+320, 320 * sizeof(pixel) ); \
        memcpy( pbuf4, pbuf1+320, 320 * sizeof(pixel) ); \
        if( mc_a.name[i] != mc_ref.name[i] ) \
        { \
            set_func_name( "%s_%s", #name, pixel_names[i] ); \
            used_asm = 1; \
            call_c1( mc_c.name[i], pbuf3, (intptr_t)16, pbuf2+1, (intptr_t)16, pbuf1+18, (intptr_t)16, weight ); \
            call_a1( mc_a.name[i], pbuf4, (intptr_t)16, pbuf2+1, (intptr_t)16, pbuf1+18, (intptr_t)16, weight ); \
            if( memcmp( pbuf3, pbuf4, 320 * sizeof(pixel) ) ) \
            { \
                ok = 0; \
                fprintf( stderr, #name "[%d]: [FAILED]\n", i ); \
            } \
            call_c2( mc_c.name[i], pbuf3, (intptr_t)16, pbuf2+1, (intptr_t)16, pbuf1+18, (intptr_t)16, weight ); \
            call_a2( mc_a.name[i], pbuf4, (intptr_t)16, pbuf2+1, (intptr_t)16, pbuf1+18, (intptr_t)16, weight ); \
        } \
    } \
}

    ok = 1, used_asm = 0;
    for( int w = -63; w <= 127 && ok; w++ )
        MC_TEST_AVG( avg, w );
    report( "mc wpredb :" );

    /* copy[16x16] (aligned), copy[8x8], copy[4x4] (height 4 or 8), copy_16x16_unaligned: every
     * height the encoder uses, src aligned and not, nothing written past w x h */
    ok = 1, used_asm = 0;
    for( int i = 0; i < 4; i++ )
    {
        static const int copy_idx[3] = { PIXEL_16x16, PIXEL_8x8, PIXEL_4x4 };
        void (*fc)( pixel *, intptr_t, pixel *, intptr_t, int ) = i < 3 ? mc_c.copy[copy_idx[i]] : mc_c.copy_16x16_unaligned;
        void (*fa)( pixel *, intptr_t, pixel *, intptr_t, int ) = i < 3 ? mc_a.copy[copy_idx[i]] : mc_a.copy_16x16_unaligned;
        void (*fr)( pixel *, intptr_t, pixel *, intptr_t, int ) = i < 3 ? mc_ref.copy[copy_idx[i]] : mc_ref.copy_16x16_unaligned;
        int w = i == 1 ? 8 : i == 2 ? 4 : 16;
        if( fa == fr )
            continue;
        used_asm = 1;
        set_func_name( i < 3 ? "mc_copy_w%d" : "mc_copy_w%d_unaligned", w );
        for( int hgt = 4; hgt <= (w == 4 ? 8 : 16) && ok; hgt <<= 1 )
            for( int a = 0; a < (i ? 16 : 1) && ok; a++ )
            {
                pixel *src = pbuf1 + 64 + a;
                for( int k = 0; k < 1024; k++ )
                    pbuf3[k] = pbuf4[k] = 0xCD;
                call_c1( fc, pbuf3, (intptr_t)32, src, (intptr_t)64, hgt );
                call_a1( fa, pbuf4, (intptr_t)32, src, (intptr_t)64, hgt );
                if( memcmp( pbuf3, pbuf4, 1024 * sizeof(pixel) ) )
                {
                    ok = 0;
                    fprintf( stderr, "mc_copy_w%d%s h %d src +%d [FAILED]\n", w, i < 3 ? "" : "_unaligned", hgt, a );
                }
            }
        call_c2( fc, pbuf3, (intptr_t)32, pbuf1+64, (intptr_t)64, w == 4 ? 8 : 16 );
        call_a2( fa, pbuf4, (intptr_t)32, pbuf1+64, (intptr_t)64, w == 4 ? 8 : 16 );
    }
    report( "mc copy :" );

    /* bench weights, one per kernel x264_weight_cache picks: scale > 1<<denom,
     * scale < 1<<denom (8-bit: the cachea < 256 path), offset > 0, offset < 0 */
    static const int16_t wbench[4][3] = { { 72, 6, 4 }, { 56, 6, -4 }, { 64, 6, 8 }, { 64, 6, -8 } };
    static const char *wbench_name[4] = { "weight", "weight_ns", "offsetadd", "offsetsub" };

#define MC_TEST_WEIGHT( name, weight, aligned, src, height ) \
    int align_off = (aligned ? 0 : rand()%16); \
    for( int i = 1; i <= 5; i++ ) \
    { \
        ALIGNED_ARRAY_64( pixel, buffC, [640] ); \
        ALIGNED_ARRAY_64( pixel, buffA, [640] ); \
        int j = X264_MAX( i*4, 2 ); \
        memset( buffC, 0, 640 * sizeof(pixel) ); \
        memset( buffA, 0, 640 * sizeof(pixel) ); \
        x264_t ha; \
        ha.mc = mc_a; \
        /* w12 is the same as w16 in some cases */ \
        if( i == 3 && mc_a.name[i] == mc_a.name[i+1] ) \
            continue; \
        if( mc_a.name[i] != mc_ref.name[i] ) \
        { \
            set_func_name( "%s_w%d", #name, j ); \
            used_asm = 1; \
            call_c1( mc_c.weight[i],     buffC, (intptr_t)32, src+align_off, (intptr_t)32, &weight, height ); \
            mc_a.weight_cache(&ha, &weight); \
            call_a1( weight.weightfn[i], buffA, (intptr_t)32, src+align_off, (intptr_t)32, &weight, height ); \
            /* all 16 rows of 32: nothing written past the width or the height */ \
            if( memcmp( buffC, buffA, 16*32*sizeof(pixel) ) ) \
            { \
                ok = 0; \
                fprintf( stderr, #name "[%d]: [FAILED] s:%d o:%d d:%d h:%d\n", i, s, o, d, height ); \
            } \
        } \
    }

    /* weight sources: pbuf2, and one dense in 0, 1, PIXEL_MAX-1 and PIXEL_MAX */
    ALIGNED_ARRAY_64( pixel, wsrc_ext, [16*32+64] );
    for( int i = 0; i < 16*32+64; i++ )
    {
        int r = rand();
        wsrc_ext[i] = r&8 ? -(r&1) & PIXEL_MAX : r&4 ? (r&1 ? PIXEL_MAX-1 : 1) : rand() & PIXEL_MAX;
    }
    pixel *wsrc[2] = { pbuf2, wsrc_ext };
    static const int wheight[4] = { 16, 8, 4, 2 };

    ok = 1; used_asm = 0;

    int align_cnt = 0;
    for( int s = HIGH_BIT_DEPTH ? -128 : 0; s <= 127 && ok; s++ )
    {
        for( int o = -128; o <= 127 && ok; o++ )
        {
            for( int d = 0; d <= 7 && ok; d++ )
            {
                if( s == 1<<d )
                    continue;
                /* edges of the asm ranges: s next to 1<<d and 32<<d, extreme offsets */
                int edge = (s == 0 || s == -1 || s == -128 || s == 127 || s == (1<<d)-1 || s == (1<<d)+1 ||
                            s == (32<<d)-1 || s == 32<<d) && (o == -128 || o == -1 || o == 0 || o == 127);
                if( !edge && (rand() & 2047) )
                    continue;
                for( int k = 0; k < 8 && ok; k++ )
                {
                    x264_weight_t weight = { .i_scale = s, .i_denom = d, .i_offset = o };
                    MC_TEST_WEIGHT( weight, weight, (align_cnt++ % 4), wsrc[k&1], wheight[k>>1] );
                }
            }
        }
    }
    report( "mc weight :" );

    ok = 1; used_asm = 0;
    for( int o = 0; o <= 127 && ok; o++ )
    {
        int s = 1, d = 0;
        if( o != 0 && o != 1 && o != 127 && (rand() & 15) ) continue;
        for( int k = 0; k < 8 && ok; k++ )
        {
            x264_weight_t weight = { .i_scale = 1, .i_denom = 0, .i_offset = o };
            MC_TEST_WEIGHT( offsetadd, weight, (align_cnt++ % 4), wsrc[k&1], wheight[k>>1] );
        }
    }
    report( "mc offsetadd :" );
    ok = 1; used_asm = 0;
    for( int o = -128; o < 0 && ok; o++ )
    {
        int s = 1, d = 0;
        if( o != -128 && o != -1 && (rand() & 15) ) continue;
        for( int k = 0; k < 8 && ok; k++ )
        {
            x264_weight_t weight = { .i_scale = 1, .i_denom = 0, .i_offset = o };
            MC_TEST_WEIGHT( offsetsub, weight, (align_cnt++ % 4), wsrc[k&1], wheight[k>>1] );
        }
    }
    report( "mc offsetsub :" );

    /* bench: the weightfn x264_weight_cache picks per kind, aligned, 16 rows */
    {
        ALIGNED_ARRAY_64( pixel, wb_c, [16*32] );
        ALIGNED_ARRAY_64( pixel, wb_a, [16*32] );
        x264_t *hwa = x264_malloc( sizeof(x264_t) );
        x264_t *hwr = x264_malloc( sizeof(x264_t) );
        if( !hwa || !hwr )
            return -1;
        hwa->mc = mc_a;
        hwr->mc = mc_ref;
        for( int k = 0; k < 4; k++ )
        {
            x264_weight_t wa = { .i_scale = wbench[k][0], .i_denom = wbench[k][1], .i_offset = wbench[k][2] };
            x264_weight_t wr = wa;
            mc_a.weight_cache( hwa, &wa );
            mc_ref.weight_cache( hwr, &wr );
            for( int i = 1; i <= 5; i++ )
            {
                if( (i == 3 && wa.weightfn[3] == wa.weightfn[4]) || wa.weightfn[i] == wr.weightfn[i] )
                    continue;
                set_func_name( "%s_w%d", wbench_name[k], i*4 );
                call_c2( mc_c.weight[i], wb_c, (intptr_t)32, pbuf2, (intptr_t)32, &wa, 16 );
                call_a2( wa.weightfn[i], wb_a, (intptr_t)32, pbuf2, (intptr_t)32, &wa, 16 );
            }
        }
        x264_free( hwa );
        x264_free( hwr );
    }

    /* weightavgfn against C: (src1+src2+1)>>1, then mc_c.weight. Every width,
     * the subpel ME's odd heights, unaligned sources and destination, edge
     * weights (each kernel x264_weight_cache picks, the edges of the SSE2
     * fallback and of the 8-bit fast path), and nothing written past the
     * w (8-bit w12: 16) x even-height area of 32-stride rows */
    ok = 1; used_asm = 0;
    {
        enum { WA_SS = 64, WA_DS = 32, WA_SRC = WA_SS*20+64, WA_DST = WA_DS*20+64 };
        ALIGNED_ARRAY_64( pixel, wa_src, [2], [WA_SRC] );
        ALIGNED_ARRAY_64( pixel, wa_avg, [WA_DST] );
        ALIGNED_ARRAY_64( pixel, wa_c, [WA_DST] );
        ALIGNED_ARRAY_64( pixel, wa_a, [WA_DST] );
        static const int wa_h[] = { 2, 4, 5, 8, 9, 16, 17 };
        x264_t *hwa = x264_malloc( sizeof(x264_t) );
        x264_t *hwr = x264_malloc( sizeof(x264_t) );
        if( !hwa || !hwr )
            return -1;
        hwa->mc = mc_a;
        hwr->mc = mc_ref;
        for( int j = 0; j < 2; j++ )
            for( int i = 0; i < WA_SRC; i++ )
            {
                int r = rand();
                wa_src[j][i] = r&8 ? -(r&1) & PIXEL_MAX : r&4 ? (r&1 ? PIXEL_MAX-1 : 1) : rand() & PIXEL_MAX;
            }
        for( int s = HIGH_BIT_DEPTH ? -128 : 0; s <= 127 && ok; s++ )
            for( int o = -128; o <= 127 && ok; o++ )
                for( int d = 0; d <= 7 && ok; d++ )
                {
                    int edge = (s == 0 || s == -1 || s == -128 || s == 127 || s == (1<<d)-1 || s == 1<<d || s == (1<<d)+1 ||
                                s == (32<<d)-1 || s == 32<<d || s == 0x7fff >> (BIT_DEPTH-d) || s == (0x7fff >> (BIT_DEPTH-d))+1) &&
                               (o == -128 || o == -1 || o == 0 || o == 1 || o == 127);
                    if( !edge && (rand() & 1023) )
                        continue;
                    x264_weight_t wa = { .i_scale = s, .i_denom = d, .i_offset = o };
                    x264_weight_t wr = wa;
                    mc_a.weight_cache( hwa, &wa );
                    mc_ref.weight_cache( hwr, &wr );
                    if( !wa.weightavgfn || wa.weightavgfn == wr.weightavgfn )
                        continue;
                    used_asm = 1;
                    int kind = s == 1<<d ? 1 + (o < 0) : 0;
                    for( int i = 1; i <= 5 && ok; i++ )
                        for( int hi = 0; hi < ARRAY_ELEMS(wa_h) && ok; hi++ )
                        {
                            int w = X264_MAX( i*4, 4 );
                            int fw = !HIGH_BIT_DEPTH && w == 12 ? 16 : w;
                            int h = wa_h[hi];
                            int rows = (h+1)&~1;
                            pixel *s1 = wa_src[0] + (rand()&15) + (rand()&1)*WA_SS;
                            pixel *s2 = wa_src[1] + (rand()&15) + (rand()&1)*WA_SS;
                            int doff = WA_DS + (rand()&1 ? rand()&7 : 0);
                            for( int k = 0; k < WA_DST; k++ )
                                wa_c[k] = wa_a[k] = rand() & PIXEL_MAX;
                            for( int y = 0; y < rows; y++ )
                                for( int x = 0; x < fw; x++ )
                                    wa_avg[y*WA_DS+x] = (s1[y*WA_SS+x] + s2[y*WA_SS+x] + 1) >> 1;
                            mc_c.weight[fw>>2]( wa_c+doff, WA_DS, wa_avg, WA_DS, &wa, rows );
                            set_func_name( "%s_avg_w%d", kind == 0 ? "weight" : kind == 1 ? "offsetadd" : "offsetsub", w );
                            call_a1( wa.weightavgfn[i], wa_a+doff, (intptr_t)WA_DS, s1, (intptr_t)WA_SS, &wa, h, s2 );
                            if( memcmp( wa_c, wa_a, WA_DST*sizeof(pixel) ) )
                            {
                                ok = 0;
                                fprintf( stderr, "weightavgfn[%d] [FAILED] s:%d o:%d d:%d h:%d doff:%d\n", i, s, o, d, h, doff );
                            }
                        }
                }
        /* bench: src1 and dst 64-byte aligned, src2 one pixel on (mvx&3 == 3) */
        for( int k = 0; k < 4; k++ )
        {
            x264_weight_t wa = { .i_scale = wbench[k][0], .i_denom = wbench[k][1], .i_offset = wbench[k][2] };
            x264_weight_t wr = wa;
            mc_a.weight_cache( hwa, &wa );
            mc_ref.weight_cache( hwr, &wr );
            if( !wa.weightavgfn )
                continue;
            for( int i = 1; i <= 5; i++ )
            {
                if( (i == 3 && wa.weightavgfn[3] == wa.weightavgfn[4]) ||
                    (wr.weightavgfn && wa.weightavgfn[i] == wr.weightavgfn[i]) )
                    continue;
                set_func_name( "%s_avg_w%d", wbench_name[k], i*4 );
                call_a2( wa.weightavgfn[i], wa_a+2*WA_DS, (intptr_t)WA_DS, wa_src[0], (intptr_t)WA_SS, &wa, 16, wa_src[1]+1 );
            }
        }
        x264_free( hwa );
        x264_free( hwr );
    }
    report( "mc weight_avg :" );

    ok = 1; used_asm = 0;
    if( mc_a.weight_plane != mc_ref.weight_plane )
    {
        /* every register/tail split of a row, odd heights, the 1080p luma and
         * lowres rows; edge scales, extreme pixels, guards around the area */
        enum { WP_STRIDE = 2048+64, WP_ROWS = 20 };
        static const int wp_w[] = { 1, 7, 8, 9, 16, 24, 32, 40, 48, 56, 64, 72, 80, 88, 96, 104, 120, 136, 1024, 1984 };
        static const int wp_h[] = { 1, 2, 3, 16, 17 };
        pixel *wp_src = x264_malloc( WP_STRIDE*WP_ROWS*sizeof(pixel) );
        pixel *wp_c = x264_malloc( WP_STRIDE*WP_ROWS*sizeof(pixel) );
        pixel *wp_a = x264_malloc( WP_STRIDE*WP_ROWS*sizeof(pixel) );
        x264_t ha;
        ha.mc = mc_a;
        wp_c_wtab = mc_c.weight;
        used_asm = 1;
        ok = wp_src && wp_c && wp_a;
        for( int i = 0; ok && i < WP_STRIDE*WP_ROWS; i++ )
        {
            int r = rand();
            wp_src[i] = r&8 ? -(r&1) & PIXEL_MAX : r&4 ? (r&1 ? PIXEL_MAX-1 : 1) : rand() & PIXEL_MAX;
        }
        for( int i = 0; ok && i < WP_STRIDE*WP_ROWS; i++ )
            wp_c[i] = wp_a[i] = rand() & PIXEL_MAX;
        for( int d = 0; d <= 7 && ok; d++ )
            for( int si = 0; si < 11 && ok; si++ )
            {
                /* (a, b): s = (a<<d) + b */
                static const int sc[11][2] = { {0,0}, {0,1}, {1,-1}, {1,0}, {1,1}, {2,-1}, {32,-1}, {32,0},
                                               {0,127}, {0,-1}, {0,-128} };
                int s = (sc[si][0]<<d) + sc[si][1];
                if( s > 127 )
                    continue;
                for( int oi = 0; oi < 5 && ok; oi++ )
                {
                    static const int of[5] = { -128, -1, 0, 1, 127 };
                    x264_weight_t weight = { .i_scale = s, .i_denom = d, .i_offset = of[oi] };
                    mc_a.weight_cache( &ha, &weight );
                    /* what x264_weight_cache_avx2/avx512 do not send to SSE2 */
                    int handled = s == 1<<d || (s >= 0 && s <= 0x7fff >> (BIT_DEPTH-d));
                    for( int wi = 0; wi < ARRAY_ELEMS(wp_w) && ok; wi++ )
                        for( int hi = 0; hi < ARRAY_ELEMS(wp_h) && ok; hi++ )
                        {
                            int width = wp_w[wi], height = wp_h[hi];
                            int soff = rand()&1 ? rand()&15 : 0;
                            int doff = rand()&1 ? rand()&15 : 0;
                            intptr_t sstride = WP_STRIDE - 32;
                            pixel *src_p = wp_src + soff;
                            /* fresh guards: the written rows plus two, columns to a zmm past the area */
                            int gw = X264_MIN( doff + ((width+7)&~7) + 64, WP_STRIDE );
                            for( int y = 0; y < ((height+1)&~1) + 2; y++ )
                                for( int x = 0; x < gw; x++ )
                                    wp_c[y*WP_STRIDE+x] = wp_a[y*WP_STRIDE+x] = rand() & PIXEL_MAX;
                            if( handled )
                                weight_plane_c( wp_c+doff, WP_STRIDE, src_p, sstride, &weight, width, height );
                            set_func_name( "weight_plane" );
                            int ret_a = (int)call_a1( mc_a.weight_plane, wp_a+doff, (intptr_t)WP_STRIDE, src_p, sstride,
                                                      &weight, width, height );
                            /* the avx512icl cache also takes the scales SSE2 gets at avx2/avx512 */
                            if( ret_a && !handled )
                                weight_plane_c( wp_c+doff, WP_STRIDE, src_p, sstride, &weight, width, height );
                            if( (handled && !ret_a) || memcmp( wp_c, wp_a, WP_STRIDE*WP_ROWS*sizeof(pixel) ) )
                            {
                                ok = 0;
                                fprintf( stderr, "weight_plane [FAILED] s:%d o:%d d:%d w:%d h:%d ret:%d\n",
                                         s, of[oi], d, width, height, ret_a );
                            }
                        }
                }
            }
        /* bench: one weight per kind, the 1080p luma row width, one 16 row strip:
         * C, the asm strips, the plane */
        for( int k = 0; k < 4 && wp_src && wp_c && wp_a; k++ )
        {
            x264_weight_t weight = { .i_scale = wbench[k][0], .i_denom = wbench[k][1], .i_offset = wbench[k][2] };
            mc_a.weight_cache( &ha, &weight );
            set_func_name( "weight_plane_%s_1984x16", wbench_name[k] );
            call_c2( weight_plane_c, wp_c, (intptr_t)WP_STRIDE, wp_src, (intptr_t)WP_STRIDE, &weight, 1984, 16 );
            call_a2( mc_a.weight_plane, wp_a, (intptr_t)WP_STRIDE, wp_src, (intptr_t)WP_STRIDE, &weight, 1984, 16 );
            set_func_name( "weight_plane_%s_1984x16_strips", wbench_name[k] );
            call_a2( weight_plane_strips, wp_a, (intptr_t)WP_STRIDE, wp_src, (intptr_t)WP_STRIDE, &weight, 1984, 16 );
        }
        x264_free( wp_src );
        x264_free( wp_c );
        x264_free( wp_a );
    }
    report( "mc weight_plane :" );

    ok = 1; used_asm = 0;
    for( int height = 8; height <= 16; height += 8 )
    {
        if( mc_a.store_interleave_chroma != mc_ref.store_interleave_chroma )
        {
            set_func_name( "store_interleave_chroma" );
            used_asm = 1;
            memset( pbuf3, 0, 64*height*sizeof(pixel) );
            memset( pbuf4, 0, 64*height*sizeof(pixel) );
            call_c( mc_c.store_interleave_chroma, pbuf3, (intptr_t)64, pbuf1, pbuf1+16, height );
            call_a( mc_a.store_interleave_chroma, pbuf4, (intptr_t)64, pbuf1, pbuf1+16, height );
            if( memcmp( pbuf3, pbuf4, 64*height*sizeof(pixel) ) )
            {
                ok = 0;
                fprintf( stderr, "store_interleave_chroma FAILED: h=%d\n", height );
                break;
            }
        }
        if( mc_a.load_deinterleave_chroma_fenc != mc_ref.load_deinterleave_chroma_fenc )
        {
            set_func_name( "load_deinterleave_chroma_fenc" );
            used_asm = 1;
            /* the functions leave parts of each row unwritten: start both outputs equal */
            memset( pbuf3, 0x5a, 64*height * sizeof(pixel) );
            memset( pbuf4, 0x5a, 64*height * sizeof(pixel) );
            call_c( mc_c.load_deinterleave_chroma_fenc, pbuf3, pbuf1, (intptr_t)64, height );
            call_a( mc_a.load_deinterleave_chroma_fenc, pbuf4, pbuf1, (intptr_t)64, height );
            if( memcmp( pbuf3, pbuf4, FENC_STRIDE*height*sizeof(pixel) ) )
            {
                ok = 0;
                fprintf( stderr, "load_deinterleave_chroma_fenc FAILED: h=%d\n", height );
                break;
            }
        }
        if( mc_a.load_deinterleave_chroma_fdec != mc_ref.load_deinterleave_chroma_fdec )
        {
            set_func_name( "load_deinterleave_chroma_fdec" );
            used_asm = 1;
            /* the functions leave parts of each row unwritten: start both outputs equal */
            memset( pbuf3, 0x5a, 64*height * sizeof(pixel) );
            memset( pbuf4, 0x5a, 64*height * sizeof(pixel) );
            call_c( mc_c.load_deinterleave_chroma_fdec, pbuf3, pbuf1, (intptr_t)64, height );
            call_a( mc_a.load_deinterleave_chroma_fdec, pbuf4, pbuf1, (intptr_t)64, height );
            if( memcmp( pbuf3, pbuf4, FDEC_STRIDE*height*sizeof(pixel) ) )
            {
                ok = 0;
                fprintf( stderr, "load_deinterleave_chroma_fdec FAILED: h=%d\n", height );
                break;
            }
        }
    }
    report( "store_interleave :" );

    struct plane_spec {
        int w, h, src_stride;
    } plane_specs[] = { {2,2,2}, {8,6,8}, {20,31,24}, {32,8,40}, {256,10,272}, {504,7,505}, {528,6,528}, {256,10,-256}, {263,9,-264}, {1904,1,0} };
    ok = 1; used_asm = 0;
    if( mc_a.plane_copy != mc_ref.plane_copy )
    {
        set_func_name( "plane_copy" );
        used_asm = 1;
        for( int i = 0; i < sizeof(plane_specs)/sizeof(*plane_specs); i++ )
        {
            int w = plane_specs[i].w;
            int h = plane_specs[i].h;
            intptr_t src_stride = plane_specs[i].src_stride;
            intptr_t dst_stride = (w + 127) & ~63;
            assert( dst_stride * h <= 0x1000 );
            pixel *src1 = pbuf1 + X264_MAX(0, -src_stride) * (h-1);
            memset( pbuf3, 0, 0x1000*sizeof(pixel) );
            memset( pbuf4, 0, 0x1000*sizeof(pixel) );
            call_c( mc_c.plane_copy, pbuf3, dst_stride, src1, src_stride, w, h );
            call_a( mc_a.plane_copy, pbuf4, dst_stride, src1, src_stride, w, h );
            for( int y = 0; y < h; y++ )
                if( memcmp( pbuf3+y*dst_stride, pbuf4+y*dst_stride, w*sizeof(pixel) ) )
                {
                    ok = 0;
                    fprintf( stderr, "plane_copy FAILED: w=%d h=%d stride=%d\n", w, h, (int)src_stride );
                    break;
                }
        }
    }

    if( mc_a.plane_copy_interleave != mc_ref.plane_copy_interleave )
    {
        set_func_name( "plane_copy_interleave" );
        used_asm = 1;
        for( int i = 0; i < sizeof(plane_specs)/sizeof(*plane_specs); i++ )
        {
            int w = (plane_specs[i].w + 1) >> 1;
            int h = plane_specs[i].h;
            intptr_t src_stride = (plane_specs[i].src_stride + 1) >> 1;
            intptr_t dst_stride = (2*w + 127) & ~63;
            assert( dst_stride * h <= 0x1000 );
            pixel *src1 = pbuf1 + X264_MAX(0, -src_stride) * (h-1);
            memset( pbuf3, 0, 0x1000*sizeof(pixel) );
            memset( pbuf4, 0, 0x1000*sizeof(pixel) );
            call_c( mc_c.plane_copy_interleave, pbuf3, dst_stride, src1, src_stride, src1+1024, src_stride+16, w, h );
            call_a( mc_a.plane_copy_interleave, pbuf4, dst_stride, src1, src_stride, src1+1024, src_stride+16, w, h );
            for( int y = 0; y < h; y++ )
                if( memcmp( pbuf3+y*dst_stride, pbuf4+y*dst_stride, 2*w*sizeof(pixel) ) )
                {
                    ok = 0;
                    fprintf( stderr, "plane_copy_interleave FAILED: w=%d h=%d stride=%d\n", w, h, (int)src_stride );
                    break;
                }
        }
    }

    if( mc_a.plane_copy_deinterleave != mc_ref.plane_copy_deinterleave )
    {
        set_func_name( "plane_copy_deinterleave" );
        used_asm = 1;
        for( int i = 0; i < sizeof(plane_specs)/sizeof(*plane_specs); i++ )
        {
            int w = (plane_specs[i].w + 1) >> 1;
            int h = plane_specs[i].h;
            intptr_t dst_stride = w;
            intptr_t src_stride = (2*w + 127) & ~63;
            intptr_t offv = (dst_stride*h + 31) & ~15;
            memset( pbuf3, 0, 0x1000*sizeof(pixel) );
            memset( pbuf4, 0, 0x1000*sizeof(pixel) );
            call_c( mc_c.plane_copy_deinterleave, pbuf3, dst_stride, pbuf3+offv, dst_stride, pbuf1, src_stride, w, h );
            call_a( mc_a.plane_copy_deinterleave, pbuf4, dst_stride, pbuf4+offv, dst_stride, pbuf1, src_stride, w, h );
            for( int y = 0; y < h; y++ )
                if( memcmp( pbuf3+y*dst_stride,      pbuf4+y*dst_stride, w*sizeof(pixel) ) ||
                    memcmp( pbuf3+y*dst_stride+offv, pbuf4+y*dst_stride+offv, w*sizeof(pixel) ) )
                {
                    ok = 0;
                    fprintf( stderr, "plane_copy_deinterleave FAILED: w=%d h=%d stride=%d\n", w, h, (int)src_stride );
                    break;
                }
        }
    }

    /* 1080p chroma rows (960 wide, 64-byte aligned, padded stride): the full-row
     * paths without the C fallbacks, and their bench */
    if( mc_a.plane_copy_interleave != mc_ref.plane_copy_interleave ||
        mc_a.plane_copy_deinterleave != mc_ref.plane_copy_deinterleave )
    {
        int w = 960, h = 4;
        intptr_t stride_p = 1024, stride_i = 2048 + 64;
        pixel *src = x264_malloc( (2*stride_p + stride_i) * h * sizeof(pixel) );
        pixel *dst_c = x264_malloc( 2 * stride_i * h * sizeof(pixel) );
        pixel *dst_a = x264_malloc( 2 * stride_i * h * sizeof(pixel) );
        if( !src || !dst_c || !dst_a )
            ok = 0;
        else
        {
            pixel *srcu = src, *srcv = src + stride_p * h, *srci = src + 2 * stride_p * h;
            for( int i = 0; i < (2*stride_p + stride_i) * h; i++ )
                src[i] = rand() & PIXEL_MAX;
            if( mc_a.plane_copy_interleave != mc_ref.plane_copy_interleave )
            {
                set_func_name( "plane_copy_interleave_960x4" );
                used_asm = 1;
                memset( dst_c, 0, 2 * stride_i * h * sizeof(pixel) );
                memset( dst_a, 0, 2 * stride_i * h * sizeof(pixel) );
                call_c( mc_c.plane_copy_interleave, dst_c, stride_i, srcu, stride_p, srcv, stride_p, w, h );
                call_a( mc_a.plane_copy_interleave, dst_a, stride_i, srcu, stride_p, srcv, stride_p, w, h );
                for( int y = 0; y < h; y++ )
                    if( memcmp( dst_c+y*stride_i, dst_a+y*stride_i, 2*w*sizeof(pixel) ) )
                    {
                        ok = 0;
                        fprintf( stderr, "plane_copy_interleave FAILED: w=%d h=%d (960x4)\n", w, h );
                        break;
                    }
            }
            if( mc_a.plane_copy_deinterleave != mc_ref.plane_copy_deinterleave )
            {
                pixel *dstv_c = dst_c + stride_p * h, *dstv_a = dst_a + stride_p * h;
                set_func_name( "plane_copy_deinterleave_960x4" );
                used_asm = 1;
                memset( dst_c, 0, 2 * stride_i * h * sizeof(pixel) );
                memset( dst_a, 0, 2 * stride_i * h * sizeof(pixel) );
                call_c( mc_c.plane_copy_deinterleave, dst_c, stride_p, dstv_c, stride_p, srci, stride_i, w, h );
                call_a( mc_a.plane_copy_deinterleave, dst_a, stride_p, dstv_a, stride_p, srci, stride_i, w, h );
                for( int y = 0; y < h; y++ )
                    if( memcmp( dst_c+y*stride_p, dst_a+y*stride_p, w*sizeof(pixel) ) ||
                        memcmp( dstv_c+y*stride_p, dstv_a+y*stride_p, w*sizeof(pixel) ) )
                    {
                        ok = 0;
                        fprintf( stderr, "plane_copy_deinterleave FAILED: w=%d h=%d (960x4)\n", w, h );
                        break;
                    }
            }
        }
        x264_free( src );
        x264_free( dst_c );
        x264_free( dst_a );
    }

    if( mc_a.plane_copy_deinterleave_rgb != mc_ref.plane_copy_deinterleave_rgb )
    {
        set_func_name( "plane_copy_deinterleave_rgb" );
        used_asm = 1;
        for( int i = 0; i < sizeof(plane_specs)/sizeof(*plane_specs); i++ )
        {
            int w = (plane_specs[i].w + 2) >> 2;
            int h = plane_specs[i].h;
            intptr_t src_stride = plane_specs[i].src_stride;
            intptr_t dst_stride = ALIGN( w, 16 );
            intptr_t offv = dst_stride*h + 16;

            for( int pw = 3; pw <= 4; pw++ )
            {
                memset( pbuf3, 0, 0x1000*sizeof(pixel) );
                memset( pbuf4, 0, 0x1000*sizeof(pixel) );
                call_c( mc_c.plane_copy_deinterleave_rgb, pbuf3, dst_stride, pbuf3+offv, dst_stride, pbuf3+2*offv, dst_stride, pbuf1, src_stride, pw, w, h );
                call_a( mc_a.plane_copy_deinterleave_rgb, pbuf4, dst_stride, pbuf4+offv, dst_stride, pbuf4+2*offv, dst_stride, pbuf1, src_stride, pw, w, h );
                for( int y = 0; y < h; y++ )
                    if( memcmp( pbuf3+y*dst_stride+0*offv, pbuf4+y*dst_stride+0*offv, w*sizeof(pixel) ) ||
                        memcmp( pbuf3+y*dst_stride+1*offv, pbuf4+y*dst_stride+1*offv, w*sizeof(pixel) ) ||
                        memcmp( pbuf3+y*dst_stride+2*offv, pbuf4+y*dst_stride+2*offv, w*sizeof(pixel) ) )
                    {
                        ok = 0;
                        fprintf( stderr, "plane_copy_deinterleave_rgb FAILED: w=%d h=%d stride=%d pw=%d\n", w, h, (int)src_stride, pw );
                        break;
                    }
            }
        }
    }
    report( "plane_copy :" );

    if( mc_a.plane_copy_deinterleave_v210 != mc_ref.plane_copy_deinterleave_v210 )
    {
        set_func_name( "plane_copy_deinterleave_v210" );
        used_asm = 1;
        for( int i = 0; i < sizeof(plane_specs)/sizeof(*plane_specs); i++ )
        {
            int w = (plane_specs[i].w + 1) >> 1;
            int h = plane_specs[i].h;
            intptr_t dst_stride = ALIGN( w, 32 );
            intptr_t src_stride = (w + 47) / 48 * 128 / sizeof(uint32_t);
            intptr_t offv = dst_stride*h + 32;
            memset( pbuf3, 0, 0x1000 );
            memset( pbuf4, 0, 0x1000 );
            call_c( mc_c.plane_copy_deinterleave_v210, pbuf3, dst_stride, pbuf3+offv, dst_stride, (uint32_t *)buf1, src_stride, w, h );
            call_a( mc_a.plane_copy_deinterleave_v210, pbuf4, dst_stride, pbuf4+offv, dst_stride, (uint32_t *)buf1, src_stride, w, h );
            for( int y = 0; y < h; y++ )
                if( memcmp( pbuf3+y*dst_stride,      pbuf4+y*dst_stride,      w*sizeof(uint16_t) ) ||
                    memcmp( pbuf3+y*dst_stride+offv, pbuf4+y*dst_stride+offv, w*sizeof(uint16_t) ) )
                {
                    ok = 0;
                    fprintf( stderr, "plane_copy_deinterleave_v210 FAILED: w=%d h=%d stride=%d\n", w, h, (int)src_stride );
                    break;
                }
        }
    }
    report( "v210 :" );

    if( mc_a.hpel_filter != mc_ref.hpel_filter )
    {
        pixel *srchpel = pbuf1+8+2*64;
        pixel *dstc[3] = { pbuf3+8, pbuf3+8+16*64, pbuf3+8+32*64 };
        pixel *dsta[3] = { pbuf4+8, pbuf4+8+16*64, pbuf4+8+32*64 };
        void *tmp = pbuf3+49*64;
        set_func_name( "hpel_filter" );
        ok = 1; used_asm = 1;
        memset( pbuf3, 0, 4096 * sizeof(pixel) );
        memset( pbuf4, 0, 4096 * sizeof(pixel) );
        call_c( mc_c.hpel_filter, dstc[0], dstc[1], dstc[2], srchpel, (intptr_t)64, 48, 10, tmp );
        call_a( mc_a.hpel_filter, dsta[0], dsta[1], dsta[2], srchpel, (intptr_t)64, 48, 10, tmp );
        for( int i = 0; i < 3; i++ )
            for( int j = 0; j < 10; j++ )
                //FIXME ideally the first pixels would match too, but they aren't actually used
                if( memcmp( dstc[i]+j*64+2, dsta[i]+j*64+2, 43 * sizeof(pixel) ) )
                {
                    ok = 0;
                    fprintf( stderr, "hpel filter differs at plane %c line %d\n", "hvc"[i], j );
                    for( int k = 0; k < 48; k++ )
                        printf( "%02x%s", dstc[i][j*64+k], (k+1)&3 ? "" : " " );
                    printf( "\n" );
                    for( int k = 0; k < 48; k++ )
                        printf( "%02x%s", dsta[i][j*64+k], (k+1)&3 ? "" : " " );
                    printf( "\n" );
                    break;
                }
        /* columns N P N N P N of vertical patterns (0,max,0 | max,0,max), period 3:
         * the extremes of the vertical 6-tap, which overflowed the 16-bit
         * intermediate of the centre filter */
        for( int phase = 0; phase < 12 && ok; phase++ )
        {
            ALIGNED_ARRAY_32( pixel, stripe,[16*64] );
            pixel *srcp = stripe+8+2*64;
            for( int y = 0; y < 16; y++ )
                for( int x = 0; x < 64; x++ )
                {
                    int p = "010010"[(x+phase)%6] - '0'; /* 0 = N, 1 = P */
                    int hi = (y%3 == 1) ^ p ^ (phase >= 6);
                    stripe[y*64+x] = hi ? PIXEL_MAX : 0;
                }
            memset( pbuf3, 0, 4096 * sizeof(pixel) );
            memset( pbuf4, 0, 4096 * sizeof(pixel) );
            mc_c.hpel_filter( dstc[0], dstc[1], dstc[2], srcp, 64, 48, 10, tmp );
            mc_a.hpel_filter( dsta[0], dsta[1], dsta[2], srcp, 64, 48, 10, tmp );
            for( int i = 0; i < 3; i++ )
                for( int j = 0; j < 10; j++ )
                    if( memcmp( dstc[i]+j*64+2, dsta[i]+j*64+2, 43 * sizeof(pixel) ) )
                    {
                        ok = 0;
                        fprintf( stderr, "hpel filter differs at plane %c line %d (stripe pattern %d)\n", "hvc"[i], j, phase );
                        break;
                    }
        }
        report( "hpel filter :" );
    }

    if( mc_a.hpel_filter_copy && mc_a.hpel_filter_copy != mc_ref.hpel_filter_copy )
    {
        pixel *srchpel = pbuf1+8+2*64;
        pixel *dstc[3] = { pbuf3+8, pbuf3+8+16*64, pbuf3+8+32*64 };
        pixel *dsta[3] = { pbuf4+8, pbuf4+8+16*64, pbuf4+8+32*64 };
        pixel *cpyc = pbuf3+8+52*64;
        pixel *cpya = pbuf4+8+52*64;
        void *tmp = pbuf3+49*64;
        set_func_name( "hpel_filter_copy" );
        ok = 1; used_asm = 1;
        /* as hpel_filter, plus the copy of src; anything else written to the
         * copy must be src at the same offset */
        for( int i_off = 0; i_off < 3 && ok; i_off++ )
        {
            int o = (int[]){ 0, 8, 24 }[i_off];
            memset( pbuf3, 0, 4096 * sizeof(pixel) );
            memset( pbuf4, 0, 4096 * sizeof(pixel) );
            mc_c.hpel_filter( dstc[0]+o, dstc[1]+o, dstc[2]+o, srchpel+o, 64, 48, 10, tmp );
            for( int j = 0; j < 10; j++ )
                memcpy( cpyc+o+j*64, srchpel+o+j*64, 48 * sizeof(pixel) );
            call_a( mc_a.hpel_filter_copy, dsta[0]+o, dsta[1]+o, dsta[2]+o, srchpel+o, (intptr_t)64, 48, 10, tmp, cpya+o );
            for( int i = 0; i < 3; i++ )
                for( int j = 0; j < 10; j++ )
                    if( memcmp( dstc[i]+o+j*64+2, dsta[i]+o+j*64+2, 43 * sizeof(pixel) ) )
                    {
                        ok = 0;
                        fprintf( stderr, "hpel filter copy differs at plane %c line %d offset %d\n", "hvc"[i], j, o );
                        break;
                    }
            for( int j = 0; j < 10; j++ )
                if( memcmp( cpyc+o+j*64, cpya+o+j*64, 48 * sizeof(pixel) ) )
                {
                    ok = 0;
                    fprintf( stderr, "hpel filter copy: copy differs at line %d offset %d\n", j, o );
                    break;
                }
            for( int k = -64; k < 11*64; k++ )
                if( cpya[o+k] && cpya[o+k] != srchpel[o+k] )
                {
                    ok = 0;
                    fprintf( stderr, "hpel filter copy: stray write at %d offset %d\n", k, o );
                    break;
                }
        }
        report( "hpel filter copy :" );
    }

    if( mc_a.frame_init_lowres_core != mc_ref.frame_init_lowres_core )
    {
        pixel *dstc[4] = { pbuf3, pbuf3+1024, pbuf3+2048, pbuf3+3072 };
        pixel *dsta[4] = { pbuf4, pbuf4+1024, pbuf4+2048, pbuf4+3072 };
        set_func_name( "lowres_init" );
        ok = 1; used_asm = 1;
        for( int w = 96; w <= 96+24; w += 8 )
        {
            intptr_t stride = (w*2+31)&~31;
            intptr_t stride_lowres = (w+31)&~31;
            call_c( mc_c.frame_init_lowres_core, pbuf1, dstc[0], dstc[1], dstc[2], dstc[3], stride, stride_lowres, w, 8 );
            call_a( mc_a.frame_init_lowres_core, pbuf1, dsta[0], dsta[1], dsta[2], dsta[3], stride, stride_lowres, w, 8 );
            for( int i = 0; i < 8; i++ )
            {
                for( int j = 0; j < 4; j++ )
                    if( memcmp( dstc[j]+i*stride_lowres, dsta[j]+i*stride_lowres, w * sizeof(pixel) ) )
                    {
                        ok = 0;
                        fprintf( stderr, "frame_init_lowres differs at plane %d line %d\n", j, i );
                        for( int k = 0; k < w; k++ )
                            printf( "%d ", dstc[j][k+i*stride_lowres] );
                        printf( "\n" );
                        for( int k = 0; k < w; k++ )
                            printf( "%d ", dsta[j][k+i*stride_lowres] );
                        printf( "\n" );
                        break;
                    }
            }
        }
        report( "lowres init :" );
    }

#if HIGH_BIT_DEPTH
    if( mc_a.frame_init_lowres_core8 != mc_ref.frame_init_lowres_core8 )
    {
        /* against frame_init_lowres_core then the 8-bit conversion, on pbuf1 and on
         * a source near PIXEL_MAX, where 1022 and 1023 round to 256 and clip */
        pixel *src_max = x264_malloc( 0x1e00*sizeof(pixel) );
        pixel *ref[4] = { pbuf3, pbuf3+1024, pbuf3+2048, pbuf3+3072 };
        uint8_t *dstc[4], *dsta[4];
        for( int j = 0; j < 4; j++ )
        {
            dstc[j] = (uint8_t*)pbuf4 + j*1024;
            dsta[j] = (uint8_t*)pbuf4 + 4096 + j*1024;
        }
        set_func_name( "lowres_init8" );
        ok = !!src_max; used_asm = 1;
        if( src_max )
            for( int i = 0; i < 0x1e00; i++ )
                src_max[i] = PIXEL_MAX - (rand()&3);
        for( int k = 0; k < 2 && ok; k++ )
            for( int w = 96; w <= 96+24 && ok; w += 8 )
            {
                pixel *src = k ? src_max : pbuf1;
                intptr_t stride = (w*2+31)&~31;
                intptr_t stride_lowres = (w+31)&~31;
                mc_c.frame_init_lowres_core( src, ref[0], ref[1], ref[2], ref[3], stride, stride_lowres, w, 8 );
                call_c( mc_c.frame_init_lowres_core8, src, dstc[0], dstc[1], dstc[2], dstc[3], stride, stride_lowres, w, 8 );
                call_a( mc_a.frame_init_lowres_core8, src, dsta[0], dsta[1], dsta[2], dsta[3], stride, stride_lowres, w, 8 );
                for( int j = 0; j < 4 && ok; j++ )
                    for( int i = 0; i < 8 && ok; i++ )
                        for( int x = 0; x < w; x++ )
                        {
                            int o = x + i*stride_lowres;
                            int v = X264_MIN( (ref[j][o] + (1 << (BIT_DEPTH-9))) >> (BIT_DEPTH-8), 255 );
                            if( dstc[j][o] != v || dsta[j][o] != v )
                            {
                                ok = 0;
                                fprintf( stderr, "frame_init_lowres8 differs: src %d w %d plane %d line %d x %d: %d c %d asm %d\n",
                                         k, w, j, i, x, v, dstc[j][o], dsta[j][o] );
                                break;
                            }
                        }
            }
        x264_free( src_max );
        report( "lowres init8 :" );
    }
#endif

#define INTEGRAL_INIT( name, size, ... )\
    if( mc_a.name != mc_ref.name )\
    {\
        intptr_t stride = 96;\
        set_func_name( #name );\
        used_asm = 1;\
        memcpy( buf3, buf1, size*2*stride );\
        memcpy( buf4, buf1, size*2*stride );\
        uint16_t *sum = (uint16_t*)buf3;\
        call_c1( mc_c.name, __VA_ARGS__ );\
        sum = (uint16_t*)buf4;\
        call_a1( mc_a.name, __VA_ARGS__ );\
        /* row 0 (v), row 1 (h: sum+stride) */\
        if( memcmp( buf3, buf4, (stride-8)*2 ) \
            || memcmp( buf3+2*stride, buf4+2*stride, (stride-8)*2 ) \
            || (size>9 && memcmp( buf3+18*stride, buf4+18*stride, (stride-8)*2 )))\
            ok = 0;\
        call_c2( mc_c.name, __VA_ARGS__ );\
        call_a2( mc_a.name, __VA_ARGS__ );\
    }
    ok = 1; used_asm = 0;
    INTEGRAL_INIT( integral_init4h, 2, sum+stride, pbuf2, stride );
    INTEGRAL_INIT( integral_init8h, 2, sum+stride, pbuf2, stride );
    INTEGRAL_INIT( integral_init4v, 14, sum, sum+9*stride, stride );
    INTEGRAL_INIT( integral_init8v, 9, sum, stride );
    report( "integral init :" );

    ok = 1; used_asm = 0;
    if( mc_a.mbtree_propagate_cost != mc_ref.mbtree_propagate_cost )
    {
        used_asm = 1;
        x264_emms();
        for( int i = 0; i < 10; i++ )
        {
            /* i >= 5: the encoder's ranges (fps_factor near 1/512, lowres costs, inv_qscale
             * near 256): most outputs unsaturated; at i < 5 nearly all are 0 or 32767 */
            int real = i >= 5;
            float fps_factor = (rand30()&65535) / 65535.0f / (real ? 256 : 1);
            set_func_name( "mbtree_propagate_cost" );
            int16_t *dsta = (int16_t*)buf3;
            int16_t *dstc = dsta+400;
            uint16_t *prop = real ? (uint16_t*)buf4 + 384 : (uint16_t*)buf1;
            uint16_t *intra = (uint16_t*)buf4;
            uint16_t *inter = intra+128;
            uint16_t *qscale = inter+128;
            uint16_t *rnd = (uint16_t*)buf2;
            x264_emms();
            for( int j = 0; j < 100; j++ )
            {
                if( real )
                {
                    intra[j]  = rand() & LOWRES_COST_MASK;
                    inter[j]  = rand() & 0x7fff;
                    qscale[j] = 128 + rand() % 768;
                    prop[j]   = rand() & 0x7fff;
                }
                else
                {
                    intra[j]  = *rnd++ & 0x7fff;
                    inter[j]  = *rnd++ & 0x7fff;
                    qscale[j] = *rnd++ & 0x7fff;
                }
                intra[j] += !intra[j];
            }
            call_c( mc_c.mbtree_propagate_cost, dstc, prop, intra, inter, qscale, &fps_factor, 100 );
            call_a( mc_a.mbtree_propagate_cost, dsta, prop, intra, inter, qscale, &fps_factor, 100 );
            // I don't care about exact rounding, this is just how close the floating-point implementation happens to be
            x264_emms();
            for( int j = 0; j < 100 && ok; j++ )
            {
                ok &= abs( dstc[j]-dsta[j] ) <= 1 || fabs( (double)dstc[j]/dsta[j]-1 ) < 1e-4;
                if( !ok )
                    fprintf( stderr, "mbtree_propagate_cost FAILED: %f !~= %f\n", (double)dstc[j], (double)dsta[j] );
            }
        }
    }

    if( mc_a.mbtree_propagate_list != mc_ref.mbtree_propagate_list )
    {
        used_asm = 1;
        for( int i = 0; i < 8; i++ )
        {
            set_func_name( "mbtree_propagate_list" );
            x264_t h;
            int height = 4;
            int width = 128;
            int size = width*height;
            h.mb.i_mb_stride = width;
            h.mb.i_mb_width = width;
            h.mb.i_mb_height = height;

            uint16_t *ref_costsc = (uint16_t*)buf3 + width;
            uint16_t *ref_costsa = (uint16_t*)buf4 + width;
            int16_t (*mvs)[2] = (int16_t(*)[2])(ref_costsc + width + size);
            int16_t *propagate_amount = (int16_t*)(mvs + width);
            uint16_t *lowres_costs = (uint16_t*)(propagate_amount + width);
            h.scratch_buffer2 = (uint8_t*)(ref_costsa + width + size);
            int bipred_weight = (rand()%63)+1;
            int mb_y = rand()&3;
            int list = i&1;
            /* also a row length that isn't a multiple of 8, with valid data past its end */
            int len = (i&2) ? width-3 : width;
            for( int j = -width; j < size+width; j++ )
                ref_costsc[j] = ref_costsa[j] = rand()&32767;
            for( int j = 0; j < width; j++ )
            {
                static const uint8_t list_dist[2][8] = {{0,1,1,1,1,1,1,1},{1,1,3,3,3,3,3,2}};
                for( int k = 0; k < 2; k++ )
                    mvs[j][k] = (rand()&127) - 64;
                propagate_amount[j] = rand()&32767;
                lowres_costs[j] = list_dist[list][rand()&7] << LOWRES_COST_SHIFT;
            }

            call_c1( mc_c.mbtree_propagate_list, &h, ref_costsc, mvs, propagate_amount, lowres_costs, bipred_weight, mb_y, len, list );
            call_a1( mc_a.mbtree_propagate_list, &h, ref_costsa, mvs, propagate_amount, lowres_costs, bipred_weight, mb_y, len, list );

            for( int j = -width; j < size+width && ok; j++ )
            {
                ok &= abs(ref_costsa[j] - ref_costsc[j]) <= 1;
                if( !ok )
                    fprintf( stderr, "mbtree_propagate_list FAILED at %d: %d !~= %d\n", j, ref_costsc[j], ref_costsa[j] );
            }
        }
        /* bench: a fixed 128-wide row in the middle of 4, each list: mvs +-32,
         * bipred weight 32, lowres costs and amounts from the private generator */
        x264_t *hb = do_bench ? x264_malloc( sizeof(x264_t) ) : NULL;
        uint8_t *mb = do_bench ? x264_malloc( 64<<10 ) : NULL;
        for( int list = 0; list < 2 && hb && mb; list++ )
        {
            static const uint8_t list_dist[2][8] = {{0,1,1,1,1,1,1,1},{1,1,3,3,3,3,3,2}};
            int width = 128, size = 4*width;
            uint16_t *ref_costsc = (uint16_t*)mb + width;
            uint16_t *ref_costsa = (uint16_t*)mb + 1024 + width;
            int16_t (*mvs)[2] = (int16_t(*)[2])((uint16_t*)mb + 2048);
            int16_t *propagate_amount = (int16_t*)(mvs + width);
            uint16_t *lowres_costs = (uint16_t*)(propagate_amount + width);
            hb->mb.i_mb_stride = width;
            hb->mb.i_mb_width = width;
            hb->mb.i_mb_height = 4;
            hb->scratch_buffer2 = mb + (32<<10);
            bench_srand( 600 + list );
            for( int j = -width; j < size+width; j++ )
                ref_costsc[j] = ref_costsa[j] = bench_rand()&32767;
            for( int j = 0; j < width; j++ )
            {
                for( int k = 0; k < 2; k++ )
                    mvs[j][k] = (bench_rand()&63) - 32;
                propagate_amount[j] = bench_rand()&4095;
                lowres_costs[j] = list_dist[list][bench_rand()&7] << LOWRES_COST_SHIFT;
            }
            set_func_name( "mbtree_propagate_list" );
            call_c2( mc_c.mbtree_propagate_list, hb, ref_costsc, mvs, propagate_amount, lowres_costs, 32, 1, width, list );
            call_a2( mc_a.mbtree_propagate_list, hb, ref_costsa, mvs, propagate_amount, lowres_costs, 32, 1, width, list );
        }
        x264_free( hb );
        x264_free( mb );
    }

    if( mc_a.mbtree_cost_scale != mc_ref.mbtree_cost_scale )
    {
        used_asm = 1;
        set_func_name( "mbtree_cost_scale" );
        uint16_t *costs = (uint16_t*)buf3;
        float *qp = (float*)buf4;
        for( int i = 0; i < 40 && ok; i++ )
        {
            /* i%4 0: the encoder's range, 1: exp2fix8 index over -64..1087, 2: clipped both ways, 3: max costs */
            int len = i < 32 ? 1 + i : 120 + rand()%200;
            for( int j = 0; j < len; j++ )
            {
                costs[j] = i%4 == 3 ? 0xffff : rand();
                if( i%4 == 1 )
                    qp[j] = ((rand()%1152) - 64 - 512 + (rand()&1)) * (6.f/-64.f);
                else if( i%4 == 2 )
                    qp[j] = (rand()&1 ? 1 : -1) * (j&1 ? 1e30f : 60.f + (rand()&1023));
                else
                    qp[j] = ((rand()&65535) - 32768) * (24.f/32768);
            }
            int resc = call_c1( mc_c.mbtree_cost_scale, costs, qp, len );
            int resa = call_a1( mc_a.mbtree_cost_scale, costs, qp, len );
            if( resc != resa )
            {
                ok = 0;
                fprintf( stderr, "mbtree_cost_scale FAILED: len %d mode %d: %d != %d\n", len, i%4, resc, resa );
            }
        }
        if( do_bench )
        {
            /* bench: a fixed 1080p row, offsets in the encoder's range */
            bench_srand( 1100 );
            for( int j = 0; j < 120; j++ )
            {
                costs[j] = bench_rand();
                qp[j] = ((bench_rand()&65535) - 32768) * (24.f/32768);
            }
            call_c2( mc_c.mbtree_cost_scale, costs, qp, 120 );
            call_a2( mc_a.mbtree_cost_scale, costs, qp, 120 );
        }
    }

    if( mc_a.mbtree_finish != mc_ref.mbtree_finish )
    {
        used_asm = 1;
        set_func_name( "mbtree_finish" );
        float *qpc = (float*)buf3;
        float *qpa = qpc + 300;
        float *qp_aq = qpa + 300;
        uint16_t *intra = (uint16_t*)buf4;
        uint16_t *invq = intra + 300;
        uint16_t *prop = invq + 300;
        for( int i = 0; i < 40 && ok; i++ )
        {
            /* i%4 0: the encoder's ranges, 1: weightdelta, 2: maxed inputs, 3: half the MBs with intra 0 */
            int len = i < 32 ? 1 + i : 120 + rand()%180;
            int fps_factor = i%4 == 2 ? 0x7fff : 384 + rand()%256;
            float params[2] = { i%4 == 2 ? 5.f : (rand()%5000) * (5.f/5000), i%4 == 1 ? (rand()&65535) * (1.f/65536) : 0.f };
            for( int j = 0; j < len; j++ )
            {
                intra[j] = i%4 == 2 ? LOWRES_COST_MASK : rand() & LOWRES_COST_MASK;
                invq[j]  = i%4 == 2 ? 0xffff : 128 + rand()%768;
                prop[j]  = i%4 == 2 ? 0xffff : rand() & 0xffff >> (rand()&15);
                if( i%4 == 3 && (rand()&1) )
                    intra[j] = rand()&1;
                qp_aq[j] = ((rand()&65535) - 32768) * (12.f/32768);
                qpc[j] = qpa[j] = rand() * (1.f/RAND_MAX);
            }
            call_c1( mc_c.mbtree_finish, qpc, qp_aq, intra, invq, prop, params, fps_factor, len );
            call_a1( mc_a.mbtree_finish, qpa, qp_aq, intra, invq, prop, params, fps_factor, len );
            /* -ffast-math may reorder the C's float sums; bit-exact otherwise */
            for( int j = 0; j < len && ok; j++ )
            {
#ifdef __FAST_MATH__
                ok &= fabs( qpc[j] - qpa[j] ) < 1e-4;
#else
                ok &= !memcmp( qpc+j, qpa+j, sizeof(float) );
#endif
                if( !ok )
                    fprintf( stderr, "mbtree_finish FAILED: len %d mode %d [%d]: %.9g != %.9g\n", len, i%4, j, qpc[j], qpa[j] );
            }
        }
        if( do_bench )
        {
            /* bench: a fixed 1080p row, qcomp 0.6, fps_factor 512, no weightdelta */
            float params[2] = { 2.f, 0.f };
            bench_srand( 1101 );
            for( int j = 0; j < 120; j++ )
            {
                intra[j] = bench_rand() & LOWRES_COST_MASK;
                invq[j]  = 128 + bench_rand()%768;
                prop[j]  = bench_rand() & 0xfff;
                qp_aq[j] = ((bench_rand()&65535) - 32768) * (12.f/32768);
            }
            call_c2( mc_c.mbtree_finish, qpc, qp_aq, intra, invq, prop, params, 512, 120 );
            call_a2( mc_a.mbtree_finish, qpa, qp_aq, intra, invq, prop, params, 512, 120 );
        }
    }
    report( "mbtree :" );

    ok = 1; used_asm = 0;
    if( mc_a.aq_variance_tail != mc_ref.aq_variance_tail )
    {
        used_asm = 1;
        set_func_name( "aq_variance_tail" );
        float *qpc = (float*)buf3;
        float *qpa = qpc + 300;
        float *qpc_aq = qpa + 300;
        float *qpa_aq = (float*)buf4;
        float *offsets = qpa_aq + 300;
        uint16_t *invc = (uint16_t*)(offsets + 300);
        uint16_t *inva = invc + 300;
        uint32_t *energy = (uint32_t*)buf1;
        for( int i = 0; i < 48 && ok; i++ )
        {
            /* i%3 0: AC energies, 1: every msb position with random low bits, 0 and 1, 2: strength up to 4, big offsets */
            int len = i < 32 ? 1 + i : 120 + rand()%180;
            float params[2] = { (i%3 == 2 ? 4.f : 1.f) * (rand()&65535) * (1.f/65536), 14.427f + 2*(rand()&1) };
            float *quant_offsets = i&4 ? offsets : NULL;
            uint16_t *inv_c = i&8 ? NULL : invc;
            uint16_t *inv_a = i&8 ? NULL : inva;
            for( int j = 0; j < len; j++ )
            {
                if( i%3 == 1 )
                    energy[j] = j < 2 ? j : j%3 == 2 ? 0xffffffffu >> (rand()&31) /* rounds up unless truncated */
                              : (uint32_t)(((uint64_t)rand() << 31 | rand()) >> (j&31));
                else
                    energy[j] = (rand() & 0xffffff) >> (rand()&15);
                offsets[j] = ((rand()&65535) - 32768) * (i%3 == 2 ? 100.f/32768 : 6.f/32768);
                qpc[j] = qpa[j] = qpc_aq[j] = qpa_aq[j] = -1.f;
                invc[j] = inva[j] = 0x5555;
            }
            qpc[len] = qpa[len] = qpc_aq[len] = qpa_aq[len] = -1.f;
            invc[len] = inva[len] = 0x5555;
            call_c1( mc_c.aq_variance_tail, qpc, qpc_aq, inv_c, energy, quant_offsets, params, len );
            call_a1( mc_a.aq_variance_tail, qpa, qpa_aq, inv_a, energy, quant_offsets, params, len );
            /* -ffast-math may reorder the C's float sums; bit-exact otherwise */
            for( int j = 0; j < len+1 && ok; j++ )
            {
#ifdef __FAST_MATH__
                ok &= fabs( qpc[j] - qpa[j] ) < 1e-4 && inva[j] == (j < len && !(i&8) ? x264_exp2fix8( qpa[j] ) : 0x5555);
#else
                ok &= !memcmp( qpc+j, qpa+j, sizeof(float) ) && invc[j] == inva[j];
#endif
                ok &= !memcmp( qpa+j, qpa_aq+j, sizeof(float) ) && !memcmp( qpc+j, qpc_aq+j, sizeof(float) );
                if( !ok )
                    fprintf( stderr, "aq_variance_tail FAILED: len %d mode %d [%d]: %.9g %d != %.9g %d\n",
                             len, i%3, j, qpc[j], invc[j], qpa[j], inva[j] );
            }
        }
        if( do_bench )
        {
            /* bench: a fixed 1080p row of AC energies, aq-strength 1, no quant offsets */
            float params[2] = { 1.0397f, 14.427f };
            bench_srand( 1102 );
            for( int j = 0; j < 120; j++ )
                energy[j] = (bench_rand() & 0xffffff) >> (bench_rand()&15);
            call_c2( mc_c.aq_variance_tail, qpc, qpc_aq, invc, energy, NULL, params, 120 );
            call_a2( mc_a.aq_variance_tail, qpa, qpa_aq, inva, energy, NULL, params, 120 );
        }
    }
    report( "aq :" );

    if( mc_a.memcpy_aligned != mc_ref.memcpy_aligned )
    {
        set_func_name( "memcpy_aligned" );
        ok = 1; used_asm = 1;
        for( size_t size = 16; size < 512; size += 16 )
        {
            for( int i = 0; i < size; i++ )
                buf1[i] = rand();
            memset( buf4-1, 0xAA, size + 2 );
            call_c( mc_c.memcpy_aligned, buf3, buf1, size );
            call_a( mc_a.memcpy_aligned, buf4, buf1, size );
            if( memcmp( buf3, buf4, size ) || buf4[-1] != 0xAA || buf4[size] != 0xAA )
            {
                ok = 0;
                fprintf( stderr, "memcpy_aligned FAILED: size=%d\n", (int)size );
                break;
            }
        }
        report( "memcpy aligned :" );
    }

    if( mc_a.memzero_aligned != mc_ref.memzero_aligned )
    {
        set_func_name( "memzero_aligned" );
        ok = 1; used_asm = 1;
        for( size_t size = 128; size < 1024; size += 128 )
        {
            memset( buf4-1, 0xAA, size + 2 );
            call_c( mc_c.memzero_aligned, buf3, size );
            call_a( mc_a.memzero_aligned, buf4, size );
            if( memcmp( buf3, buf4, size ) || buf4[-1] != 0xAA || buf4[size] != 0xAA )
            {
                ok = 0;
                fprintf( stderr, "memzero_aligned FAILED: size=%d\n", (int)size );
                break;
            }
        }
        report( "memzero aligned :" );
    }

    return ret;
}

static int check_deblock( int cpu_ref, int cpu_new )
{
    x264_deblock_function_t db_c;
    x264_deblock_function_t db_ref;
    x264_deblock_function_t db_a;
    int ret = 0, ok = 1, used_asm = 0;
    int alphas[36], betas[36];
    int8_t tcs[36][4], tcs_c[36][4];

    x264_deblock_init( 0, &db_c, 0 );
    x264_deblock_init( cpu_ref, &db_ref, 0 );
    x264_deblock_init( cpu_new, &db_a, 0 );

    /* not exactly the real values of a,b,tc but close enough */
    for( int i = 35, a = 255, c = 250; i >= 0; i-- )
    {
        alphas[i] = a << (BIT_DEPTH-8);
        betas[i] = (i+1)/2 << (BIT_DEPTH-8);
        tcs[i][0] = tcs[i][3] = (c+6)/10 << (BIT_DEPTH-8);
        tcs[i][1] = (c+7)/15 << (BIT_DEPTH-8);
        tcs[i][2] = (c+9)/20 << (BIT_DEPTH-8);
        memcpy( tcs_c[i], tcs[i], sizeof(tcs[i]) );
        if( i%3 == 1 )
        {
            /* a bS=0 edge next to filtered ones: tc0 is -1 << (BIT_DEPTH-8), +1 for chroma */
            tcs[i][i&3] = -(1 << (BIT_DEPTH-8));
            tcs_c[i][i&3] = 1 - (1 << (BIT_DEPTH-8));
        }
        a = a*9/10;
        c = c*9/10;
    }

#define TEST_DEBLOCK( name, align, ... ) \
    for( int k = 0; k < 72; k++ ) \
    { \
        int i = k % 36; \
        intptr_t off = 8*32 + (i&15)*4*!align; /* benchmark various alignments of h filter */ \
        for( int j = 0; j < 1024; j++ ) \
            /* three distributions of random to excersize different failure modes; \
             * k >= 36 near PIXEL_MAX, where the filtered pixels clip at the top */ \
            pbuf3[j] = k >= 36 ? PIXEL_MAX - (rand() & 0xf) : rand() & (i&1 ? 0xf : PIXEL_MAX ); \
        memcpy( pbuf4, pbuf3, 1024 * sizeof(pixel) ); \
        if( db_a.name != db_ref.name ) \
        { \
            set_func_name( #name ); \
            used_asm = 1; \
            call_c1( db_c.name, pbuf3+off, (intptr_t)32, alphas[i], betas[i], ##__VA_ARGS__ ); \
            call_a1( db_a.name, pbuf4+off, (intptr_t)32, alphas[i], betas[i], ##__VA_ARGS__ ); \
            if( memcmp( pbuf3, pbuf4, 1024 * sizeof(pixel) ) ) \
            { \
                ok = 0; \
                fprintf( stderr, #name "(a=%d, b=%d%s): [FAILED]\n", alphas[i], betas[i], k >= 36 ? ", near max" : "" ); \
                break; \
            } \
            if( k < 36 ) \
            { \
                call_c2( db_c.name, pbuf3+off, (intptr_t)32, alphas[i], betas[i], ##__VA_ARGS__ ); \
                call_a2( db_a.name, pbuf4+off, (intptr_t)32, alphas[i], betas[i], ##__VA_ARGS__ ); \
            } \
        } \
    }

    TEST_DEBLOCK( deblock_luma[0], 0, tcs[i] );
    TEST_DEBLOCK( deblock_luma[1], 1, tcs[i] );
    TEST_DEBLOCK( deblock_luma_mbaff, 0, tcs[i] );
    TEST_DEBLOCK( deblock_h_chroma_420, 0, tcs_c[i] );
    TEST_DEBLOCK( deblock_h_chroma_422, 0, tcs_c[i] );
    TEST_DEBLOCK( deblock_chroma_420_mbaff, 0, tcs_c[i] );
    TEST_DEBLOCK( deblock_chroma_422_mbaff, 0, tcs_c[i] );
    TEST_DEBLOCK( deblock_chroma[1], 1, tcs_c[i] );
    TEST_DEBLOCK( deblock_luma_intra[0], 0 );
    TEST_DEBLOCK( deblock_luma_intra[1], 1 );
    TEST_DEBLOCK( deblock_luma_intra_mbaff, 0 );
    TEST_DEBLOCK( deblock_h_chroma_420_intra, 0 );
    TEST_DEBLOCK( deblock_h_chroma_422_intra, 0 );
    TEST_DEBLOCK( deblock_chroma_420_intra_mbaff, 0 );
    TEST_DEBLOCK( deblock_chroma_422_intra_mbaff, 0 );
    TEST_DEBLOCK( deblock_chroma_intra[1], 1 );

    if( db_a.deblock_luma_mb && db_a.deblock_luma_mb != db_ref.deblock_luma_mb )
    {
        ALIGNED_ARRAY_16( uint8_t, bs, [2],[8][4] );
        x264_deblock_edge_t e[3];
        set_func_name( "deblock_luma_mb" );
        used_asm = 1;
        for( int i = 0; i < 200; i++ )
        {
            /* frame and field (2x) strides; the block has 4 rows above and 16 columns left */
            intptr_t stride = 32 << (i&1);
            intptr_t off = 4*stride + 16;
            int edges = rand() & 0xff;
            /* full range, near 0, and (i&8) near PIXEL_MAX */
            for( int j = 0; j < 1280; j++ )
                pbuf3[j] = i&8 ? PIXEL_MAX - (rand() & 0xf) : rand() & (i&2 ? 0xf : PIXEL_MAX);
            memcpy( pbuf4, pbuf3, 1280 * sizeof(pixel) );
            for( int j = 0; j < 2*8*4; j++ )
                ((uint8_t*)bs)[j] = (rand()&3) ? rand()&3 : 0;
            if( i&4 )
                for( int j = 0; j < 2*8; j++ )
                    if( !(rand()&3) )
                        M32( (uint8_t*)bs + 4*j ) = 0;
            for( int c = 0; c < 3; c++ )
            {
                int k = rand()%36;
                e[c].tc0[0] = -(1 << (BIT_DEPTH-8));
                for( int j = 1; j < 4; j++ )
                    e[c].tc0[j] = tcs[k][j];
                e[c].alpha = alphas[k];
                e[c].beta = betas[k];
                if( !alphas[k] || !betas[k] )
                    edges &= c == 2 ? 0x11 : ~(c ? 0x10 : 0x01);
            }
            call_c1( db_c.deblock_luma_mb, pbuf3+off, stride, bs, e, edges );
            call_a1( db_a.deblock_luma_mb, pbuf4+off, stride, bs, e, edges );
            if( memcmp( pbuf3, pbuf4, 1280 * sizeof(pixel) ) )
            {
                ok = 0;
                fprintf( stderr, "deblock_luma_mb (stride=%d, edges=%#x): [FAILED]\n", (int)stride, edges );
                break;
            }
        }
        /* bench: one MB per class, edge classes at index 24 (mid qp), smooth pixels:
         * bs12: every edge, bS 1-2; t8x8: the 8x8 transform's edges, bS 2;
         * skip: bS 1 on the MB edges only; intra: bS 3 on the MB edges, bS 2 inside */
        static const char *mb_name[4] = { "bs12", "t8x8", "skip", "intra" };
        static const uint8_t mb_edges[4] = { 0xff, 0x55, 0xff, 0xff };
        ALIGNED_ARRAY_64( pixel, mb_pix,[2][64*24] );
        for( int c = 0; c < 3; c++ )
        {
            e[c].tc0[0] = -(1 << (BIT_DEPTH-8));
            for( int j = 1; j < 4; j++ )
                e[c].tc0[j] = tcs[24][j];
            e[c].alpha = alphas[24];
            e[c].beta = betas[24];
        }
        for( int m = 0; m < 4 && do_bench; m++ )
        {
            bench_srand( 100 + m );
            for( int j = 0; j < 64*24; j++ )
                mb_pix[0][j] = mb_pix[1][j] = PIXEL_MAX/4 + ((bench_rand()&15) << (BIT_DEPTH-8));
            for( int dir = 0; dir < 2; dir++ )
                for( int edge = 0; edge < 8; edge++ )
                    for( int j = 0; j < 4; j++ )
                        bs[dir][edge][j] = m == 0 ? 1 + (bench_rand()&1) : m == 1 ? 2 :
                                           m == 2 ? !edge : edge ? 2 : 3;
            set_func_name( "deblock_luma_mb_%s", mb_name[m] );
            call_c2( db_c.deblock_luma_mb, mb_pix[0]+4*64+16, (intptr_t)64, bs, e, mb_edges[m] );
            call_a2( db_a.deblock_luma_mb, mb_pix[1]+4*64+16, (intptr_t)64, bs, e, mb_edges[m] );
        }
    }

    if( db_a.deblock_strength != db_ref.deblock_strength )
    {
        used_asm = 1;
        for( int i = 0; i < 100; i++ )
        {
            ALIGNED_ARRAY_16( uint8_t, nnz, [X264_SCAN8_SIZE] );
            ALIGNED_4( int8_t ref[2][X264_SCAN8_LUMA_SIZE] );
            ALIGNED_ARRAY_16( int16_t, mv, [2],[X264_SCAN8_LUMA_SIZE][2] );
            ALIGNED_ARRAY_N( uint8_t, bs, [2],[2][8][4] );
            memset( bs, 99, sizeof(uint8_t)*2*4*8*2 );
            for( int j = 0; j < X264_SCAN8_SIZE; j++ )
                nnz[j] = ((rand()&7) == 7) * rand() & 0xf;
            for( int j = 0; j < 2; j++ )
                for( int k = 0; k < X264_SCAN8_LUMA_SIZE; k++ )
                {
                    ref[j][k] = ((rand()&3) != 3) ? 0 : (rand() & 31) - 2;
                    for( int l = 0; l < 2; l++ )
                        mv[j][k][l] = ((rand()&7) != 7) ? (rand()&7) - 3 : (rand()&1023) - 512;
                }
            set_func_name( "deblock_strength" );
            call_c( db_c.deblock_strength, nnz, ref, mv, bs[0], 2<<(i&1), ((i>>1)&1) );
            call_a( db_a.deblock_strength, nnz, ref, mv, bs[1], 2<<(i&1), ((i>>1)&1) );
            if( memcmp( bs[0], bs[1], sizeof(uint8_t)*2*4*8 ) )
            {
                ok = 0;
                fprintf( stderr, "deblock_strength: [FAILED]\n" );
                for( int j = 0; j < 2; j++ )
                {
                    for( int k = 0; k < 2; k++ )
                        for( int l = 0; l < 4; l++ )
                        {
                            for( int m = 0; m < 4; m++ )
                                printf("%d ",bs[j][k][l][m]);
                            printf("\n");
                        }
                    printf("\n");
                }
                break;
            }
        }
    }

    report( "deblock :" );

    return ret;
}

#if HAVE_MMX && ARCH_X86_64
/* the C trellis of encoder/rdo.c, which x86_64 never reaches, on the asm's arguments */
#define x264_cabac_size_unary x264_template(cabac_size_unary)
#define x264_cabac_transition_unary x264_template(cabac_transition_unary)
#define x264_rdo_init x264_template(rdo_init)
extern uint16_t x264_cabac_size_unary[15][128];
extern uint8_t x264_cabac_transition_unary[15][128];
void x264_rdo_init( void );

#define TREF_SCORE_MAX ((uint64_t)-1LL)
#define TREF_SIGN(x,y) ((x^(y >> 31))-(y >> 31))

typedef struct
{
    uint64_t score;
    int level_idx;
    uint8_t cabac_state[4];
} tref_node_t;

typedef struct
{
    uint16_t next;
    uint16_t abs_level;
} tref_level_t;

static int tref_coef( int j, int const_level, int abs_level, int prefix, int suffix_cost,
                      int node_ctx, int level1_ctx, int levelgt1_ctx, uint64_t ssd, int cost_siglast[3],
                      tref_node_t *nodes_cur, tref_node_t *nodes_prev,
                      tref_level_t *level_tree, int levels_used, int lambda2, uint8_t *level_state )
{
    uint64_t score = nodes_prev[j].score + ssd;
    unsigned f8_bits = cost_siglast[ j ? 1 : 2 ];
    uint8_t level1_state = (j >= 3) ? nodes_prev[j].cabac_state[level1_ctx>>2] : level_state[level1_ctx];
    f8_bits += x264_cabac_entropy[level1_state ^ (const_level > 1)];
    uint8_t levelgt1_state = 0;
    if( const_level > 1 )
    {
        levelgt1_state = j >= 6 ? nodes_prev[j].cabac_state[levelgt1_ctx-6] : level_state[levelgt1_ctx];
        f8_bits += x264_cabac_size_unary[prefix][levelgt1_state] + suffix_cost;
    }
    else
        f8_bits += 1 << 8;
    score += (uint64_t)f8_bits * lambda2 >> 4;

    if( score < nodes_cur[node_ctx].score )
    {
        nodes_cur[node_ctx].score = score;
        if( j == 2 || (j <= 3 && node_ctx == 4) )
            memcpy( nodes_cur[node_ctx].cabac_state, level_state+12, 4 );
        else if( j >= 3 )
            memcpy( nodes_cur[node_ctx].cabac_state, nodes_prev[j].cabac_state, 4 );
        if( j >= 3 )
            nodes_cur[node_ctx].cabac_state[level1_ctx>>2] = x264_cabac_transition[level1_state][const_level > 1];
        if( const_level > 1 && node_ctx == 7 )
            nodes_cur[node_ctx].cabac_state[levelgt1_ctx-6] = x264_cabac_transition_unary[prefix][levelgt1_state];
        level_tree[levels_used].next = nodes_prev[j].level_idx;
        level_tree[levels_used].abs_level = abs_level;
        nodes_cur[node_ctx].level_idx = levels_used++;
    }
    return levels_used;
}

static int tref_coef0( int ctx_hi, uint64_t ssd0, tref_node_t *nodes_cur, tref_node_t *nodes_prev,
                       tref_level_t *level_tree, int levels_used )
{
    if( !ctx_hi )
    {
        nodes_cur[0].score = nodes_prev[0].score + ssd0;
        nodes_cur[0].level_idx = nodes_prev[0].level_idx;
    }
    for( int j = 1; j < (ctx_hi ? 8 : 4); j++ )
    {
        if( (int64_t)nodes_prev[j].score < 0 )
        {
            if( !ctx_hi )
                break;
            continue;
        }
        nodes_cur[j].score = nodes_prev[j].score;
        if( j >= 3 )
            memcpy( nodes_cur[j].cabac_state, nodes_prev[j].cabac_state, 4 );
        level_tree[levels_used].next = nodes_prev[j].level_idx;
        level_tree[levels_used].abs_level = 0;
        nodes_cur[j].level_idx = levels_used++;
    }
    return levels_used;
}

/* { j, node_ctx, level1_ctx, levelgt1_ctx (-1: the block's) } in call order */
static const int8_t tref_tab1[2][7][4] =
{
    {{0,1,1,0},{1,2,2,0},{2,3,3,0},{3,3,4,0}},
    {{1,2,2,0},{2,3,3,0},{3,3,4,0},{4,4,0,0},{5,5,0,0},{6,6,0,0},{7,7,0,0}}
};
static const int8_t tref_tabn[2][7][4] =
{
    {{0,4,1,5},{1,4,2,5},{2,4,3,5},{3,4,4,5}},
    {{1,4,2,5},{2,4,3,5},{3,4,4,5},{4,5,0,6},{5,6,0,7},{6,7,0,8},{7,7,0,-1}}
};

static int tref_coefs( int ctx_hi, int const_level, int abs_level, uint64_t ssd0, uint64_t ssd1, int cost_siglast[3],
                       tref_node_t *nodes_cur, tref_node_t *nodes_prev, tref_level_t *level_tree, int levels_used,
                       int lambda2, uint8_t *level_state, int levelgt1_ctx )
{
    int prefix = X264_MIN( abs_level-1, 14 );
    int suffix_cost = const_level > 1 && abs_level >= 15 ? bs_size_ue_big( abs_level - 15 ) << 8 : 0;
    const int8_t (*tab)[4] = const_level > 1 ? tref_tabn[ctx_hi] : tref_tab1[ctx_hi];
    for( int k = 0; k < (ctx_hi ? 7 : 4); k++ )
    {
        int j = tab[k][0];
        if( j && (int64_t)nodes_prev[j].score < 0 )
        {
            if( !ctx_hi )
                break;
            continue;
        }
        levels_used = tref_coef( j, const_level, abs_level, prefix, suffix_cost, tab[k][1], tab[k][2],
                                 tab[k][3] < 0 ? levelgt1_ctx : tab[k][3], j ? ssd1 : ssd0, cost_siglast,
                                 nodes_cur, nodes_prev, level_tree, levels_used, lambda2, level_state );
    }
    return levels_used;
}

static int trellis_ref( const int *unquant_mf, const uint8_t *zigzag, int lambda2, int last_nnz,
                        dctcoef *orig_coefs, dctcoef *quant_coefs, dctcoef *dct,
                        uint8_t *cabac_state_sig, uint8_t *cabac_state_last,
                        uint64_t level_state0, uint16_t level_state1,
                        int num_coefs, int dc, int b_ac, int b_interlaced, dctcoef *fenc_dct, int psy_trellis )
{
    const uint32_t *coef_weight1 = num_coefs == 64 ? x264_dct8_weight_tab : x264_dct4_weight_tab;
    const uint32_t *coef_weight2 = num_coefs == 64 ? x264_dct8_weight2_tab : x264_dct4_weight2_tab;
    int levelgt1_ctx = dc && num_coefs == 8 ? 8 : 9;
    tref_level_t level_tree[64*8*2];
    int levels_used = 1;
    tref_node_t nodes[2][8];
    tref_node_t *nodes_cur = nodes[0];
    tref_node_t *nodes_prev = nodes[1];
    tref_node_t *bnode;
    uint8_t level_state[16];
    memset( nodes, 0, sizeof(nodes) );
    for( int j = 1; j < 8; j++ )
        nodes_cur[j].score = TREF_SCORE_MAX;
    nodes_cur[0].score = 1ULL<<60;
    nodes_cur[0].level_idx = 0;
    level_tree[0].abs_level = 0;
    level_tree[0].next = 0;
    for( int k = 0; k < 8; k++ )
        level_state[k] = level_state0 >> (8*k);
    level_state[8] = level_state1;
    level_state[9] = level_state1 >> 8;
    level_state[12] = level_state[0];
    level_state[13] = level_state[4];
    level_state[14] = level_state[8];
    level_state[15] = level_state[9];

    int ctx_hi = 0;
    for( int i = last_nnz; i >= b_ac; i-- )
    {
        /* never read for the last coef, which has no 4:2:2 dc table entry */
#define TREF_SIGINDEX ( !dc && num_coefs == 64 ? x264_significant_coeff_flag_offset_8x8[b_interlaced][i] :\
                        dc && num_coefs == 8 ? x264_coeff_flag_offset_chroma_422_dc[i] : i )
        if( !quant_coefs[i] )
        {
            if( !ctx_hi )
                nodes_cur[0].score -= (uint64_t)x264_cabac_size_decision_noup2( &cabac_state_sig[TREF_SIGINDEX], 0 ) * lambda2 >> 4;
            for( int j = 1; j < (ctx_hi?8:4); j++ )
            {
                level_tree[levels_used].next = nodes_cur[j].level_idx;
                level_tree[levels_used].abs_level = 0;
                nodes_cur[j].level_idx = levels_used++;
            }
            continue;
        }

        int sign_coef = orig_coefs[zigzag[i]];
        int abs_coef = abs( sign_coef );
        int q = abs( quant_coefs[i] );
        int cost_siglast[3];
        XCHG( tref_node_t*, nodes_cur, nodes_prev );
        for( int j = ctx_hi; j < 8; j++ )
            nodes_cur[j].score = TREF_SCORE_MAX;

        if( i < num_coefs-1 || ctx_hi )
        {
            int lastindex = !dc && num_coefs == 64 ? x264_last_coeff_flag_offset_8x8[i] :
                            dc && num_coefs == 8 ? x264_coeff_flag_offset_chroma_422_dc[i] : i;
            cost_siglast[0] = x264_cabac_size_decision_noup2( &cabac_state_sig[TREF_SIGINDEX], 0 );
            int cost_sig1   = x264_cabac_size_decision_noup2( &cabac_state_sig[TREF_SIGINDEX], 1 );
            cost_siglast[1] = x264_cabac_size_decision_noup2( &cabac_state_last[lastindex], 0 ) + cost_sig1;
            cost_siglast[2] = ctx_hi ? 0 : x264_cabac_size_decision_noup2( &cabac_state_last[lastindex], 1 ) + cost_sig1;
        }
        else
            cost_siglast[0] = cost_siglast[1] = cost_siglast[2] = 0;
#undef TREF_SIGINDEX

        uint64_t ssd0[2], ssd1[2];
        for( int k = 0; k < 2; k++ )
        {
            int abs_level = q-1+k;
            int unquant_abs_level = (((dc?unquant_mf[0]<<1:unquant_mf[zigzag[i]]) * abs_level + 128) >> 8);
            int d = abs_coef - unquant_abs_level;
            if( psy_trellis && i && !dc )
            {
                int predicted_coef = fenc_dct[zigzag[i]] - sign_coef;
                int psy_value = abs(unquant_abs_level + TREF_SIGN(predicted_coef, sign_coef));
                int psy_weight = coef_weight1[zigzag[i]] * psy_trellis;
                int64_t tmp = (int64_t)d*d * coef_weight2[zigzag[i]] - (int64_t)psy_weight * psy_value;
                ssd1[k] = (uint64_t)tmp;
            }
            else
                ssd1[k] = (int64_t)d*d * (dc?256:coef_weight2[zigzag[i]]);
            ssd0[k] = ssd1[k];
            if( !i && !dc && !ctx_hi )
            {
                d = sign_coef - ((TREF_SIGN(unquant_abs_level, sign_coef) + 8)&~15);
                ssd0[k] = (int64_t)d*d * coef_weight2[zigzag[i]];
            }
        }

        if( q == 1 )
        {
            ssd1[0] += (uint64_t)cost_siglast[0] * lambda2 >> 4;
            levels_used = tref_coef0( ctx_hi, ssd0[0]-ssd1[0], nodes_cur, nodes_prev, level_tree, levels_used );
            levels_used = tref_coefs( ctx_hi, 1, 1, ssd0[1]-ssd1[0], ssd1[1]-ssd1[0], cost_siglast, nodes_cur, nodes_prev,
                                      level_tree, levels_used, lambda2, level_state, levelgt1_ctx );
        }
        else if( q == 2 )
        {
            levels_used = tref_coefs( ctx_hi, 1, 1, ssd0[0], ssd1[0], cost_siglast, nodes_cur, nodes_prev,
                                      level_tree, levels_used, lambda2, level_state, levelgt1_ctx );
            levels_used = tref_coefs( ctx_hi, 2, 2, ssd0[1], ssd1[1], cost_siglast, nodes_cur, nodes_prev,
                                      level_tree, levels_used, lambda2, level_state, levelgt1_ctx );
            ctx_hi = 1;
        }
        else
        {
            levels_used = tref_coefs( ctx_hi, 2, q-1, ssd0[0], ssd1[0], cost_siglast, nodes_cur, nodes_prev,
                                      level_tree, levels_used, lambda2, level_state, levelgt1_ctx );
            levels_used = tref_coefs( ctx_hi, 2, q, ssd0[1], ssd1[1], cost_siglast, nodes_cur, nodes_prev,
                                      level_tree, levels_used, lambda2, level_state, levelgt1_ctx );
            ctx_hi = 1;
        }
    }

    bnode = &nodes_cur[ctx_hi];
    for( int j = ctx_hi+1; j < (ctx_hi?8:4); j++ )
        if( nodes_cur[j].score < bnode->score )
            bnode = &nodes_cur[j];

    if( bnode == &nodes_cur[0] )
    {
        if( num_coefs == 16 && !dc )
            memset( dct, 0, 16 * sizeof(dctcoef) );
        return 0;
    }

    int level = bnode->level_idx;
    for( int i = b_ac; i <= last_nnz; i++ )
    {
        dct[zigzag[i]] = TREF_SIGN(level_tree[level].abs_level, dct[zigzag[i]]);
        level = level_tree[level].next;
    }
    return 1;
}
#endif

static x264_quant_function_t *q8s_qf;
static x264_zigzag_function_t *q8s_zz;
/* asm only in zigzagf (NULL in C), so the C reference is called directly */
static int (* const q8s_c[2])( dctcoef dct[64], dctcoef level[64], udctcoef mf[64], udctcoef bias[64], int dequant_mf[6][64], int i_qp ) =
    { x264_quant_8x8_scan_frame, x264_quant_8x8_scan_field };
/* the calls quant_8x8_scan replaces */
static int quant_8x8_scan_split( dctcoef dct[64], dctcoef level[64], udctcoef mf[64], udctcoef bias[64],
                                 int dequant_mf[6][64], int i_qp )
{
    if( !q8s_qf->quant_8x8( dct, mf, bias ) )
        return 0;
    q8s_zz->scan_8x8( level, dct );
    int score = q8s_qf->decimate_score64( level );
    if( dequant_mf )
        q8s_qf->dequant_8x8( dct, dequant_mf, i_qp );
    return 1 | X264_MIN( score, 9 ) << 4;
}

static int check_quant( int cpu_ref, int cpu_new )
{
    x264_quant_function_t qf_c;
    x264_quant_function_t qf_ref;
    x264_quant_function_t qf_a;
    ALIGNED_ARRAY_64( dctcoef, dct1,[64] );
    ALIGNED_ARRAY_64( dctcoef, dct2,[64] );
    ALIGNED_ARRAY_32( dctcoef, dct3,[8],[16] );
    ALIGNED_ARRAY_32( dctcoef, dct4,[8],[16] );
    ALIGNED_ARRAY_32( uint8_t, cqm_buf,[64] );
    ALIGNED_ARRAY_32( dctcoef, lvl1,[4],[16] );
    ALIGNED_ARRAY_32( dctcoef, lvl2,[4],[16] );
    ALIGNED_ARRAY_64( dctcoef, dct0,[64] );
    ALIGNED_ARRAY_64( dctcoef, dct5,[64] );
    ALIGNED_ARRAY_64( dctcoef, lvl3,[64] );
    x264_zigzag_function_t zz_c[2], zz_ref[2], zz_a[2];
    int ret = 0, ok, used_asm;
    int oks[4] = {1,1,1,1}, used_asms[4] = {0,0,0,0};
    x264_t h_buf;
    x264_t *h = &h_buf;
    memset( h, 0, sizeof(*h) );
    h->sps->i_chroma_format_idc = 1;
    x264_param_default( &h->param );
    h->chroma_qp_table = i_chroma_qp_table + 12;
    h->param.analyse.b_transform_8x8 = 1;

    static const uint8_t cqm_test4[16] =
    {
        6,4,6,4,
        4,3,4,3,
        6,4,6,4,
        4,3,4,3
    };
    static const uint8_t cqm_test8[64] =
    {
        3,3,4,3,3,3,4,3,
        3,3,4,3,3,3,4,3,
        4,4,5,4,4,4,5,4,
        3,3,4,3,3,3,4,3,
        3,3,4,3,3,3,4,3,
        3,3,4,3,3,3,4,3,
        4,4,5,4,4,4,5,4,
        3,3,4,3,3,3,4,3
    };

    for( int i_cqm = 0; i_cqm < 7; i_cqm++ )
    {
        if( i_cqm == 0 )
        {
            for( int i = 0; i < 6; i++ )
                h->pps->scaling_list[i] = x264_cqm_flat16;
            h->param.i_cqm_preset = h->pps->i_cqm_preset = X264_CQM_FLAT;
        }
        else if( i_cqm == 1 )
        {
            for( int i = 0; i < 6; i++ )
                h->pps->scaling_list[i] = x264_cqm_jvt[i];
            h->param.i_cqm_preset = h->pps->i_cqm_preset = X264_CQM_JVT;
        }
        else if( i_cqm == 2 )
        {
            for( int i = 0; i < 4; i++ )
                h->pps->scaling_list[i] = cqm_test4;
            for( int i = 4; i < 6; i++ )
                h->pps->scaling_list[i] = x264_cqm_flat16;
            h->param.i_cqm_preset = h->pps->i_cqm_preset = X264_CQM_CUSTOM;
        }
        else if( i_cqm == 3 )
        {
            for( int i = 0; i < 4; i++ )
                h->pps->scaling_list[i] = x264_cqm_flat16;
            for( int i = 4; i < 6; i++ )
                h->pps->scaling_list[i] = cqm_test8;
            h->param.i_cqm_preset = h->pps->i_cqm_preset = X264_CQM_CUSTOM;
        }
        else
        {
            int max_scale = BIT_DEPTH < 10 ? 255 : 228;
            if( i_cqm == 4 )
                for( int i = 0; i < 64; i++ )
                    cqm_buf[i] = 10 + rand() % (max_scale - 9);
            else if( i_cqm == 5 )
                for( int i = 0; i < 64; i++ )
                    cqm_buf[i] = 1;
            else /* at high bit depth dmf << qbits passes 2^15 at the highest qps */
                for( int i = 0; i < 64; i++ )
                    cqm_buf[i] = max_scale;
            for( int i = 0; i < 6; i++ )
                h->pps->scaling_list[i] = cqm_buf;
            h->param.i_cqm_preset = h->pps->i_cqm_preset = X264_CQM_CUSTOM;
        }

        h->param.rc.i_qp_min = 0;
        h->param.rc.i_qp_max = QP_MAX_SPEC;
        x264_cqm_init( h );
        x264_quant_init( h, 0, &qf_c );
        x264_quant_init( h, cpu_ref, &qf_ref );
        x264_quant_init( h, cpu_new, &qf_a );
        x264_zigzag_init( 0, &zz_c[0], &zz_c[1] );
        x264_zigzag_init( cpu_ref, &zz_ref[0], &zz_ref[1] );
        x264_zigzag_init( cpu_new, &zz_a[0], &zz_a[1] );

#define INIT_QUANT8(j,max) \
        { \
            static const int scale1d[8] = {32,31,24,31,32,31,24,31}; \
            for( int i = 0; i < max; i++ ) \
            { \
                int scale = (PIXEL_MAX*scale1d[(i>>3)&7]*scale1d[i&7])/16; \
                dct1[i] = dct2[i] = (j>>(i>>6))&1 ? (rand30()%(2*scale+1))-scale : 0; \
            } \
        }

#define INIT_QUANT4(j,max) \
        { \
            static const int scale1d[4] = {4,6,4,6}; \
            for( int i = 0; i < max; i++ ) \
            { \
                int scale = PIXEL_MAX*scale1d[(i>>2)&3]*scale1d[i&3]; \
                dct1[i] = dct2[i] = (j>>(i>>4))&1 ? (rand30()%(2*scale+1))-scale : 0; \
            } \
        }

#define TEST_QUANT_DC( name, cqm ) \
        if( qf_a.name != qf_ref.name ) \
        { \
            set_func_name( #name ); \
            used_asms[0] = 1; \
            for( int qp = h->param.rc.i_qp_max; qp >= h->param.rc.i_qp_min; qp-- ) \
            { \
                for( int j = 0; j < 2; j++ ) \
                { \
                    int result_c, result_a; \
                    for( int i = 0; i < 16; i++ ) \
                        dct1[i] = dct2[i] = j ? (rand() & 0x1fff) - 0xfff : 0; \
                    result_c = call_c1( qf_c.name, dct1, h->quant4_mf[CQM_4IY][qp][0], h->quant4_bias[CQM_4IY][qp][0] ); \
                    result_a = call_a1( qf_a.name, dct2, h->quant4_mf[CQM_4IY][qp][0], h->quant4_bias[CQM_4IY][qp][0] ); \
                    if( memcmp( dct1, dct2, 16*sizeof(dctcoef) ) || result_c != result_a ) \
                    { \
                        oks[0] = 0; \
                        fprintf( stderr, #name "(cqm=%d): [FAILED]\n", i_cqm ); \
                        break; \
                    } \
                    call_c2( qf_c.name, dct1, h->quant4_mf[CQM_4IY][qp][0], h->quant4_bias[CQM_4IY][qp][0] ); \
                    call_a2( qf_a.name, dct2, h->quant4_mf[CQM_4IY][qp][0], h->quant4_bias[CQM_4IY][qp][0] ); \
                } \
            } \
        }

#define TEST_QUANT( qname, block, type, w, maxj ) \
        if( qf_a.qname != qf_ref.qname ) \
        { \
            set_func_name( #qname ); \
            used_asms[0] = 1; \
            for( int qp = h->param.rc.i_qp_max; qp >= h->param.rc.i_qp_min; qp-- ) \
            { \
                for( int j = 0; j < maxj; j++ ) \
                { \
                    INIT_QUANT##type(j, w*w) \
                    if( j >= 2 && maxj == 4 ) \
                    { \
                        /* one coefficient, anywhere in the block */ \
                        int k = rand() % (w*w); \
                        dctcoef v = dct1[k] ? dct1[k] : 1; \
                        memset( dct1, 0, w*w*sizeof(dctcoef) ); \
                        memset( dct2, 0, w*w*sizeof(dctcoef) ); \
                        dct1[k] = dct2[k] = j&1 ? v : (v < 0 ? -1 : 1) * PIXEL_MAX*4; \
                    } \
                    int result_c = call_c1( qf_c.qname, (void*)dct1, h->quant##type##_mf[block][qp], h->quant##type##_bias[block][qp] ); \
                    int result_a = call_a1( qf_a.qname, (void*)dct2, h->quant##type##_mf[block][qp], h->quant##type##_bias[block][qp] ); \
                    if( memcmp( dct1, dct2, w*w*sizeof(dctcoef) ) || result_c != result_a ) \
                    { \
                        oks[0] = 0; \
                        fprintf( stderr, #qname "(qp=%d, cqm=%d, block="#block"): [FAILED]\n", qp, i_cqm ); \
                        break; \
                    } \
                    call_c2( qf_c.qname, (void*)dct1, h->quant##type##_mf[block][qp], h->quant##type##_bias[block][qp] ); \
                    call_a2( qf_a.qname, (void*)dct2, h->quant##type##_mf[block][qp], h->quant##type##_bias[block][qp] ); \
                } \
            } \
        }

        TEST_QUANT( quant_8x8, CQM_8IY, 8, 8, 4 );
        TEST_QUANT( quant_8x8, CQM_8PY, 8, 8, 4 );
        TEST_QUANT( quant_4x4, CQM_4IY, 4, 4, 4 );
        TEST_QUANT( quant_4x4, CQM_4PY, 4, 4, 4 );
        TEST_QUANT( quant_4x4x4, CQM_4IY, 4, 8, 16 );
        TEST_QUANT( quant_4x4x4, CQM_4PY, 4, 8, 16 );
        TEST_QUANT_DC( quant_4x4_dc, **h->quant4_mf[CQM_4IY] );
        TEST_QUANT_DC( quant_2x2_dc, **h->quant4_mf[CQM_4IC] );

#define TEST_DEQUANT( qname, dqname, block, w ) \
        if( qf_a.dqname != qf_ref.dqname ) \
        { \
            set_func_name( "%s_%s", #dqname, i_cqm?"cqm":"flat" ); \
            used_asms[1] = 1; \
            for( int qp = h->param.rc.i_qp_max; qp >= h->param.rc.i_qp_min; qp-- ) \
            { \
                INIT_QUANT##w(1, w*w) \
                qf_c.qname( dct1, h->quant##w##_mf[block][qp], h->quant##w##_bias[block][qp] ); \
                memcpy( dct2, dct1, w*w*sizeof(dctcoef) ); \
                call_c1( qf_c.dqname, dct1, h->dequant##w##_mf[block], qp ); \
                call_a1( qf_a.dqname, dct2, h->dequant##w##_mf[block], qp ); \
                if( memcmp( dct1, dct2, w*w*sizeof(dctcoef) ) ) \
                { \
                    oks[1] = 0; \
                    fprintf( stderr, #dqname "(qp=%d, cqm=%d, block="#block"): [FAILED]\n", qp, i_cqm ); \
                    break; \
                } \
                call_c2( qf_c.dqname, dct1, h->dequant##w##_mf[block], qp ); \
                call_a2( qf_a.dqname, dct2, h->dequant##w##_mf[block], qp ); \
            } \
        }

        TEST_DEQUANT( quant_8x8, dequant_8x8, CQM_8IY, 8 );
        TEST_DEQUANT( quant_8x8, dequant_8x8, CQM_8PY, 8 );
        TEST_DEQUANT( quant_4x4, dequant_4x4, CQM_4IY, 4 );
        TEST_DEQUANT( quant_4x4, dequant_4x4, CQM_4PY, 4 );

        /* j: bits 0-3 nonzero blocks (all zero when j%8 == 7), bits 4-5 level size, bit 6 no dequant,
         * bit 7 zero DC; levels near +-1 exercise the decimate score */
#define TEST_QUANT_SCAN( name, block, ac ) \
        for( int fld = 0; fld < 2; fld++ ) \
            if( zz_a[fld].name != zz_ref[fld].name ) \
            { \
                set_func_name( "%s_%s_%s", #name, fld?"field":"frame", i_cqm?"cqm":"flat" ); \
                used_asms[3] = 1; \
                for( int qp = h->param.rc.i_qp_max; qp >= h->param.rc.i_qp_min; qp-- ) \
                { \
                    udctcoef *mf = h->quant4_mf[block][qp], *bias = h->quant4_bias[block][qp]; \
                    for( int j = 0; j < 256; j++ ) \
                    { \
                        static const int scale1d[4] = {4,6,4,6}; \
                        int (*dmf)[16] = j&64 ? NULL : h->dequant4_mf[block]; \
                        for( int k = 0; k < 64; k++ ) \
                        { \
                            int big = PIXEL_MAX*scale1d[(k>>2)&3]*scale1d[k&3]; \
                            int small = X264_MIN( big, ((j>>4)&3) == 1 ? (3<<15)/mf[k&15] : (3<<16)/mf[k&15] ); \
                            int x = ((j>>4)&3) == 0 ? rand()%(2*big+1) - big \
                                  : ((j>>4)&3) == 3 ? (rand()&15 ? 0 : rand()&1 ? big : -big) \
                                  : (rand()&3 ? 0 : rand()%(2*small+1) - small); \
                            dct3[k>>4][k&15] = dct4[k>>4][k&15] = (j>>(k>>4))&1 && (j&7) != 7 ? x : 0; \
                        } \
                        if( (ac) && (j&128) ) \
                            for( int k = 0; k < 4; k++ ) \
                                dct3[k][0] = dct4[k][0] = 0; \
                        for( int k = 0; k < 64; k++ ) \
                            lvl1[k>>4][k&15] = lvl2[k>>4][k&15] = 0x5a5a + k; \
                        int res_c = call_c1( zz_c[fld].name, dct3, lvl1, mf, bias, dmf, qp ); \
                        int res_a = call_a1( zz_a[fld].name, dct4, lvl2, mf, bias, dmf, qp ); \
                        if( res_c != res_a || memcmp( dct3, dct4, 64*sizeof(dctcoef) ) || memcmp( lvl1, lvl2, 64*sizeof(dctcoef) ) ) \
                        { \
                            oks[3] = 0; \
                            fprintf( stderr, #name "_%s (qp=%d, cqm=%d, block="#block", j=%d, res_c=%x, res_asm=%x): [FAILED]\n", \
                                     fld?"field":"frame", qp, i_cqm, j, res_c, res_a ); \
                            break; \
                        } \
                        call_c2( zz_c[fld].name, dct3, lvl1, mf, bias, dmf, qp ); \
                        call_a2( zz_a[fld].name, dct4, lvl2, mf, bias, dmf, qp ); \
                    } \
                } \
            }

        TEST_QUANT_SCAN( quant_4x4x4_scan, CQM_4PY, 0 );
        TEST_QUANT_SCAN( quant_4x4x4_scan, CQM_4PC, 0 );
        TEST_QUANT_SCAN( quant_4x4x4_scan_ac, CQM_4IY, 1 );
        TEST_QUANT_SCAN( quant_4x4x4_scan_ac, CQM_4IC, 1 );

        /* j: bits 0-1 level size (full range, about +-1, about +-3, extremes), bits 2-3 nonzero rate 1, 1/4, 1/16,
         * 1/64, bit 4 no dequant, bit 5 all zero. Checked against C and the C calls it replaces. */
#define TEST_QUANT8_SCAN( block ) \
        for( int fld = 0; fld < 2; fld++ ) \
            if( zz_a[fld].quant_8x8_scan != zz_ref[fld].quant_8x8_scan ) \
            { \
                used_asms[3] = 1; \
                for( int qp = h->param.rc.i_qp_max; qp >= h->param.rc.i_qp_min; qp-- ) \
                { \
                    udctcoef *mf = h->quant8_mf[block][qp], *bias = h->quant8_bias[block][qp]; \
                    dctcoef *l1 = (dctcoef*)lvl1, *l2 = (dctcoef*)lvl2; \
                    for( int j = 0; j < 64; j++ ) \
                    { \
                        static const int scale1d[8] = {32,31,24,31,32,31,24,31}; \
                        int (*dmf)[64] = j&16 ? NULL : h->dequant8_mf[block]; \
                        int size = j&3, rate = 2*((j>>2)&3); \
                        set_func_name( "quant_8x8_scan_%s_%s", fld?"field":"frame", i_cqm?"cqm":"flat" ); \
                        for( int k = 0; k < 64; k++ ) \
                        { \
                            int big = PIXEL_MAX*scale1d[k>>3]*scale1d[k&7]/16; \
                            int small = X264_MIN( big, size == 1 ? (3<<15)/mf[k] : (3<<16)/mf[k] ); \
                            int x = size == 0 ? rand30()%(2*big+1) - big \
                                  : size == 3 ? (rand()&1 ? big : -big) \
                                  : rand()%(2*small+1) - small; \
                            dct0[k] = (rand() & ((1<<rate)-1)) || (j&32) ? 0 : x; \
                        } \
                        memcpy( dct1, dct0, 64*sizeof(dctcoef) ); \
                        memcpy( dct2, dct0, 64*sizeof(dctcoef) ); \
                        memcpy( dct5, dct0, 64*sizeof(dctcoef) ); \
                        for( int k = 0; k < 64; k++ ) \
                            l1[k] = l2[k] = lvl3[k] = 0x5a5a + k; \
                        q8s_qf = &qf_c; \
                        q8s_zz = &zz_c[fld]; \
                        int res_s = quant_8x8_scan_split( dct5, lvl3, mf, bias, dmf, qp ); \
                        int res_c = call_c1( q8s_c[fld], dct1, l1, mf, bias, dmf, qp ); \
                        int res_a = call_a1( zz_a[fld].quant_8x8_scan, dct2, l2, mf, bias, dmf, qp ); \
                        if( res_c != res_a || res_c != res_s || memcmp( dct1, dct2, 64*sizeof(dctcoef) ) || \
                            memcmp( dct1, dct5, 64*sizeof(dctcoef) ) || memcmp( l1, l2, 64*sizeof(dctcoef) ) || \
                            memcmp( l1, lvl3, 64*sizeof(dctcoef) ) ) \
                        { \
                            oks[3] = 0; \
                            fprintf( stderr, "quant_8x8_scan_%s (qp=%d, cqm=%d, block="#block", j=%d, res_c=%x, res_asm=%x, res_split=%x): [FAILED]\n", \
                                     fld?"field":"frame", qp, i_cqm, j, res_c, res_a, res_s ); \
                            break; \
                        } \
                    } \
                } \
            }

        TEST_QUANT8_SCAN( CQM_8IY );
        TEST_QUANT8_SCAN( CQM_8PY );

        /* bench, flat and jvt cqm: 16 fixed inter blocks, the check's 4 level sizes at its 4 nonzero rates,
         * qp 24-36, with dequant. _split times the dispatched calls it replaces on the same blocks. */
        if( do_bench && i_cqm < 2 )
            for( int fld = 0; fld < 2; fld++ )
                if( zz_a[fld].quant_8x8_scan != zz_ref[fld].quant_8x8_scan )
                {
                    q8s_qf = &qf_a;
                    q8s_zz = &zz_a[fld];
                    bench_srand( 800 + fld );
                    for( int i = 0; i < 16; i++ )
                    {
                        static const int scale1d[8] = {32,31,24,31,32,31,24,31};
                        int qp = 24 + 4*(i>>2), size = i&3, rate = 2*(i>>2);
                        udctcoef *mf = h->quant8_mf[CQM_8PY][qp], *bias = h->quant8_bias[CQM_8PY][qp];
                        int (*dmf)[64] = h->dequant8_mf[CQM_8PY];
                        for( int k = 0; k < 64; k++ )
                        {
                            int big = PIXEL_MAX*scale1d[k>>3]*scale1d[k&7]/16;
                            int small = X264_MIN( big, size == 1 ? (3<<15)/mf[k] : (3<<16)/mf[k] );
                            int x = size == 0 ? bench_rand()%(2*big+1) - big
                                  : size == 3 ? (bench_rand()&1 ? big : -big)
                                  : bench_rand()%(2*small+1) - small;
                            dct0[k] = bench_rand() & ((1<<rate)-1) ? 0 : x;
                        }
                        dctcoef *l1 = (dctcoef*)lvl1, *l2 = (dctcoef*)lvl2;
                        set_func_name( "quant_8x8_scan_%s_%s", fld?"field":"frame", i_cqm?"cqm":"flat" );
                        memcpy( dct1, dct0, 64*sizeof(dctcoef) );
                        memcpy( dct2, dct0, 64*sizeof(dctcoef) );
                        call_c2( q8s_c[fld], dct1, l1, mf, bias, dmf, qp );
                        call_a2( zz_a[fld].quant_8x8_scan, dct2, l2, mf, bias, dmf, qp );
                        set_func_name( "quant_8x8_scan_split_%s_%s", fld?"field":"frame", i_cqm?"cqm":"flat" );
                        memcpy( dct5, dct0, 64*sizeof(dctcoef) );
                        call_bench( quant_8x8_scan_split, cpu_new, dct5, lvl3, mf, bias, dmf, qp );
                    }
                }

#define TEST_DEQUANT_DC( qname, dqname, block, w ) \
        if( qf_a.dqname != qf_ref.dqname ) \
        { \
            set_func_name( "%s_%s", #dqname, i_cqm?"cqm":"flat" ); \
            used_asms[1] = 1; \
            for( int qp = h->param.rc.i_qp_max; qp >= h->param.rc.i_qp_min; qp-- ) \
            { \
                for( int i = 0; i < 16; i++ ) \
                    dct1[i] = rand()%(PIXEL_MAX*16*2+1) - PIXEL_MAX*16; \
                qf_c.qname( dct1, h->quant##w##_mf[block][qp][0]>>1, h->quant##w##_bias[block][qp][0]>>1 ); \
                memcpy( dct2, dct1, w*w*sizeof(dctcoef) ); \
                call_c1( qf_c.dqname, dct1, h->dequant##w##_mf[block], qp ); \
                call_a1( qf_a.dqname, dct2, h->dequant##w##_mf[block], qp ); \
                if( memcmp( dct1, dct2, w*w*sizeof(dctcoef) ) ) \
                { \
                    oks[1] = 0; \
                    fprintf( stderr, #dqname "(qp=%d, cqm=%d, block="#block"): [FAILED]\n", qp, i_cqm ); \
                } \
                /* small levels at every qp: with a cqm, dmf << qbits passes 2^15 at high qp */ \
                for( int i = 0; i < 16; i++ ) \
                    dct1[i] = dct2[i] = rand()%7 - 3; \
                call_c1( qf_c.dqname, dct1, h->dequant##w##_mf[block], qp ); \
                call_a1( qf_a.dqname, dct2, h->dequant##w##_mf[block], qp ); \
                if( memcmp( dct1, dct2, w*w*sizeof(dctcoef) ) ) \
                { \
                    oks[1] = 0; \
                    fprintf( stderr, #dqname "(qp=%d, cqm=%d, block="#block", small levels): [FAILED]\n", qp, i_cqm ); \
                } \
                call_c2( qf_c.dqname, dct1, h->dequant##w##_mf[block], qp ); \
                call_a2( qf_a.dqname, dct2, h->dequant##w##_mf[block], qp ); \
            } \
        }

        TEST_DEQUANT_DC( quant_4x4_dc, dequant_4x4_dc, CQM_4IY, 4 );

        if( qf_a.idct_dequant_2x4_dc != qf_ref.idct_dequant_2x4_dc )
        {
            set_func_name( "idct_dequant_2x4_dc_%s", i_cqm?"cqm":"flat" );
            used_asms[1] = 1;
            for( int qp = h->chroma_qp_table[h->param.rc.i_qp_max]; qp >= h->chroma_qp_table[h->param.rc.i_qp_min]; qp-- )
            {
                for( int i = 0; i < 8; i++ )
                    dct1[i] = rand()%(PIXEL_MAX*16*2+1) - PIXEL_MAX*16;
                qf_c.quant_2x2_dc( &dct1[0], h->quant4_mf[CQM_4IC][qp+3][0]>>1, h->quant4_bias[CQM_4IC][qp+3][0]>>1 );
                qf_c.quant_2x2_dc( &dct1[4], h->quant4_mf[CQM_4IC][qp+3][0]>>1, h->quant4_bias[CQM_4IC][qp+3][0]>>1 );
                call_c( qf_c.idct_dequant_2x4_dc, dct1, dct3, h->dequant4_mf[CQM_4IC], qp+3 );
                call_a( qf_a.idct_dequant_2x4_dc, dct1, dct4, h->dequant4_mf[CQM_4IC], qp+3 );
                for( int i = 0; i < 8; i++ )
                    if( dct3[i][0] != dct4[i][0] )
                    {
                        oks[1] = 0;
                        fprintf( stderr, "idct_dequant_2x4_dc (qp=%d, cqm=%d): [FAILED]\n", qp, i_cqm );
                        break;
                    }
            }
        }

        if( qf_a.idct_dequant_2x4_dconly != qf_ref.idct_dequant_2x4_dconly )
        {
            set_func_name( "idct_dequant_2x4_dconly_%s", i_cqm?"cqm":"flat" );
            used_asms[1] = 1;
            for( int qp = h->chroma_qp_table[h->param.rc.i_qp_max]; qp >= h->chroma_qp_table[h->param.rc.i_qp_min]; qp-- )
            {
                for( int i = 0; i < 8; i++ )
                    dct1[i] = rand()%(PIXEL_MAX*16*2+1) - PIXEL_MAX*16;
                qf_c.quant_2x2_dc( &dct1[0], h->quant4_mf[CQM_4IC][qp+3][0]>>1, h->quant4_bias[CQM_4IC][qp+3][0]>>1 );
                qf_c.quant_2x2_dc( &dct1[4], h->quant4_mf[CQM_4IC][qp+3][0]>>1, h->quant4_bias[CQM_4IC][qp+3][0]>>1 );
                memcpy( dct2, dct1, 8*sizeof(dctcoef) );
                call_c1( qf_c.idct_dequant_2x4_dconly, dct1, h->dequant4_mf[CQM_4IC], qp+3 );
                call_a1( qf_a.idct_dequant_2x4_dconly, dct2, h->dequant4_mf[CQM_4IC], qp+3 );
                if( memcmp( dct1, dct2, 8*sizeof(dctcoef) ) )
                {
                    oks[1] = 0;
                    fprintf( stderr, "idct_dequant_2x4_dconly (qp=%d, cqm=%d): [FAILED]\n", qp, i_cqm );
                    break;
                }
                call_c2( qf_c.idct_dequant_2x4_dconly, dct1, h->dequant4_mf[CQM_4IC], qp+3 );
                call_a2( qf_a.idct_dequant_2x4_dconly, dct2, h->dequant4_mf[CQM_4IC], qp+3 );
            }
        }

#define TEST_OPTIMIZE_CHROMA_DC( optname, size ) \
        if( qf_a.optname != qf_ref.optname ) \
        { \
            set_func_name( #optname ); \
            used_asms[2] = 1; \
            for( int qp = h->param.rc.i_qp_max; qp >= h->param.rc.i_qp_min; qp-- ) \
            { \
                int qpdc = qp + (size == 8 ? 3 : 0); \
                int dmf = h->dequant4_mf[CQM_4IC][qpdc%6][0] << qpdc/6; \
                if( dmf > 32*64 ) \
                    continue; \
                for( int i = 16; ; i <<= 1 ) \
                { \
                    int res_c, res_asm; \
                    int max = X264_MIN( i, PIXEL_MAX*16 ); \
                    for( int j = 0; j < size; j++ ) \
                        dct1[j] = rand()%(max*2+1) - max; \
                    for( int j = 0; j < size; j += 4 ) \
                        qf_c.quant_2x2_dc( &dct1[j], h->quant4_mf[CQM_4IC][qpdc][0]>>1, h->quant4_bias[CQM_4IC][qpdc][0]>>1 ); \
                    memcpy( dct2, dct1, size*sizeof(dctcoef) ); \
                    res_c   = call_c1( qf_c.optname, dct1, dmf ); \
                    res_asm = call_a1( qf_a.optname, dct2, dmf ); \
                    if( res_c != res_asm || memcmp( dct1, dct2, size*sizeof(dctcoef) ) ) \
                    { \
                        oks[2] = 0; \
                        fprintf( stderr, #optname "(qp=%d, res_c=%d, res_asm=%d): [FAILED]\n", qp, res_c, res_asm ); \
                    } \
                    if( i >= PIXEL_MAX*16 ) \
                        break; \
                } \
                for( int k = 0; k <= 3*size+8; k++ ) \
                { \
                    int res_c, res_asm; \
                    memset( dct1, 0, size*sizeof(dctcoef) ); \
                    if( k < 2*size ) \
                        dct1[k>>1] = (k&1 ? -1 : 1) * (1 + rand()%3); \
                    else if( k < 3*size ) \
                        dct1[k-2*size] = (rand()&1 ? -1 : 1) * PIXEL_MAX*16; \
                    else if( k > 3*size ) \
                        for( int j = 0; j < size; j++ ) \
                            dct1[j] = rand()%5 - 2; \
                    memcpy( dct2, dct1, size*sizeof(dctcoef) ); \
                    res_c   = call_c1( qf_c.optname, dct1, dmf ); \
                    res_asm = call_a1( qf_a.optname, dct2, dmf ); \
                    if( res_c != res_asm || memcmp( dct1, dct2, size*sizeof(dctcoef) ) ) \
                    { \
                        oks[2] = 0; \
                        fprintf( stderr, #optname "(qp=%d, edge=%d, res_c=%d, res_asm=%d): [FAILED]\n", qp, k, res_c, res_asm ); \
                    } \
                } \
            } \
        }

/* bench: flat cqm only, chroma dc qps 12, 18, 21, four fixed blocks each of
 * levels from coefs +-64 */
#define BENCH_OPTIMIZE_CHROMA_DC( optname, size ) \
        if( qf_a.optname != qf_ref.optname && !i_cqm && do_bench ) \
        { \
            static const int qpdcs[3] = { 12, 18, 21 }; \
            set_func_name( #optname "_flat" ); \
            bench_srand( 500 + size ); \
            for( int q = 0; q < 3; q++ ) \
            { \
                int qpdc = qpdcs[q]; \
                int dmf = h->dequant4_mf[CQM_4IC][qpdc%6][0] << qpdc/6; \
                for( int blk = 0; blk < 4; blk++ ) \
                { \
                    for( int j = 0; j < size; j++ ) \
                        dct1[j] = bench_rand()%129 - 64; \
                    for( int j = 0; j < size; j += 4 ) \
                        qf_c.quant_2x2_dc( &dct1[j], h->quant4_mf[CQM_4IC][qpdc][0]>>1, h->quant4_bias[CQM_4IC][qpdc][0]>>1 ); \
                    memcpy( dct2, dct1, size*sizeof(dctcoef) ); \
                    call_c2( qf_c.optname, dct1, dmf ); \
                    call_a2( qf_a.optname, dct2, dmf ); \
                } \
            } \
        }

        TEST_OPTIMIZE_CHROMA_DC( optimize_chroma_2x2_dc, 4 );
        TEST_OPTIMIZE_CHROMA_DC( optimize_chroma_2x4_dc, 8 );
        BENCH_OPTIMIZE_CHROMA_DC( optimize_chroma_2x2_dc, 4 );
        BENCH_OPTIMIZE_CHROMA_DC( optimize_chroma_2x4_dc, 8 );

        x264_cqm_delete( h );
    }

    ok = oks[0]; used_asm = used_asms[0];
    report( "quant :" );

    ok = oks[1]; used_asm = used_asms[1];
    report( "dequant :" );

    ok = oks[2]; used_asm = used_asms[2];
    report( "optimize chroma dc :" );

    ok = oks[3]; used_asm = used_asms[3];
    report( "quant scan :" );

    ok = 1; used_asm = 0;
    if( qf_a.denoise_dct != qf_ref.denoise_dct )
    {
        used_asm = 1;
        for( int size = 16; size <= 64; size += 48 )
        {
            set_func_name( "denoise_dct" );
            memcpy( dct1, buf1, size*sizeof(dctcoef) );
            memcpy( dct2, buf1, size*sizeof(dctcoef) );
            memcpy( buf3+256, buf3, 256 );
            call_c1( qf_c.denoise_dct, dct1, (uint32_t*)buf3,       (udctcoef*)buf2, size );
            call_a1( qf_a.denoise_dct, dct2, (uint32_t*)(buf3+256), (udctcoef*)buf2, size );
            if( memcmp( dct1, dct2, size*sizeof(dctcoef) ) || memcmp( buf3, buf3+256, size*sizeof(uint32_t) ) )
                ok = 0;
            call_c2( qf_c.denoise_dct, dct1, (uint32_t*)buf3,       (udctcoef*)buf2, size );
            call_a2( qf_a.denoise_dct, dct2, (uint32_t*)(buf3+256), (udctcoef*)buf2, size );
        }
        /* offsets below the coefficient range, so both the zeroing and the sign restore are reached */
        ALIGNED_ARRAY_64( udctcoef, nr_offset,[64] );
        ALIGNED_ARRAY_64( uint32_t, nr_sum,[2],[64] );
        for( int i = 0; i < 32 && ok; i++ )
        {
            int size = i&1 ? 64 : 16;
            int range = i&2 ? 1<<(BIT_DEPTH+6) : 1<<(BIT_DEPTH-2);
            for( int k = 0; k < 64; k++ )
            {
                dct1[k] = dct2[k] = i == 31 ? (k&1 ? -1 : 1)*(1<<(BIT_DEPTH+6))
                                  : i&4 && !(rand()&3) ? 0 : rand()%(2*range+1) - range;
                nr_offset[k] = rand() % (i&8 ? 1<<BIT_DEPTH : 64);
                nr_sum[0][k] = nr_sum[1][k] = rand30();
            }
            qf_c.denoise_dct( dct1, nr_sum[0], nr_offset, size );
            qf_a.denoise_dct( dct2, nr_sum[1], nr_offset, size );
            if( memcmp( dct1, dct2, 64*sizeof(dctcoef) ) || memcmp( nr_sum[0], nr_sum[1], sizeof(nr_sum[0]) ) )
            {
                ok = 0;
                fprintf( stderr, "denoise_dct (size=%d, range=%d): [FAILED]\n", size, range );
            }
        }
    }
    report( "denoise dct :" );

#define TEST_DECIMATE( decname, w, ac, thresh ) \
    if( qf_a.decname != qf_ref.decname ) \
    { \
        set_func_name( #decname ); \
        used_asm = 1; \
        for( int i = 0; i < 200; i++ ) \
        { \
            static const int distrib[16] = {1,1,1,1,1,1,1,1,1,1,1,1,2,3,4};\
            static const int zerorate_lut[4] = {3,7,15,31};\
            int zero_rate = zerorate_lut[i&3];\
            for( int idx = 0; idx < w*w; idx++ ) \
            { \
                int sign = (rand()&1) ? -1 : 1; \
                int abs_level = distrib[rand()&15]; \
                if( abs_level == 4 ) abs_level = rand()&0x3fff; \
                int zero = !(rand()&zero_rate); \
                /* i >= 100: levels +-1 only; dense, all set, a single coef, or long runs */ \
                if( i >= 100 ) \
                { \
                    abs_level = 1; \
                    zero = (i&3) == 0 ? rand()&1 : (i&3) == 1 ? 1 : (i&3) == 2 ? idx == i%(w*w) : !(rand()&63); \
                } \
                dct1[idx] = zero * abs_level * sign; \
            } \
            /* the DC is not part of the AC score */ \
            if( ac ) \
                dct1[0] = i&1 ? 0 : (rand()&0x3ff) - 0x200; \
            int result_c = call_c1( qf_c.decname, dct1 ); \
            int result_a = call_a1( qf_a.decname, dct1 ); \
            if( X264_MIN(result_c,thresh) != X264_MIN(result_a,thresh) ) \
            { \
                ok = 0; \
                fprintf( stderr, #decname ": [FAILED]\n" ); \
                break; \
            } \
        } \
        /* every run length: one coef at p, or a pair p > q */ \
        for( int p = ac; p < w*w && ok; p++ ) \
            for( int q = ac-1; q < p && ok; q++ ) \
            { \
                memset( dct1, 0, w*w*sizeof(dctcoef) ); \
                dct1[p] = 1; \
                if( q >= ac ) \
                    dct1[q] = -1; \
                int result_c = call_c1( qf_c.decname, dct1 ); \
                int result_a = call_a1( qf_a.decname, dct1 ); \
                if( X264_MIN(result_c,thresh) != X264_MIN(result_a,thresh) ) \
                { \
                    ok = 0; \
                    fprintf( stderr, #decname " (p=%d, q=%d): [FAILED]\n", p, q ); \
                } \
            } \
    }

    ok = 1; used_asm = 0;
    TEST_DECIMATE( decimate_score64, 8, 0, 6 );
    TEST_DECIMATE( decimate_score16, 4, 0, 6 );
    TEST_DECIMATE( decimate_score15, 4, 1, 7 );

/* bench: 16 fixed blocks, the check's level distribution at each of its four zero rates */
#define BENCH_DECIMATE( decname, w, ac ) \
    if( qf_a.decname != qf_ref.decname && do_bench ) \
    { \
        set_func_name( #decname ); \
        bench_srand( 700 + w*w + ac ); \
        for( int i = 0; i < 16; i++ ) \
        { \
            static const int distrib[16] = {1,1,1,1,1,1,1,1,1,1,1,1,2,3,4}; \
            int zero_rate = (4 << (i&3)) - 1; \
            for( int idx = 0; idx < w*w; idx++ ) \
            { \
                int r = bench_rand(); \
                int abs_level = distrib[r&15]; \
                if( abs_level == 4 ) \
                    abs_level = (r>>4)&0x3fff; \
                dct1[idx] = !((r>>18)&zero_rate) * abs_level * ((r>>24)&1 ? -1 : 1); \
            } \
            if( ac ) \
                dct1[0] = 0; \
            call_c2( qf_c.decname, dct1 ); \
            call_a2( qf_a.decname, dct1 ); \
        } \
    }

    BENCH_DECIMATE( decimate_score64, 8, 0 );
    BENCH_DECIMATE( decimate_score16, 4, 0 );
    BENCH_DECIMATE( decimate_score15, 4, 1 );
    report( "decimate_score :" );

/* i 8-15: dense +-1, else sparse with either sign and magnitudes up to the dctcoef range */
#define TEST_LAST_COEF( i ) \
    ( (i) >= 8 && (i) < 16 ? (rand()&1 ? -1 : 1) \
      : ((i)&1 ? -1 : 1) * (!(rand()&3) + (!(rand()&15))*(rand()&0x3fffffff)) )

#define TEST_LAST( last, lastname, size, ac ) \
    if( qf_a.last != qf_ref.last ) \
    { \
        set_func_name( #lastname ); \
        used_asm = 1; \
        for( int i = 0; i < 100; i++ ) \
        { \
            int nnz = 0; \
            int max = i < 16 ? size : rand() % (size+1); \
            memset( dct1, 0, size*sizeof(dctcoef) ); \
            for( int idx = ac; idx < max; idx++ ) \
                nnz |= dct1[idx] = TEST_LAST_COEF( i ); \
            /* max < size: the last coef also, negative or with only its high half set */ \
            if( (i&3) == 3 ) \
                nnz |= dct1[size-1] = i&4 ? -1 : 1 << (4*sizeof(dctcoef)); \
            if( !nnz ) \
                dct1[ac] = 1; \
            if( ac && (i&1) ) \
                dct1[0] = -1; /* the coef before the block */ \
            int result_c = call_c( qf_c.last, dct1+ac ); \
            int result_a = call_a( qf_a.last, dct1+ac ); \
            if( result_c != result_a ) \
            { \
                ok = 0; \
                fprintf( stderr, #lastname ": [FAILED]\n" ); \
                break; \
            } \
        } \
    }

    ok = 1; used_asm = 0;
    TEST_LAST( coeff_last4              , coeff_last4,   4, 0 );
    TEST_LAST( coeff_last8              , coeff_last8,   8, 0 );
    TEST_LAST( coeff_last[  DCT_LUMA_AC], coeff_last15, 16, 1 );
    TEST_LAST( coeff_last[ DCT_LUMA_4x4], coeff_last16, 16, 0 );
    TEST_LAST( coeff_last[ DCT_LUMA_8x8], coeff_last64, 64, 0 );
    report( "coeff_last :" );

#define TEST_LEVELRUN( lastname, name, size, ac ) \
    if( qf_a.lastname != qf_ref.lastname ) \
    { \
        set_func_name( #name ); \
        used_asm = 1; \
        for( int i = 0; i < 100; i++ ) \
        { \
            x264_run_level_t runlevel_c, runlevel_a; \
            int nnz = 0; \
            int max = i < 16 ? size : rand() % (size+1); \
            memset( dct1, 0, size*sizeof(dctcoef) ); \
            memcpy( &runlevel_a, buf1+i, sizeof(x264_run_level_t) ); \
            memcpy( &runlevel_c, buf1+i, sizeof(x264_run_level_t) ); \
            for( int idx = ac; idx < max; idx++ ) \
                nnz |= dct1[idx] = TEST_LAST_COEF( i ); \
            /* max < size: the last coef also, negative or with only its high half set */ \
            if( (i&3) == 3 ) \
                nnz |= dct1[size-1] = i&4 ? -1 : 1 << (4*sizeof(dctcoef)); \
            if( !nnz ) \
                dct1[ac] = 1; \
            if( i == 99 ) \
            { \
                memset( dct1, 0, size*sizeof(dctcoef) ); \
                dct1[size-1] = -1; \
            } \
            if( ac && (i&1) ) \
                dct1[0] = -1; /* the coef before the block */ \
            int result_c = call_c( qf_c.lastname, dct1+ac, &runlevel_c ); \
            int result_a = call_a( qf_a.lastname, dct1+ac, &runlevel_a ); \
            if( result_c != result_a || runlevel_c.last != runlevel_a.last || \
                runlevel_c.mask != runlevel_a.mask || \
                memcmp(runlevel_c.level, runlevel_a.level, sizeof(dctcoef)*result_c)) \
            { \
                ok = 0; \
                fprintf( stderr, #name ": [FAILED]\n" ); \
                break; \
            } \
        } \
    }

    ok = 1; used_asm = 0;
    TEST_LEVELRUN( coeff_level_run4              , coeff_level_run4,   4, 0 );
    TEST_LEVELRUN( coeff_level_run8              , coeff_level_run8,   8, 0 );
    TEST_LEVELRUN( coeff_level_run[  DCT_LUMA_AC], coeff_level_run15, 16, 1 );
    TEST_LEVELRUN( coeff_level_run[ DCT_LUMA_4x4], coeff_level_run16, 16, 0 );
    report( "coeff_level_run :" );

#if HAVE_MMX && ARCH_X86_64
    ok = 1; used_asm = 0;
    x264_rdo_init();
    for( int v = 0; v < 7; v++ )
    {
        /* 4x4, 8x8, 4x4_psy, 8x8_psy, dc 4x4, dc 2x2, chroma 4:2:2 dc */
        static const char *names[7] = { "trellis_cabac_4x4", "trellis_cabac_8x8", "trellis_cabac_4x4_psy", "trellis_cabac_8x8_psy",
                                        "trellis_cabac_dc", "trellis_cabac_dc_2x2", "trellis_cabac_chroma_422_dc" };
        static const uint8_t zz2x2[4] = { 0, 1, 2, 3 };
        static const uint8_t zz2x4[8] = { 0, 2, 1, 4, 6, 3, 5, 7 };
        void *fa = v == 0 ? (void*)qf_a.trellis_cabac_4x4 : v == 1 ? (void*)qf_a.trellis_cabac_8x8 :
                   v == 2 ? (void*)qf_a.trellis_cabac_4x4_psy : v == 3 ? (void*)qf_a.trellis_cabac_8x8_psy :
                   v <= 5 ? (void*)qf_a.trellis_cabac_dc : (void*)qf_a.trellis_cabac_chroma_422_dc;
        void *fr = v == 0 ? (void*)qf_ref.trellis_cabac_4x4 : v == 1 ? (void*)qf_ref.trellis_cabac_8x8 :
                   v == 2 ? (void*)qf_ref.trellis_cabac_4x4_psy : v == 3 ? (void*)qf_ref.trellis_cabac_8x8_psy :
                   v <= 5 ? (void*)qf_ref.trellis_cabac_dc : (void*)qf_ref.trellis_cabac_chroma_422_dc;
        /* the sse2 versions are installed without any cpu flag: test them once, against the C */
        if( !fa || (fa == fr && !((cpu_new&X264_CPU_SSE2) && !(cpu_ref&X264_CPU_SSE2))) )
            continue;
        used_asm = 1;
        set_func_name( "%s", names[v] );
        int num_coefs = v == 1 || v == 3 ? 64 : v == 5 ? 4 : v == 6 ? 8 : 16;
        int dc = v >= 4;
        int psy = v == 2 || v == 3;
        /* same check blocks at every cpu level */
        srand( bench_seed * 7919 + v );
        for( int pass = 0; pass < 1 + do_bench && ok; pass++ )
        for( int it = 0; it < (pass ? 32 : 8000); it++ )
        {
            /* pass 1, bench: blocks 0-31 (kind 0, every mode, frame/field, ac) from the private generator */
            int (*trand)( void ) = pass ? bench_rand : rand;
            if( pass && !it )
                bench_srand( 300 + v );
            ALIGNED_ARRAY_64( dctcoef, tdct, [3],[64] );
            ALIGNED_ARRAY_64( dctcoef, torig, [80] );
            ALIGNED_ARRAY_64( dctcoef, tfenc, [80] );
            ALIGNED_ARRAY_64( dctcoef, tquant, [64] );
            ALIGNED_ARRAY_64( int, tunquant, [64] );
            ALIGNED_ARRAY_16( uint8_t, tstate, [48] );
            /* mode 0: typical, 1: dense, 2: sparse with long zero runs, 3: large levels and suffixes,
             * 4: all ones, 5: a few coefs near the start, 6: levels up to 20, 7: levels 1-4 */
            int mode = it&7;
            /* kind 1: every coef nonzero, levels 1-2, a high lambda2; 2: ties: lambda2 0-3, unquant_mf
             * a multiple of 256, abs_coef on or halfway between the candidates, few distinct cabac states */
            int kind = it < 4000 ? 0 : it < 6000 ? 1 : 2;
            int b_field = (it>>3)&1;
            int b_ac = (v == 0 || v == 2) ? (it>>4)&1 : 0;
            const uint8_t *zigzag = num_coefs == 64 ? x264_zigzag_scan8[b_field] : num_coefs == 16 ? x264_zigzag_scan4[b_field] :
                                    num_coefs == 8 ? zz2x4 : zz2x2;
            int lambda2 = x264_trellis_lambda2_tab[trand()&1][trand()%(QP_MAX+1)];
            int psy_trellis = psy ? 1 + trand()%512 : 0;
            int coef_max = (1 << (BIT_DEPTH+7)) - 1;
            int unq_base = (16 + trand()%240) << (trand()%13);
            int kmax = mode == 5 ? trand()%6 : num_coefs-1;
            int last_nnz = -1;
            for( int k = 0; k < 48; k++ )
                tstate[k] = kind == 2 ? (trand()&1 ? 0 : 62 + (trand()&1)) : trand()&127;
            for( int k = 0; k < 64; k++ )
            {
                tunquant[k] = kind == 2 ? 256 << (trand()%5) : unq_base * (16 + (trand()&15)) >> 4;
                tdct[0][k] = 0;
                /* past num_coefs: junk, as in rdo.c */
                tquant[k] = trand() - RAND_MAX/2;
            }
            if( kind == 2 )
                lambda2 = trand()&3;
            if( kind == 1 )
                lambda2 = x264_trellis_lambda2_tab[1][QP_MAX/2 + trand()%(QP_MAX/2)];
            for( int k = 0; k < 80; k++ )
            {
                torig[k] = (trand()&0x3ff) - 0x200;
                tfenc[k] = (trand()&0x3fff) - 0x2000;
            }
            for( int i = 0; i < num_coefs; i++ )
            {
                int pos = zigzag[i];
                int unq = dc ? tunquant[0]<<1 : tunquant[pos];
                int step = X264_MAX( unq>>8, 1 );
                int rnd = trand();
                int level;
                if( kind == 1 )
                    level = (trand()%4) == 0 && i > num_coefs-12 ? 2 : (it&8) && (trand()%8) == 0 ? 2 : 1;
                else if( i > kmax )
                    level = 0;
                else if( mode == 1 )
                    level = (rnd&7) ? 1 + (trand()&1) + !(trand()&3) : 0;
                else if( mode == 2 )
                    level = (rnd&7) ? 0 : 1 + !(trand()&3);
                else if( mode == 3 )
                    level = (rnd&3) ? 0 : !(trand()&3) ? 1 : (trand()&1) ? 15 + trand()%40 : 1 + trand()%2000;
                else if( mode == 4 )
                    level = (rnd&3) ? 1 : 0;
                else if( mode == 6 )
                    level = (rnd&1) ? 0 : 1 + trand()%20;
                else if( mode == 7 )
                    level = (rnd&1) ? 1 + (trand()&3) : 0;
                else
                    level = (trand()%(num_coefs+4)) < num_coefs-i ? 1 + !(trand()&3) + !(trand()&15)*(trand()&7) : 0;
                /* the asm keeps unquant*level in 32 bits and the squared error in 32 bits */
                while( level > 1 && ((int64_t)unq*level >= (1<<30) || (int64_t)step*level >= coef_max) )
                    level >>= 1;
                int sign = (trand()&1) ? -1 : 1;
                int abs_coef;
                if( kind == 2 && level )
                    abs_coef = (trand()&1) ? ((unq*(2*level-1) + 256) >> 9) : (unq*(level-(trand()&1)) + 128) >> 8;
                else if( kind == 1 )
                    abs_coef = X264_MAX( (unq*level + 128) >> 8, 1 );
                else
                    abs_coef = level ? ((unq*level + 128) >> 8) + trand()%(step+1) - step/2 : trand()%((step>>1)+1);
                abs_coef = x264_clip3( abs_coef, 0, coef_max );
                /* quant never makes a level from a zero coef, and keeps its sign */
                if( level && !abs_coef )
                    abs_coef = 1;
                torig[8+pos] = sign*abs_coef;
                tfenc[8+pos] = torig[8+pos] + (trand()&0x3ff) - 0x200;
                tquant[i] = sign*level;
                tdct[0][pos] = sign*level;
                if( level && i >= b_ac )
                    last_nnz = i;
            }
            if( !kind && b_ac && (trand()&1) )
                tdct[0][zigzag[0]] = tquant[0] = 1 + (trand()&3);
            int min_nnz = dc ? 0 : X264_MAX( b_ac, 1 );
            if( last_nnz < min_nnz )
            {
                last_nnz = min_nnz + trand()%(num_coefs-min_nnz);
                int pos = zigzag[last_nnz];
                int sign = (trand()&1) ? 1 : -1;
                tdct[0][pos] = tquant[last_nnz] = sign;
                torig[8+pos] = sign * X264_MAX( ((dc ? tunquant[0]<<1 : tunquant[pos]) + 128) >> 8, 1 );
            }
            uint64_t ls0;
            uint16_t ls1;
            memcpy( &ls0, tstate+32, 8 );
            memcpy( &ls1, tstate+40, 2 );
            memcpy( tdct[1], tdct[0], sizeof(tdct[0]) );
            memcpy( tdct[2], tdct[0], sizeof(tdct[0]) );
#define TRELLIS_ARGS_T(d) tunquant, zigzag, lambda2, last_nnz, torig+8, tquant, d, tstate, tstate+16, ls0, ls1
            if( pass )
            {
                /* no C row: trellis_ref takes 17 args, x264_checkasm_call passes 15 */
                if( v == 0 )
                    call_a2( qf_a.trellis_cabac_4x4, TRELLIS_ARGS_T(tdct[2]), b_ac );
                else if( v == 1 )
                    call_a2( qf_a.trellis_cabac_8x8, TRELLIS_ARGS_T(tdct[2]), b_field );
                else if( v == 2 )
                    call_a2( qf_a.trellis_cabac_4x4_psy, TRELLIS_ARGS_T(tdct[2]), b_ac, tfenc+8, psy_trellis );
                else if( v == 3 )
                    call_a2( qf_a.trellis_cabac_8x8_psy, TRELLIS_ARGS_T(tdct[2]), b_field, tfenc+8, psy_trellis );
                else if( v <= 5 )
                    call_a2( qf_a.trellis_cabac_dc, TRELLIS_ARGS_T(tdct[2]), num_coefs-1 );
                else
                    call_a2( qf_a.trellis_cabac_chroma_422_dc, TRELLIS_ARGS_T(tdct[2]) );
                continue;
            }
            int res_c = trellis_ref( TRELLIS_ARGS_T(tdct[1]), num_coefs, dc, b_ac, b_field, tfenc+8, psy_trellis );
            int res_a;
            if( v == 0 )
                res_a = call_a1( qf_a.trellis_cabac_4x4, TRELLIS_ARGS_T(tdct[2]), b_ac );
            else if( v == 1 )
                res_a = call_a1( qf_a.trellis_cabac_8x8, TRELLIS_ARGS_T(tdct[2]), b_field );
            else if( v == 2 )
                res_a = call_a1( qf_a.trellis_cabac_4x4_psy, TRELLIS_ARGS_T(tdct[2]), b_ac, tfenc+8, psy_trellis );
            else if( v == 3 )
                res_a = call_a1( qf_a.trellis_cabac_8x8_psy, TRELLIS_ARGS_T(tdct[2]), b_field, tfenc+8, psy_trellis );
            else if( v <= 5 )
                res_a = call_a1( qf_a.trellis_cabac_dc, TRELLIS_ARGS_T(tdct[2]), num_coefs-1 );
            else
                res_a = call_a1( qf_a.trellis_cabac_chroma_422_dc, TRELLIS_ARGS_T(tdct[2]) );
            if( res_c != res_a || memcmp( tdct[1], tdct[2], sizeof(tdct[0]) ) )
            {
                ok = 0;
                fprintf( stderr, "%s: [FAILED] kind %d mode %d last_nnz %d b_ac %d field %d: %d != %d\n",
                         names[v], kind, mode, last_nnz, b_ac, b_field, res_c, res_a );
                break;
            }
#undef TRELLIS_ARGS_T
        }
    }
    report( "trellis :" );
#endif

    return ret;
}

static int check_intra( int cpu_ref, int cpu_new )
{
    int ret = 0, ok = 1, used_asm = 0;
    ALIGNED_ARRAY_32( pixel, edge,[36] );
    ALIGNED_ARRAY_32( pixel, edge2,[36] );
    ALIGNED_ARRAY_32( pixel, fdec,[FDEC_STRIDE*20] );
    struct
    {
        x264_predict_t      predict_16x16[4+3];
        x264_predict_t      predict_8x8c[4+3];
        x264_predict_t      predict_8x16c[4+3];
        x264_predict8x8_t   predict_8x8[9+3];
        x264_predict_t      predict_4x4[9+3];
        x264_predict_8x8_filter_t predict_8x8_filter;
    } ip_c, ip_ref, ip_a;

    x264_predict_16x16_init( 0, ip_c.predict_16x16 );
    x264_predict_8x8c_init( 0, ip_c.predict_8x8c );
    x264_predict_8x16c_init( 0, ip_c.predict_8x16c );
    x264_predict_8x8_init( 0, ip_c.predict_8x8, &ip_c.predict_8x8_filter );
    x264_predict_4x4_init( 0, ip_c.predict_4x4 );

    x264_predict_16x16_init( cpu_ref, ip_ref.predict_16x16 );
    x264_predict_8x8c_init( cpu_ref, ip_ref.predict_8x8c );
    x264_predict_8x16c_init( cpu_ref, ip_ref.predict_8x16c );
    x264_predict_8x8_init( cpu_ref, ip_ref.predict_8x8, &ip_ref.predict_8x8_filter );
    x264_predict_4x4_init( cpu_ref, ip_ref.predict_4x4 );

    x264_predict_16x16_init( cpu_new, ip_a.predict_16x16 );
    x264_predict_8x8c_init( cpu_new, ip_a.predict_8x8c );
    x264_predict_8x16c_init( cpu_new, ip_a.predict_8x16c );
    x264_predict_8x8_init( cpu_new, ip_a.predict_8x8, &ip_a.predict_8x8_filter );
    x264_predict_4x4_init( cpu_new, ip_a.predict_4x4 );

    memcpy( fdec, pbuf1, 32*20 * sizeof(pixel) );\

    ip_c.predict_8x8_filter( fdec+48, edge, ALL_NEIGHBORS, ALL_NEIGHBORS );

#define INTRA_TEST( name, dir, w, h, align, bench, ... )\
    if( ip_a.name[dir] != ip_ref.name[dir] )\
    {\
        set_func_name( "intra_%s_%s", #name, intra_##name##_names[dir] );\
        used_asm = 1;\
        memcpy( pbuf3, fdec, FDEC_STRIDE*20 * sizeof(pixel) );\
        memcpy( pbuf4, fdec, FDEC_STRIDE*20 * sizeof(pixel) );\
        for( int a = 0; a < (do_bench ? 64/sizeof(pixel) : 1); a += align )\
        {\
            call_c##bench( ip_c.name[dir], pbuf3+48+a, ##__VA_ARGS__ );\
            call_a##bench( ip_a.name[dir], pbuf4+48+a, ##__VA_ARGS__ );\
            if( memcmp( pbuf3, pbuf4, FDEC_STRIDE*20 * sizeof(pixel) ) )\
            {\
                fprintf( stderr, #name "[%d] :  [FAILED]\n", dir );\
                ok = 0;\
                for( int k = -1; k < 16; k++ )\
                    printf( "%2x ", edge[16+k] );\
                printf( "\n" );\
                for( int j = 0; j < h; j++ )\
                {\
                    printf( "%2x ", edge[14-j] );\
                    for( int k = 0; k < w; k++ )\
                        printf( "%2x ", pbuf4[48+k+j*FDEC_STRIDE] );\
                    printf( "\n" );\
                }\
                printf( "\n" );\
                for( int j = 0; j < h; j++ )\
                {\
                    printf( "   " );\
                    for( int k = 0; k < w; k++ )\
                        printf( "%2x ", pbuf3[48+k+j*FDEC_STRIDE] );\
                    printf( "\n" );\
                }\
                break;\
            }\
        }\
    }

    /* pat = 0: random neighbours; 1: every sample PIXEL_MAX; 2: every sample 0;
     * 3: a random mix of 0 and PIXEL_MAX */
    for( int pat = 0; pat < (do_bench ? 1 : 4) && ok; pat++ )
    {
        if( pat )
        {
            for( int i = 0; i < 32*20; i++ )
                fdec[i] = pat == 1 ? PIXEL_MAX : pat == 2 ? 0 : (rand()&1)*PIXEL_MAX;
            ip_c.predict_8x8_filter( fdec+48, edge, ALL_NEIGHBORS, ALL_NEIGHBORS );
        }
        for( int i = 0; i < 12; i++ )
            INTRA_TEST(   predict_4x4, i,  4,  4,  4, );
        for( int i = 0; i < 7; i++ )
            INTRA_TEST(  predict_8x8c, i,  8,  8, 16, );
        for( int i = 0; i < 7; i++ )
            INTRA_TEST( predict_8x16c, i,  8, 16, 16, );
        for( int i = 0; i < 7; i++ )
            INTRA_TEST( predict_16x16, i, 16, 16, 16, );
        for( int i = 0; i < 12; i++ )
            INTRA_TEST(   predict_8x8, i,  8,  8,  8, , edge );

        set_func_name("intra_predict_8x8_filter");
        if( ip_a.predict_8x8_filter != ip_ref.predict_8x8_filter )
        {
            used_asm = 1;
            for( int i = 0; i < 32; i++ )
            {
                if( !(i&7) || ((i&MB_TOPRIGHT) && !(i&MB_TOP)) )
                    continue;
                int neighbor = (i&24)>>1;
                memset( edge,  0, 36*sizeof(pixel) );
                memset( edge2, 0, 36*sizeof(pixel) );
                call_c( ip_c.predict_8x8_filter, fdec+48, edge,  neighbor, i&7 );
                call_a( ip_a.predict_8x8_filter, fdec+48, edge2, neighbor, i&7 );
                if( !(neighbor&MB_TOPLEFT) )
                    edge[15] = edge2[15] = 0;
                /* from edge[6], which the filter writes as l7 */
                if( memcmp( edge+6, edge2+6, (i&MB_TOPRIGHT ? 27 : i&MB_TOP ? 18 : 9) * sizeof(pixel) ) )
                {
                    fprintf( stderr, "predict_8x8_filter :  [FAILED] %d %d\n", (i&24)>>1, i&7);
                    ok = 0;
                }
            }
        }
    }
    memcpy( fdec, pbuf1, 32*20 * sizeof(pixel) );

#define EXTREMAL_PLANE( w, h ) \
    { \
        int max[7]; \
        for( int j = 0; j < 7; j++ ) \
            max[j] = test ? rand()&PIXEL_MAX : PIXEL_MAX; \
        fdec[48-1-FDEC_STRIDE] = (i&1)*max[0]; \
        for( int j = 0; j < w/2; j++ ) \
            fdec[48+j-FDEC_STRIDE] = (!!(i&2))*max[1]; \
        for( int j = w/2; j < w-1; j++ ) \
            fdec[48+j-FDEC_STRIDE] = (!!(i&4))*max[2]; \
        fdec[48+(w-1)-FDEC_STRIDE] = (!!(i&8))*max[3]; \
        for( int j = 0; j < h/2; j++ ) \
            fdec[48+j*FDEC_STRIDE-1] = (!!(i&16))*max[4]; \
        for( int j = h/2; j < h-1; j++ ) \
            fdec[48+j*FDEC_STRIDE-1] = (!!(i&32))*max[5]; \
        fdec[48+(h-1)*FDEC_STRIDE-1] = (!!(i&64))*max[6]; \
    }
    /* Extremal test case for planar prediction. */
    for( int test = 0; test < 100 && ok; test++ )
        for( int i = 0; i < 128 && ok; i++ )
        {
            EXTREMAL_PLANE(  8,  8 );
            INTRA_TEST(  predict_8x8c, I_PRED_CHROMA_P,  8,  8, 64, 1 );
            EXTREMAL_PLANE(  8, 16 );
            INTRA_TEST( predict_8x16c, I_PRED_CHROMA_P,  8, 16, 64, 1 );
            EXTREMAL_PLANE( 16, 16 );
            INTRA_TEST( predict_16x16,  I_PRED_16x16_P, 16, 16, 64, 1 );
        }
    report( "intra pred :" );
    return ret;
}

#define DECL_CABAC(cpu) \
static void run_cabac_decision_##cpu( x264_t *h, uint8_t *dst, const uint8_t *src )\
{\
    x264_cabac_t cb;\
    x264_cabac_context_init( h, &cb, SLICE_TYPE_P, 26, 0 );\
    x264_cabac_encode_init( &cb, dst, dst+0xff0 );\
    for( int i = 0; i < 0x1000; i++ )\
        x264_cabac_encode_decision_##cpu( &cb, src[i]>>1, src[i]&1 );\
    /* the bits still in low/queue, and the contexts: all in the compared 0x1000 bytes */\
    x264_cabac_encode_flush( h, &cb );\
    memcpy( dst+0xe00, cb.state, 128 );\
}\
static void run_cabac_bypass_##cpu( x264_t *h, uint8_t *dst, const uint8_t *src )\
{\
    x264_cabac_t cb;\
    x264_cabac_context_init( h, &cb, SLICE_TYPE_P, 26, 0 );\
    x264_cabac_encode_init( &cb, dst, dst+0xff0 );\
    for( int i = 0; i < 0x1000; i++ )\
        x264_cabac_encode_bypass_##cpu( &cb, src[i]&1 );\
    x264_cabac_encode_flush( h, &cb );\
}\
static void run_cabac_terminal_##cpu( x264_t *h, uint8_t *dst )\
{\
    x264_cabac_t cb;\
    x264_cabac_context_init( h, &cb, SLICE_TYPE_P, 26, 0 );\
    x264_cabac_encode_init( &cb, dst, dst+0xff0 );\
    for( int i = 0; i < 0x1000; i++ )\
        x264_cabac_encode_terminal_##cpu( &cb );\
    x264_cabac_encode_flush( h, &cb );\
}
DECL_CABAC(c)
#if HAVE_MMX
DECL_CABAC(asm)
/* src: 4096 contexts and bins; the first 128 contexts start in states 2-127 from st
 * (0-1: terminate only) */
static void run_cabac_decision_states( x264_t *h, uint8_t *dst, const uint8_t *src, const uint8_t *st,
                                       void (*decision)( x264_cabac_t *, intptr_t, intptr_t ) )
{
    x264_cabac_t cb;
    x264_cabac_context_init( h, &cb, SLICE_TYPE_P, 26, 0 );
    for( int i = 0; i < 128; i++ )
        cb.state[i] = 2 + st[i]%126;
    x264_cabac_encode_init( &cb, dst, dst+0xff0 );
    for( int i = 0; i < 0x1000; i++ )
        decision( &cb, src[i]>>1, src[i]&1 );
    x264_cabac_encode_flush( h, &cb );
    memcpy( dst+0xe00, cb.state, 128 );
}
static void cabac_decision_c( x264_cabac_t *cb, intptr_t i_ctx, intptr_t b )
{
    x264_cabac_encode_decision_c( cb, i_ctx, b );
}
/* separate functions, so the bench tells them apart */
static void run_cabac_decision_states_c( x264_t *h, uint8_t *dst, const uint8_t *src, const uint8_t *st )
{
    run_cabac_decision_states( h, dst, src, st, cabac_decision_c );
}
static void run_cabac_decision_states_bmi2( x264_t *h, uint8_t *dst, const uint8_t *src, const uint8_t *st )
{
    run_cabac_decision_states( h, dst, src, st, x264_cabac_encode_decision_bmi2 );
}
#else
#define run_cabac_decision_asm run_cabac_decision_c
#define run_cabac_bypass_asm run_cabac_bypass_c
#define run_cabac_terminal_asm run_cabac_terminal_c
#endif

extern const uint8_t x264_count_cat_m1[14];
#define x264_cabac_block_residual_c x264_template(cabac_block_residual_c)
#define x264_cabac_block_residual_8x8_rd_c x264_template(cabac_block_residual_8x8_rd_c)
#define x264_cabac_block_residual_rd_c x264_template(cabac_block_residual_rd_c)
void x264_cabac_block_residual_c( x264_t *h, x264_cabac_t *cb, int ctx_block_cat, dctcoef *l );
void x264_cabac_block_residual_8x8_rd_c( x264_t *h, x264_cabac_t *cb, int ctx_block_cat, dctcoef *l );
void x264_cabac_block_residual_rd_c( x264_t *h, x264_cabac_t *cb, int ctx_block_cat, dctcoef *l );
#define x264_cabac_block_residual_422_dc_c x264_template(cabac_block_residual_422_dc_c)
#define x264_cabac_block_residual_422_dc_rd_c x264_template(cabac_block_residual_422_dc_rd_c)
void x264_cabac_block_residual_422_dc_c( x264_t *h, x264_cabac_t *cb, int ctx_block_cat, dctcoef *l );
void x264_cabac_block_residual_422_dc_rd_c( x264_t *h, x264_cabac_t *cb, int ctx_block_cat, dctcoef *l );
#define x264_rdo_init x264_template(rdo_init)
void x264_rdo_init( void );

/* residual bench classes: nonzero coefs 1/16, 1/4, 7/8 with levels mostly 1-2;
 * large: 1/4 nonzero, levels up to 64, some escapes in the hundreds and beyond */
static const char *cabac_res_class[4] = { "sparse", "mid", "dense", "large" };
static void cabac_bench_block( dctcoef dct[2][64], int cat, int ac, int cls )
{
    int nz = 0;
    memset( dct, 0, 2*64*sizeof(dctcoef) );
    while( !nz )
        for( int k = 0; k <= x264_count_cat_m1[cat]; k++ )
        {
            int r = bench_rand();
            int coef = cls == 0 ? !(r&15) : cls == 2 ? !!(r&7) : !(r&3);
            if( coef && cls < 3 )
                coef += !(r&0x70) * ((r>>8)&3);
            else if( coef )
                coef += (r>>8)&63 ? (r>>14)&63 : (r>>14)&0x3fff;
            nz |= dct[0][ac+k] = dct[1][ac+k] = r&0x80 ? -coef : coef;
        }
}

static int check_cabac( int cpu_ref, int cpu_new )
{
    int ret = 0, ok = 1, used_asm = 0;
    x264_t h;
    h.sps->i_chroma_format_idc = 3;
    h.i_frame = 0;

    x264_bitstream_function_t bs_ref;
    x264_bitstream_function_t bs_a;
    x264_bitstream_init( cpu_ref, &bs_ref );
    x264_bitstream_init( cpu_new, &bs_a );
    x264_quant_init( &h, cpu_new, &h.quantf );
    h.quantf.coeff_last[DCT_CHROMA_DC] = h.quantf.coeff_last4;
    /* the rd functions read the unary tables and the context init states */
    x264_rdo_init();
    x264_cabac_init( &h );

#define CABAC_RESIDUAL(name, cats, rd)\
{\
    if( bs_a.name##_internal && (bs_a.name##_internal != bs_ref.name##_internal || (cpu_new&X264_CPU_SSE2_IS_SLOW)) )\
    {\
        used_asm = 1;\
        set_func_name( #name );\
        for( int i = 0; i < 2; i++ )\
        {\
            for( intptr_t ctx_block_cat = 0; ctx_block_cat < 14; ctx_block_cat++ )\
            {\
                if( !(((cats) >> ctx_block_cat) & 1) )\
                    continue;\
                for( int j = 0; j < 256; j++ )\
                {\
                    ALIGNED_ARRAY_64( dctcoef, dct, [2],[64] );\
                    uint8_t bitstream[2][1<<16];\
                    static const uint8_t ctx_ac[14] = {0,1,0,0,1,0,0,1,0,0,0,1,0,0};\
                    int ac = ctx_ac[ctx_block_cat];\
                    /* mode 0: as before, 1: dense, 2: sparse with long zero runs, 3: large levels */\
                    int mode = (j>>2)&3;\
                    /* sparse, j&64: only the first kmax+1 can be nonzero, so last is small */\
                    int kmax = mode == 2 && (j&64) ? (j&3) | ((j>>2)&4) : 63;\
                    int nz = 0;\
                    while( !nz )\
                    {\
                        for( int k = 0; k <= x264_count_cat_m1[ctx_block_cat]; k++ )\
                        {\
                            if( k > kmax )\
                            {\
                                dct[0][ac+k] = dct[1][ac+k] = 0;\
                                continue;\
                            }\
                            /* Very rough distribution that covers possible inputs */\
                            int rnd = rand();\
                            int coef = mode == 1 ? !!(rnd&7) : mode == 2 ? !(rnd&15) : !(rnd&3);\
                            coef += !(rnd&  15) * (rand()&0x0006);\
                            coef += !(rnd&  63) * (rand()&0x0008);\
                            coef += !(rnd& 255) * (rand()&0x00F0);\
                            coef += !(rnd&1023) * (rand()&0x7F00);\
                            if( mode == 3 && coef && coef < 256 )\
                                coef += rand()&31;\
                            nz |= dct[0][ac+k] = dct[1][ac+k] = coef * ((rand()&1) ? 1 : -1);\
                        }\
                    }\
                    h.mb.b_interlaced = i;\
                    x264_cabac_t cb[2];\
                    x264_cabac_context_init( &h, &cb[0], (j&32) ? SLICE_TYPE_I : SLICE_TYPE_P, (j*13)%52, (j>>6)%3 );\
                    memcpy( cb[1].state, cb[0].state, 1024 );\
                    x264_cabac_encode_init( &cb[0], bitstream[0], bitstream[0]+0xfff0 );\
                    x264_cabac_encode_init( &cb[1], bitstream[1], bitstream[1]+0xfff0 );\
                    cb[0].f8_bits_encoded = 0;\
                    cb[1].f8_bits_encoded = 0;\
                    if( !rd ) memcpy( bitstream[1], bitstream[0], 0x400 );\
                    /* start mid-stream: arbitrary low/queue, sometimes bytes outstanding */\
                    if( !rd )\
                        for( int k = (rand()&63) | (j&2)*12; k > 0; k-- )\
                        {\
                            int bit = -(rand()&1);\
                            x264_cabac_encode_bypass_c( &cb[0], bit );\
                            x264_cabac_encode_bypass_c( &cb[1], bit );\
                        }\
                    /* low just below a byte boundary inside the interval: pending 0xff bits on entry;\
                     * j&1: steered bypasses keep it there, so bytes outstanding on entry, more 0xff\
                     * bytes, then a carry or not through them */\
                    if( !rd && (j&2) && cb[0].p > cb[0].p_start )\
                    {\
                        cb[0].i_low = cb[1].i_low = (1 << (cb[0].i_queue+18)) - 1 - (rand()&0x7f);\
                        for( int k = (j&1) * (8 + (rand()&31)); k > 0; k-- )\
                        {\
                            int bit = -(2*cb[0].i_low + cb[0].i_range < (2 << (cb[0].i_queue+18)));\
                            x264_cabac_encode_bypass_c( &cb[0], bit );\
                            x264_cabac_encode_bypass_c( &cb[1], bit );\
                        }\
                    }\
                    call_c1( x264_##name##_c, &h, &cb[0], ctx_block_cat, dct[0]+ac );\
                    call_a1( bs_a.name##_internal, dct[1]+ac, i, ctx_block_cat, &cb[1] );\
                    int cok = cb[0].f8_bits_encoded == cb[1].f8_bits_encoded && !memcmp(cb[0].state, cb[1].state, 1024);\
                    if( !rd )\
                    {\
                        /* a carry or a 0xff byte may be held in another form: compare the position,\
                         * then flush copies and compare the whole stream */\
                        x264_cabac_t fl[2];\
                        cok &= x264_cabac_pos( &cb[0] ) == x264_cabac_pos( &cb[1] ) &&\
                              cb[0].i_range == cb[1].i_range && cb[0].i_queue == cb[1].i_queue;\
                        memcpy( &fl[0], &cb[0], sizeof(x264_cabac_t) );\
                        memcpy( &fl[1], &cb[1], sizeof(x264_cabac_t) );\
                        x264_cabac_encode_bypass_c( &fl[0], 0 ); /* flush ORs in bit 0 */\
                        x264_cabac_encode_bypass_c( &fl[1], 0 );\
                        x264_cabac_encode_flush( &h, &fl[0] );\
                        x264_cabac_encode_flush( &h, &fl[1] );\
                        cok &= fl[0].p - bitstream[0] == fl[1].p - bitstream[1] &&\
                              !memcmp( bitstream[1], bitstream[0], fl[0].p - bitstream[0] );\
                    }\
                    if( !cok )\
                    {\
                        ok = 0;\
                        fprintf( stderr, #name " :  [FAILED] ctx_block_cat %d", (int)ctx_block_cat );\
                        if( rd && cb[0].f8_bits_encoded != cb[1].f8_bits_encoded )\
                            fprintf( stderr, " (%d != %d)", cb[0].f8_bits_encoded, cb[1].f8_bits_encoded );\
                        fprintf( stderr, "\n");\
                        goto name##fail;\
                    }\
                }\
            }\
        }\
        /* bench: fixed blocks per class, frame and field, every category; contexts\
         * of a P slice at qp 26, a fixed coder state on entry */\
        uint8_t *bsb = do_bench ? x264_malloc( 2<<20 ) : NULL;\
        for( int cls = 0; cls < 4 && bsb; cls++ )\
        {\
            set_func_name( #name "_%s", cabac_res_class[cls] );\
            bench_srand( 1 + cls );\
            for( int i = 0; i < 2; i++ )\
                for( intptr_t ctx_block_cat = 0; ctx_block_cat < 14; ctx_block_cat++ )\
                {\
                    if( !(((cats) >> ctx_block_cat) & 1) )\
                        continue;\
                    static const uint8_t ctx_ac[14] = {0,1,0,0,1,0,0,1,0,0,0,1,0,0};\
                    int ac = ctx_ac[ctx_block_cat];\
                    for( int blk = 0; blk < 4; blk++ )\
                    {\
                        ALIGNED_ARRAY_64( dctcoef, dct, [2],[64] );\
                        x264_cabac_t cb[2];\
                        cabac_bench_block( dct, ctx_block_cat, ac, cls );\
                        h.mb.b_interlaced = i;\
                        x264_cabac_context_init( &h, &cb[0], SLICE_TYPE_P, 26, 0 );\
                        memcpy( cb[1].state, cb[0].state, 1024 );\
                        x264_cabac_encode_init( &cb[0], bsb, bsb+(1<<20)-16 );\
                        x264_cabac_encode_init( &cb[1], bsb+(1<<20), bsb+(2<<20)-16 );\
                        cb[0].f8_bits_encoded = cb[1].f8_bits_encoded = 0;\
                        for( int k = 0; k < 13 && !rd; k++ )\
                        {\
                            x264_cabac_encode_bypass_c( &cb[0], -((0x1a5b >> k) & 1) );\
                            x264_cabac_encode_bypass_c( &cb[1], -((0x1a5b >> k) & 1) );\
                        }\
                        call_c2( x264_##name##_c, &h, &cb[0], ctx_block_cat, dct[0]+ac );\
                        call_a2( bs_a.name##_internal, dct[1]+ac, i, ctx_block_cat, &cb[1] );\
                    }\
                }\
        }\
        x264_free( bsb );\
    }\
}\
name##fail:

    CABAC_RESIDUAL( cabac_block_residual, (1<<(DCT_LUMA_8x8+1))-1, 0 )
    report( "cabac residual:" );

    ok = 1; used_asm = 0;
    /* every category the rd functions are called with, including 4:4:4 Cb/Cr */
#define CATS_8x8 ((1<<DCT_LUMA_8x8) | (1<<DCT_CHROMAU_8x8) | (1<<DCT_CHROMAV_8x8))
    CABAC_RESIDUAL( cabac_block_residual_rd, ((1<<14)-1) & ~CATS_8x8, 1 )
    CABAC_RESIDUAL( cabac_block_residual_8x8_rd, CATS_8x8, 1 )
#undef CATS_8x8
    report( "cabac residual rd:" );

    /* 4:2:2 chroma dc (8 coefs, repeated sig/last contexts): writer and rd; the C finds last
     * through coeff_last[DCT_CHROMA_DC], which the encoder sets to coeff_last8 for 4:2:2 */
    ok = 1; used_asm = 0;
    h.quantf.coeff_last[DCT_CHROMA_DC] = h.quantf.coeff_last8;
    for( int rd = 0; rd < 2; rd++ )
    {
        void (*fa)( dctcoef *, int, intptr_t, x264_cabac_t * ) = rd ? bs_a.cabac_block_residual_422_dc_rd_internal : bs_a.cabac_block_residual_422_dc_internal;
        void (*fr)( dctcoef *, int, intptr_t, x264_cabac_t * ) = rd ? bs_ref.cabac_block_residual_422_dc_rd_internal : bs_ref.cabac_block_residual_422_dc_internal;
        if( !fa || fa == fr )
            continue;
        used_asm = 1;
        set_func_name( rd ? "cabac_block_residual_422_dc_rd" : "cabac_block_residual_422_dc" );
        for( int i = 0; i < 2 && ok; i++ )
            for( int j = 0; j < 2048 && ok; j++ )
            {
                static const int lv[12] = { 1, 2, 3, 4, 13, 14, 15, 16, 17, 255, 0x7f00, 0x7fff };
                ALIGNED_ARRAY_64( dctcoef, dct, [2],[16] );
                uint8_t bitstream[2][1<<16];
                x264_cabac_t cb[2];
                int mask = (j & 255) ? (j & 255) : 1 + (rand() & 127);
                for( int k = 0; k < 16; k++ )
                {
                    int v = (j&256) ? lv[rand()%12] : 1 + (rand()&3);
                    dct[0][k] = dct[1][k] = k < 8 && (mask >> k & 1) ? v * ((rand()&1) ? 1 : -1) : 0;
                }
                h.mb.b_interlaced = i;
                x264_cabac_context_init( &h, &cb[0], (j&512) ? SLICE_TYPE_I : SLICE_TYPE_P, (j*13)%52, (j>>10)%3 );
                /* states reachable from the init states (rd: any state) */
                if( j&1024 )
                    for( int k = 0; k < 1024; k++ )
                    {
                        if( rd )
                            cb[0].state[k] = rand()&127;
                        else
                            for( int t = rand()%48; t > 0; t-- )
                                cb[0].state[k] = x264_cabac_transition[cb[0].state[k]][rand()&1];
                    }
                memcpy( cb[1].state, cb[0].state, 1024 );
                x264_cabac_encode_init( &cb[0], bitstream[0], bitstream[0]+0xfff0 );
                x264_cabac_encode_init( &cb[1], bitstream[1], bitstream[1]+0xfff0 );
                cb[0].f8_bits_encoded = cb[1].f8_bits_encoded = 0;
                if( !rd )
                {
                    memcpy( bitstream[1], bitstream[0], 0x400 );
                    for( int k = (rand()&63) | (j&2)*12; k > 0; k-- )
                    {
                        int bit = -(rand()&1);
                        x264_cabac_encode_bypass_c( &cb[0], bit );
                        x264_cabac_encode_bypass_c( &cb[1], bit );
                    }
                    if( (j&2) && cb[0].p > cb[0].p_start )
                    {
                        cb[0].i_low = cb[1].i_low = (1 << (cb[0].i_queue+18)) - 1 - (rand()&0x7f);
                        for( int k = (j&1) * (8 + (rand()&31)); k > 0; k-- )
                        {
                            int bit = -(2*cb[0].i_low + cb[0].i_range < (2 << (cb[0].i_queue+18)));
                            x264_cabac_encode_bypass_c( &cb[0], bit );
                            x264_cabac_encode_bypass_c( &cb[1], bit );
                        }
                    }
                }
                if( rd )
                    call_c1( x264_cabac_block_residual_422_dc_rd_c, &h, &cb[0], DCT_CHROMA_DC, dct[0] );
                else
                    call_c1( x264_cabac_block_residual_422_dc_c, &h, &cb[0], DCT_CHROMA_DC, dct[0] );
                call_a1( fa, dct[1], i, DCT_CHROMA_DC, &cb[1] );
                ok = cb[0].f8_bits_encoded == cb[1].f8_bits_encoded && !memcmp( cb[0].state, cb[1].state, 1024 );
                if( !rd )
                {
                    x264_cabac_t fl[2];
                    ok &= x264_cabac_pos( &cb[0] ) == x264_cabac_pos( &cb[1] ) &&
                          cb[0].i_range == cb[1].i_range && cb[0].i_queue == cb[1].i_queue;
                    memcpy( &fl[0], &cb[0], sizeof(x264_cabac_t) );
                    memcpy( &fl[1], &cb[1], sizeof(x264_cabac_t) );
                    x264_cabac_encode_bypass_c( &fl[0], 0 );
                    x264_cabac_encode_bypass_c( &fl[1], 0 );
                    x264_cabac_encode_flush( &h, &fl[0] );
                    x264_cabac_encode_flush( &h, &fl[1] );
                    ok &= fl[0].p - bitstream[0] == fl[1].p - bitstream[1] &&
                          !memcmp( bitstream[1], bitstream[0], fl[0].p - bitstream[0] );
                }
                if( !ok )
                    fprintf( stderr, "%s :  [FAILED] mask %02x field %d\n", rd ? "cabac_block_residual_422_dc_rd" : "cabac_block_residual_422_dc", mask, i );
                if( (j&255) == 0 )
                {
                    if( rd )
                        call_c2( x264_cabac_block_residual_422_dc_rd_c, &h, &cb[0], DCT_CHROMA_DC, dct[0] );
                    else
                        call_c2( x264_cabac_block_residual_422_dc_c, &h, &cb[0], DCT_CHROMA_DC, dct[0] );
                    call_a2( fa, dct[1], i, DCT_CHROMA_DC, &cb[1] );
                }
            }
    }
    h.quantf.coeff_last[DCT_CHROMA_DC] = h.quantf.coeff_last4;
    report( "cabac 4:2:2 dc :" );

#if HAVE_MMX
    if( (cpu_new & (X264_CPU_BMI2|X264_CPU_LZCNT)) == (X264_CPU_BMI2|X264_CPU_LZCNT) &&
        (cpu_ref & (X264_CPU_BMI2|X264_CPU_LZCNT)) != (X264_CPU_BMI2|X264_CPU_LZCNT) )
    {
        ok = 1; used_asm = 1;
        x264_cabac_init( &h );
        set_func_name( "cabac_encode_decision_bmi2" );
        memcpy( buf4, buf3, 0x1000 );
        call_c1( run_cabac_decision_states_c, &h, buf3, buf1, buf2 );
        call_a1( run_cabac_decision_states_bmi2, &h, buf4, buf1, buf2 );
        ok = !memcmp( buf3, buf4, 0x1000 );
        report( "cabac decision bmi2:" );
        /* bench: fixed contexts, bins and states from the private generator, private buffers */
        uint8_t *cbuf = do_bench ? x264_malloc( 4*0x1000 ) : NULL;
        if( cbuf )
        {
            bench_srand( 901 );
            for( int i = 0; i < 0x2000; i++ )
                cbuf[i] = bench_rand() >> 8;
            call_c2( run_cabac_decision_states_c, &h, cbuf+0x2000, cbuf, cbuf+0x1000 );
            call_a2( run_cabac_decision_states_bmi2, &h, cbuf+0x3000, cbuf, cbuf+0x1000 );
            x264_free( cbuf );
        }
    }
#endif

    if( cpu_ref || run_cabac_decision_c == run_cabac_decision_asm )
        return ret;
    ok = 1; used_asm = 0;
    x264_cabac_init( &h );

    set_func_name( "cabac_encode_decision" );
    memcpy( buf4, buf3, 0x1000 );
    call_c1( run_cabac_decision_c, &h, buf3, buf1 );
    call_a1( run_cabac_decision_asm, &h, buf4, buf1 );
    ok = !memcmp( buf3, buf4, 0x1000 );
    report( "cabac decision:" );

    set_func_name( "cabac_encode_bypass" );
    memcpy( buf4, buf3, 0x1000 );
    call_c1( run_cabac_bypass_c, &h, buf3, buf1 );
    call_a1( run_cabac_bypass_asm, &h, buf4, buf1 );
    ok = !memcmp( buf3, buf4, 0x1000 );
    report( "cabac bypass:" );

    /* bench: 4096 fixed contexts and bins from the private generator, private buffers */
    uint8_t *cbuf = do_bench ? x264_malloc( 3*0x1000 ) : NULL;
    if( cbuf )
    {
        bench_srand( 900 );
        for( int i = 0; i < 0x1000; i++ )
            cbuf[i] = bench_rand() >> 8;
        set_func_name( "cabac_encode_decision" );
        call_c2( run_cabac_decision_c, &h, cbuf+0x1000, cbuf );
        call_a2( run_cabac_decision_asm, &h, cbuf+0x2000, cbuf );
        set_func_name( "cabac_encode_bypass" );
        call_c2( run_cabac_bypass_c, &h, cbuf+0x1000, cbuf );
        call_a2( run_cabac_bypass_asm, &h, cbuf+0x2000, cbuf );
        x264_free( cbuf );
    }

    set_func_name( "cabac_encode_terminal" );
    memcpy( buf4, buf3, 0x1000 );
    call_c( run_cabac_terminal_c, &h, buf3 );
    call_a( run_cabac_terminal_asm, &h, buf4 );
    ok = !memcmp( buf3, buf4, 0x1000 );
    report( "cabac terminal:" );

    return ret;
}

static int check_bitstream( int cpu_ref, int cpu_new )
{
    x264_bitstream_function_t bs_c;
    x264_bitstream_function_t bs_ref;
    x264_bitstream_function_t bs_a;

    int ret = 0, ok = 1, used_asm = 0;

    x264_bitstream_init( 0, &bs_c );
    x264_bitstream_init( cpu_ref, &bs_ref );
    x264_bitstream_init( cpu_new, &bs_a );
    if( bs_a.nal_escape != bs_ref.nal_escape )
    {
        int size = 0x4000;
        uint8_t *input = malloc(size+NALU_ESCAPE_PADDING);
        uint8_t *output1 = malloc(size*2);
        uint8_t *output2 = malloc(size*2);
        used_asm = 1;
        set_func_name( "nal_escape" );
#if SYS_LINUX
        /* src ends NALU_ESCAPE_PADDING bytes before a PROT_NONE page: reading
         * further than x264_nal_end guarantees faults */
        long pg = sysconf( _SC_PAGESIZE );
        uint8_t *guard_buf = mmap( NULL, 2*pg, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0 );
        if( guard_buf != MAP_FAILED && !mprotect( guard_buf + pg, pg, PROT_NONE ) )
        {
            uint8_t *end = guard_buf + pg - NALU_ESCAPE_PADDING;
            memset( end, 0xff, NALU_ESCAPE_PADDING );
            int max_size = X264_MIN( pg - NALU_ESCAPE_PADDING, size );
            for( int i = 0; i < 2000 && ok; i++ )
            {
                int test_size = i < 1000 ? i : rand() % max_size;
                uint8_t *src = end - test_size;
                for( int j = 0; j < test_size; j++ )
                {
                    int r = rand();
                    src[j] = i & 1 ? r : (r & 3) ? 0 : (r >> 2) & 3;
                }
                uint8_t *dst = output2 + (i & 63);
                uint8_t *end_c = (uint8_t*)call_c1( bs_c.nal_escape, output1, src, end );
                uint8_t *end_a = (uint8_t*)call_a1( bs_a.nal_escape, dst, src, end );
                int size_c = end_c - output1;
                int size_a = end_a - dst;
                if( size_c != size_a || memcmp( output1, dst, size_c ) )
                {
                    fprintf( stderr, "nal_escape :  [FAILED] padded size %d: %d %d\n", test_size, size_c, size_a );
                    ok = 0;
                }
            }
        }
        if( guard_buf != MAP_FAILED )
            munmap( guard_buf, 2*pg );
#endif
        for( int i = 0; i < 100; i++ )
        {
            /* Test corner-case sizes */
            int test_size = i < 10 ? i+1 : rand() & 0x3fff;
            /* Test 8 different probability distributions of zeros */
            for( int j = 0; j < test_size+32; j++ )
                input[j] = (rand()&((1 << ((i&7)+1)) - 1)) * rand();
            uint8_t *end_c = (uint8_t*)call_c1( bs_c.nal_escape, output1, input, input+test_size );
            uint8_t *end_a = (uint8_t*)call_a1( bs_a.nal_escape, output2, input, input+test_size );
            int size_c = end_c-output1;
            int size_a = end_a-output2;
            if( size_c != size_a || memcmp( output1, output2, size_c ) )
            {
                fprintf( stderr, "nal_escape :  [FAILED] %d %d\n", size_c, size_a );
                ok = 0;
                break;
            }
        }
        /* Runs of zeros and of 00 00 0x across every block boundary and dst/src
         * alignment; nothing written before dst or more than 64 bytes past the end */
        for( int i = 0; i < 4000 && ok; i++ )
        {
            int test_size = i < 300 ? i : rand() & 0x7ff;
            int src_off = rand() & 63;
            int dst_off = i < 300 ? i & 63 : rand() & 63;
            uint8_t *src = input + src_off;
            uint8_t *dst = output2 + 64 + dst_off;
            int mode = (i / 7) % 9;
            for( int j = 0; j < test_size; j++ )
            {
                int r = rand();
                switch( mode )
                {
                    case 0: src[j] = (r & 3) ? 0 : (r >> 2) & 3; break;     /* mostly zeros, escapable bytes */
                    case 1: src[j] = (r & 7) ? 0 : r >> 3; break;
                    case 2: src[j] = (j % (3 + (i & 7))) < 2 ? 0 : (r & 1) ? (r >> 1) & 3 : r >> 1; break;
                    case 3: src[j] = ((j + (i >> 3)) & 63) >= 60 ? 0 : (r & 1) ? 1 : r >> 1; break; /* zeros at block ends */
                    case 4: src[j] = (r & 0x3f) ? 0 : 0xff; break;          /* long zero runs */
                    case 5: src[j] = (r & 15) ? r >> 4 : (r >> 4) & 3; break;
                    default: src[j] = 4 + (r >> 4) % 252; break;            /* no zeros, then isolated events */
                }
            }
            /* isolated 00 00 0x / 00 00 00 .. at random offsets: blocks without
             * escapes around them, pairs split across blocks */
            if( mode >= 6 )
                for( int j = rand() % 40; j + 5 < test_size; j += mode == 8 ? 128 + rand() % 384 : 8 + rand() % 64 )
                {
                    int r = rand();
                    src[j] = src[j+1] = 0;
                    if( mode >= 7 && (r & 1) )
                        src[j+2] = 0;
                    src[j+2+(mode >= 7 && (r & 1))] = (r >> 1) & 3;
                }
            memset( output1, 0xa5, size*2 );
            memset( output2, 0xa5, size*2 );
            uint8_t *end_c = (uint8_t*)call_c1( bs_c.nal_escape, output1 + 64 + dst_off, src, src+test_size );
            uint8_t *end_a = (uint8_t*)call_a1( bs_a.nal_escape, dst, src, src+test_size );
            int size_c = end_c - (output1 + 64 + dst_off);
            int size_a = end_a - dst;
            /* avx512icl writes nothing past the end */
            int slack = cpu_new & X264_CPU_AVX512ICL ? 0 : 64;
            int guard = 1;
            for( uint8_t *p = output2; p < dst; p++ )
                guard &= *p == 0xa5;
            for( uint8_t *p = end_a + slack; p < output2 + size*2; p++ )
                guard &= *p == 0xa5;
            if( size_c != size_a || memcmp( output1 + 64 + dst_off, dst, size_c ) || !guard )
            {
                fprintf( stderr, "nal_escape :  [FAILED] size %d mode %d: %d %d%s\n", test_size, mode,
                         size_c, size_a, guard ? "" : " (out of bounds write)" );
                ok = 0;
            }
        }
        /* the draws of the former bench inputs: the rand() stream of the later checks */
        for( int j = 0; j < 2*(size+32); j++ )
            rand();
        /* bench: 64-byte aligned buffers, 16 KiB of fixed bytes: uniform, and
         * escape-dense (3/4 zero bytes, the rest 1-3) */
        uint8_t *nb = do_bench ? x264_malloc( 5*size + NALU_ESCAPE_PADDING ) : NULL;
        for( int k = 0; k < 2 && nb; k++ )
        {
            uint8_t *src = nb, *dst_c = nb + size + NALU_ESCAPE_PADDING, *dst_a = dst_c + 2*size;
            bench_srand( 800 + k );
            for( int j = 0; j < size + NALU_ESCAPE_PADDING; j++ )
            {
                int r = bench_rand();
                src[j] = k ? ((r & 3) ? 0 : (r >> 2) & 3) : r >> 8;
            }
            set_func_name( k ? "nal_escape_dense" : "nal_escape" );
            call_c2( bs_c.nal_escape, dst_c, src, src+size );
            call_a2( bs_a.nal_escape, dst_a, src, src+size );
        }
        x264_free( nb );
        free(input);
        free(output1);
        free(output2);
    }
    report( "nal escape:" );

    return ret;
}

static int check_all_funcs( int cpu_ref, int cpu_new )
{
    return check_pixel( cpu_ref, cpu_new )
         + check_dct( cpu_ref, cpu_new )
         + check_mc( cpu_ref, cpu_new )
         + check_intra( cpu_ref, cpu_new )
         + check_deblock( cpu_ref, cpu_new )
         + check_quant( cpu_ref, cpu_new )
         + check_cabac( cpu_ref, cpu_new )
         + check_bitstream( cpu_ref, cpu_new );
}

static int add_flags( int *cpu_ref, int *cpu_new, int flags, const char *name )
{
    *cpu_ref = *cpu_new;
    *cpu_new |= flags;
#if STACK_ALIGNMENT < 16
    *cpu_new |= X264_CPU_STACK_MOD4;
#endif
    if( *cpu_new & X264_CPU_SSE2_IS_FAST )
        *cpu_new &= ~X264_CPU_SSE2_IS_SLOW;
    if( !quiet )
        fprintf( stderr, "x264: %s\n", name );
    return check_all_funcs( *cpu_ref, *cpu_new );
}

static int check_all_flags( void )
{
    int ret = 0;
    int cpu0 = 0, cpu1 = 0;
#if HAVE_MMX
    if( x264_cpu_detect() & X264_CPU_MMX2 )
    {
        ret |= add_flags( &cpu0, &cpu1, X264_CPU_MMX | X264_CPU_MMX2, "MMX" );
        ret |= add_flags( &cpu0, &cpu1, X264_CPU_CACHELINE_64, "MMX Cache64" );
        cpu1 &= ~X264_CPU_CACHELINE_64;
#if ARCH_X86
        ret |= add_flags( &cpu0, &cpu1, X264_CPU_CACHELINE_32, "MMX Cache32" );
        cpu1 &= ~X264_CPU_CACHELINE_32;
#endif
        if( x264_cpu_detect() & X264_CPU_LZCNT )
        {
            ret |= add_flags( &cpu0, &cpu1, X264_CPU_LZCNT, "MMX_LZCNT" );
            cpu1 &= ~X264_CPU_LZCNT;
        }
    }
    if( x264_cpu_detect() & X264_CPU_SSE )
        ret |= add_flags( &cpu0, &cpu1, X264_CPU_SSE, "SSE" );
    if( x264_cpu_detect() & X264_CPU_SSE2 )
    {
        ret |= add_flags( &cpu0, &cpu1, X264_CPU_SSE2 | X264_CPU_SSE2_IS_SLOW, "SSE2Slow" );
        ret |= add_flags( &cpu0, &cpu1, X264_CPU_SSE2_IS_FAST, "SSE2Fast" );
        ret |= add_flags( &cpu0, &cpu1, X264_CPU_CACHELINE_64, "SSE2Fast Cache64" );
        cpu1 &= ~X264_CPU_CACHELINE_64;
        ret |= add_flags( &cpu0, &cpu1, X264_CPU_SLOW_SHUFFLE, "SSE2 SlowShuffle" );
        cpu1 &= ~X264_CPU_SLOW_SHUFFLE;
    }
    if( x264_cpu_detect() & X264_CPU_LZCNT )
    {
        ret |= add_flags( &cpu0, &cpu1, X264_CPU_LZCNT, "SSE_LZCNT" );
        cpu1 &= ~X264_CPU_LZCNT;
    }
    if( x264_cpu_detect() & X264_CPU_SSE3 )
    {
        ret |= add_flags( &cpu0, &cpu1, X264_CPU_SSE3 | X264_CPU_CACHELINE_64, "SSE3" );
        cpu1 &= ~X264_CPU_CACHELINE_64;
    }
    if( x264_cpu_detect() & X264_CPU_SSSE3 )
    {
        ret |= add_flags( &cpu0, &cpu1, X264_CPU_SSSE3, "SSSE3" );
        ret |= add_flags( &cpu0, &cpu1, X264_CPU_CACHELINE_64, "SSSE3 Cache64" );
        cpu1 &= ~X264_CPU_CACHELINE_64;
        ret |= add_flags( &cpu0, &cpu1, X264_CPU_SLOW_SHUFFLE, "SSSE3 SlowShuffle" );
        cpu1 &= ~X264_CPU_SLOW_SHUFFLE;
        ret |= add_flags( &cpu0, &cpu1, X264_CPU_SLOW_ATOM, "SSSE3 SlowAtom" );
        ret |= add_flags( &cpu0, &cpu1, X264_CPU_CACHELINE_64, "SSSE3 Cache64 SlowAtom" );
        cpu1 &= ~X264_CPU_CACHELINE_64;
        cpu1 &= ~X264_CPU_SLOW_ATOM;
    }
    if( x264_cpu_detect() & X264_CPU_SSE4 )
        ret |= add_flags( &cpu0, &cpu1, X264_CPU_SSE4, "SSE4" );
    if( x264_cpu_detect() & X264_CPU_AVX )
        ret |= add_flags( &cpu0, &cpu1, X264_CPU_AVX, "AVX" );
    if( x264_cpu_detect() & X264_CPU_XOP )
        ret |= add_flags( &cpu0, &cpu1, X264_CPU_XOP, "XOP" );
    if( x264_cpu_detect() & X264_CPU_FMA4 )
    {
        ret |= add_flags( &cpu0, &cpu1, X264_CPU_FMA4, "FMA4" );
        cpu1 &= ~X264_CPU_FMA4;
    }
    if( x264_cpu_detect() & X264_CPU_BMI1 )
    {
        ret |= add_flags( &cpu0, &cpu1, X264_CPU_BMI1, "BMI1" );
        cpu1 &= ~X264_CPU_BMI1;
    }
    if( x264_cpu_detect() & X264_CPU_AVX2 )
    {
        ret |= add_flags( &cpu0, &cpu1, X264_CPU_AVX2, "AVX2" );
        if( x264_cpu_detect() & X264_CPU_LZCNT )
        {
            ret |= add_flags( &cpu0, &cpu1, X264_CPU_LZCNT, "AVX2_LZCNT" );
            cpu1 &= ~X264_CPU_LZCNT;
        }
    }
    if( x264_cpu_detect() & X264_CPU_BMI2 )
    {
        ret |= add_flags( &cpu0, &cpu1, X264_CPU_BMI1|X264_CPU_BMI2, "BMI2" );
        cpu1 &= ~(X264_CPU_BMI1|X264_CPU_BMI2);
    }
    if( x264_cpu_detect() & X264_CPU_FMA3 )
    {
        ret |= add_flags( &cpu0, &cpu1, X264_CPU_FMA3, "FMA3" );
        cpu1 &= ~X264_CPU_FMA3;
    }
    /* everything AVX-512 machines have, as x264_cpu_names' AVX512 */
    if( x264_cpu_detect() & X264_CPU_AVX512 )
        ret |= add_flags( &cpu0, &cpu1, X264_CPU_FMA3|X264_CPU_LZCNT|X264_CPU_BMI1|X264_CPU_BMI2|X264_CPU_AVX512, "AVX512" );
    if( x264_cpu_detect() & X264_CPU_AVX512ICL )
        ret |= add_flags( &cpu0, &cpu1, X264_CPU_AVX512ICL, "AVX512ICL" );
#elif ARCH_PPC
    if( x264_cpu_detect() & X264_CPU_ALTIVEC )
    {
        fprintf( stderr, "x264: ALTIVEC against C\n" );
        ret = check_all_funcs( 0, X264_CPU_ALTIVEC );
    }
#elif ARCH_ARM
    if( x264_cpu_detect() & X264_CPU_ARMV6 )
        ret |= add_flags( &cpu0, &cpu1, X264_CPU_ARMV6, "ARMv6" );
    if( x264_cpu_detect() & X264_CPU_NEON )
        ret |= add_flags( &cpu0, &cpu1, X264_CPU_NEON, "NEON" );
    if( x264_cpu_detect() & X264_CPU_FAST_NEON_MRC )
        ret |= add_flags( &cpu0, &cpu1, X264_CPU_FAST_NEON_MRC, "Fast NEON MRC" );
#endif
    return ret;
}

int main(int argc, char *argv[])
{
    if( argc > 1 && !strncmp( argv[1], "--bench", 7 ) )
    {
#if !ARCH_X86 && !ARCH_X86_64 && !ARCH_PPC && !ARCH_ARM
        fprintf( stderr, "no --bench for your cpu until you port rdtsc\n" );
        return 1;
#endif
        do_bench = 1;
        if( argv[1][7] == '=' )
        {
            bench_pattern = argv[1]+8;
            bench_pattern_len = strlen(bench_pattern);
        }
        argc--;
        argv++;
    }

    int seed = ( argc > 1 ) ? atoi(argv[1]) : x264_mdate();
    fprintf( stderr, "x264: using random seed %u\n", seed );
    srand( seed );
    bench_seed = seed;
#if ARCH_X86_64
    if( x264_cpu_detect() & X264_CPU_AVX512 )
        x264_checkasm_kmask = ((uint64_t)rand30() << 34 ^ (uint64_t)rand30() << 17 ^ rand30()) | 1;
#endif

    buf1 = x264_malloc( 0x1e00 + 0x2000*sizeof(pixel) );
    pbuf1 = x264_malloc( 0x1e00*sizeof(pixel) );
    if( !buf1 || !pbuf1 )
    {
        fprintf( stderr, "malloc failed, unable to initiate tests!\n" );
        return -1;
    }
#define INIT_POINTER_OFFSETS\
    buf2 = buf1 + 0xf00;\
    buf3 = buf2 + 0xf00;\
    buf4 = buf3 + 0x1000*sizeof(pixel);\
    pbuf2 = pbuf1 + 0xf00;\
    pbuf3 = (pixel*)buf3;\
    pbuf4 = (pixel*)buf4;
    INIT_POINTER_OFFSETS;
    for( int i = 0; i < 0x1e00; i++ )
    {
        buf1[i] = rand() & 0xFF;
        pbuf1[i] = rand() & PIXEL_MAX;
    }
    memset( buf1+0x1e00, 0, 0x2000*sizeof(pixel) );

    if( x264_stack_pagealign( check_all_flags, 0 ) )
    {
        fprintf( stderr, "x264: at least one test has failed. Go and fix that Right Now!\n" );
        return -1;
    }
    fprintf( stderr, "x264: All tests passed Yeah :)\n" );
    if( do_bench )
        print_bench();
    return 0;
}

