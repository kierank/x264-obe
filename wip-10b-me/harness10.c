/* me_search_fpel harness, high bit depth (from fpel/harness.c): x264_me_search_ref with
 * pixf.me_search_fpel NULL (the real C path: me_search_ref + refine_subpel on the AVX2
 * kernels) vs the fused entries, on realistic search states. Kernels at AVX2 (AVX-512
 * masked off); the avx512 entries run too where the host has AVX-512. Laptop numbers are
 * indicative only. Arms: 0 C, 1 base avx2 (old ME_SEARCH_FPEL xmm entry, fpel_b0_avx2),
 * 2 new avx2, 3 old avx512 (dispatched on AVX-512), 4 new inline avx512. */
#include "common/common.h"
#include "encoder/me.h"
#include "common/x86/pixel.h"
#include <x86intrin.h>
#include <math.h>

#define PST 768
#define PROWS 480
#define FW 640
#define FH 368
#define OX 64
#define OY 56
#define NST 2048
#define NARM 5

static uint32_t rng = 12345;
static int rnd( void ) { rng = rng*1103515245u + 12345u; return (rng >> 8) & 0xffffff; }

typedef struct
{
    int i_pixel, mbx, mby, px, py;
    int16_t mvp[2];
    int16_t mvc[16][2];
    int i_mvc;
    int16_t lim[2][2];
    int spel_min[2], spel_max[2];
    pixel *fenc;  /* 16x16 MB at FENC_STRIDE */
} state_t;

static pixel *planes[2][4];  /* set 0 smooth, 1 random: fpel, h, v, c */
static uint16_t *cost_tab;

static void hpel( pixel *src, pixel *h, pixel *v, pixel *c )
{
    static int32_t tv[PST*PROWS];
#define T6(p,s) ((p)[-2*(s)] - 5*(p)[-(s)] + 20*(p)[0] + 20*(p)[(s)] - 5*(p)[2*(s)] + (p)[3*(s)])
    for( int k = 0; k < PST*PROWS; k++ )
        h[k] = v[k] = c[k] = PIXEL_MAX/2;
    for( int y = 3; y < PROWS-3; y++ )
        for( int x = 3; x < PST-3; x++ )
        {
            pixel *p = src + y*PST + x;
            h[y*PST+x] = x264_clip_pixel( (T6(p,1) + 16) >> 5 );
            tv[y*PST+x] = T6(p,PST);
            v[y*PST+x] = x264_clip_pixel( (tv[y*PST+x] + 16) >> 5 );
        }
    for( int y = 3; y < PROWS-3; y++ )
        for( int x = 6; x < PST-6; x++ )
        {
            int32_t *p = tv + y*PST + x;
            c[y*PST+x] = x264_clip_pixel( (T6(p,1) + 512) >> 10 );
        }
}

/* qpel prediction pixel at fpel (x,y) + qpel (mx,my) from the hpel planes, as get_ref */
static pixel qpel_pix( pixel **fref, int x, int y, int mx, int my )
{
    static const uint8_t r0[16] = {0,1,1,1,0,1,1,1,2,3,3,3,0,1,1,1};
    static const uint8_t r1[16] = {0,0,1,0,2,2,3,2,2,2,3,2,2,2,3,2};
    int qi = ((my&3)<<2) + (mx&3);
    int off = (y + (my>>2))*PST + x + (mx>>2);
    pixel a = fref[r0[qi]][off + ((my&3)==3)*PST];
    if( qi & 5 )
        return (a + fref[r1[qi]][off + ((mx&3)==3)] + 1) >> 1;
    return a;
}

static void true_mv( int set, int mbx, int mby, int *mx, int *my )
{
    if( set )
    {
        *mx = (rnd()%161) - 80;
        *my = (rnd()%97) - 48;
        return;
    }
    /* a pan with a slow zoom and a wobble, qpel */
    *mx = 21 + (mbx - 20) * 3 / 4 + (int)(6*sinf( mby*0.4f ));
    *my = -10 + (mby - 11) / 2 + (int)(4*cosf( mbx*0.3f ));
}

