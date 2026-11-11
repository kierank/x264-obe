/* cabacrd driver: avx2 cabac rd 4x4 / 8x8 and 4:2:2 dc writer vs x264's C.
 * C reference copied from x264 encoder/cabac.c, encoder/rdo.c, common/cabac.c. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <x86intrin.h>
#include "tables.h"

typedef int32_t dctcoef;
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

/* asm externs */
uint8_t  x264_10_cabac_transition_unary[15][128];
uint16_t x264_10_cabac_size_unary[15][128];
__attribute__((aligned(64))) const uint8_t  x264_10_pb_1[64] = { [0 ... 63] = 1 };
__attribute__((aligned(64))) const uint16_t x264_10_pw_1[32] = { [0 ... 31] = 1 };
__attribute__((aligned(64))) const uint32_t x264_10_pd_1[16] = { [0 ... 15] = 1 };
__attribute__((aligned(64))) const uint32_t x264_10_deinterleave_shufd[8] = { 0,4,1,5,2,6,3,7 };
#define STUB(n) void n( void ) { abort(); }
STUB(x264_10_coeff_last4_mmx2) STUB(x264_10_coeff_last4_mmx2_lzcnt) STUB(x264_10_coeff_last4_avx512)
STUB(x264_10_coeff_last15_sse2) STUB(x264_10_coeff_last15_sse2_lzcnt) STUB(x264_10_coeff_last15_avx512)
STUB(x264_10_coeff_last16_sse2) STUB(x264_10_coeff_last16_sse2_lzcnt) STUB(x264_10_coeff_last16_avx512)
STUB(x264_10_coeff_last64_sse2) STUB(x264_10_coeff_last64_sse2_lzcnt) STUB(x264_10_coeff_last64_avx2_lzcnt)
STUB(x264_10_coeff_last64_avx512) STUB(x264_10_cabac_encode_ue_bypass) STUB(x264_10_intel_cpu_indicator_init)
intptr_t x264_10_stack_align( void (*func)(), ... );

typedef void (*resfn)( dctcoef *l, int b_interlaced, intptr_t ctx_block_cat, x264_cabac_t *cb );
void x264_10_cabac_block_residual_rd_internal_ssse3_lzcnt( dctcoef *, int, intptr_t, x264_cabac_t * );
void x264_10_cabac_block_residual_rd_internal_avx2_bmi2( dctcoef *, int, intptr_t, x264_cabac_t * );
void x264_10_cabac_block_residual_rd_internal_avx512icl( dctcoef *, int, intptr_t, x264_cabac_t * );
void x264_10_cabac_block_residual_8x8_rd_internal_ssse3_lzcnt( dctcoef *, int, intptr_t, x264_cabac_t * );
void x264_10_cabac_block_residual_8x8_rd_internal_avx2_bmi2( dctcoef *, int, intptr_t, x264_cabac_t * );
void x264_10_cabac_block_residual_8x8_rd_internal_avx512icl( dctcoef *, int, intptr_t, x264_cabac_t * );
void x264_10_cabac_block_residual_422_dc_internal_avx2_bmi2( dctcoef *, int, intptr_t, x264_cabac_t * );
void x264_10_cabac_block_residual_422_dc_internal_avx512icl( dctcoef *, int, intptr_t, x264_cabac_t * );

