/*****************************************************************************
 * s3cnt.h: survey 3 measurement counters (test builds only)
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

/* -DX264_S3CNT=1 only (measurement builds, never merged). Every hook observes: no
 * decision, rng or encoder state changes. Counters are process-wide, relaxed
 * __atomic adds; context is __thread. Printed to stderr at x264_encoder_close. */

#ifndef X264_S3CNT_H
#define X264_S3CNT_H

#if X264_S3CNT

/* C1 refine_qpel: list of the refined x264_me_t */
enum { S3_P, S3_L0, S3_L1, S3_BI, S3_NLIST };
/* qpel_search caller */
enum { S3_QO_OTHER, S3_QO_SEARCH, S3_QO_REFDUPE, S3_QO_REFINE, S3_QO_N };
/* qpel_search exit: iters 0, range edge, no move (the record), moved on the last iteration */
enum { S3_QX_ITERS0, S3_QX_RANGE, S3_QX_NOMOVE, S3_QX_EXHAUST, S3_QX_N };
/* C4 sites */
enum { S4_I16, S4_I4, S4_I8, S4_TRD, S4_PRD, S4_ANA, S4_OTHER, S4_N };
/* C5 decimation groups / trellis callers */
enum { S5_I16AC, S5_LUMA4, S5_CHROMAAC, S5_G };
enum { S5T_I16AC, S5T_LUMA4, S5T_CHROMAAC, S5T_4x4, S5T_8x8, S5T_LUMADC, S5T_CHROMADC, S5T_OTHER, S5T_N };

#define S3_HIST 11      /* 10 % bins of the crossing point, [10]: only at the end (nothing saved) */
#define S3_RDTR_MAX 96  /* RD sizing checkpoints per MB */
#define S3_FL_MAX 256   /* fpel positions logged per search */

typedef struct
{
    /* C1 */
    uint64_t rq_calls[S3_NLIST][7], rq_weighted[S3_NLIST][7], rq_hpel[S3_NLIST][7];
    uint64_t rq_nochange[S3_NLIST][7], rq_rec[S3_NLIST][7], rq_skip[S3_NLIST][7], rq_viol[S3_NLIST][7];
    uint64_t rq_qcalls[S3_NLIST][7], rq_qcalls_skip[S3_NLIST][7];
    uint64_t q_calls[S3_QO_N][4], q_exit[S3_QO_N][S3_QX_N], q_rec_set, q_shadow, q_err;
    /* C2: [0 P, 1 B][i_pixel] */
    uint64_t s2_n[2][4], s2_nof[2][4], s2_feqw[2][4], s2_fhexsq[2][4], s2_fins[2][4], s2_startw_still[2][4];
    uint64_t s2_hpeleq[2][4], s2_served[2][4], s2_postot[2][4], s2_posserv[2][4], s2_predtot[2][4], s2_predserv[2][4];
    uint64_t s2_survb[2][4], s2_moved[2][4], s2_zexit[2][4];
    uint64_t s2_w16_n[2], s2_w16_hex6[2], s2_w16_sq8[2], s2_w16_pos[2];
    uint64_t s2_shadow_n[2][4], s2_mis_a[2][4], s2_mis_b[2][4], s2_logovf;
    /* C3: [0 16x16, 1 other] */
    uint64_t s3_calls[2], s3_edge[2], s3_passes[2], s3_gr[2], s3_gr_avg[2], s3_gr_ovl[2], s3_gr_ovl_avg[2], s3_pass_hist[2][9];
    uint64_t s3_lists_moved[2][3];
    /* C4 */
    uint64_t r4_calls[S4_N], r4_bounded[S4_N], r4_lose[S4_N], r4_ssd_cross[S4_N], r4_skip[S4_N];
    uint64_t r4_f8_all[S4_N], r4_f8_lose[S4_N], r4_f8_save_fine[S4_N], r4_f8_save_coarse[S4_N];
    uint64_t r4_hist_fine[S4_N][S3_HIST], r4_hist_coarse[S4_N][S3_HIST], r4_hist_blk[S4_N][S3_HIST], r4_trovf;
    uint64_t r4_part_calls[2], r4_part_lose[2], r4_part_ssd_cross[2];   /* rd_cost_i4x4, rd_cost_i8x8 (subme >= 8) */
    /* C5 */
    uint64_t t5_calls[S5T_N], t5_dps[S5T_N];
    uint64_t g5_n[S5_G], g5_proven[S5_G], g5_dec[S5_G], g5_viol[S5_G], g5_dps[S5_G], g5_dps_skip[S5_G];
    uint64_t g5_mb_n, g5_mb_proven, g5_mb_dec, g5_mb_viol, g5_blk, g5_blk_viol, g5_dps_skip_refined;
    /* C6: [frame type 0-6] */
    uint64_t f6_cost_calls, f6_cost_hits, f6_ihit, f6_i_run[7][2], f6_intra_pass[7][3];
    uint64_t f6_frames[7], f6_frames_irun[7], f6_frames_irun2[7], f6_irun_sum[7], f6_intra_sum[7], f6_frames_intra2[7], f6_late[7];
} x264_s3cnt_t;

/* RD sizing trace of the current x264_rd_cost_mb */
typedef struct
{
    int on;
    int n;
    int f8[S3_RDTR_MAX];
    uint8_t coarse[S3_RDTR_MAX];
} x264_s3_rdtr_t;

