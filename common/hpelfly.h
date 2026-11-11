/*****************************************************************************
 * hpelfly.h: subpel interpolation on the fly, without stored hpel planes
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

#ifndef X264_HPELFLY_H
#define X264_HPELFLY_H

#ifndef HPEL_FLY
#define HPEL_FLY 0          /* x264_encoder_open's default: 1 drops the stored hpel planes */
#endif
#ifndef HPELFLY_SWAP
#define HPELFLY_SWAP 1      /* the fused me_search_fpel on band planes when they cover its reads; 0: C search */
#endif
#ifndef HPELFLY_STATS
#define HPELFLY_STATS 0     /* window and hpel traffic counters, logged at close */
#endif

/* With h->fly, reference frames keep only the fullpel plane F. The H, V and C
 * samples (hpel_filter's) are interpolated from F when a consumer needs them:
 * for references 0 and 1 of each list into a band of whole rows around the mb
 * row (x264_fly_band_t), else and for reads outside the band into small
 * windows: per reference (list, index, frame or field by absolute parity), two
 * 64x64 windows, each F, H, V, C at stride FLY_WS, with per 16-column group a
 * bitmap of the rows computed. Every legal read (mvs clipped to mv_min/mv_max)
 * has its 6-tap inside F's padding, where the stored planes equal the 6-tap of
 * F, so a band or window sample equals the stored plane's.
 *
 * h->mb.pic.p_fref[l][j][1..3] are not pointers then: p_fref[1] - p_fref[0]
 * is FLY_TAG << 40 | slot << 20, preserved by every LOAD_HPELS. A consumer
 * that reads H, V or C asks x264_fly_planes for window planes first. */

#define FLY_W   64              /* window columns */
#define FLY_H   64              /* window rows */
#define FLY_WS  64              /* window stride, pixels */
#define FLY_NG  (FLY_W/16)      /* 16-column groups */
#define FLY_PLANE ((FLY_H+2)*FLY_WS) /* a row of slack above and below */
#define FLY_TAG 0x40
#define FLY_HMAX 4              /* refine_subpel hpel iterations */
#define FLY_QMAX 10             /* and qpel iterations, the box table's range */

typedef struct
{
    int x0, y0;                 /* origin, px of the reference plane; x0 == INT_MIN: empty */
    uint64_t valid[4][FLY_NG];  /* plane, group: bit r = row r computed */
    pixel *plane[4];            /* F, H, V, C at the origin */
} x264_fly_win_t;

/* A band: H, V, C of whole rows (columns -PADH..width+PADH) of one reference around
 * the mb row, at F's stride, so the planes a consumer gets are F itself and the band
 * at the same offsets. Rows are computed when a read first needs them, once per
 * slice, and the band is moved down (memmove of its computed rows) as the mb rows
 * advance, so the same lines are reused and stay in L2. Reads outside it take a
 * window. */
#define FLY_BR  112             /* band rows: an mb pair row +- 40 */
typedef struct
{
    pixel *plane[4];            /* -, H, V, C at band row 0, column 0 */
    intptr_t stride;
    int org;                    /* reference row of band row 0 */
    int gen;
    uint64_t valid[2];          /* band rows 0..63, 64..FLY_BR-1 computed */
} x264_fly_band_t;

typedef struct
{
    x264_fly_win_t win[2];
    int last;                   /* the most recently used window */
    int gen;
    x264_fly_band_t *band;      /* NULL: windows only */
} x264_fly_slot_t;

/* per-plane rects relative to the block's top-left px: cols [x0,x1), rows [y0,y1) */
typedef struct
{
    int mask;                   /* bit k: plane k read */
    int16_t x0[4], x1[4], y0[4], y1[4];
} x264_fly_box_t;

typedef struct
{
    int8_t mask, x0[4], x1[4], y0[4], y1[4];
    int8_t ry0, ry1;            /* rows of H, V, C together (the band's) */
} x264_fly_ofs_t;

struct x264_fly
{
    int gen;
    int nslot;
    int nref[2];                /* frame slots per list; field slots 2*nref */
    x264_fly_slot_t *slot;
    pixel *buf;
    x264_fly_band_t *bands;
    pixel *band_buf[12];
    int nband;
    int width;                  /* the reference planes' */
#if HPELFLY_STATS
    /* fly: requests, window placements, samples computed and kernel calls per plane */
    int64_t st_req, st_place, st_px[4], st_calls[4];
    int64_t st_band_req, st_band_rows, st_band_moved;
    int64_t st_swap_hit, st_swap_miss;     /* me_search_fpel on band planes, or the C search */
    /* stored planes: bytes the hpel pass and its borders write; distinct 64-byte lines
     * of H, V and C that a slice's consumers read (the ledger, cleared every slice) */
    int64_t st_wr_bytes, st_rd_lines, st_slices;
    struct
    {
        x264_frame_t *frame;
        uint64_t *bits[2];      /* lines of buffer[0], buffer_fld[0] */
    } led[2*X264_REF_MAX];
    int nled;
    size_t led_words;
    uint64_t *led_buf;
#endif
};

