/* Copyright (C) 2026 Open Broadcast Systems Ltd
 * old vs new 8-bit hpel_filter(_copy)_avx2 over full planes, against the C formula.
 * Guard pages (PROT_NONE) tight at the first or the last byte read and written. */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

void old8_hpel_filter_avx2(void), new8_hpel_filter_avx2(void), old8_hpel_filter_copy_avx2(void), new8_hpel_filter_copy_avx2(void);
void tramp( void *fn, uint64_t *args, uint64_t *out );
void bad_upper(void), bad_rbx(void), good_fn(void);

static uint32_t rs = 1;
static uint32_t rnd( void ) { rs ^= rs << 13; rs ^= rs >> 17; rs ^= rs << 5; return rs; }
static int clip( int v ) { return v < 0 ? 0 : v > 255 ? 255 : v; }
#define TAP(p,x,d) ((p)[(x)-2*(d)] + (p)[(x)+3*(d)] - 5*((p)[(x)-(d)] + (p)[(x)+2*(d)]) + 20*((p)[(x)] + (p)[(x)+(d)]))

static long pg;
/* a region of n bytes whose start (front=1) or end (front=0) touches a PROT_NONE page */
static uint8_t *galloc( size_t n, int front, void **base, size_t *blen )
{
    size_t data = (n + pg - 1) / pg * pg;
    *blen = data + 2*pg;
    uint8_t *b = mmap( NULL, *blen, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0 );
    if( b == MAP_FAILED ) { perror( "mmap" ); exit( 1 ); }
    mprotect( b, pg, PROT_NONE );
    mprotect( b + pg + data, pg, PROT_NONE );
    *base = b;
    return front ? b + pg : b + pg + data - n;
}

static long nruns, nfail, ngarb_old, nxin, ncs, ntiny;
static int xin_ref = -1;
static int only = -1; /* -1 both kernels, 0 old only checked, 1 new only checked */

static void call( void *fn, uint8_t *h, uint8_t *v, uint8_t *c, uint8_t *s, intptr_t st, int w, int ht, int16_t *buf, uint8_t *cp )
{
    uint64_t a[9] = { (uintptr_t)h, (uintptr_t)v, (uintptr_t)c, (uintptr_t)s, st, (uint64_t)(int64_t)w, (uint64_t)ht, (uintptr_t)buf, (uintptr_t)cp };
    uint64_t out[2];
    tramp( fn, a, out );
    if( (out[0] & 0x44) != (uint64_t)(xin_ref & 0x44) ) { nxin++; if( nxin < 5 ) printf( "XINUSE %llx (ref %x)\n", (unsigned long long)out[0], xin_ref ); }
    if( out[1] ) { ncs++; if( ncs < 5 ) printf( "callee-saved changed mask %llx\n", (unsigned long long)out[1] ); }
}