static void make_states( state_t *st, int n, int set, int i_pixel )
{
    for( int k = 0; k < n; k++ )
    {
        state_t *s = &st[k];
        s->i_pixel = i_pixel;
        s->mbx = 1 + rnd()%(FW/16-2);
        s->mby = 1 + rnd()%(FH/16-2);
        s->px = i_pixel == PIXEL_16x16 || i_pixel == PIXEL_16x8 ? 0 : 8*(rnd()&1);
        s->py = i_pixel == PIXEL_16x16 || i_pixel == PIXEL_8x16 ? 0 : 8*(rnd()&1);
        int tmx, tmy;
        true_mv( set, s->mbx, s->mby, &tmx, &tmy );
        /* limits as x264_mb_analyse_init, border 6 */
        s->spel_min[0] = 4*(-16*s->mbx - 24);
        s->spel_max[0] = 4*(16*(FW/16 - s->mbx - 1) + 24);
        s->spel_min[1] = 4*(-16*s->mby - 24);
        s->spel_max[1] = 4*(16*(FH/16 - s->mby - 1) + 24);
        for( int i = 0; i < 2; i++ )
        {
            s->lim[0][i] = (s->spel_min[i]>>2) + 6;
            s->lim[1][i] = (s->spel_max[i]>>2) - 6;
        }
        /* fenc: the true-mv prediction plus noise (set 0), else random */
        s->fenc = x264_malloc( 16*FENC_STRIDE*sizeof(pixel) );
        int x0 = OX + 16*s->mbx, y0 = OY + 16*s->mby;
        for( int y = 0; y < 16; y++ )
            for( int x = 0; x < 16; x++ )
                s->fenc[y*FENC_STRIDE+x] = set ? rnd() & PIXEL_MAX
                    : x264_clip_pixel( qpel_pix( planes[0], x0+x, y0+y, tmx, tmy ) + (rnd()%9) - 4 );
        /* mvp near the true mv; predictors: neighbours, 0, far */
        int e = set ? 40 : 6;
        s->mvp[0] = tmx + (rnd()%(2*e+1)) - e;
        s->mvp[1] = tmy + (rnd()%(2*e+1)) - e;
        if( !(rnd()&15) ) s->mvp[0] = s->mvp[1] = 0;
        s->i_mvc = i_pixel == PIXEL_16x16 ? 2 + rnd()%5 : 1 + rnd()%3;
        for( int i = 0; i < s->i_mvc; i++ )
        {
            int t = rnd()&7;
            int mx = tmx + (rnd()%(2*e+1)) - e, my = tmy + (rnd()%(2*e+1)) - e;
            if( t == 0 ) mx = my = 0;
            else if( t == 1 ) { mx = s->mvp[0]; my = s->mvp[1]; }
            else if( t == 2 ) { mx = (rnd()%201) - 100; my = (rnd()%121) - 60; }
            else if( t == 3 ) { mx &= ~3; my &= ~3; }
            s->mvc[i][0] = mx;
            s->mvc[i][1] = my;
        }
    }
}

static x264_t *h;
static x264_me_t mtab[NST];

static void setup_m( state_t *s, x264_me_t *m, int set )
{
    memset( m, 0, sizeof(*m) );
    m->i_pixel = s->i_pixel;
    m->p_cost_mv = cost_tab;
    m->weight = x264_weight_none;
    int off = (OY + 16*s->mby + s->py)*PST + OX + 16*s->mbx + s->px;
    for( int p = 0; p < 4; p++ )
        m->p_fref[p] = planes[set][p] + off;
    m->p_fref_w = m->p_fref[0];
    m->p_fenc[0] = s->fenc + s->px + s->py*FENC_STRIDE;
    m->i_stride[0] = PST;
    m->mvp[0] = s->mvp[0];
    m->mvp[1] = s->mvp[1];
}

