/*****************************************************************************
 * analyse.h: macroblock analysis
 *****************************************************************************
 * Copyright (C) 2003-2014 x264 project
 *
 * Authors: Laurent Aimar <fenrir@via.ecp.fr>
 *          Loren Merritt <lorenm@u.washington.edu>
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

#ifndef X264_ANALYSE_H
#define X264_ANALYSE_H

#define x264_analyse_prepare_costs x264_template(analyse_prepare_costs)
float *x264_analyse_prepare_costs( x264_t *h );
#define x264_analyse_init_costs x264_template(analyse_init_costs)
int x264_analyse_init_costs( x264_t *h, float *logs, int qp );
#define x264_analyse_free_costs x264_template(analyse_free_costs)
void x264_analyse_free_costs( x264_t *h );
#define x264_analyse_weight_frame x264_template(analyse_weight_frame)
void x264_analyse_weight_frame( x264_t *h, int end );
#define x264_analyse_weight_height x264_template(analyse_weight_height)
int x264_analyse_weight_height( x264_t *h );
#define x264_analyse_weight_rows x264_template(analyse_weight_rows)
void x264_analyse_weight_rows( x264_t *h, int y0, int y1 );
#define x264_macroblock_analyse x264_template(macroblock_analyse)
void x264_macroblock_analyse( x264_t *h );
#define x264_slicetype_decide x264_template(slicetype_decide)
void x264_slicetype_decide( x264_t *h );

#define x264_slicetype_analyse x264_template(slicetype_analyse)
void x264_slicetype_analyse( x264_t *h, int intra_minigop );

#define x264_weighted_reference_duplicate x264_template(weighted_reference_duplicate)
int x264_weighted_reference_duplicate( x264_t *h, int i_ref, const x264_weight_t *w );

#define x264_lookahead_init x264_template(lookahead_init)
int  x264_lookahead_init( x264_t *h, int i_slicetype_length );
#define x264_lookahead_is_empty x264_template(lookahead_is_empty)
int  x264_lookahead_is_empty( x264_t *h );
#define x264_lookahead_put_frame x264_template(lookahead_put_frame)
void x264_lookahead_put_frame( x264_t *h, x264_frame_t *frame );
#define x264_lookahead_get_frames x264_template(lookahead_get_frames)
void x264_lookahead_get_frames( x264_t *h );
#define x264_lookahead_delete x264_template(lookahead_delete)
void x264_lookahead_delete( x264_t *h );

/* vbv-reuse counters (test only). Per thread, summed into fdec->rcn per slice. */
enum
{
    RCN_EV, RCN_EV_EMERG, RCN_EV_ROOM, RCN_EV_JUMP, RCN_EV_LAST, RCN_EV_LASTEMERG, RCN_DQP100,
    RCN_MB, RCN_MB_REDO, RCN_MB_REDO_EMERG, RCN_MB_REDO_INTRA, RCN_MB_REDO_SKIP, RCN_MB_REDO_CMP,
    RCN_TSC_AN, RCN_TSC_ENC, RCN_TSC_REDO_AN, RCN_TSC_REDO_ENC,
    RCN_TSC_REDO_ME, RCN_TSC_REDO_INTRA, RCN_TSC_REDO_I16C, RCN_TSC_REDO_I16C_SAME, RCN_TSC_REDO_PSKIP, RCN_TSC_REDO_TRANS,
    RCN_SAME_TYPE, RCN_SAME_MODE, RCN_INTER_BOTH, RCN_SAME_MV, RCN_MVP_BOTH, RCN_SAME_MVP,
    RCN_EDGE_X0, RCN_EDGE_CHK, RCN_EDGE_SAME, RCN_COL_SAME,
    RCN_N
};
enum { RCN_SRC_EMERG, RCN_SRC_ROOM, RCN_SRC_JUMP, RCN_SRC_LAST, RCN_SRC_LASTEMERG };
#define x264_rcn x264_template(rcn)
extern __thread uint64_t x264_rcn[RCN_N];
#define x264_rcn_src x264_template(rcn_src)
extern __thread int x264_rcn_src;
#define x264_rcn_mb_begin x264_template(rcn_mb_begin)
void x264_rcn_mb_begin( x264_t *h );
#define x264_rcn_mb_end x264_template(rcn_mb_end)
void x264_rcn_mb_end( x264_t *h, uint64_t t0, uint64_t t1, uint64_t t2 );
#define x264_rcn_restart x264_template(rcn_restart)
void x264_rcn_restart( x264_t *h, int y );
#define x264_rcn_slice_end x264_template(rcn_slice_end)
void x264_rcn_slice_end( x264_t *h, uint64_t tsc );
#define x264_rcn_frame_fold x264_template(rcn_frame_fold)
void x264_rcn_frame_fold( x264_t *h );
#define x264_rcn_print x264_template(rcn_print)
void x264_rcn_print( x264_t *h );
static inline uint64_t x264_rcn_tsc( void ) { return __builtin_ia32_rdtsc(); }

#endif