/* one plane: misalign m, width w, height ht, stride st, guard mode gm (0 = front, 1 = back), pattern pat */
static void run( int copy, int m, int w, int ht, intptr_t st, int gm, int pat )
{
    /* the kernel's block schedule: nbv v blocks, nbc c/h blocks, lastx = last c/h step has no right neighbour */
    int r4 = -(m + w - 32), nbc = 0, nbv = 1, lastx = 0;
    for( ;; ) { nbv++; nbc++; r4 += 32; if( r4 < 0 ) continue; if( r4 < 32 ) { nbc++; lastx = 1; } break; }
    /* rows after the first of a plane with no lastx step: the old kernel advances its source pointers per v
     * block but rewinds them per c/h step, so it reads the wrong columns there. Unreachable from x264
     * (width+misalign > 32). Only row 0 is compared for the old kernel then. */
    int tiny = !lastx;
    ntiny += tiny;
    int ext = 32*nbv;                 /* written columns per row, from -m */
    size_t in_n = (size_t)(ht+4)*st + ext + (tiny ? 32*(ht+4) : 0);
    void *ib; size_t il;
    uint8_t *in = galloc( in_n, !gm, &ib, &il );
    for( size_t i = 0; i < in_n; i++ ) {
        int r = rnd();
        switch( pat ) {
        case 0: in[i] = r; break;
        case 1: in[i] = (r & 1) ? 255 : 0; break;
        case 2: in[i] = ((i / st) % 3 == 1) ^ ((i % st) % 6 == 1 || (i % st) % 6 == 4) ? 255 : 0; break;
        case 3: in[i] = ((i % st) & 1) ^ ((i / st) & 1) ? 255 : 0; break;
        case 4: in[i] = (r & 3) == 0 ? 255 : (r & 3) == 1 ? 0 : r >> 8; break;
        default: in[i] = (r & 7) ? 255 : r; break;
        }
    }
    uint8_t *src = in + 2*st + m;     /* (row -2, col -m) is in[0] */
    size_t out_n = (size_t)(ht-1)*st + ext + (tiny ? 32*ht : 0);
    void *ob[2][4]; size_t ol[2][4];
    uint8_t *o[2][4], *dst[2][4];
    for( int k = 0; k < 2; k++ ) for( int p = 0; p < 4; p++ ) {
        o[k][p] = galloc( out_n, !gm, &ob[k][p], &ol[k][p] );
        dst[k][p] = o[k][p] + m;
    }
    static int16_t buf[1<<16];
    uint8_t *res[2][2][4]; /* kernel, sentinel pass, plane */
    for( int k = 0; k < 2; k++ ) for( int sp = 0; sp < 2; sp++ ) {
        for( int p = 0; p < 4; p++ ) memset( o[k][p], sp ? 0x5a : 0xa5, out_n );
        void *fn = copy ? (k ? (void*)new8_hpel_filter_copy_avx2 : (void*)old8_hpel_filter_copy_avx2)
                        : (k ? (void*)new8_hpel_filter_avx2 : (void*)old8_hpel_filter_avx2);
        call( fn, dst[k][0], dst[k][1], dst[k][2], src, st, w, ht, buf, copy ? dst[k][3] : NULL );
        for( int p = 0; p < 4; p++ ) { res[k][sp][p] = malloc( out_n ); memcpy( res[k][sp][p], o[k][p], out_n ); }
    }
    nruns++;
    int bad = 0;
    char why[256] = "";
    /* written bytes: identical for old and new, and as the schedule says */
    for( int p = 0; p < 4 && !bad; p++ )
        for( size_t i = 0; i < out_n; i++ ) {
            int wo = res[0][0][p][i] != 0xa5 || res[0][1][p][i] != 0x5a;
            int wn = res[1][0][p][i] != 0xa5 || res[1][1][p][i] != 0x5a;
            int row = i / st, col = (int)(i % st) - m;
            int expect = row < ht && col < ext - m && (p == 3 ? copy : 1);
            if( (p == 0 || p == 2) && col >= 32*nbc - m ) expect = 0;
            int ko = only != 1 && !(tiny && row > 0), kn = only != 0;
            if( (kn && wn != expect) || (ko && wo != expect) ) {
                bad = 1; snprintf( why, sizeof(why), "mask plane %d row %d col %d old %d new %d expect %d", p, row, col, wo, wn, expect ); break;
            }
        }
    /* values */
    for( int y = 0; y < ht && !bad; y++ ) {
        uint8_t *s = src + y*st;
        int ko = only != 1 && !(tiny && y > 0), kn = only != 0;
        for( int x = -m; x < ext - m && !bad; x++ ) {
            size_t i = (size_t)y*st + x + m;
            int vv = clip( (TAP( s, x, st ) + 16) >> 5 );
            int blk = (x + m) >> 5, bo = (x + m) & 31;
            int inch = x < 32*nbc - m;
            int garb = (blk == 0 && bo < 2) || (lastx && blk == nbc-1 && bo >= 29);
            for( int k = 0; k < 2 && !bad; k++ ) {
                if( !(k ? kn : ko) ) continue;
                if( res[k][0][1][i] != vv || res[k][1][1][i] != vv ) { bad = 1; snprintf( why, sizeof(why), "v k%d y%d x%d got %d want %d", k, y, x, res[k][0][1][i], vv ); }
                if( copy && (res[k][0][3][i] != s[x] || res[k][1][3][i] != s[x]) ) { bad = 1; snprintf( why, sizeof(why), "copy k%d y%d x%d", k, y, x ); }
            }
            if( !inch || bad ) continue;
            int hv = clip( (TAP( s, x, 1 ) + 16) >> 5 );
            int cv = -1;
            if( !garb ) {
                int t[6];
                for( int d = -2; d <= 3; d++ ) t[d+2] = TAP( s, x+d, st );
                cv = clip( (t[0] + t[5] - 5*(t[1] + t[4]) + 20*(t[2] + t[3]) + 512) >> 10 );
            }
            for( int sp = 0; sp < 2 && !bad; sp++ ) {
                if( kn && res[1][sp][0][i] != hv ) { bad = 1; snprintf( why, sizeof(why), "h new y%d x%d got %d want %d", y, x, res[1][sp][0][i], hv ); }
                if( ko && !garb && res[0][sp][0][i] != hv ) { bad = 1; snprintf( why, sizeof(why), "h old y%d x%d got %d want %d", y, x, res[0][sp][0][i], hv ); }
                if( ko && garb && res[0][sp][0][i] != hv ) ngarb_old++;
                if( !garb ) for( int k = 0; k < 2 && !bad; k++ )
                    if( (k ? kn : ko) && res[k][sp][2][i] != cv ) { bad = 1; snprintf( why, sizeof(why), "c k%d y%d x%d got %d want %d", k, y, x, res[k][sp][2][i], cv ); }
            }
        }
    }
    if( bad ) { nfail++; if( nfail < 20 ) printf( "FAIL copy %d m %d w %d h %d st %ld gm %d pat %d: %s\n", copy, m, w, ht, (long)st, gm, pat, why ); }
    for( int k = 0; k < 2; k++ ) for( int sp = 0; sp < 2; sp++ ) for( int p = 0; p < 4; p++ ) free( res[k][sp][p] );
    for( int k = 0; k < 2; k++ ) for( int p = 0; p < 4; p++ ) munmap( ob[k][p], ol[k][p] );
    munmap( ib, il );
}