static inline void set_mb( state_t *s )
{
    for( int i = 0; i < 2; i++ )
    {
        h->mb.mv_min_spel[i] = s->spel_min[i];
        h->mb.mv_max_spel[i] = s->spel_max[i];
        h->mb.mv_limit_fpel[0][i] = s->lim[0][i];
        h->mb.mv_limit_fpel[1][i] = s->lim[1][i];
    }
    h->mb.pic.p_fenc[0] = s->fenc;
    h->mb.pic.i_fenc_pre = 0;
}

static void init_pixf( int cpu, int subme )
{
    x264_pixel_function_t *pf = &h->pixf;
    memset( pf, 0, sizeof(*pf) );
    x264_pixel_init( cpu, pf );
    int satd = subme > 1;
    memcpy( pf->mbcmp, satd ? pf->satd : pf->sad_aligned, sizeof(pf->mbcmp) );
    memcpy( pf->mbcmp_unaligned, satd ? pf->satd : pf->sad, sizeof(pf->mbcmp_unaligned) );
    if( satd )
    {
        memcpy( pf->mbcmp_avg2, pf->satd_avg2, sizeof(pf->mbcmp_avg2) );
        memcpy( pf->mbcmp_pre, pf->satd_pre, sizeof(pf->mbcmp_pre) );
        memcpy( pf->mbcmp_avg2_pre, pf->satd_avg2_pre, sizeof(pf->mbcmp_avg2_pre) );
        memcpy( pf->mbcmp_qpel_search, pf->satd_qpel_search, sizeof(pf->mbcmp_qpel_search) );
        memcpy( pf->mbcmp_subpel_search, pf->satd_subpel_search, sizeof(pf->mbcmp_subpel_search) );
    }
    memcpy( pf->fpelcmp, pf->sad, sizeof(pf->fpelcmp) );
    memcpy( pf->fpelcmp_x3, pf->sad_x3, sizeof(pf->fpelcmp_x3) );
    memcpy( pf->fpelcmp_x4, pf->sad_x4, sizeof(pf->fpelcmp_x4) );
    for( int i = 0; i < 7; i++ )
    {
        pf->fpelcmp_x3_min[i] = pf->sad_x3_min[i];
        pf->fpelcmp_x4_min[i] = pf->sad_x4_min[i];
        pf->fpelcmp_sq_min[i] = pf->sad_sq_min[i];
        pf->fpelcmp_dia_min[i] = pf->sad_dia_min[i];
        pf->fpelcmp_hex_min[i] = pf->sad_hex_min[i];
        pf->fpelcmp_oct_min[i] = pf->sad_oct_min[i];
        pf->fpelcmp_ring_min[i] = pf->sad_ring_min[i];
        pf->fpelcmp_hpel_min[i] = pf->sad_hpel_min[i];
        pf->fpelcmp_dia_search[i] = pf->sad_dia_search[i];
        pf->fpelcmp_hex_search[i] = pf->sad_hex_search[i];
    }
    memcpy( pf->fpelcmp_avg2, pf->sad_avg2, sizeof(pf->fpelcmp_avg2) );
    x264_me_fpel_init( pf );
}

static int run( state_t *st, int n, int (*fused)( x264_me_fpel_t * ), int *thr )
{
    h->pixf.me_search_fpel = fused;
    for( int k = 0; k < n; k++ )
    {
        set_mb( &st[k] );
        int t = 1500;
        x264_me_search_ref( h, &mtab[k], st[k].mvc, st[k].i_mvc, thr ? &t : NULL );
    }
    return 0;
}

static int cmp_s64( const void *a, const void *b )
{
    int64_t x = *(const int64_t*)a, y = *(const int64_t*)b;
    return x < y ? -1 : x > y;
}

int fpel_b0_avx2( x264_me_fpel_t *c );