/* slot of (list, reference index j of the mb's lists, abs_parity for field refs) */
static ALWAYS_INLINE int x264_fly_slot_idx( x264_fly_t *fly, int list, int j, int field )
{
    int base = field ? fly->nref[0] + fly->nref[1] : 0;
    return base + list * (fly->nref[0] << field) + j;
}

static ALWAYS_INLINE uintptr_t x264_fly_magic( int slot )
{
    return (uintptr_t)FLY_TAG << 40 | (uintptr_t)slot << 20;
}

/* slot of a 4-plane array, -1 for stored planes */
static ALWAYS_INLINE int x264_fly_ref( pixel **src )
{
    uintptr_t d = (uintptr_t)src[1] - (uintptr_t)src[0];
    return (d >> 40) == FLY_TAG ? (int)((d >> 20) & 0xfffff) : -1;
}

#define x264_fly_box_search_tab x264_template(fly_box_search_tab)
extern x264_fly_ofs_t x264_fly_box_search_tab[FLY_HMAX+1][FLY_QMAX+1][16];
#define x264_fly_tables_init x264_template(fly_tables_init)
void x264_fly_tables_init( void );

/* reads of a bw x bh block at the qpel mv */
static ALWAYS_INLINE void x264_fly_box_mv( x264_fly_box_t *b, int mvx, int mvy, int bw, int bh )
{
    int qpel_idx = ((mvy&3)<<2) + (mvx&3);
    int x = mvx>>2, y = mvy>>2;
    int p0 = x264_hpel_ref0[qpel_idx];
    b->mask = 1 << p0;
    b->x0[p0] = x;
    b->x1[p0] = x + bw;
    b->y0[p0] = y + ((mvy&3) == 3);
    b->y1[p0] = b->y0[p0] + bh;
    if( qpel_idx & 5 )
    {
        int p1 = x264_hpel_ref1[qpel_idx];
        b->mask |= 1 << p1;
        b->x0[p1] = x + ((mvx&3) == 3);
        b->x1[p1] = b->x0[p1] + bw;
        b->y0[p1] = y;
        b->y1[p1] = y + bh;
    }
}

/* reads of refine_subpel's search from (mvx,mvy): up to hpel_iters hpel diamond
 * steps, then up to qpel_iters qpel steps */
static ALWAYS_INLINE void x264_fly_box_search( x264_fly_box_t *b, int mvx, int mvy, int hpel_iters, int qpel_iters, int bw, int bh )
{
    const x264_fly_ofs_t *o = &x264_fly_box_search_tab[hpel_iters][qpel_iters][((mvy&3)<<2) + (mvx&3)];
    int x = mvx>>2, y = mvy>>2;
    b->mask = o->mask;
    for( int k = 0; k < 4; k++ )
    {
        b->x0[k] = x + o->x0[k];
        b->x1[k] = x + o->x1[k] + bw;
        b->y0[k] = y + o->y0[k];
        b->y1[k] = y + o->y1[k] + bh;
    }
}

/* fref: the 4 planes of a fly reference at the block (fref[0] is F there, the
 * block (bx,by) px from the mb's top-left in the mb's rows); sets dst[0..3] to
 * window planes at the block for the reads of b. Returns the window stride.
 * The planes stay valid until the next x264_fly_planes on the same reference. */
#define x264_fly_planes x264_template(fly_planes)
intptr_t x264_fly_planes( x264_t *h, pixel **fref, intptr_t stride, int bx, int by, const x264_fly_box_t *b, pixel *dst[4] );
/* the band's planes holding H, V, C rows [ry0, ry1) (relative to the block (bx,by)),
 * computing the missing ones, or 0 if the reference has no band or the rows are not
 * in it: for a caller that reads these planes in place (the fused me_search_fpel) */
#define x264_fly_band_cover x264_template(fly_band_cover)
intptr_t x264_fly_band_cover( x264_t *h, pixel **fref, intptr_t stride, int bx, int by, int ry0, int ry1, pixel *dst[4] );

/* the band's planes if H, V, C rows [ry0, ry1) of the block (bx,by) (ry1 > ry0) are in
 * it and computed, else 0: x264_fly_planes' common case, inline */
