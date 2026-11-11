/*****************************************************************************
 * bwledger_wrap.h: ledger build only, included by encoder.c
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

/* Line touches for every read of a registered plane through the pixel/mc
 * primitives. The asm-only composites (NULL in the C init: fused fpel search,
 * point sets, subpel/qpel search, satd_bi, lowres/analyse kernels...) read refs
 * internally, so they are dropped and the encoder takes its C paths, which call
 * the primitives; checkasm holds those composites bit-exact to the C paths, and
 * the jobs compare recon md5 against the base build. One thunk per original
 * function, so pointer comparisons between slots (analyse.c, me.c, slicetype.c)
 * see the same relations as without the ledger. */

#define BWL_REP64(M) \
    M(0)  M(1)  M(2)  M(3)  M(4)  M(5)  M(6)  M(7)  M(8)  M(9)  M(10) M(11) M(12) M(13) M(14) M(15) \
    M(16) M(17) M(18) M(19) M(20) M(21) M(22) M(23) M(24) M(25) M(26) M(27) M(28) M(29) M(30) M(31) \
    M(32) M(33) M(34) M(35) M(36) M(37) M(38) M(39) M(40) M(41) M(42) M(43) M(44) M(45) M(46) M(47) \
    M(48) M(49) M(50) M(51) M(52) M(53) M(54) M(55) M(56) M(57) M(58) M(59) M(60) M(61) M(62) M(63)
#define BWL_REP16(M) \
    M(0)  M(1)  M(2)  M(3)  M(4)  M(5)  M(6)  M(7)  M(8)  M(9)  M(10) M(11) M(12) M(13) M(14) M(15)

#define BWL_PX ((intptr_t)sizeof(pixel))

static x264_pixel_cmp_t bwl_cmp_orig[64];
static uint8_t bwl_cmp_wh[64][2];
static x264_pixel_cmp_x3_t bwl_x3_orig[16];
static uint8_t bwl_x3_wh[16][2];
static x264_pixel_cmp_x4_t bwl_x4_orig[16];
static uint8_t bwl_x4_wh[16][2];

static void bwl_blk( pixel *p, intptr_t stride, const uint8_t wh[2] )
{
    BWL_TOUCH( p, stride * BWL_PX, wh[0] * BWL_PX, wh[1] );
}

#define BWL_CMP_FN( k ) \
static int bwl_cmp_##k( pixel *a, intptr_t sa, pixel *b, intptr_t sb ) \
{ \
    bwl_blk( a, sa, bwl_cmp_wh[k] ); \
    bwl_blk( b, sb, bwl_cmp_wh[k] ); \
    return bwl_cmp_orig[k]( a, sa, b, sb ); \
}
#define BWL_X3_FN( k ) \
static void bwl_x3_##k( pixel *f, pixel *p0, pixel *p1, pixel *p2, intptr_t s, int res[3] ) \
{ \
    bwl_blk( p0, s, bwl_x3_wh[k] ); \
    bwl_blk( p1, s, bwl_x3_wh[k] ); \
    bwl_blk( p2, s, bwl_x3_wh[k] ); \
    bwl_x3_orig[k]( f, p0, p1, p2, s, res ); \
}
#define BWL_X4_FN( k ) \
static void bwl_x4_##k( pixel *f, pixel *p0, pixel *p1, pixel *p2, pixel *p3, intptr_t s, int res[4] ) \
{ \
    bwl_blk( p0, s, bwl_x4_wh[k] ); \
    bwl_blk( p1, s, bwl_x4_wh[k] ); \
    bwl_blk( p2, s, bwl_x4_wh[k] ); \
    bwl_blk( p3, s, bwl_x4_wh[k] ); \
    bwl_x4_orig[k]( f, p0, p1, p2, p3, s, res ); \
}
BWL_REP64( BWL_CMP_FN )
BWL_REP16( BWL_X3_FN )
BWL_REP16( BWL_X4_FN )
#define BWL_CMP_PTR( k ) bwl_cmp_##k,
#define BWL_X3_PTR( k ) bwl_x3_##k,
#define BWL_X4_PTR( k ) bwl_x4_##k,
static const x264_pixel_cmp_t bwl_cmp_thunk[64] = { BWL_REP64( BWL_CMP_PTR ) };
static const x264_pixel_cmp_x3_t bwl_x3_thunk[16] = { BWL_REP16( BWL_X3_PTR ) };
static const x264_pixel_cmp_x4_t bwl_x4_thunk[16] = { BWL_REP16( BWL_X4_PTR ) };