int main( int argc, char **argv )
{
    int rounds = argc > 1 ? atoi( argv[1] ) : 41;
    uint32_t host = x264_cpu_detect();
    uint32_t cpu = host & ~(X264_CPU_AVX512|X264_CPU_AVX512ICL);
    int narm = host & X264_CPU_AVX512 ? NARM : 3;
    h = x264_malloc( sizeof(x264_t) );
    memset( h, 0, sizeof(x264_t) );
    x264_mc_init( cpu, &h->mc, 0 );
    cost_tab = x264_malloc( (2*16384+1)*sizeof(uint16_t) );
    cost_tab += 16384;
    int lambda = 5;
    for( int i = -16384; i <= 16384; i++ )
        cost_tab[i] = X264_MIN( (int)(lambda * (log2f( abs(i)+1 )*2 + 1.718f) + .5f), 65535 );
    for( int s = 0; s < 2; s++ )
        for( int p = 0; p < 4; p++ )
            planes[s][p] = x264_malloc( PST*PROWS*sizeof(pixel) );
    /* smooth texture: blurred noise plus edges */
    for( int k = 0; k < PST*PROWS; k++ )
        planes[0][0][k] = rnd() & PIXEL_MAX;
    for( int pass = 0; pass < 4; pass++ )
        for( int k = 0; k < PST*PROWS - PST - 1; k++ )
            planes[0][0][k] = (planes[0][0][k] + planes[0][0][k+1] + planes[0][0][k+PST] + planes[0][0][k+PST+1] + 2) >> 2;
    for( int y = 0; y < PROWS; y++ )
        for( int x = 0; x < PST; x++ )
        {
            int v = planes[0][0][y*PST+x] + ((x/37 + y/29) & 1 ? 96 : -96) + (int)(120*sinf( x*0.05f + y*0.031f ));
            planes[0][0][y*PST+x] = x264_clip_pixel( v );
        }
    for( int k = 0; k < PST*PROWS; k++ )
        planes[1][0][k] = rnd() & PIXEL_MAX;
    for( int s = 0; s < 2; s++ )
        hpel( planes[s][0], planes[s][1], planes[s][2], planes[s][3] );

    static const int sizes[] = { PIXEL_16x16, PIXEL_8x8, PIXEL_16x8, PIXEL_8x16 };
    static const int submes[] = { 2, 4, 7 };
    static const char *pname[] = { "16x16", "16x8", "8x16", "8x8" };
    static const char *aname[NARM] = { "C", "b0avx2", "avx2", "o512", "i512" };
    static state_t st[NST];
    static x264_me_t mref[NST];
    int smask = argc > 2 ? strtol( argv[2], NULL, 0 ) : 15;
    int (*arm[NARM])( x264_me_fpel_t * ) = { NULL, fpel_b0_avx2, x264_me_search_fpel_avx2,
                                             x264_me_search_fpel_avx512, x264_me_search_fpel_inline_avx512 };
    if( argc > 5 )
    {
        /* profile mode: rounds runs of one arm on one cell (perf stat / record) */
        int a = atoi( argv[3] ), set = atoi( argv[4] ), subme = atoi( argv[5] ), si = 0;
        while( !(smask & (1 << si)) ) si++;
        make_states( st, NST, set, sizes[si] );
        init_pixf( cpu, subme );
        h->param.analyse.i_me_range = 16;
        h->mb.i_me_method = X264_ME_HEX;
        h->mb.i_subpel_refine = subme;
        h->mb.b_chroma_me = 0;
        for( int k = 0; k < NST; k++ )
            setup_m( &st[k], &mtab[k], set );
        for( int r = 0; r < rounds; r++ )
            run( st, NST, arm[a], NULL );
        return 0;
    }
    int fail = 0;
    printf( "cpu 0x%x rounds %d states %d arms %d; rdtsc ticks per call: C median; per arm the paired per-round median - C [q1,q3]; avx2-b0\n",
            cpu, rounds, NST, narm );
    double tot[NARM] = {0}, tc = 0;
    for( int set = 0; set < 2; set++ )
        for( int si = 0; si < 4; si++ )
        {
            if( !(smask & (1 << si)) )
                continue;
            int i_pixel = sizes[si];
            make_states( st, NST, set, i_pixel );
            for( int mi = 0; mi < 3; mi++ )
            {
                int subme = submes[mi];
                init_pixf( cpu, subme );
                h->param.analyse.i_me_range = 16;
                h->mb.i_me_method = X264_ME_HEX;
                h->mb.i_subpel_refine = subme;
                h->mb.b_chroma_me = 0;
                for( int k = 0; k < NST; k++ )
                    setup_m( &st[k], &mtab[k], set );
                /* bit-exact: each fused arm vs the C path */
                for( int thr = 0; thr < 2; thr++ )
                {
                    run( st, NST, NULL, thr ? &thr : NULL );
                    memcpy( mref, mtab, sizeof(mref) );
                    for( int a = 1; a < narm; a++ )
                    {
                        run( st, NST, arm[a], thr ? &thr : NULL );
                        for( int k = 0; k < NST; k++ )
                            if( memcmp( &mref[k], &mtab[k], sizeof(x264_me_t) ) )
                            {
                                if( fail++ < 10 )
                                    printf( "MISMATCH arm %s set %d %s subme %d thr %d state %d: C mv %d,%d cost %d cmv %d | fused mv %d,%d cost %d cmv %d\n",
                                            aname[a], set, pname[si], subme, thr, k, mref[k].mv[0], mref[k].mv[1], mref[k].cost, mref[k].cost_mv,
                                            mtab[k].mv[0], mtab[k].mv[1], mtab[k].cost, mtab[k].cost_mv );
                                break;
                            }
                    }
                }
                /* timing: each round runs the arms in a rotated order */
                static int64_t t[NARM][512], d[NARM][512];
                int nr = rounds < 512 ? rounds : 512;
                for( int r = 0; r < nr; r++ )
                    for( int j = 0; j < narm; j++ )
                    {
                        int a = (r + j) % narm;
                        int64_t best = INT64_MAX;
                        for( int rep = 0; rep < 3; rep++ )
                        {
                            uint64_t t0 = __rdtsc();
                            run( st, NST, arm[a], NULL );
                            int64_t dt = __rdtsc() - t0;
                            if( dt < best ) best = dt;
                        }
                        t[a][r] = best;
                    }
                for( int r = 0; r < nr; r++ )
                {
                    for( int a = 1; a < narm; a++ )
                        d[a][r] = t[a][r] - t[0][r];
                    d[0][r] = t[2][r] - t[1][r];
                }
                for( int a = 0; a < narm; a++ )
                    qsort( d[a], nr, 8, cmp_s64 );
                qsort( t[0], nr, 8, cmp_s64 );
                double c = (double)t[0][nr/2]/NST;
#define Q(k,i) ((double)d[k][(i)*(nr-1)/4]/NST)
                printf( "%-6s %-5s subme %d: C %6.1f", set ? "random" : "smooth", pname[si], subme, c );
                for( int a = 1; a < narm; a++ )
                {
                    printf( " | %s %+6.1f [%+5.1f,%+5.1f]", aname[a], Q(a,2), Q(a,1), Q(a,3) );
                    tot[a] += Q(a,2);
                }
                printf( " | avx2-b0 %+6.1f\n", Q(0,2) );
                tc += c;
                fflush( stdout );
            }
        }
    printf( "sum: C %.1f", tc );
    for( int a = 1; a < narm; a++ )
        printf( " %s-C %+.1f", aname[a], tot[a] );
    printf( "\n" );
    printf( fail ? "FAILED %d\n" : "bit-exact OK\n", fail );
    return !!fail;
}
