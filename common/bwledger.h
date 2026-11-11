/*****************************************************************************
 * bwledger.h: test-only DRAM byte ledger
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

/* Build with --extra-cflags="-DX264_BWLEDGER=1"; never in production. Counters
 * only: per stage and plane class, bytes read and written, plus a 64 B
 * line-touch bitmap of every registered plane (refs, lowres, weight buffers)
 * for the reads made through the pixel/mc primitives. Rows go to stderr as
 * BWL* lines, one per x264_encoder_encode call; run --threads 1 for rows that
 * map to frames. Off, every macro is empty. */

#ifndef X264_BWLEDGER_H
#define X264_BWLEDGER_H

#ifndef X264_BWLEDGER
#define X264_BWLEDGER 0
#endif

enum
{
    BWL_OTHER,
    BWL_SRCCOPY,  /* CLI picture copy into x264's own fenc planes (encode_ext borrows: none) */
    BWL_SRCPAD,   /* writes into the source plane: mod16 pad, lowres edge column */
    BWL_AQ,       /* AQ energy source reads, qp offset arrays */
    BWL_LOWRES,   /* lowres init: source reads, 4 planes + their pads */
    BWL_LA,       /* lookahead ME (touch context) */
    BWL_LAINTRA,  /* lookahead intra source reads */
    BWL_LATREE,   /* mbtree propagate / finish arrays */
    BWL_SRCENC,   /* encode: fenc MB loads */
    BWL_ME,       /* analyse (touch context): fpel, subpel, RD MC */
    BWL_MC,       /* macroblock_encode (touch context): final MC */
    BWL_WEIGHT,   /* weighted reference planes */
    BWL_FDEC,     /* recon stores */
    BWL_MBARR,    /* per-MB arrays: cache_save writes, cache_load neighbour/co-located reads */
    BWL_DEBLOCK,
    BWL_FLDCOPY,  /* plane -> plane_fld rows */
    BWL_HPEL,     /* H/V/C frame and field planes */
    BWL_BORDER,   /* pads of fdec planes (lowres pads count as BWL_LOWRES) */
    BWL_BS,       /* entropy output + NAL escape */
    BWL_NSTAGE
};

enum
{
    BWL_EXT,      /* unregistered memory (caller's planes) */
    BWL_SRC_Y, BWL_SRC_C,
    BWL_LR0, BWL_LR1, BWL_LR2, BWL_LR3,
    BWL_F, BWL_H, BWL_V, BWL_C,
    BWL_FF, BWL_HF, BWL_VF, BWL_CF,
    BWL_UV, BWL_UVF,
    BWL_WBUF,
    BWL_ARR_LA, BWL_ARR_RC, BWL_ARR_MB,
    BWL_BSBUF,
    BWL_NCLS
};

#if X264_BWLEDGER
#include <stddef.h>
#include <stdint.h>
void x264_bwl_init( int b_threads );
void x264_bwl_close( void );
/* nplanes planes of plane_size bytes from base; class cls0 + i*cls_step for plane i;
 * interior = picture bytes per plane (stride * lines), for the touched fraction */
void x264_bwl_register( const void *owner, const void *base, size_t plane_size, int nplanes,
                        int cls0, int cls_step, const int *frame_num, size_t interior );
void x264_bwl_unregister( const void *owner );
void x264_bwl_acc( int stage, const void *p, int cls, uint64_t rd, uint64_t wr );
void x264_bwl_touch( int stage, const void *p, intptr_t stride, int width, int rows );
int  x264_bwl_ctx_set( int stage );
int  x264_bwl_ctx( void );
void x264_bwl_frame_done( int frame, char type );
void x264_bwl_row( void );

#define BWL_RD( st, p, n )  x264_bwl_acc( st, p, BWL_EXT, (uint64_t)(n), 0 )
#define BWL_WR( st, p, n )  x264_bwl_acc( st, p, BWL_EXT, 0, (uint64_t)(n) )
#define BWL_RDC( st, c, n ) x264_bwl_acc( st, NULL, c, (uint64_t)(n), 0 )
#define BWL_WRC( st, c, n ) x264_bwl_acc( st, NULL, c, 0, (uint64_t)(n) )
/* reads of rows x width bytes at p (stride in bytes) in the current context */
#define BWL_TOUCH( p, stride, w, rows ) x264_bwl_touch( -1, p, stride, w, rows )
#define BWL_TOUCH_ST( st, p, stride, w, rows ) x264_bwl_touch( st, p, stride, w, rows )
#define BWL_CTX_PUSH( st ) int bwl_ctx_saved_ = x264_bwl_ctx_set( st )
#define BWL_CTX_POP() x264_bwl_ctx_set( bwl_ctx_saved_ )
#define BWL_CTX_SET( st ) x264_bwl_ctx_set( st )
#else
#define BWL_RD( st, p, n )
#define BWL_WR( st, p, n )
#define BWL_RDC( st, c, n )
#define BWL_WRC( st, c, n )
#define BWL_TOUCH( p, stride, w, rows )
#define BWL_TOUCH_ST( st, p, stride, w, rows )
#define BWL_CTX_PUSH( st )
#define BWL_CTX_POP()
#define BWL_CTX_SET( st )
#endif

#endif