/* slot arrays indexed by PIXEL_*; the same original always gets the same thunk */
#define BWL_WRAP_ARRAY( NAME, arr, n, orig, wh, thunk, cnt, max ) \
for( int i = 0; i < (n); i++ ) \
{ \
    int k; \
    if( !(arr)[i] ) \
        continue; \
    for( k = 0; k < (max) && (arr)[i] != thunk[k]; k++ ); \
    if( k < (max) ) \
        continue; \
    for( k = 0; k < cnt && orig[k] != (arr)[i]; k++ ); \
    if( k == cnt ) \
    { \
        if( cnt == (max) ) \
        { \
            fprintf( stderr, "BWL: out of " NAME " thunks\n" ); \
            abort(); \
        } \
        orig[k] = (arr)[i]; \
        wh[k][0] = x264_pixel_size[i].w; \
        wh[k][1] = x264_pixel_size[i].h; \
        cnt++; \
    } \
    (arr)[i] = thunk[k]; \
}

static void (*bwl_mc_luma_orig)( pixel *, intptr_t, pixel **, intptr_t, int, int, int, int, const x264_weight_t * );
static pixel *(*bwl_get_ref_orig)( pixel *, intptr_t *, pixel **, intptr_t, int, int, int, int, const x264_weight_t * );
static void (*bwl_mc_chroma_orig)( pixel *, pixel *, intptr_t, pixel *, intptr_t, int, int, int, int );

/* the planes get_ref / mc_luma read at a qpel mv */
static void bwl_qpel( pixel **src, intptr_t i_src, int mvx, int mvy, int w, int h )
{
    pixel *s[2];
    x264_mc_hpel_pair( s, src, i_src, mvx, mvy );
    BWL_TOUCH( s[0], i_src * BWL_PX, w * BWL_PX, h );
    if( s[1] != s[0] )
        BWL_TOUCH( s[1], i_src * BWL_PX, w * BWL_PX, h );
}

static void bwl_mc_luma( pixel *dst, intptr_t i_dst, pixel **src, intptr_t i_src,
                         int mvx, int mvy, int w, int h, const x264_weight_t *wt )
{
    bwl_qpel( src, i_src, mvx, mvy, w, h );
    bwl_mc_luma_orig( dst, i_dst, src, i_src, mvx, mvy, w, h, wt );
}

static pixel *bwl_get_ref( pixel *dst, intptr_t *i_dst, pixel **src, intptr_t i_src,
                           int mvx, int mvy, int w, int h, const x264_weight_t *wt )
{
    bwl_qpel( src, i_src, mvx, mvy, w, h );
    return bwl_get_ref_orig( dst, i_dst, src, i_src, mvx, mvy, w, h, wt );
}

/* NV12/NV16 bilinear: 2*(w+1) bytes x (h+1) rows of the interleaved plane */
static void bwl_mc_chroma( pixel *dstu, pixel *dstv, intptr_t i_dst, pixel *src, intptr_t i_src,
                           int mvx, int mvy, int w, int h )
{
    BWL_TOUCH( src + (mvy >> 3) * i_src + (mvx >> 3) * 2, i_src * BWL_PX, (2*w + 2) * BWL_PX, h + 1 );
    bwl_mc_chroma_orig( dstu, dstv, i_dst, src, i_src, mvx, mvy, w, h );
}

/* the slot loop below treats the struct as pointers */
typedef char bwl_pixf_all_pointers[sizeof(x264_pixel_function_t) % sizeof(void*) ? -1 : 1];

