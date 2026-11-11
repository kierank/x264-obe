/*****************************************************************************
 * bwledger.c: test-only DRAM byte ledger
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

#include "bwledger.h"

#if X264_BWLEDGER
#include "osdep.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Output (stderr), all sizes in bytes; n = row (one per x264_encoder_encode
 * call), frame/type = the frame that call output (-1 / '-' if none):
 *   BWLROW n frame type
 *   BWLS   n stage cls rd wr       stage x class bytes (touches count as rd)
 *   BWLU   n grp cls owner uniq interior
 *                                  distinct 64 B lines x 64 read in the row from one
 *                                  plane of one owner frame; grp LA / ME / MC, EN = ME|MC
 *   BWLT   frames stage cls rd wr  totals at close
 *   BWLTU  frames grp cls uniq     summed per-row uniq at close */

static const char *const stage_names[BWL_NSTAGE] =
{
    "other", "srccopy", "srcpad", "aq", "lowres", "la", "laintra", "latree", "srcenc",
    "me", "mc", "weight", "fdec", "mbarr", "deblock", "fldcopy", "hpel", "border", "bs"
};
static const char *const cls_names[BWL_NCLS] =
{
    "ext", "src_y", "src_c", "lr0", "lr1", "lr2", "lr3", "F", "H", "V", "C",
    "Ffld", "Hfld", "Vfld", "Cfld", "uv", "uvfld", "wbuf", "arr_la", "arr_rc", "arr_mb", "bs"
};

#define NGRP 3 /* LA, ME, MC */
static const char *const grp_names[NGRP+1] = { "LA", "ME", "MC", "EN" };

typedef struct
{
    uintptr_t lo, hi;
    size_t plane_size;
    size_t interior;
    int nplanes, cls0, cls_step;
    const void *owner;
    const int *frame_num;
    size_t words;          /* per bitmap */
    uint64_t *bm[NGRP];
} bwl_ent_t;

static x264_pthread_mutex_t bwl_lock;
static int bwl_inited;
static bwl_ent_t *ents;
static int nents, ments;
static uint64_t acc[BWL_NSTAGE][BWL_NCLS][2];
static uint64_t tot[BWL_NSTAGE][BWL_NCLS][2];
static uint64_t totu[NGRP+1][BWL_NCLS];
static int row_n, frames_done, last_frame = -1;
static char last_type = '-';
static __thread int bwl_ctx_stage;

/* first call from x264_encoder_open, before any frame exists; one encoder per process */
void x264_bwl_init( int b_threads )
{
    if( !bwl_inited )
    {
        (void)x264_pthread_mutex_init( &bwl_lock, NULL );
        bwl_inited = 1;
        fprintf( stderr, "BWLINFO ledger build: counters only\n" );
    }
    if( b_threads )
        fprintf( stderr, "BWLINFO threads > 1: totals valid, rows do not map to frames\n" );
}

static int grp_of( int stage )
{
    return stage == BWL_LA || stage == BWL_LAINTRA || stage == BWL_LATREE ? 0 : stage == BWL_MC ? 2 : 1;
}

/* entry holding p, or NULL; caller holds the lock */
static bwl_ent_t *find( uintptr_t p )
{
    int lo = 0, hi = nents - 1;
    while( lo <= hi )
    {
        int mid = (lo + hi) >> 1;
        if( p < ents[mid].lo )
            hi = mid - 1;
        else if( p >= ents[mid].hi )
            lo = mid + 1;
        else
            return &ents[mid];
    }
    return NULL;
}

static int cls_at( bwl_ent_t *e, uintptr_t p )
{
    int plane = (int)((p - e->lo) / e->plane_size);
    if( plane >= e->nplanes )
        plane = e->nplanes - 1;
    return e->cls0 + plane * e->cls_step;
}

