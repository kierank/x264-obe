/* 4:2:2 chroma dc rd driver: asm kernels vs x264's C (encoder/cabac.c RDO_SKIP_BS,
 * chroma422dc = 1), 8 or 10-bit (-DBIT_DEPTH). Laptop use only.
 * Copyright (C) 2026 Open Broadcast Systems Ltd */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <x86intrin.h>
#include "tables.h"

#if BIT_DEPTH > 8
typedef int32_t dctcoef;
#define P(n) x264_10_##n
#else
typedef int16_t dctcoef;
#define P(n) x264_8_##n
#endif
typedef struct
{
    int i_low;
    int i_range;
    int i_queue;
    int i_bytes_outstanding;
    uint8_t *p_start;
    uint8_t *p;
    uint8_t *p_end;
    __attribute__((aligned(64))) int f8_bits_encoded;
    uint8_t state[1024];
    uint8_t padding[12];
} x264_cabac_t;

uint8_t  P(cabac_transition_unary)[15][128];
uint16_t P(cabac_size_unary)[15][128];
__attribute__((aligned(64))) const uint8_t  P(pb_1)[64] = { [0 ... 63] = 1 };
__attribute__((aligned(64))) const uint16_t P(pw_1)[32] = { [0 ... 31] = 1 };
__attribute__((aligned(64))) const uint32_t P(pd_1)[16] = { [0 ... 15] = 1 };
__attribute__((aligned(64))) const uint32_t P(deinterleave_shufd)[8] = { 0,4,1,5,2,6,3,7 };
#define STUB(n) void n( void ) { abort(); }
STUB(P(coeff_last4_mmx2)) STUB(P(coeff_last4_mmx2_lzcnt)) STUB(P(coeff_last4_avx512))
STUB(P(coeff_last15_sse2)) STUB(P(coeff_last15_sse2_lzcnt)) STUB(P(coeff_last15_avx512))
STUB(P(coeff_last16_sse2)) STUB(P(coeff_last16_sse2_lzcnt)) STUB(P(coeff_last16_avx512))
STUB(P(coeff_last64_sse2)) STUB(P(coeff_last64_sse2_lzcnt)) STUB(P(coeff_last64_avx2_lzcnt))
STUB(P(coeff_last64_avx512)) STUB(P(cabac_encode_ue_bypass)) STUB(P(intel_cpu_indicator_init))
intptr_t P(stack_align)( void (*func)(), ... );

typedef void (*resfn)( dctcoef *l, int b_interlaced, intptr_t ctx_block_cat, x264_cabac_t *cb );
void P(cabac_block_residual_422_dc_rd_internal_avx512icl)( dctcoef *, int, intptr_t, x264_cabac_t * );
void P(cabac_block_residual_422_dc_rd_internal_avx2_bmi2)( dctcoef *, int, intptr_t, x264_cabac_t * );
#ifdef ICL2
void P(cabac_block_residual_422_dc_rd2_internal_avx512icl)( dctcoef *, int, intptr_t, x264_cabac_t * );
#endif
#ifdef XARMS
void x1_fn( dctcoef *, int, intptr_t, x264_cabac_t * );
void x2_fn( dctcoef *, int, intptr_t, x264_cabac_t * );
#endif