/* bench W H rounds reps [copy]: whole luma frames filtered per 16-row strip as x264_frame_filter does
 * (dst = plane - 8, width W+16, misalign 24), old and new alternating, ns per frame */
#include <time.h>
typedef void (*hfn)( uint8_t*, uint8_t*, uint8_t*, uint8_t*, intptr_t, int, int, int16_t*, uint8_t* );
static double now( void ) { struct timespec t; clock_gettime( CLOCK_MONOTONIC, &t ); return t.tv_sec*1e9 + t.tv_nsec; }
static int dcmp( const void *a, const void *b ) { double x = *(double*)a, y = *(double*)b; return x < y ? -1 : x > y; }
static int bench( int W, int H, int rounds, int reps, int copy )
{
    intptr_t st = (W + 64 + 63) & ~63;
    int lines = (H + 15) & ~15;
    size_t n = (size_t)(lines + 64) * st + 64;
    uint8_t *pl[5];
    for( int p = 0; p < 5; p++ ) {
        pl[p] = aligned_alloc( 64, n );
        for( size_t i = 0; i < n; i++ ) pl[p][i] = p ? 0 : rnd();
    }
    static int16_t buf[1<<16];
    hfn f[2] = { (hfn)(copy ? (void*)old8_hpel_filter_copy_avx2 : (void*)old8_hpel_filter_avx2),
                 (hfn)(copy ? (void*)new8_hpel_filter_copy_avx2 : (void*)new8_hpel_filter_avx2) };
    intptr_t org = 32*st + 32;        /* plane origin: 32 rows and 32 columns of padding, 64-aligned base */
    double t[2][256], r[256];
    for( int rd = -1; rd < rounds; rd++ )
        for( int kk = 0; kk < 2; kk++ ) {
            int k = (rd & 1) ? !kk : kk;
            double t0 = now();
            for( int rep = 0; rep < reps; rep++ )
                for( int mby = 0; mby < lines/16; mby++ ) {
                    int start = mby*16 - 8, end = mby*16 + 8 + (mby == lines/16 - 1 ? 16 : 0);
                    intptr_t o = org + start*st - 8;
                    f[k]( pl[1]+o, pl[2]+o, pl[3]+o, pl[0]+o, st, W+16, end - start, buf, pl[4]+o );
                }
            if( rd >= 0 ) t[k][rd] = (now() - t0) / reps;
        }
    for( int rd = 0; rd < rounds; rd++ ) r[rd] = t[1][rd] / t[0][rd];
    for( int rd = 0; rd < rounds; rd++ ) printf( "round %2d old %9.0f new %9.0f ns/frame new/old %.4f\n", rd, t[0][rd], t[1][rd], r[rd] );
    qsort( t[0], rounds, sizeof(double), dcmp ); qsort( t[1], rounds, sizeof(double), dcmp ); qsort( r, rounds, sizeof(double), dcmp );
    printf( "%s %dx%d median old %.0f new %.0f ns/frame, median new/old %.4f (min %.4f max %.4f)\n",
            copy ? "hpel_filter_copy" : "hpel_filter", W, H, t[0][rounds/2], t[1][rounds/2], r[rounds/2], r[0], r[rounds-1] );
    return 0;
}