void x264_bwl_register( const void *owner, const void *base, size_t plane_size, int nplanes,
                        int cls0, int cls_step, const int *frame_num, size_t interior )
{
    if( !bwl_inited || !base || !plane_size || !nplanes )
        return;
    x264_pthread_mutex_lock( &bwl_lock );
    if( nents == ments )
    {
        ments = ments ? 2*ments : 256;
        ents = realloc( ents, ments * sizeof(*ents) );
        if( !ents )
            abort();
    }
    bwl_ent_t e;
    memset( &e, 0, sizeof(e) );
    e.lo = (uintptr_t)base;
    e.hi = e.lo + plane_size * nplanes;
    e.plane_size = plane_size;
    e.interior = interior;
    e.nplanes = nplanes;
    e.cls0 = cls0;
    e.cls_step = cls_step;
    e.owner = owner;
    e.frame_num = frame_num;
    e.words = ((e.hi - e.lo + 63) / 64 + 63) / 64 + 1;
    for( int g = 0; g < NGRP; g++ )
    {
        e.bm[g] = calloc( e.words, sizeof(uint64_t) );
        if( !e.bm[g] )
            abort();
    }
    int i = nents;
    while( i > 0 && ents[i-1].lo > e.lo )
    {
        ents[i] = ents[i-1];
        i--;
    }
    ents[i] = e;
    nents++;
    x264_pthread_mutex_unlock( &bwl_lock );
}

void x264_bwl_unregister( const void *owner )
{
    if( !bwl_inited )
        return;
    x264_pthread_mutex_lock( &bwl_lock );
    int j = 0;
    for( int i = 0; i < nents; i++ )
    {
        if( ents[i].owner == owner )
        {
            for( int g = 0; g < NGRP; g++ )
                free( ents[i].bm[g] );
            continue;
        }
        ents[j++] = ents[i];
    }
    nents = j;
    x264_pthread_mutex_unlock( &bwl_lock );
}

void x264_bwl_acc( int stage, const void *p, int cls, uint64_t rd, uint64_t wr )
{
    if( !bwl_inited )
        return;
    x264_pthread_mutex_lock( &bwl_lock );
    if( p )
    {
        bwl_ent_t *e = find( (uintptr_t)p );
        cls = e ? cls_at( e, (uintptr_t)p ) : BWL_EXT;
    }
    if( stage == BWL_BORDER && cls >= BWL_LR0 && cls <= BWL_LR3 )
        stage = BWL_LOWRES;
    acc[stage][cls][0] += rd;
    acc[stage][cls][1] += wr;
    x264_pthread_mutex_unlock( &bwl_lock );
}

/* Only registered memory is counted: scratch buffers (fenc/fdec caches, MC
 * outputs) are cache-resident by construction. */
void x264_bwl_touch( int stage, const void *p, intptr_t stride, int width, int rows )
{
    if( !bwl_inited || !p || width <= 0 || rows <= 0 )
        return;
    if( stage < 0 )
        stage = bwl_ctx_stage;
    int g = grp_of( stage );
    x264_pthread_mutex_lock( &bwl_lock );
    bwl_ent_t *e = find( (uintptr_t)p );
    if( e )
    {
        for( int r = 0; r < rows; r++ )
        {
            uintptr_t a = (uintptr_t)p + (intptr_t)r * stride;
            uintptr_t b = a + width - 1;
            if( a < e->lo || b >= e->hi )
            {
                /* a row outside the entry (block hanging off a pad): clip */
                if( b < e->lo || a >= e->hi )
                    continue;
                if( a < e->lo ) a = e->lo;
                if( b >= e->hi ) b = e->hi - 1;
            }
            acc[stage][cls_at( e, a )][0] += b - a + 1;
            for( size_t l = (a - e->lo) >> 6; l <= (b - e->lo) >> 6; l++ )
                e->bm[g][l >> 6] |= 1ULL << (l & 63);
        }
    }
    x264_pthread_mutex_unlock( &bwl_lock );
}

int x264_bwl_ctx_set( int stage )
{
    int old = bwl_ctx_stage;
    bwl_ctx_stage = stage;
    return old;
}

int x264_bwl_ctx( void )
{
    return bwl_ctx_stage;
}

void x264_bwl_frame_done( int frame, char type )
{
    if( !bwl_inited )
        return;
    x264_pthread_mutex_lock( &bwl_lock );
    last_frame = frame;
    last_type = type;
    frames_done++;
    x264_pthread_mutex_unlock( &bwl_lock );
}

static uint64_t popcount_range( const uint64_t *bm, size_t l0, size_t l1 )
{
    uint64_t n = 0;
    for( size_t l = l0; l < l1; )
    {
        if( !(l & 63) && l + 64 <= l1 )
        {
            n += __builtin_popcountll( bm[l >> 6] );
            l += 64;
        }
        else
        {
            n += (bm[l >> 6] >> (l & 63)) & 1;
            l++;
        }
    }
    return n;
}