static inline int cabac_size_decision2( uint8_t *state, long b )
{
    int i_state = *state;
    *state = x264_cabac_transition[i_state][b];
    return x264_cabac_entropy[i_state^b];
}
static void rdo_init( void )
{
    for( int i_prefix = 0; i_prefix < 15; i_prefix++ )
        for( int i_ctx = 0; i_ctx < 128; i_ctx++ )
        {
            int f8_bits = 0;
            uint8_t ctx = i_ctx;
            for( int i = 1; i < i_prefix; i++ )
                f8_bits += cabac_size_decision2( &ctx, 1 );
            if( i_prefix > 0 && i_prefix < 14 )
                f8_bits += cabac_size_decision2( &ctx, 0 );
            f8_bits += 1 << 8; //sign
            P(cabac_size_unary)[i_prefix][i_ctx] = f8_bits;
            P(cabac_transition_unary)[i_prefix][i_ctx] = ctx;
        }
}
static inline int bs_size_ue_big( unsigned int val )
{
    return 2*(31 - __builtin_clz( val+1 )) + 1;
}
static const uint8_t coeff_abs_level1_ctx[8] = { 1, 2, 3, 4, 0, 0, 0, 0 };
static const uint8_t coeff_abs_levelgt1_ctx_chroma_dc[8] = { 5, 5, 5, 5, 6, 7, 8, 8 };
static const uint8_t coeff_abs_level_transition[2][8] = {
    { 1, 2, 3, 3, 4, 5, 6, 7 },
    { 4, 4, 4, 4, 5, 6, 7, 7 }
};
static inline void cabac_size_decision( x264_cabac_t *cb, long i_ctx, long b )
{
    int i_state = cb->state[i_ctx];
    cb->state[i_ctx] = x264_cabac_transition[i_state][b];
    cb->f8_bits_encoded += x264_cabac_entropy[i_state^b];
}
#define RD_DEC(c,x,v) cabac_size_decision(c,x,v)
#define RD_BYP(c,v) ((c)->f8_bits_encoded += 256)
#define RD_UE(c,e,v) ((c)->f8_bits_encoded += (bs_size_ue_big(v+(1<<e)-1)-e)<<8)
/* encoder/cabac.c x264_cabac_block_residual_internal, RDO_SKIP_BS, b_8x8 = 0, chroma422dc = 1 */
static __attribute__((noinline)) void ref_rd( x264_cabac_t *cb, int MB_INTERLACED, int ctx_block_cat, dctcoef *l )
{
    int ctx_sig = x264_significant_coeff_flag_offset[MB_INTERLACED][ctx_block_cat];
    int ctx_last = x264_last_coeff_flag_offset[MB_INTERLACED][ctx_block_cat];
    int ctx_level = x264_coeff_abs_level_m1_offset[ctx_block_cat];
    int last = 7;
    while( last >= 0 && !l[last] ) last--;
    int coeff_abs = abs(l[last]);
    int ctx = coeff_abs_level1_ctx[0] + ctx_level;
    int node_ctx;
    const uint8_t *levelgt1_ctx = coeff_abs_levelgt1_ctx_chroma_dc;
    if( last != 7 )
    {
        RD_DEC( cb, ctx_sig + x264_coeff_flag_offset_chroma_422_dc[last], 1 );
        RD_DEC( cb, ctx_last + x264_coeff_flag_offset_chroma_422_dc[last], 1 );
    }
    if( coeff_abs > 1 )
    {
        RD_DEC( cb, ctx, 1 );
        ctx = levelgt1_ctx[0] + ctx_level;
        if( coeff_abs < 15 )
        {
            cb->f8_bits_encoded += P(cabac_size_unary)[coeff_abs-1][cb->state[ctx]];
            cb->state[ctx] = P(cabac_transition_unary)[coeff_abs-1][cb->state[ctx]];
        }
        else
        {
            cb->f8_bits_encoded += P(cabac_size_unary)[14][cb->state[ctx]];
            cb->state[ctx] = P(cabac_transition_unary)[14][cb->state[ctx]];
            RD_UE( cb, 0, coeff_abs - 15 );
        }
        node_ctx = coeff_abs_level_transition[1][0];
    }
    else
    {
        RD_DEC( cb, ctx, 0 );
        node_ctx = coeff_abs_level_transition[0][0];
        RD_BYP( cb, 0 );
    }
    for( int i = last-1 ; i >= 0; i-- )
    {
        if( l[i] )
        {
            coeff_abs = abs(l[i]);
            RD_DEC( cb, ctx_sig + x264_coeff_flag_offset_chroma_422_dc[i], 1 );
            RD_DEC( cb, ctx_last + x264_coeff_flag_offset_chroma_422_dc[i], 0 );
            ctx = coeff_abs_level1_ctx[node_ctx] + ctx_level;
            if( coeff_abs > 1 )
            {
                RD_DEC( cb, ctx, 1 );
                ctx = levelgt1_ctx[node_ctx] + ctx_level;
                if( coeff_abs < 15 )
                {
                    cb->f8_bits_encoded += P(cabac_size_unary)[coeff_abs-1][cb->state[ctx]];
                    cb->state[ctx] = P(cabac_transition_unary)[coeff_abs-1][cb->state[ctx]];
                }
                else
                {
                    cb->f8_bits_encoded += P(cabac_size_unary)[14][cb->state[ctx]];
                    cb->state[ctx] = P(cabac_transition_unary)[14][cb->state[ctx]];
                    RD_UE( cb, 0, coeff_abs - 15 );
                }
                node_ctx = coeff_abs_level_transition[1][node_ctx];
            }
            else
            {
                RD_DEC( cb, ctx, 0 );
                node_ctx = coeff_abs_level_transition[0][node_ctx];
                RD_BYP( cb, 0 );
            }
        }
        else
            RD_DEC( cb, ctx_sig + x264_coeff_flag_offset_chroma_422_dc[i], 0 );
    }
}