/* ---- common/cabac.c ---- */
static void cabac_encode_init( x264_cabac_t *cb, uint8_t *p_data, uint8_t *p_end )
{
    cb->i_low   = 0;
    cb->i_range = 0x01FE;
    cb->i_queue = -9;
    cb->i_bytes_outstanding = 0;
    cb->p_start = p_data;
    cb->p       = p_data;
    cb->p_end   = p_end;
}
static inline void cabac_putbyte( x264_cabac_t *cb )
{
    if( cb->i_queue >= 0 )
    {
        int out = cb->i_low >> (cb->i_queue+10);
        cb->i_low &= (0x400<<cb->i_queue)-1;
        cb->i_queue -= 8;
        if( (out & 0xff) == 0xff )
            cb->i_bytes_outstanding++;
        else
        {
            int carry = out >> 8;
            int bytes_outstanding = cb->i_bytes_outstanding;
            cb->p[-1] += carry;
            while( bytes_outstanding > 0 )
            {
                *(cb->p++) = carry-1;
                bytes_outstanding--;
            }
            *(cb->p++) = out;
            cb->i_bytes_outstanding = 0;
        }
    }
}
static inline void cabac_encode_renorm( x264_cabac_t *cb )
{
    int shift = x264_cabac_renorm_shift[cb->i_range>>3];
    cb->i_range <<= shift;
    cb->i_low   <<= shift;
    cb->i_queue  += shift;
    cabac_putbyte( cb );
}
static void cabac_encode_decision_c( x264_cabac_t *cb, int i_ctx, int b )
{
    int i_state = cb->state[i_ctx];
    int i_range_lps = x264_cabac_range_lps[i_state>>1][(cb->i_range>>6)-4];
    cb->i_range -= i_range_lps;
    if( b != (i_state & 1) )
    {
        cb->i_low += cb->i_range;
        cb->i_range = i_range_lps;
    }
    cb->state[i_ctx] = x264_cabac_transition[i_state][b];
    cabac_encode_renorm( cb );
}
static void cabac_encode_bypass_c( x264_cabac_t *cb, int b )
{
    cb->i_low <<= 1;
    cb->i_low += b & cb->i_range;
    cb->i_queue += 1;
    cabac_putbyte( cb );
}
static const int bypass_lut[16] =
{
    -1,      0x2,     0x14,     0x68,     0x1d0,     0x7a0,     0x1f40,     0x7e80,
    0x1fd00, 0x7fa00, 0x1ff400, 0x7fe800, 0x1ffd000, 0x7ffa000, 0x1fff4000, 0x7ffe8000
};
static void cabac_encode_ue_bypass( x264_cabac_t *cb, int exp_bits, int val )
{
    uint32_t v = val + (1<<exp_bits);
    int k = 31 - __builtin_clz( v );
    uint32_t x = (bypass_lut[k-exp_bits]<<exp_bits) + v;
    k = 2*k+1-exp_bits;
    int i = ((k-1)&7)+1;
    do {
        k -= i;
        cb->i_low <<= i;
        cb->i_low += ((x>>k)&0xff) * cb->i_range;
        cb->i_queue += i;
        cabac_putbyte( cb );
        i = 8;
    } while( k > 0 );
}
static void cabac_encode_flush( x264_cabac_t *cb )
{
    cb->i_low += cb->i_range - 2;
    cb->i_low |= 1;
    cb->i_low <<= 9;
    cb->i_queue += 9;
    cabac_putbyte( cb );
    cabac_putbyte( cb );
    cb->i_low <<= -cb->i_queue;
    cb->i_low |= (0x35a4e4f5 >> (0 & 31) & 1) << 10;
    cb->i_queue = 0;
    cabac_putbyte( cb );
    while( cb->i_bytes_outstanding > 0 )
    {
        *(cb->p++) = 0xff;
        cb->i_bytes_outstanding--;
    }
}
static int cabac_pos( x264_cabac_t *cb )
{
    return (cb->p - cb->p_start + cb->i_bytes_outstanding) * 8 + cb->i_queue;
}

/* ---- common/cabac.h size decision, encoder/rdo.c ---- */
static inline void cabac_size_decision( x264_cabac_t *cb, long i_ctx, long b )
{
    int i_state = cb->state[i_ctx];
    cb->state[i_ctx] = x264_cabac_transition[i_state][b];
    cb->f8_bits_encoded += x264_cabac_entropy[i_state^b];
}
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
            x264_10_cabac_size_unary[i_prefix][i_ctx] = f8_bits;
            x264_10_cabac_transition_unary[i_prefix][i_ctx] = ctx;
        }
}
static inline int bs_size_ue_big( unsigned int val )
{
    /* same value as x264's table version */
    return 2*(31 - __builtin_clz( val+1 )) + 1;
}

static const uint8_t coeff_abs_level1_ctx[8] = { 1, 2, 3, 4, 0, 0, 0, 0 };
static const uint8_t coeff_abs_levelgt1_ctx[8] = { 5, 5, 5, 5, 6, 7, 8, 9 };
static const uint8_t coeff_abs_levelgt1_ctx_chroma_dc[8] = { 5, 5, 5, 5, 6, 7, 8, 8 };
static const uint8_t coeff_abs_level_transition[2][8] = {
    { 1, 2, 3, 3, 4, 5, 6, 7 },
    { 4, 4, 4, 4, 5, 6, 7, 7 }
};

static int coeff_last( dctcoef *l, int count )
{
    int i = count-1;
    while( i >= 0 && !l[i] ) i--;
    return i;
}