static void bwl_wrap( x264_t *h )
{
    static int busy;
    static int ncmp, nx3, nx4;
    if( busy )
        return;
    busy = 1;

    /* the C init plus the derived slots, on a copy */
    x264_t *t = x264_malloc( sizeof(x264_t) );
    if( !t )
        abort();
    memcpy( t, h, sizeof(x264_t) );
    x264_pixel_init( 0, &t->pixf );
    mbcmp_init( t );
    chroma_dsp_init( t );
    int nulled = 0;
    for( size_t i = 0; i < sizeof(x264_pixel_function_t); i += sizeof(void*) )
    {
        void *c, *a;
        memcpy( &c, (char*)&t->pixf + i, sizeof(void*) );
        memcpy( &a, (char*)&h->pixf + i, sizeof(void*) );
        if( !c && a )
        {
            memset( (char*)&h->pixf + i, 0, sizeof(void*) );
            nulled++;
        }
    }
    x264_free( t );

    BWL_WRAP_ARRAY( "cmp", h->pixf.sad, 8, bwl_cmp_orig, bwl_cmp_wh, bwl_cmp_thunk, ncmp, 64 )
    BWL_WRAP_ARRAY( "cmp", h->pixf.sad_aligned, 8, bwl_cmp_orig, bwl_cmp_wh, bwl_cmp_thunk, ncmp, 64 )
    BWL_WRAP_ARRAY( "cmp", h->pixf.ssd, 8, bwl_cmp_orig, bwl_cmp_wh, bwl_cmp_thunk, ncmp, 64 )
    BWL_WRAP_ARRAY( "cmp", h->pixf.satd, 8, bwl_cmp_orig, bwl_cmp_wh, bwl_cmp_thunk, ncmp, 64 )
    BWL_WRAP_ARRAY( "cmp", h->pixf.sa8d, 4, bwl_cmp_orig, bwl_cmp_wh, bwl_cmp_thunk, ncmp, 64 )
    BWL_WRAP_ARRAY( "cmp", h->pixf.mbcmp, 8, bwl_cmp_orig, bwl_cmp_wh, bwl_cmp_thunk, ncmp, 64 )
    BWL_WRAP_ARRAY( "cmp", h->pixf.mbcmp_unaligned, 8, bwl_cmp_orig, bwl_cmp_wh, bwl_cmp_thunk, ncmp, 64 )
    BWL_WRAP_ARRAY( "cmp", h->pixf.fpelcmp, 8, bwl_cmp_orig, bwl_cmp_wh, bwl_cmp_thunk, ncmp, 64 )
    BWL_WRAP_ARRAY( "x3", h->pixf.sad_x3, 7, bwl_x3_orig, bwl_x3_wh, bwl_x3_thunk, nx3, 16 )
    BWL_WRAP_ARRAY( "x3", h->pixf.satd_x3, 7, bwl_x3_orig, bwl_x3_wh, bwl_x3_thunk, nx3, 16 )
    BWL_WRAP_ARRAY( "x3", h->pixf.fpelcmp_x3, 7, bwl_x3_orig, bwl_x3_wh, bwl_x3_thunk, nx3, 16 )
    BWL_WRAP_ARRAY( "x4", h->pixf.sad_x4, 7, bwl_x4_orig, bwl_x4_wh, bwl_x4_thunk, nx4, 16 )
    BWL_WRAP_ARRAY( "x4", h->pixf.satd_x4, 7, bwl_x4_orig, bwl_x4_wh, bwl_x4_thunk, nx4, 16 )
    BWL_WRAP_ARRAY( "x4", h->pixf.fpelcmp_x4, 7, bwl_x4_orig, bwl_x4_wh, bwl_x4_thunk, nx4, 16 )
    if( h->mc.mc_luma != bwl_mc_luma )
    {
        bwl_mc_luma_orig = h->mc.mc_luma;
        h->mc.mc_luma = bwl_mc_luma;
    }
    if( h->mc.get_ref != bwl_get_ref )
    {
        bwl_get_ref_orig = h->mc.get_ref;
        h->mc.get_ref = bwl_get_ref;
    }
    if( h->mc.mc_chroma != bwl_mc_chroma )
    {
        bwl_mc_chroma_orig = h->mc.mc_chroma;
        h->mc.mc_chroma = bwl_mc_chroma;
    }
    x264_me_fpel_init( &h->pixf );
    fprintf( stderr, "BWLINFO composite slots dropped %d; thunks cmp %d x3 %d x4 %d\n", nulled, ncmp, nx3, nx4 );
    busy = 0;
}