static uint32_t rs = 1;
static uint32_t rnd( void ) { rs = rs*1664525u + 1013904223u; return rs >> 8; }
static int gen_level( int big )
{
#if BIT_DEPTH > 8
    static const int lv[22] = { 1, 2, 3, 13, 14, 15, 16, 17, 29, 30, 31, 255, 256, 0x7f00, 0x7fff, 32768, 0xffff, 0x8001, 0xfff0, 0xc000, 0x12345, 0x3fffff };
    int r = rnd(), v;
    if( big ) v = lv[r%22];
#else
    static const int lv[16] = { 1, 2, 3, 13, 14, 15, 16, 17, 29, 30, 31, 255, 256, 0x7f00, 0x7fff, 32768 };
    int r = rnd(), v;
    if( big ) v = lv[r%16];
#endif
    else if( r&3 ) v = 1;
    else if( r&4 ) v = 2 + (rnd()&3);
    else v = 1 + (rnd()%20);
    if( v == 32768 && BIT_DEPTH == 8 ) return -32768;
    return rnd()&1 ? -v : v;
}
static void rand_states( x264_cabac_t *cb )
{
    int m = rnd()%6;
    for( int k = 0; k < 1024; k++ )
        cb->state[k] = m == 0 ? rnd()&127 : m == 1 ? (rnd()&1 ? 2 + (rnd()&7) : 118 + (rnd()&9)) :
                       m == 2 ? 60 + (rnd()&7) : m == 3 ? 2 + 2*(rnd()&3) : m == 4 ? 3 + 2*(rnd()&3) : rnd()&1;
}