static void row_locked( void )
{
    int any = 0;
    for( int s = 0; s < BWL_NSTAGE; s++ )
        for( int c = 0; c < BWL_NCLS; c++ )
            any |= acc[s][c][0] || acc[s][c][1];
    if( !any && last_frame < 0 )
        return;
    fprintf( stderr, "BWLROW %d %d %c\n", row_n, last_frame, last_type );
    for( int s = 0; s < BWL_NSTAGE; s++ )
        for( int c = 0; c < BWL_NCLS; c++ )
            if( acc[s][c][0] || acc[s][c][1] )
            {
                fprintf( stderr, "BWLS %d %s %s %llu %llu\n", row_n, stage_names[s], cls_names[c],
                         (unsigned long long)acc[s][c][0], (unsigned long long)acc[s][c][1] );
                tot[s][c][0] += acc[s][c][0];
                tot[s][c][1] += acc[s][c][1];
                acc[s][c][0] = acc[s][c][1] = 0;
            }
    for( int i = 0; i < nents; i++ )
    {
        bwl_ent_t *e = &ents[i];
        size_t lines = (e->hi - e->lo + 63) >> 6;
        int used = 0;
        for( int g = 0; g < NGRP; g++ )
            for( size_t w = 0; w < e->words && !used; w++ )
                used = !!e->bm[g][w];
        if( !used )
            continue;
        for( int pl = 0; pl < e->nplanes; pl++ )
        {
            size_t l0 = (pl * e->plane_size) >> 6;
            size_t l1 = pl == e->nplanes - 1 ? lines : ((pl + 1) * e->plane_size) >> 6;
            int cls = e->cls0 + pl * e->cls_step;
            int owner = e->frame_num ? *e->frame_num : -1;
            for( int g = 0; g < NGRP; g++ )
            {
                uint64_t n = popcount_range( e->bm[g], l0, l1 );
                if( n )
                {
                    fprintf( stderr, "BWLU %d %s %s %d %llu %llu\n", row_n, grp_names[g], cls_names[cls], owner,
                             (unsigned long long)(n << 6), (unsigned long long)e->interior );
                    totu[g][cls] += n << 6;
                }
            }
            /* EN: lines read by analyse or encode */
            uint64_t n = 0;
            for( size_t l = l0; l < l1; l++ )
                n += ((e->bm[1][l >> 6] | e->bm[2][l >> 6]) >> (l & 63)) & 1;
            if( n )
            {
                fprintf( stderr, "BWLU %d EN %s %d %llu %llu\n", row_n, cls_names[cls], owner,
                         (unsigned long long)(n << 6), (unsigned long long)e->interior );
                totu[NGRP][cls] += n << 6;
            }
        }
        for( int g = 0; g < NGRP; g++ )
            memset( e->bm[g], 0, e->words * sizeof(uint64_t) );
    }
    last_frame = -1;
    last_type = '-';
    row_n++;
}

void x264_bwl_row( void )
{
    if( !bwl_inited )
        return;
    x264_pthread_mutex_lock( &bwl_lock );
    row_locked();
    x264_pthread_mutex_unlock( &bwl_lock );
}

void x264_bwl_close( void )
{
    if( !bwl_inited )
        return;
    x264_pthread_mutex_lock( &bwl_lock );
    row_locked();
    for( int s = 0; s < BWL_NSTAGE; s++ )
        for( int c = 0; c < BWL_NCLS; c++ )
            if( tot[s][c][0] || tot[s][c][1] )
                fprintf( stderr, "BWLT %d %s %s %llu %llu\n", frames_done, stage_names[s], cls_names[c],
                         (unsigned long long)tot[s][c][0], (unsigned long long)tot[s][c][1] );
    for( int g = 0; g <= NGRP; g++ )
        for( int c = 0; c < BWL_NCLS; c++ )
            if( totu[g][c] )
                fprintf( stderr, "BWLTU %d %s %s %llu\n", frames_done, grp_names[g], cls_names[c],
                         (unsigned long long)totu[g][c] );
    memset( tot, 0, sizeof(tot) );
    memset( totu, 0, sizeof(totu) );
    frames_done = 0;
    row_n = 0;
    x264_pthread_mutex_unlock( &bwl_lock );
}
#else
typedef int x264_bwl_unused_t;
#endif