/* encoder/cabac.c, RDO_SKIP_BS */
#define RD_DEC(c,x,v) cabac_size_decision(c,x,v)
#define RD_BYP(c,v) ((c)->f8_bits_encoded += 256)
#define RD_UE(c,e,v) ((c)->f8_bits_encoded += (bs_size_ue_big(v+(1<<e)-1)-e)<<8)
static void ref_rd( x264_cabac_t *cb, int MB_INTERLACED, int ctx_block_cat, dctcoef *l, int b_8x8, int chroma422dc )
{
    const uint8_t *sig_offset = x264_significant_coeff_flag_offset_8x8[MB_INTERLACED];
    int ctx_sig = x264_significant_coeff_flag_offset[MB_INTERLACED][ctx_block_cat];
    int ctx_last = x264_last_coeff_flag_offset[MB_INTERLACED][ctx_block_cat];
    int ctx_level = x264_coeff_abs_level_m1_offset[ctx_block_cat];
    int last = coeff_last( l, chroma422dc ? 8 : x264_count_cat_m1[ctx_block_cat]+1 );
    int coeff_abs = abs(l[last]);
    int ctx = coeff_abs_level1_ctx[0] + ctx_level;
    int node_ctx;
    const uint8_t *levelgt1_ctx = chroma422dc ? coeff_abs_levelgt1_ctx_chroma_dc : coeff_abs_levelgt1_ctx;

    if( last != (b_8x8 ? 63 : chroma422dc ? 7 : x264_count_cat_m1[ctx_block_cat]) )
    {
        RD_DEC( cb, ctx_sig + (b_8x8 ? sig_offset[last] :
                chroma422dc ? x264_coeff_flag_offset_chroma_422_dc[last] : last), 1 );
        RD_DEC( cb, ctx_last + (b_8x8 ? x264_last_coeff_flag_offset_8x8[last] :
                chroma422dc ? x264_coeff_flag_offset_chroma_422_dc[last] : last), 1 );
    }
    if( coeff_abs > 1 )
    {
        RD_DEC( cb, ctx, 1 );
        ctx = levelgt1_ctx[0] + ctx_level;
        if( coeff_abs < 15 )
        {
            cb->f8_bits_encoded += x264_10_cabac_size_unary[coeff_abs-1][cb->state[ctx]];
            cb->state[ctx] = x264_10_cabac_transition_unary[coeff_abs-1][cb->state[ctx]];
        }
        else
        {
            cb->f8_bits_encoded += x264_10_cabac_size_unary[14][cb->state[ctx]];
            cb->state[ctx] = x264_10_cabac_transition_unary[14][cb->state[ctx]];
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
            RD_DEC( cb, ctx_sig + (b_8x8 ? sig_offset[i] :
                    chroma422dc ? x264_coeff_flag_offset_chroma_422_dc[i] : i), 1 );
            RD_DEC( cb, ctx_last + (b_8x8 ? x264_last_coeff_flag_offset_8x8[i] :
                    chroma422dc ? x264_coeff_flag_offset_chroma_422_dc[i] : i), 0 );
            ctx = coeff_abs_level1_ctx[node_ctx] + ctx_level;
            if( coeff_abs > 1 )
            {
                RD_DEC( cb, ctx, 1 );
                ctx = levelgt1_ctx[node_ctx] + ctx_level;
                if( coeff_abs < 15 )
                {
                    cb->f8_bits_encoded += x264_10_cabac_size_unary[coeff_abs-1][cb->state[ctx]];
                    cb->state[ctx] = x264_10_cabac_transition_unary[coeff_abs-1][cb->state[ctx]];
                }
                else
                {
                    cb->f8_bits_encoded += x264_10_cabac_size_unary[14][cb->state[ctx]];
                    cb->state[ctx] = x264_10_cabac_transition_unary[14][cb->state[ctx]];
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
            RD_DEC( cb, ctx_sig + (b_8x8 ? sig_offset[i] :
                    chroma422dc ? x264_coeff_flag_offset_chroma_422_dc[i] : i), 0 );
    }
}

/* encoder/cabac.c writer, chroma422dc = 1 */
static void ref_422dc( x264_cabac_t *cb, int MB_INTERLACED, dctcoef *l )
{
    int ctx_block_cat = 3; /* DCT_CHROMA_DC */
    int ctx_sig = x264_significant_coeff_flag_offset[MB_INTERLACED][ctx_block_cat];
    int ctx_last = x264_last_coeff_flag_offset[MB_INTERLACED][ctx_block_cat];
    int ctx_level = x264_coeff_abs_level_m1_offset[ctx_block_cat];
    int coeff_idx = -1, node_ctx = 0;
    int last = coeff_last( l, 8 );
    const uint8_t *levelgt1_ctx = coeff_abs_levelgt1_ctx_chroma_dc;
    dctcoef coeffs[64];
    int count_m1 = 7;
    int i = 0;
    while( 1 )
    {
        if( l[i] )
        {
            coeffs[++coeff_idx] = l[i];
            cabac_encode_decision_c( cb, ctx_sig + x264_coeff_flag_offset_chroma_422_dc[i], 1 );
            if( i == last )
            {
                cabac_encode_decision_c( cb, ctx_last + x264_coeff_flag_offset_chroma_422_dc[i], 1 );
                break;
            }
            else
                cabac_encode_decision_c( cb, ctx_last + x264_coeff_flag_offset_chroma_422_dc[i], 0 );
        }
        else
            cabac_encode_decision_c( cb, ctx_sig + x264_coeff_flag_offset_chroma_422_dc[i], 0 );
        if( ++i == count_m1 )
        {
            coeffs[++coeff_idx] = l[i];
            break;
        }
    }
    do
    {
        int coeff = coeffs[coeff_idx];
        int abs_coeff = abs(coeff);
        int coeff_sign = coeff >> 31;
        int ctx = coeff_abs_level1_ctx[node_ctx] + ctx_level;
        if( abs_coeff > 1 )
        {
            cabac_encode_decision_c( cb, ctx, 1 );
            ctx = levelgt1_ctx[node_ctx] + ctx_level;
            for( int i = (abs_coeff < 15 ? abs_coeff : 15) - 2; i > 0; i-- )
                cabac_encode_decision_c( cb, ctx, 1 );
            if( abs_coeff < 15 )
                cabac_encode_decision_c( cb, ctx, 0 );
            else
                cabac_encode_ue_bypass( cb, 0, abs_coeff - 15 );
            node_ctx = coeff_abs_level_transition[1][node_ctx];
        }
        else
        {
            cabac_encode_decision_c( cb, ctx, 0 );
            node_ctx = coeff_abs_level_transition[0][node_ctx];
        }
        cabac_encode_bypass_c( cb, coeff_sign );
    } while( --coeff_idx >= 0 );
}

/* ---- test ---- */
static uint32_t rs = 1;
static uint32_t rnd( void ) { rs = rs*1664525u + 1013904223u; return rs >> 8; }
static int gen_level( int big )
{
    static const int lv[20] = { 1, 2, 3, 13, 14, 15, 16, 17, 29, 30, 31, 255, 256, 0x7f00, 0x7fff, 32768, 0xffff, 0x8001, 0xfff0, 0xc000 };
    int r = rnd();
    int v;
    if( big ) v = lv[r%20];
    else if( r&3 ) v = 1;
    else if( r&4 ) v = 2 + (rnd()&3);
    else v = 1 + (rnd()%20);
    if( v == 32768 ) return -32768;
    return rnd()&1 ? -v : v;
}
/* modes: 0 random density, 1 single coef, 2 dense, 3 sparse, 4 escapes, 5 all nonzero, 6 last at end only, 7 first only */
static void gen_block( dctcoef *l, int count, int mode )
{
    int nz = 0;
    do {
        int dens = mode == 0 ? rnd()%16 : mode == 2 ? 14 : mode == 3 ? 1 : mode == 4 ? 6 : 16;
        for( int k = 0; k < count; k++ )
        {
            int c = 0;
            if( mode == 1 || mode == 6 || mode == 7 )
                c = 0;
            else if( (int)(rnd()%16) < dens )
                c = gen_level( mode == 4 || (rnd()&7) == 0 );
            l[k] = c;
            nz |= c;
        }
        if( mode == 1 ) { l[rnd()%count] = gen_level( rnd()&1 ); nz = 1; }
        if( mode == 6 ) { l[count-1] = gen_level( rnd()&1 ); if( rnd()&1 ) l[rnd()%count] = gen_level( 0 ); nz = 1; }
        if( mode == 7 ) { l[0] = gen_level( rnd()&1 ); nz = 1; }
        if( mode >= 8 ) /* levels +-1 at a random density; 9-11: plus 1-8 levels > 1; 12+: long +-1 runs */
        {
            int d = mode >= 12 ? 15 : rnd()%17;
            nz = 0;
            for( int k = 0; k < count; k++ ) { l[k] = (int)(rnd()%16) < d ? (rnd()&1 ? 1 : -1) : 0; nz |= l[k]; }
            for( int g = mode >= 9 && mode < 12 ? 1 + rnd()%8 : mode >= 12 ? rnd()%3 : 0; g > 0; g-- )
            { int k = rnd()%count; l[k] = gen_level( 1 ); if( l[k] == 1 || l[k] == -1 ) l[k] *= 2; nz = 1; }
            if( !nz ) { l[rnd()%count] = 1; nz = 1; }
        }
    } while( !nz );
}
static void rand_states( x264_cabac_t *cb )
{
    int m = rnd()%6;
    /* 3, 4: the most skewed states, MPS 0 or 1; 5: states 0-1, which keep 5.7 bits per LPS bin */
    for( int k = 0; k < 1024; k++ )
        cb->state[k] = m == 0 ? rnd()&127 : m == 1 ? (rnd()&1 ? 2 + (rnd()&7) : 118 + (rnd()&9)) :
                       m == 2 ? 60 + (rnd()&7) : m == 3 ? 2 + 2*(rnd()&3) : m == 4 ? 3 + 2*(rnd()&3) : rnd()&1;
}

static int fails = 0;
static long tests = 0;

static void test_rd( const char *name, resfn fa, int is8x8, int iters )
{
    int maxdelta = 0;
    static const int cats4[] = { 0, 1, 2, 3, 4, 6, 7, 8, 10, 11, 12 };
    static const int cats8[] = { 5, 9, 13 };
    const int *cats = is8x8 ? cats8 : cats4;
    int ncat = is8x8 ? 3 : 11;
    int bad = 0;
    for( int it = 0; it < iters && bad < 5; it++ )
        for( int ci = 0; ci < ncat; ci++ )
            for( int inter = 0; inter < 2; inter++ )
            {
                int cat = cats[ci];
                static const uint8_t ctx_ac[14] = {0,1,0,0,1,0,0,1,0,0,0,1,0,0};
                int ac = ctx_ac[cat];
                int count = x264_count_cat_m1[cat]+1;
                __attribute__((aligned(64))) dctcoef dct[2][80];
                for( int k = 0; k < 80; k++ )
                    dct[0][k] = dct[1][k] = (int32_t)rnd(); /* junk around the block (AC: the DC slot) */
                gen_block( dct[0]+ac, count, it&15 );
                memcpy( dct[1]+ac, dct[0]+ac, count*sizeof(dctcoef) );
                x264_cabac_t cb[2];
                memset( cb, 0, sizeof(cb) );
                rand_states( &cb[0] );
                memcpy( cb[1].state, cb[0].state, 1024 );
                int f8_0 = cb[0].f8_bits_encoded = cb[1].f8_bits_encoded = rnd() & 0xffff;
                ref_rd( &cb[0], inter, cat, dct[0]+ac, is8x8, 0 );
                if( cb[0].f8_bits_encoded - f8_0 > maxdelta ) maxdelta = cb[0].f8_bits_encoded - f8_0;
                fa( dct[1]+ac, inter, cat, &cb[1] );
                tests++;
                if( cb[0].f8_bits_encoded != cb[1].f8_bits_encoded || memcmp( cb[0].state, cb[1].state, 1024 ) ||
                    memcmp( dct[0], dct[1], sizeof(dct[0]) ) )
                {
                    if( bad++ < 3 )
                        printf( "%s FAIL cat %d field %d mode %d bits %d vs %d\n", name, cat, inter, it&15,
                                cb[0].f8_bits_encoded, cb[1].f8_bits_encoded );
                    if( bad == 1 ) { int nd = 0; for( int k = 0; k < 1024; k++ ) nd += cb[0].state[k] != cb[1].state[k]; printf( "  f8_0 %d states differ %d input %s:", f8_0, nd, memcmp( dct[0], dct[1], sizeof(dct[0]) ) ? "DIFFERS" : "same" ); for( int k = 0; k < count; k++ ) printf( " %d", dct[0][ac+k] ); printf( "\n  states:" ); for( int k = 0; k < 1024; k++ ) if( cb[0].state[k] != cb[1].state[k] ) printf( " [%d] %d/%d", k, cb[0].state[k], cb[1].state[k] ); printf( "\n" ); }
                }
            }
    printf( "%-48s %s (max f8 per block %d)\n", name, bad ? "FAILED" : "ok", maxdelta );
    fails += !!bad;
}

static void test_422( const char *name, resfn fa, int iters )
{
    int bad = 0;
    static uint8_t bs[2][1<<16];
    for( int it = 0; it < iters && bad < 5; it++ )
        for( int inter = 0; inter < 2; inter++ )
        {
            __attribute__((aligned(64))) dctcoef dct[2][16];
            int mask = (it & 255) ? (it & 255) : 1 + (rnd() & 254);
            for( int k = 0; k < 16; k++ )
                dct[0][k] = k < 8 && (mask >> k & 1) ? gen_level( (it>>8)&1 ) : (k < 8 ? 0 : (int32_t)rnd());
            memcpy( dct[1], dct[0], sizeof(dct[0]) );
            x264_cabac_t cb[2];
            memset( cb, 0, sizeof(cb) );
            rand_states( &cb[0] );
            for( int k = 0; k < 1024; k++ ) /* states 0-1 (terminate) are never coded as decisions */
                if( cb[0].state[k] < 2 ) cb[0].state[k] += 2;
            memcpy( cb[1].state, cb[0].state, 1024 );
            cabac_encode_init( &cb[0], bs[0], bs[0]+0xfff0 );
            cabac_encode_init( &cb[1], bs[1], bs[1]+0xfff0 );
            memset( bs[0], 0x5a, 0x400 );
            memcpy( bs[1], bs[0], 0x400 );
            for( int k = rnd()&63 | (it&2)*12; k > 0; k-- )
            {
                int bit = -(rnd()&1);
                cabac_encode_bypass_c( &cb[0], bit );
                cabac_encode_bypass_c( &cb[1], bit );
            }
            if( (it&2) && cb[0].p > cb[0].p_start )
            {
                cb[0].i_low = cb[1].i_low = (1 << (cb[0].i_queue+18)) - 1 - (rnd()&0x7f);
                for( int k = (it&1) * (8 + (rnd()&31)); k > 0; k-- )
                {
                    int bit = -(2*cb[0].i_low + cb[0].i_range < (2 << (cb[0].i_queue+18)));
                    cabac_encode_bypass_c( &cb[0], bit );
                    cabac_encode_bypass_c( &cb[1], bit );
                }
            }
            ref_422dc( &cb[0], inter, dct[0] );
            fa( dct[1], inter, 3, &cb[1] );
            tests++;
            int ok = !memcmp( cb[0].state, cb[1].state, 1024 ) && cabac_pos( &cb[0] ) == cabac_pos( &cb[1] ) &&
                     cb[0].i_range == cb[1].i_range && cb[0].i_queue == cb[1].i_queue;
            x264_cabac_t fl[2];
            memcpy( fl, cb, sizeof(fl) );
            cabac_encode_bypass_c( &fl[0], 0 );
            cabac_encode_bypass_c( &fl[1], 0 );
            cabac_encode_flush( &fl[0] );
            cabac_encode_flush( &fl[1] );
            ok &= fl[0].p - bs[0] == fl[1].p - bs[1] && !memcmp( bs[0], bs[1], fl[0].p - bs[0] );
            if( !ok && bad++ < 3 )
            {
                int nd = 0;
                for( int k = 0; k < 1024; k++ ) nd += cb[0].state[k] != cb[1].state[k];
                printf( "%s FAIL mask %02x field %d: states %d pos %d/%d range %d/%d queue %d/%d coefs", name, mask, inter, nd,
                        cabac_pos( &cb[0] ), cabac_pos( &cb[1] ), cb[0].i_range, cb[1].i_range, cb[0].i_queue, cb[1].i_queue );
                for( int k = 0; k < 8; k++ ) printf( " %d", dct[0][k] );
                printf( "\n" );
            }
        }
    printf( "%-48s %s\n", name, bad ? "FAILED" : "ok" );
    fails += !!bad;
}

/* ---- bench: checkasm's block classes ---- */
static void bench_block( dctcoef *l, int count, int cls )
{
    int nz = 0;
    memset( l, 0, 64*sizeof(dctcoef) );
    if( cls >= 4 ) /* scan-order decay: low frequencies dense, levels > 1 there; 4: short (~16), 5: long (~40) */
    {
        int len = cls == 4 ? 16 + rnd()%12 : 32 + rnd()%30;
        while( !nz )
            for( int k = 0; k < count; k++ )
            {
                int r = rnd(), p = k < len ? 240 * (len - k) / len : 0;
                int coef = (int)(r & 255) < p;
                if( coef && (int)((r >> 8) & 255) < p / 3 ) coef += 1 + ((r >> 16) & 3) * !((r >> 18) & 3);
                nz |= l[k] = r & 0x800000 ? -coef : coef;
            }
        return;
    }
    while( !nz )
        for( int k = 0; k < count; k++ )
        {
            int r = rnd();
            int coef = cls == 0 ? !(r&15) : cls == 2 ? !!(r&7) : !(r&3);
            if( coef && cls < 3 )
                coef += !(r&0x70) * ((r>>8)&3);
            else if( coef )
                coef += (r>>8)&63 ? (r>>14)&63 : (r>>14)&0x3fff;
            nz |= l[k] = r&0x80 ? -coef : coef;
        }
}
typedef void (*cfn)( x264_cabac_t *cb, int inter, int cat, dctcoef *l );
static void c_rd4( x264_cabac_t *cb, int inter, int cat, dctcoef *l ) { ref_rd( cb, inter, cat, l, 0, 0 ); }
static void c_rd8( x264_cabac_t *cb, int inter, int cat, dctcoef *l ) { ref_rd( cb, inter, cat, l, 1, 0 ); }
static void c_422( x264_cabac_t *cb, int inter, int cat, dctcoef *l ) { ref_422dc( cb, inter, l ); }
#define NB 64
static int fresh = 0;
static double bench( resfn fa, cfn fc, int kind, int cls )
{
    static const int cats4[] = { 0, 1, 2, 3, 4, 6, 7, 8, 10, 11, 12 };
    static const int cats8[] = { 5, 9, 13 };
    static __attribute__((aligned(64))) dctcoef blk[NB][80];
    static int bcat[NB], binter[NB], bac[NB];
    static uint8_t bs[1<<20];
    static const uint8_t ctx_ac[14] = {0,1,0,0,1,0,0,1,0,0,0,1,0,0};
    rs = 12345 + cls;
    for( int b = 0; b < NB; b++ )
    {
        int cat = kind == 0 ? cats4[b%11] : kind == 1 ? cats8[b%3] : 3;
        int count = kind == 2 ? 8 : x264_count_cat_m1[cat]+1;
        bcat[b] = cat; binter[b] = (b>>4)&1; bac[b] = kind == 2 ? 0 : ctx_ac[cat];
        bench_block( blk[b]+bac[b], count, cls );
    }
    x264_cabac_t cb;
    memset( &cb, 0, sizeof(cb) );
    for( int k = 0; k < 1024; k++ ) cb.state[k] = 20 + (k*7)%80;
    uint64_t best = ~0ULL;
    if( fresh )
    {
        /* new blocks every batch: the branch predictor cannot learn them */
        for( int rep = 0; rep < 7; rep++ )
        {
            uint64_t sum = 0;
            rs = 777 + cls;
            for( int t = 0; t < 400; t++ )
            {
                for( int b = 0; b < NB; b++ )
                    bench_block( blk[b]+bac[b], kind == 2 ? 8 : x264_count_cat_m1[bcat[b]]+1, cls );
                cabac_encode_init( &cb, bs, bs + sizeof(bs) - 64 );
                uint64_t t0 = __rdtsc();
                for( int b = 0; b < NB; b++ )
                {
                    if( fa ) fa( blk[b]+bac[b], binter[b], bcat[b], &cb );
                    else fc( &cb, binter[b], bcat[b], blk[b]+bac[b] );
                }
                sum += __rdtsc() - t0;
            }
            if( sum < best ) best = sum;
        }
        return (double)best / (NB*400);
    }
    for( int t = 0; t < 200; t++ )
    {
        cabac_encode_init( &cb, bs, bs + sizeof(bs) - 64 );
        uint64_t t0 = __rdtsc();
        for( int b = 0; b < NB; b++ )
        {
            if( fa ) fa( blk[b]+bac[b], binter[b], bcat[b], &cb );
            else fc( &cb, binter[b], bcat[b], blk[b]+bac[b] );
        }
        uint64_t t1 = __rdtsc();
        if( t1 - t0 < best ) best = t1 - t0;
    }
    return (double)best / NB;
}

/* interleaved bench: every arm on the same fresh batch, so drift hits all arms alike */
#ifdef ARMS
void v1_rd4( dctcoef *, int, intptr_t, x264_cabac_t * );
void v1_rd8( dctcoef *, int, intptr_t, x264_cabac_t * );
#endif
#define NARM 12
int cmpu( const void *x, const void *y ) { uint32_t a = *(const uint32_t*)x, b = *(const uint32_t*)y; return a < b ? -1 : a > b; }
static void ibench( int kind, int cls, int narm, const char **an, resfn *af, cfn cf )
{
    static const int cats4[] = { 0, 1, 2, 3, 4, 6, 7, 8, 10, 11, 12 };
    static const int cats8[] = { 5, 9, 13 };
    static const uint8_t ctx_ac[14] = {0,1,0,0,1,0,0,1,0,0,0,1,0,0};
    static __attribute__((aligned(64))) dctcoef blk[NB][80];
    static int bcat[NB], binter[NB], bac[NB];
    static uint8_t bs[1<<16];
    static x264_cabac_t cb0, cb;
    uint64_t sum[NARM] = {0}; static uint32_t tt[NARM][3000];
    rs = 4242 + cls;
    memset( &cb0, 0, sizeof(cb0) );
    for( int k = 0; k < 1024; k++ ) cb0.state[k] = 20 + (k*7)%80;
    for( int t = 0; t < 3000; t++ )
    {
        for( int b = 0; b < NB; b++ )
        {
            int cat = kind == 0 ? cats4[rnd()%11] : kind == 1 ? cats8[rnd()%3] : 3;
            bcat[b] = cat; binter[b] = rnd()&1; bac[b] = kind == 2 ? 0 : ctx_ac[cat];
            bench_block( blk[b]+bac[b], kind == 2 ? 8 : x264_count_cat_m1[cat]+1, cls );
        }
        for( int a0 = 0; a0 < narm; a0++ )
        {
            int a = (a0 + t) % narm;
            memcpy( &cb, &cb0, sizeof(cb) );
            cabac_encode_init( &cb, bs, bs + sizeof(bs) - 64 );
            uint64_t t0 = __rdtsc();
            for( int b = 0; b < NB; b++ )
            {
                if( af[a] ) af[a]( blk[b]+bac[b], binter[b], bcat[b], &cb );
                else cf( &cb, binter[b], bcat[b], blk[b]+bac[b] );
            }
            uint64_t dt = __rdtsc() - t0; sum[a] += dt; tt[a][t] = dt;
        }
    }
    static const char *kn[3] = { "rd4x4", "rd8x8", "422dc" };
    static const char *cn[6] = { "sparse", "mid", "dense", "large", "decay16", "decay40" };
    printf( "%s %-6s", kn[kind], cn[cls] );
    for( int a = 0; a < narm; a++ )
    { int cmpu( const void *x, const void *y ); qsort( tt[a], 3000, 4, cmpu ); printf( "  %s %6.1f", an[a], (double)tt[a][1500] / NB ); }
    printf( "\n" );
}

/* 10-bit arms */
void x264_10_cabac_block_residual_8x8_rd_internal_avx512( dctcoef *, int, intptr_t, x264_cabac_t * );
void x264_10_cabac_block_residual_rd2_internal_avx512icl( dctcoef *, int, intptr_t, x264_cabac_t * );
#ifdef ICL2
void x264_10_cabac_block_residual_8x8_rd2_internal_avx512icl( dctcoef *, int, intptr_t, x264_cabac_t * );
#endif
#ifdef XARMS
void x1_fn( dctcoef *, int, intptr_t, x264_cabac_t * );
void x2_fn( dctcoef *, int, intptr_t, x264_cabac_t * );
void x3_fn( dctcoef *, int, intptr_t, x264_cabac_t * );
void x4_fn( dctcoef *, int, intptr_t, x264_cabac_t * );
#endif
#ifndef K4
#define K4 1
#endif
#ifndef K8
#define K8 0
#endif
#ifndef K422
#define K422 0
#endif
static void run( int mode, int iters )
{
    rdo_init();
    if( mode == 0 )
    {
        test_rd( "rd 4x4 ssse3_lzcnt (control)", x264_10_cabac_block_residual_rd_internal_ssse3_lzcnt, 0, iters/10 );
        test_rd( "rd 4x4 avx512icl (control)", x264_10_cabac_block_residual_rd_internal_avx512icl, 0, iters/10 );
#if K4
        test_rd( "rd 4x4 avx2_bmi2 (new)", x264_10_cabac_block_residual_rd_internal_avx2_bmi2, 0, iters );
#endif
        test_rd( "rd 4x4 rd2 avx512icl (new)", x264_10_cabac_block_residual_rd2_internal_avx512icl, 0, iters );
        test_rd( "rd 8x8 ssse3_lzcnt (control)", x264_10_cabac_block_residual_8x8_rd_internal_ssse3_lzcnt, 1, iters/10 );
        test_rd( "rd 8x8 avx512icl (control)", x264_10_cabac_block_residual_8x8_rd_internal_avx512icl, 1, iters/10 );
#if K8
        test_rd( "rd 8x8 avx2_bmi2 (new)", x264_10_cabac_block_residual_8x8_rd_internal_avx2_bmi2, 1, iters );
#endif
#ifdef ICL2
        test_rd( "rd 8x8 rd2 avx512icl (new)", x264_10_cabac_block_residual_8x8_rd2_internal_avx512icl, 1, iters );
#endif
#ifdef XARMS
        test_rd( "x1 " X1NAME, x1_fn, XKIND, iters );
        test_rd( "x2 " X2NAME, x2_fn, XKIND, iters );
        test_rd( "x3 " X3NAME, x3_fn, XKIND, iters );
        test_rd( "x4 " X4NAME, x4_fn, XKIND, iters );
#endif
        test_422( "422 dc avx512icl (control)", x264_10_cabac_block_residual_422_dc_internal_avx512icl, iters/10 );
#if K422
        test_422( "422 dc avx2_bmi2 (new)", x264_10_cabac_block_residual_422_dc_internal_avx2_bmi2, iters );
#endif
        printf( "%ld cases, %s\n", tests, fails ? "FAILURES" : "all bit-exact" );
        return;
    }
    const char *an[NARM]; resfn af[NARM]; int n;
    /* rd 4x4 */
    n = 0;
    an[n] = "C"; af[n++] = 0;
    an[n] = "ssse3"; af[n++] = x264_10_cabac_block_residual_rd_internal_ssse3_lzcnt;
#if K4
    an[n] = "avx2"; af[n++] = x264_10_cabac_block_residual_rd_internal_avx2_bmi2;
#endif
#ifdef XARMS
    if( XKIND == 0 ) { an[n] = X1NAME; af[n++] = x1_fn; an[n] = X2NAME; af[n++] = x2_fn; an[n] = X3NAME; af[n++] = x3_fn; an[n] = X4NAME; af[n++] = x4_fn; }
#endif
    an[n] = "icl"; af[n++] = x264_10_cabac_block_residual_rd_internal_avx512icl;
    an[n] = "icl2"; af[n++] = x264_10_cabac_block_residual_rd2_internal_avx512icl;
    for( int cls = 0; cls < 6; cls++ )
        ibench( 0, cls, n, an, af, c_rd4 );
    /* rd 8x8 */
    n = 0;
    an[n] = "C"; af[n++] = 0;
    an[n] = "ssse3"; af[n++] = x264_10_cabac_block_residual_8x8_rd_internal_ssse3_lzcnt;
#if K8
    an[n] = "avx2"; af[n++] = x264_10_cabac_block_residual_8x8_rd_internal_avx2_bmi2;
#endif
    an[n] = "avx512"; af[n++] = x264_10_cabac_block_residual_8x8_rd_internal_avx512;
#ifdef XARMS
    if( XKIND == 1 ) { an[n] = X1NAME; af[n++] = x1_fn; an[n] = X2NAME; af[n++] = x2_fn; an[n] = X3NAME; af[n++] = x3_fn; an[n] = X4NAME; af[n++] = x4_fn; }
#endif
    an[n] = "icl"; af[n++] = x264_10_cabac_block_residual_8x8_rd_internal_avx512icl;
#ifdef ICL2
    an[n] = "icl2"; af[n++] = x264_10_cabac_block_residual_8x8_rd2_internal_avx512icl;
#endif
    for( int cls = 0; cls < 6; cls++ )
        ibench( 1, cls, n, an, af, c_rd8 );
    /* 4:2:2 dc writer */
    n = 0;
    an[n] = "C"; af[n++] = 0;
#if K422
    an[n] = "avx2"; af[n++] = x264_10_cabac_block_residual_422_dc_internal_avx2_bmi2;
#endif
    an[n] = "icl"; af[n++] = x264_10_cabac_block_residual_422_dc_internal_avx512icl;
    for( int cls = 0; cls < 4; cls++ )
        ibench( 2, cls, n, an, af, c_422 );
}

static int g_mode, g_iters;
static void run_aligned( void ) { run( g_mode, g_iters ); }
int main( int argc, char **argv )
{
    g_mode = argc > 1 && !strcmp( argv[1], "ibench" );
    g_iters = argc > 2 ? atoi( argv[2] ) : 20000;
    x264_10_stack_align( run_aligned, 0 );
    return fails ? 1 : 0;
}