static int fails = 0;
static long tests = 0;
static void test( const char *name, resfn fa, int iters )
{
    int bad = 0;
    for( int it = 0; it < iters && bad < 5; it++ )
        for( int inter = 0; inter < 2; inter++ )
        {
            __attribute__((aligned(64))) dctcoef dct[2][16];
            int mask = (it & 255) ? (it & 255) : 1 + (rnd() & 254);
            int mode = (it >> 8) % 4; /* 0: small, 1: big, 2: all +-1, 3: levels > 1 */
            for( int k = 0; k < 16; k++ )
            {
                int v = mode == 0 ? gen_level( 0 ) : mode == 1 ? gen_level( 1 ) : mode == 2 ? (rnd()&1 ? 1 : -1) : gen_level( rnd()&1 ) * 2;
                if( mode == 3 && (v == 0 || v > 0x7fff || v < -0x7fff) && BIT_DEPTH == 8 ) v = 2;
                dct[0][k] = k < 8 && (mask >> k & 1) ? v : (k < 8 ? 0 : (dctcoef)rnd());
            }
            memcpy( dct[1], dct[0], sizeof(dct[0]) );
            x264_cabac_t cb[2];
            memset( cb, 0, sizeof(cb) );
            rand_states( &cb[0] );
            memcpy( cb[1].state, cb[0].state, 1024 );
            cb[0].f8_bits_encoded = cb[1].f8_bits_encoded = rnd() & 0xffff;
            ref_rd( &cb[0], inter, 3, dct[0] );
            fa( dct[1], inter, 3, &cb[1] );
            tests++;
            if( cb[0].f8_bits_encoded != cb[1].f8_bits_encoded || memcmp( cb[0].state, cb[1].state, 1024 ) ||
                memcmp( dct[0], dct[1], sizeof(dct[0]) ) )
            {
                if( bad++ < 3 )
                {
                    printf( "%s FAIL mask %02x field %d bits %d vs %d coefs", name, mask, inter, cb[0].f8_bits_encoded, cb[1].f8_bits_encoded );
                    for( int k = 0; k < 8; k++ ) printf( " %d", (int)dct[0][k] );
                    printf( "\n  states:" );
                    for( int k = 0; k < 1024; k++ ) if( cb[0].state[k] != cb[1].state[k] ) printf( " [%d] %d/%d", k, cb[0].state[k], cb[1].state[k] );
                    printf( "\n" );
                }
            }
        }
    printf( "%-48s %s\n", name, bad ? "FAILED" : "ok" );
    fails += !!bad;
}

/* bench classes over the 8 coefs: sparse 1/16, mid 1/4, dense 7/8 (levels mostly 1-2),
 * large 1/4 with big levels, dc0 (l[0] only), full (all nonzero, levels 1-24) */
static void bench_block( dctcoef *l, int cls )
{
    int nz = 0;
    while( !nz )
        for( int k = 0; k < 8; k++ )
        {
            int r = rnd(), coef;
            if( cls == 4 )
                coef = k == 0 ? 1 + ((r>>8)&7) : 0;
            else if( cls == 5 )
                coef = 1 + ((r>>8)%24);
            else
            {
                coef = cls == 0 ? !(r&15) : cls == 2 ? !!(r&7) : !(r&3);
                if( coef && cls < 3 )
                    coef += !(r&0x70) * ((r>>8)&3);
                else if( coef )
                    coef += (r>>8)&63 ? (r>>14)&63 : (r>>14)&0x3fff;
            }
            nz |= l[k] = r&0x80 ? -coef : coef;
        }
}
#define NB 64
#define NARM 6
static int cmpu( const void *x, const void *y ) { uint32_t a = *(const uint32_t*)x, b = *(const uint32_t*)y; return a < b ? -1 : a > b; }
static void ibench( int cls, int narm, const char **an, resfn *af )
{
    static __attribute__((aligned(64))) dctcoef blk[NB][16];
    static int binter[NB];
    static x264_cabac_t cb0, cb;
    static uint32_t tt[NARM][3000];
    rs = 4242 + cls;
    memset( &cb0, 0, sizeof(cb0) );
    for( int k = 0; k < 1024; k++ ) cb0.state[k] = 20 + (k*7)%80;
    for( int t = 0; t < 3000; t++ )
    {
        for( int b = 0; b < NB; b++ )
        {
            binter[b] = rnd()&1;
            bench_block( blk[b], cls );
        }
        for( int a0 = 0; a0 < narm; a0++ )
        {
            int a = (a0 + t) % narm;
            memcpy( &cb, &cb0, sizeof(cb) );
            uint64_t t0 = __rdtsc();
            for( int b = 0; b < NB; b++ )
            {
                if( af[a] ) af[a]( blk[b], binter[b], 3, &cb );
                else ref_rd( &cb, binter[b], 3, blk[b] );
            }
            tt[a][t] = __rdtsc() - t0;
        }
    }
    static const char *cn[6] = { "sparse", "mid", "dense", "large", "dc0", "full" };
    printf( "%-6s", cn[cls] );
    for( int a = 0; a < narm; a++ )
    {
        qsort( tt[a], 3000, 4, cmpu );
        printf( "  %s %6.1f", an[a], (double)tt[a][1500] / NB );
    }
    printf( "\n" );
}