static ALWAYS_INLINE intptr_t x264_fly_band_hit( x264_t *h, pixel **fref, int bx, int by, int ry0, int ry1, pixel *dst[4] )
{
    x264_fly_band_t *bd = h->fly->slot[x264_fly_ref( fref )].band;
    if( !bd || bd->gen != h->fly->gen )
        return 0;
    int ay = 16*(h->mb.i_mb_y >> MB_INTERLACED) + by - bd->org;
    int r0 = ay + ry0, r1 = ay + ry1;
    if( r0 < 0 || r1 > FLY_BR )
        return 0;
    /* rows r0..r1-1 of the FLY_BR-row bitmap, 0 < r1 - r0 < 64 */
    uint64_t m = (1ULL << (r1 - r0)) - 1;
    uint64_t lo = r0 < 64 ? m << r0 : 0;
    uint64_t hi = r0 >= 64 ? m << (r0 - 64) : r1 > 64 ? m >> (64 - r0) : 0;
    if( (lo & ~bd->valid[0]) | (hi & ~bd->valid[1]) )
        return 0;
    intptr_t off = ay * bd->stride + 16*h->mb.i_mb_x + bx;
    dst[0] = fref[0];
    dst[1] = bd->plane[1] + off;
    dst[2] = bd->plane[2] + off;
    dst[3] = bd->plane[3] + off;
    return bd->stride;
}

/* x264_fly_planes for the reads at one mv (not fullpel) */
static ALWAYS_INLINE intptr_t x264_fly_planes_mv( x264_t *h, pixel **fref, intptr_t stride, int bx, int by,
                                                  int mvx, int mvy, int bw, int bh, pixel *dst[4] )
{
    intptr_t s = x264_fly_band_hit( h, fref, bx, by, mvy >> 2, (mvy >> 2) + bh + 1, dst );
    if( s )
        return s;
    x264_fly_box_t b;
    x264_fly_box_mv( &b, mvx, mvy, bw, bh );
    return x264_fly_planes( h, fref, stride, bx, by, &b, dst );
}

/* x264_fly_planes for the reads of a refine_subpel search */
static ALWAYS_INLINE intptr_t x264_fly_planes_search( x264_t *h, pixel **fref, intptr_t stride, int bx, int by,
                                                      int mvx, int mvy, int hpel_iters, int qpel_iters, int bw, int bh,
                                                      pixel *dst[4] )
{
    const x264_fly_ofs_t *o = &x264_fly_box_search_tab[hpel_iters][qpel_iters][((mvy&3)<<2) + (mvx&3)];
    intptr_t s = x264_fly_band_hit( h, fref, bx, by, (mvy >> 2) + o->ry0, (mvy >> 2) + o->ry1 + bh, dst );
    if( s )
        return s;
    x264_fly_box_t b;
    x264_fly_box_search( &b, mvx, mvy, hpel_iters, qpel_iters, bw, bh );
    return x264_fly_planes( h, fref, stride, bx, by, &b, dst );
}

/* mc.get_ref / mc_luma on a fly reference, the block at (bx,by) of the mb */
#define x264_fly_get_ref x264_template(fly_get_ref)
pixel *x264_fly_get_ref( x264_t *h, pixel *dst, intptr_t *i_dst_stride, pixel **src, intptr_t i_src_stride,
                         int mvx, int mvy, int i_width, int i_height, const x264_weight_t *weight, int bx, int by );
#define x264_fly_mc_luma x264_template(fly_mc_luma)
void x264_fly_mc_luma( x264_t *h, pixel *dst, intptr_t i_dst_stride, pixel **src, intptr_t i_src_stride,
                       int mvx, int mvy, int i_width, int i_height, const x264_weight_t *weight, int bx, int by );

/* get_ref that never returns src's planes: the prediction is in dst at *i_dst_stride */
#define x264_fly_get_ref_copy x264_template(fly_get_ref_copy)
pixel *x264_fly_get_ref_copy( x264_t *h, pixel *dst, intptr_t *i_dst_stride, pixel **src, intptr_t i_src_stride,
                              int mvx, int mvy, int i_width, int i_height, const x264_weight_t *weight, int bx, int by );

#define x264_fly_alloc x264_template(fly_alloc)
int  x264_fly_alloc( x264_t *h, intptr_t stride, int width ); /* the reference planes' frame stride and width */
#define x264_fly_free x264_template(fly_free)
void x264_fly_free( x264_t *h );
#define x264_fly_report x264_template(fly_report)
void x264_fly_report( x264_t *h );

/* invalidates every window (new slice: new references) */
static ALWAYS_INLINE void x264_fly_invalidate( x264_t *h )
{
    if( h->fly )
        h->fly->gen++;
}