/* fpel position log of a shadow search: on 1 = full C search (record the fpel result),
 * 2 = log the positions, no whole-walk kernels, stop at fpel_done */
typedef struct
{
    int on;
    int n;
    int16_t pos[S3_FL_MAX][2];
    int npred;          /* positions logged before the walk starts */
    int sx, sy;         /* walk start */
    int fx, fy, fcost;  /* fpel result */
    int done;           /* reached fpel_done */
    int walked;         /* reached the walk (no zero sad exit) */
} x264_s3_fl_t;

typedef struct
{
    /* C1 */
    int qo;             /* S3_QO_* of the current qpel_search caller */
    int shadow;         /* inside a shadow search: count nothing */
    void *cur_m;        /* x264_me_t of the current search, for the record */
    uint64_t qcalls;    /* qpel_search calls so far (refine deltas) */
    /* C4 */
    int rd_site;        /* S4_* + 1, 0 = none */
    uint64_t rd_bound;  /* cost >= bound loses; UINT64_MAX none */
    /* C5 */
    int tr_site;        /* S5T_* + 1 */
    int rtn_valid;
    int rtn_nz;
    int rtn_score[4];
    int rtn_dps;
    /* C4 intra_rd: the cost its caller compares the intra types against, 8x8 compared before 4x4 */
    int intra_inter;
    int intra_b8first;
    void *cur_a;        /* x264_mb_analysis_t of the current MB */
} x264_s3_ctx_t;

#define x264_s3 x264_template(s3)
extern x264_s3cnt_t x264_s3;
#define x264_s3_ctx x264_template(s3_ctx)
extern __thread x264_s3_ctx_t x264_s3_ctx;
#define x264_s3_rdtr x264_template(s3_rdtr)
extern __thread x264_s3_rdtr_t x264_s3_rdtr;
#define x264_s3_fl x264_template(s3_fl)
extern __thread x264_s3_fl_t x264_s3_fl;
#define x264_s3_print x264_template(s3_print)
void x264_s3_print( void );
#define x264_s3_intra_bound x264_template(s3_intra_bound)
uint64_t x264_s3_intra_bound( int type, int c16, int c4 );
#define x264_s3_minb x264_template(s3_minb)
uint64_t x264_s3_minb( int a, int b, int c );
#define x264_s3_f6_cost x264_template(s3_f6_cost)
void x264_s3_f6_cost( x264_frame_t *fenc, int p0, int p1, int b, int hit );
#define x264_s3_f6_tally x264_template(s3_f6_tally)
void x264_s3_f6_tally( x264_frame_t *f );

#define S3_ADD( field, n ) __atomic_fetch_add( &x264_s3.field, (uint64_t)(n), __ATOMIC_RELAXED )
#define S3_INC( field ) S3_ADD( field, 1 )
#define S3_LIVE ( !x264_s3_ctx.shadow )

/* fpel position (mx, my) scored by a logged shadow search */
#define S3_POS( mx, my ) do { if( x264_s3_fl.on == 2 ) { if( x264_s3_fl.n < S3_FL_MAX ) { x264_s3_fl.pos[x264_s3_fl.n][0] = (mx); x264_s3_fl.pos[x264_s3_fl.n][1] = (my); x264_s3_fl.n++; } else S3_INC( s2_logovf ); } } while( 0 )
#define S3_POS_FPEL( mx, my ) do { if( !(((mx)|(my))&3) ) S3_POS( (mx)>>2, (my)>>2 ); } while( 0 )
#define S3_NOWALK ( x264_s3_fl.on != 2 )
/* RD sizing checkpoint */
#define S3_RD_CK( cb, c ) do { if( x264_s3_rdtr.on ) { if( x264_s3_rdtr.n < S3_RDTR_MAX ) { x264_s3_rdtr.f8[x264_s3_rdtr.n] = (cb)->f8_bits_encoded; x264_s3_rdtr.coarse[x264_s3_rdtr.n++] = (c); } else S3_INC( r4_trovf ); } } while( 0 )
#define S3_TR_SITE( s ) ( x264_s3_ctx.tr_site = (s) + 1 )
#define S3_RD_SET( site, bound ) ( x264_s3_ctx.rd_site = (site) + 1, x264_s3_ctx.rd_bound = (bound) )
#define S3_INTRA_CTX( inter, b8 ) ( x264_s3_ctx.intra_inter = (inter), x264_s3_ctx.intra_b8first = (b8) )
#define S3_SET_A( a ) ( x264_s3_ctx.cur_a = (a) )
#define S3_F6_COST( h, fenc, p0, p1, b, hit ) x264_s3_f6_cost( fenc, p0, p1, b, hit )
#define S3_F6_TALLY( f ) x264_s3_f6_tally( f )
#define S3_PRINT() x264_s3_print()

#else

#define S3_POS( mx, my )
#define S3_POS_FPEL( mx, my )
#define S3_NOWALK 1
#define S3_RD_CK( cb, c )
#define S3_TR_SITE( s )
#define S3_RD_SET( site, bound )
#define S3_INTRA_CTX( inter, b8 )
#define S3_SET_A( a )
#define S3_F6_COST( h, fenc, p0, p1, b, hit )
#define S3_F6_TALLY( f )
#define S3_PRINT()

#endif

#endif