int main( int argc, char **argv )
{
    setvbuf( stdout, NULL, _IONBF, 0 );
    if( argc > 1 && !strcmp( argv[1], "bench" ) )
        return bench( argc > 2 ? atoi( argv[2] ) : 1920, argc > 3 ? atoi( argv[3] ) : 1080,
                      argc > 4 ? atoi( argv[4] ) : 11, argc > 5 ? atoi( argv[5] ) : 20, argc > 6 ? atoi( argv[6] ) : 0 );
    pg = sysconf( _SC_PAGESIZE );
    int full = argc > 1 ? atoi( argv[1] ) : 1;
    rs = argc > 2 ? atoi( argv[2] ) : 1;
    only = argc > 3 ? atoi( argv[3] ) : -1;
    /* the instruments must see a fault before they testify */
    uint64_t a[9] = {0}, out[2];
    tramp( (void*)good_fn, a, out ); xin_ref = out[0];
    printf( "XINUSE after vzeroupper %x, callee-saved mask %llx\n", xin_ref, (unsigned long long)out[1] );
    tramp( (void*)bad_upper, a, out ); printf( "XINUSE with dirty ymm upper %llx\n", (unsigned long long)out[0] );
    if( !(out[0] & 4) || (xin_ref & 0x44) ) { printf( "XINUSE instrument useless\n" ); return 2; }
    tramp( (void*)bad_rbx, a, out ); printf( "rbx clobber mask %llx\n", (unsigned long long)out[1] );
    if( out[1] != 1 ) { printf( "callee-saved instrument useless\n" ); return 2; }
    for( int copy = 0; copy < 2; copy++ )
    for( int m = 0; m < 32; m++ )
    for( int w = 32; w <= (full ? 300 : 100); w++ ) { /* the kernels take width >= 32 (sub r5d, mmsize) */
        int ht = 1 + rnd() % 4;
        int sts[3] = { (m + w + 63) & ~31, ((m + w + 63) & ~31) + 32*(1 + rnd() % 4), 2048 };
        for( int si = 0; si < 3; si++ )
            run( copy, m, w, ht, sts[si], (w + si) & 1, (w*3 + si + m) % 6 );
    }
    /* frame-like widths; misalign 24 as frame_filter */
    int fw[] = { 16+16, 32+16, 64+16, 720+16, 960+16, 1280+16, 1920+16, 3840+16, 1921, 1939 };
    for( int copy = 0; copy < 2; copy++ )
    for( int i = 0; i < 10; i++ ) for( int pat = 0; pat < 6; pat++ ) for( int gm = 0; gm < 2; gm++ ) {
        int m = (pat & 1) ? 24 : rnd() % 32;
        run( copy, m, fw[i], 1 + (pat + gm) * 2, (fw[i] + 64 + 63) & ~63, gm, pat );
    }
    printf( "runs %ld fail %ld xinuse %ld callee-saved %ld (tiny planes %ld, old garbage h bytes %ld)\n", nruns, nfail, nxin, ncs, ntiny, ngarb_old );
    return nfail || nxin || ncs;
}