/* the block (bx,by) of a me_t's partition, from its fenc */
#define FLY_PART_X( h, m ) ((int)((m)->p_fenc[0] - (h)->mb.pic.p_fenc[0]) & 15)
#define FLY_PART_Y( h, m ) ((int)((m)->p_fenc[0] - (h)->mb.pic.p_fenc[0]) >> 4)

#if HPELFLY_STATS
/* the ledger of stored-plane reads (H, V, C of the box) and the hpel pass's writes */
#define x264_fly_ledger x264_template(fly_ledger)
void x264_fly_ledger( x264_t *h, pixel **src, intptr_t stride, int bx, int by, const x264_fly_box_t *b );
#define x264_fly_ledger_flush x264_template(fly_ledger_flush)
void x264_fly_ledger_flush( x264_t *h );
#define FLY_COUNT_WR( h, bytes ) do { if( (h)->fly ) (h)->fly->st_wr_bytes += (bytes); } while( 0 )
static ALWAYS_INLINE void x264_fly_ledger_mv( x264_t *h, pixel **src, intptr_t stride, int bx, int by,
                                              int mvx, int mvy, int bw, int bh )
{
    if( h->fly && ((mvx|mvy)&3) )
    {
        x264_fly_box_t b;
        x264_fly_box_mv( &b, mvx, mvy, bw, bh );
        x264_fly_ledger( h, src, stride, bx, by, &b );
    }
}
#else
#define FLY_COUNT_WR( h, bytes )
#define x264_fly_ledger_mv( h, src, stride, bx, by, mvx, mvy, bw, bh )
#endif

/* mc_luma / get_ref of the 4 planes src, stored or fly, for the block (bx,by) of the
 * mb: fullpel mvs read F only */
static ALWAYS_INLINE void x264_mc_luma_ref( x264_t *h, pixel *dst, intptr_t ds, pixel **src, intptr_t ss, int mvx, int mvy,
                                            int w, int hh, const x264_weight_t *weight, int bx, int by )
{
    if( HPEL_FLY && ((mvx|mvy)&3) && x264_fly_ref( src ) >= 0 )
        x264_fly_mc_luma( h, dst, ds, src, ss, mvx, mvy, w, hh, weight, bx, by );
    else
    {
        x264_fly_ledger_mv( h, src, ss, bx, by, mvx, mvy, w, hh );
        h->mc.mc_luma( dst, ds, src, ss, mvx, mvy, w, hh, weight );
    }
}

static ALWAYS_INLINE pixel *x264_get_ref_ref( x264_t *h, pixel *dst, intptr_t *pds, pixel **src, intptr_t ss, int mvx, int mvy,
                                              int w, int hh, const x264_weight_t *weight, int bx, int by, int b_copy )
{
    if( HPEL_FLY && ((mvx|mvy)&3) && x264_fly_ref( src ) >= 0 )
        return b_copy ? x264_fly_get_ref_copy( h, dst, pds, src, ss, mvx, mvy, w, hh, weight, bx, by )
                      : x264_fly_get_ref( h, dst, pds, src, ss, mvx, mvy, w, hh, weight, bx, by );
    x264_fly_ledger_mv( h, src, ss, bx, by, mvx, mvy, w, hh );
    return h->mc.get_ref( dst, pds, src, ss, mvx, mvy, w, hh, weight );
}

#define X264_MC_LUMA( h, dst, ds, src, ss, mvx, mvy, w, hh, weight, bx, by )\
    x264_mc_luma_ref( h, dst, ds, src, ss, mvx, mvy, w, hh, weight, bx, by )
#define X264_GET_REF( h, dst, pds, src, ss, mvx, mvy, w, hh, weight, bx, by )\
    x264_get_ref_ref( h, dst, pds, src, ss, mvx, mvy, w, hh, weight, bx, by, 0 )
/* X264_GET_REF whose result is never in a window */
#define X264_GET_REF_COPY( h, dst, pds, src, ss, mvx, mvy, w, hh, weight, bx, by )\
    x264_get_ref_ref( h, dst, pds, src, ss, mvx, mvy, w, hh, weight, bx, by, 1 )

/* src, or fly window planes holding the reads of the bw x bh block (bx,by) at the
 * mv, whose stride replaces *stride */
static ALWAYS_INLINE pixel **x264_fly_ref_mv( x264_t *h, pixel **src, intptr_t *stride, int bx, int by,
                                              int mvx, int mvy, int bw, int bh, pixel *tmp[4] )
{
    if( HPEL_FLY && x264_fly_ref( src ) >= 0 )
    {
        *stride = x264_fly_planes_mv( h, src, *stride, bx, by, mvx, mvy, bw, bh, tmp );
        return tmp;
    }
    x264_fly_ledger_mv( h, src, *stride, bx, by, mvx, mvy, bw, bh );
    return src;
}

#endif