/* instructions per call by single-stepping (trap flag): user instructions of the call,
 * the call/ret and the TF toggling included equally in every arm */
#include <signal.h>
static volatile long g_steps;
static void on_trap( int sig, siginfo_t *si, void *uc ) { (void)sig; (void)si; (void)uc; g_steps++; }
static inline void tf_on( void ) { __asm__ volatile( "pushfq; orq $0x100, (%%rsp); popfq" ::: "memory", "cc" ); }
static inline void tf_off( void ) { __asm__ volatile( "pushfq; andq $~0x100, (%%rsp); popfq" ::: "memory", "cc" ); }
static void icount( int narm, const char **an, resfn *af )
{
    struct sigaction sa;
    memset( &sa, 0, sizeof(sa) );
    sa.sa_sigaction = on_trap;
    sa.sa_flags = SA_SIGINFO;
    sigaction( SIGTRAP, &sa, NULL );
    static const char *cn[6] = { "sparse", "mid", "dense", "large", "dc0", "full" };
    for( int cls = 0; cls < 6; cls++ )
    {
        printf( "%-6s", cn[cls] );
        for( int a = 0; a < narm; a++ )
        {
            static __attribute__((aligned(64))) dctcoef blk[16];
            static x264_cabac_t cb;
            rs = 999 + cls;
            for( int k = 0; k < 1024; k++ ) cb.state[k] = 20 + (k*7)%80;
            long tot = 0;
            for( int b = 0; b < 2000; b++ )
            {
                bench_block( blk, cls );
                int inter = rnd()&1;
                g_steps = 0;
                tf_on();
                if( af[a] ) af[a]( blk, inter, 3, &cb );
                else ref_rd( &cb, inter, 3, blk );
                tf_off();
                tot += g_steps;
            }
            printf( "  %s %6.1f", an[a], tot / 2000. );
        }
        printf( "\n" );
    }
}

static void run( int mode, int iters )
{
    rdo_init();
    const char *an[NARM]; resfn af[NARM]; int n = 0;
    an[n] = "C"; af[n++] = 0;
    an[n] = "icl"; af[n++] = P(cabac_block_residual_422_dc_rd_internal_avx512icl);
    an[n] = "avx2"; af[n++] = P(cabac_block_residual_422_dc_rd_internal_avx2_bmi2);
#ifdef ICL2
    an[n] = "icl2"; af[n++] = P(cabac_block_residual_422_dc_rd2_internal_avx512icl);
#endif
#ifdef XARMS
    an[n] = "x1"; af[n++] = x1_fn;
    an[n] = "x2"; af[n++] = x2_fn;
#endif
    if( mode == 0 )
    {
        for( int a = 1; a < n; a++ )
            test( an[a], af[a], iters );
        printf( "%ld cases, %s\n", tests, fails ? "FAILURES" : "all bit-exact" );
        return;
    }
    if( mode == 2 )
    {
        icount( n, an, af );
        return;
    }
    for( int cls = 0; cls < 6; cls++ )
        ibench( cls, n, an, af );
}

static int g_mode, g_iters;
static void run_aligned( void ) { run( g_mode, g_iters ); }
int main( int argc, char **argv )
{
    g_mode = argc > 1 && !strcmp( argv[1], "bench" ) ? 1 : argc > 1 && !strcmp( argv[1], "icount" ) ? 2 : 0;
    g_iters = argc > 2 ? atoi( argv[2] ) : 20000;
    P(stack_align)( run_aligned, 0 );
    return fails ? 1 : 0;
}
