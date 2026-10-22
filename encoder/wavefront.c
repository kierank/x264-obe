/*****************************************************************************
 * wavefront.c: --wavefront, one slice coded by MB rows in a wavefront
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

/* Included by encoder.c.
 *
 * The row workers (the main thread on thread 0, slice pool workers 1.. on their
 * threads) take MB rows in order; row y codes MB x once row y-1 has done MB x+1.
 * A worker binarises its MBs into the row's tape as ctxIdx and bin
 * (encoder/cabac_wf.c). The coder (slice pool worker 0, on its own context) codes
 * the tapes in raster order with the context states, keeps the QP chain of
 * mb_qp_delta, runs the row ratecontrol, then deblocks and measures the row.
 * Row y's QP is decided after row y-lag is coded, so the output doesn't depend on
 * the timing. A re-encode rolls the rows back to the one being coded. After the
 * frame the pool workers run hpel and the borders in bands. */

#if HAVE_THREAD

#define WF_LOAD(p)       __atomic_load_n( (p), __ATOMIC_ACQUIRE )
#define WF_LOAD_SC(p)    __atomic_load_n( (p), __ATOMIC_SEQ_CST )
#define WF_STORE_SC(p,v) __atomic_store_n( (p), (v), __ATOMIC_SEQ_CST )

typedef struct
{
    uint32_t *buf;
    int i_size;                 /* entries allocated */
    int i_len;                  /* entries, once the row is done */
} x264_wf_slot_t;

typedef struct x264_wf_t
{
    x264_t *coder;
    x264_ratecontrol_t *rc;     /* the frame's; the coder's while the rows are coded */
    x264_ratecontrol_t *rc_qpm; /* thread 0's meanwhile: only qpm */
    int i_rows;
    int i_width;
    int i_lag;
    int i_workers;
    int i_slots;
    x264_wf_slot_t *slot;       /* the tape of row y is slot y % i_slots */
    int *done;                  /* MBs of the row done */
    int *want;                  /* the fewest done a waiter on the row waits for, INT_MAX: none */
    float *row_qpm;             /* QP of the row, set before it is taken */
    int *row_emerg;             /* its emergency step */
    x264_frame_stat_t *stat_bak; /* the worker's stats at the start of the row */
    int *worker_rows;           /* per worker: the rows it took this frame */
    int *worker_n;
    int *band_done;             /* hpel band past pass 1 */
    int i_borders;
    pixel **border;             /* [row % i_borders][plane]: the row's last line for intra prediction below */
    pixel **own_border;         /* [worker][2][plane]: the contexts' own intra_border_backup */

    x264_pthread_mutex_t mutex;
    x264_pthread_cond_t cv;
    /* under mutex */
    int i_next;                 /* next row to take */
    int i_decided;              /* rows with a QP */
    int i_coded;                /* rows coded and final */
    int i_deblocked;
    int i_active;               /* workers in a row */
    int i_gen;                  /* rollbacks; read unlocked by the workers */
    int b_done;                 /* the slice NAL is complete */
    int b_fail;
    int b_rollback;             /* no rows are taken meanwhile */
} x264_wf_t;

static void x264_wf_delete( x264_t *h )
{
    x264_wf_t *wf = h->wf;
    if( !wf )
        return;
    if( wf->slot )
        for( int i = 0; i < wf->i_slots; i++ )
            x264_free( wf->slot[i].buf );
    x264_free( wf->slot );
    x264_free( wf->done );
    x264_free( wf->want );
    x264_free( wf->row_qpm );
    x264_free( wf->row_emerg );
    x264_free( wf->stat_bak );
    x264_free( wf->worker_rows );
    x264_free( wf->worker_n );
    x264_free( wf->band_done );
    if( wf->border )
        for( int i = 0; i < wf->i_borders * 3; i++ )
            if( wf->border[i] )
                x264_free( wf->border[i] - 16 );
    x264_free( wf->border );
    x264_free( wf->own_border );
    x264_free( wf->rc_qpm );
    x264_t *c = wf->coder;
    if( c )
    {
        x264_macroblock_thread_free( c, 0 );
        x264_free( c->out.p_bitstream );
        x264_free( c->out.nal );
        x264_free( c->threadslice_buf );
        x264_free( c );
    }
    x264_pthread_mutex_destroy( &wf->mutex );
    x264_pthread_cond_destroy( &wf->cv );
    x264_free( wf );
    for( int i = 0; i < h->param.i_threads; i++ )
        h->thread[i]->wf = NULL;
}

/* After the thread contexts and the slice pool. */
static int x264_wf_init( x264_t *h )
{
    x264_wf_t *wf;
    int rows = h->mb.i_mb_height;
    int threads = h->param.i_threads;
    CHECKED_MALLOCZERO( wf, sizeof(x264_wf_t) );
    for( int i = 0; i < threads; i++ )
        h->thread[i]->wf = wf;
    if( x264_pthread_mutex_init( &wf->mutex, NULL ) || x264_pthread_cond_init( &wf->cv, NULL ) )
        goto fail;
    wf->i_rows = rows;
    wf->i_width = h->mb.i_mb_width;
    wf->i_lag = h->param.i_wavefront_lag;
    wf->i_workers = threads;
    wf->i_slots = threads + 2;
    CHECKED_MALLOCZERO( wf->slot, wf->i_slots * sizeof(x264_wf_slot_t) );
    for( int i = 0; i < wf->i_slots; i++ )
    {
        wf->slot[i].i_size = wf->i_width * 256 + X264_WF_TAPE_MB;
        CHECKED_MALLOC( wf->slot[i].buf, wf->slot[i].i_size * sizeof(uint32_t) );
    }
    CHECKED_MALLOCZERO( wf->done, rows * sizeof(int) );
    CHECKED_MALLOCZERO( wf->want, rows * sizeof(int) );
    CHECKED_MALLOCZERO( wf->row_qpm, rows * sizeof(float) );
    CHECKED_MALLOCZERO( wf->row_emerg, rows * sizeof(int) );
    CHECKED_MALLOCZERO( wf->stat_bak, rows * sizeof(x264_frame_stat_t) );
    CHECKED_MALLOCZERO( wf->worker_rows, threads * rows * sizeof(int) );
    CHECKED_MALLOCZERO( wf->worker_n, threads * sizeof(int) );
    CHECKED_MALLOCZERO( wf->band_done, threads * sizeof(int) );
    wf->rc_qpm = x264_ratecontrol_wf_new();
    if( !wf->rc_qpm )
        goto fail;

    /* the coder: thread 0 with its own output, cabac and scratch */
    x264_t *c;
    CHECKED_MALLOC( c, sizeof(x264_t) );
    *c = *h->thread[0];
    c->out.p_bitstream = NULL;
    c->out.nal = NULL;
    c->threadslice_buf = NULL;
    c->i_threadslice_buf_size = 0;
    c->lowres8 = NULL;
    wf->coder = c;
    CHECKED_MALLOC( c->out.p_bitstream, h->out.i_bitstream + NALU_ESCAPE_PADDING );
    c->out.i_bitstream = h->out.i_bitstream;
    CHECKED_MALLOC( c->out.nal, 4 * sizeof(x264_nal_t) );
    c->out.i_nals_allocated = 4;
    if( x264_macroblock_thread_allocate( c, 0 ) < 0 )
        goto fail;

    /* the intra borders of the rows that can be in flight and the row above them */
    wf->i_borders = wf->i_slots + 1;
    CHECKED_MALLOCZERO( wf->border, wf->i_borders * 3 * sizeof(pixel*) );
    for( int i = 0; i < wf->i_borders * 3; i++ )
    {
        CHECKED_MALLOC( wf->border[i], (h->sps->i_mb_width*16+32) * sizeof(pixel) );
        wf->border[i] += 16;
    }
    CHECKED_MALLOC( wf->own_border, threads * 2 * 3 * sizeof(pixel*) );
    for( int i = 0; i < threads; i++ )
        for( int j = 0; j < 2; j++ )
            for( int p = 0; p < 3; p++ )
                wf->own_border[(i*2+j)*3+p] = h->thread[i]->intra_border_backup[j][p];
    return 0;
fail:
    return -1;
}

/* Row y has done need MBs; -1 once the rows are rolled back (gen < 0: never). */
static int x264_wf_wait_row( x264_wf_t *wf, int y, int need, int gen )
{
    if( WF_LOAD( &wf->done[y] ) >= need )
        return 0;
    int ret = 0;
    x264_pthread_mutex_lock( &wf->mutex );
    for( ;; )
    {
        if( (gen >= 0 && wf->i_gen != gen) || wf->b_fail )
        {
            ret = -1;
            break;
        }
        /* seq_cst against x264_wf_publish: one of the two sees the other */
        if( WF_LOAD_SC( &wf->want[y] ) > need )
            WF_STORE_SC( &wf->want[y], need );
        if( WF_LOAD_SC( &wf->done[y] ) >= need )
            break;
        x264_pthread_cond_wait( &wf->cv, &wf->mutex );
    }
    x264_pthread_mutex_unlock( &wf->mutex );
    return ret;
}

static void x264_wf_publish( x264_wf_t *wf, int y, int done )
{
    WF_STORE_SC( &wf->done[y], done );
    if( done >= WF_LOAD_SC( &wf->want[y] ) )
    {
        x264_pthread_mutex_lock( &wf->mutex );
        WF_STORE_SC( &wf->want[y], INT_MAX );
        x264_pthread_cond_broadcast( &wf->cv );
        x264_pthread_mutex_unlock( &wf->mutex );
    }
}

/* Analyses, encodes and binarises row y. -1: rolled back, -2: failed. */
static int x264_wf_row( x264_t *h, x264_wf_t *wf, int y, int gen )
{
    int w = wf->i_width;
    int b_deblock = h->sh.i_disable_deblocking_filter_idc != 1
                    && (h->fdec->b_kept_as_ref || h->param.b_full_recon || h->param.psz_dump_yuv
                        || h->param.analyse.b_psnr || h->param.analyse.b_ssim);
    x264_wf_slot_t *slot = &wf->slot[y % wf->i_slots];
    float qpm = wf->row_qpm[y];

    x264_ratecontrol_wf_set_qpm( h, qpm );
    h->mb.i_vbv_emerg = wf->row_emerg[y];
    /* AQ's +-1 snap starts the row at its QP; the coder keeps the bitstream's QPs */
    h->mb.i_last_qp = SPEC_QP( x264_clip3( qpm + .5f, h->param.rc.i_qp_min, h->param.rc.i_qp_max ) );
    h->mb.i_last_dqp = 0;
    h->mb.b_reencode_mb = 0;
    h->i_wf_intra = 0;
    h->cabac.p_tape = slot->buf;
    for( int p = 0; p < 3; p++ )
    {
        h->intra_border_backup[y&1][p] = wf->border[(y % wf->i_borders)*3 + p];
        h->intra_border_backup[!(y&1)][p] = wf->border[((y + wf->i_borders - 1) % wf->i_borders)*3 + p];
    }

    for( int x = 0; x < w; x++ )
    {
        if( WF_LOAD( &wf->i_gen ) != gen )
            return -1;
        if( y && x264_wf_wait_row( wf, y-1, X264_MIN( x+2, w ), gen ) < 0 )
            return -1;
        int used = h->cabac.p_tape - slot->buf;
        if( slot->i_size - used < X264_WF_TAPE_MB )
        {
            int size = slot->i_size * 2;
            uint32_t *buf = x264_malloc( size * sizeof(uint32_t) );
            if( !buf )
                return -2;
            memcpy( buf, slot->buf, used * sizeof(uint32_t) );
            x264_free( slot->buf );
            slot->buf = buf;
            slot->i_size = size;
            h->cabac.p_tape = buf + used;
        }

        x264_macroblock_cache_load_progressive( h, x, y );
        x264_macroblock_analyse( h );
        x264_macroblock_encode( h );

        int mb_xy = y * h->mb.i_mb_stride + x;
        int b_skip = IS_SKIP( h->mb.i_type );
        int b_dqp = !b_skip && (h->mb.i_cbp_luma || (!CHROMA444 && h->mb.i_cbp_chroma) || h->mb.i_type == I_16x16);
        int b_i16_empty = h->mb.i_type == I_16x16 && !h->mb.cbp[mb_xy];
        x264_cabac_wf_special( &h->cabac, X264_WF_MB, h->mb.i_qp | b_dqp << 8 | b_i16_empty << 9
                                                      | (mb_xy > h->sh.i_first_mb) << 10 );
        if( b_skip )
            x264_cabac_mb_skip_wf( h, 1 );
        else
        {
            if( h->sh.i_type != SLICE_TYPE_I )
                x264_cabac_mb_skip_wf( h, 0 );
            x264_macroblock_write_cabac_wf( h, &h->cabac );
        }

        x264_macroblock_cache_save( h );
        h->i_wf_intra += IS_INTRA( h->mb.i_type );
        x264_slice_mb_stats( h );
        if( b_deblock )
            x264_macroblock_deblock_strength( h );

        if( x == w - 1 )
            slot->i_len = h->cabac.p_tape - slot->buf;
        x264_wf_publish( wf, y, x + 1 );
    }
    return 0;
}

/* A row worker: rows until the slice is coded. */
static intptr_t x264_wf_rows( x264_t *h, int idx )
{
    x264_wf_t *wf = h->wf;
    int *rows = wf->worker_rows + idx * wf->i_rows;

    memset( &h->stat.frame, 0, sizeof(h->stat.frame) );
    h->mb.b_fenc_bot = 0;
    x264_macroblock_thread_init( h );
    /* rd and trellis see the states of the slice start */
    x264_cabac_context_init( h, &h->cabac, h->sh.i_type, x264_clip3( h->sh.i_qp-QP_BD_OFFSET, 0, 51 ), h->sh.i_cabac_init_idc );

    x264_pthread_mutex_lock( &wf->mutex );
    while( !wf->b_done && !wf->b_fail )
    {
        int y = wf->i_next;
        if( !wf->b_rollback && y < wf->i_rows && y < wf->i_decided && y < wf->i_coded + wf->i_slots )
        {
            int gen = wf->i_gen;
            wf->i_next++;
            wf->i_active++;
            rows[wf->worker_n[idx]++] = y;
            x264_pthread_mutex_unlock( &wf->mutex );
            wf->stat_bak[y] = h->stat.frame;
            int ret = x264_wf_row( h, wf, y, gen );
            x264_pthread_mutex_lock( &wf->mutex );
            if( ret < -1 )
                wf->b_fail = 1;
            wf->i_active--;
            x264_pthread_cond_broadcast( &wf->cv );
            continue;
        }
        x264_pthread_cond_wait( &wf->cv, &wf->mutex );
    }
    x264_pthread_mutex_unlock( &wf->mutex );
    for( int j = 0; j < 2; j++ )
        for( int p = 0; p < 3; p++ )
            h->intra_border_backup[j][p] = wf->own_border[(idx*2+j)*3+p];
    return 0;
}

/* Rows from y again, at qpm and emergency step emerg: the workers leave their rows
 * and their stats go back to the start of the first of them they took. */
static void x264_wf_rollback( x264_wf_t *wf, int y, float qpm, int emerg )
{
    x264_t *h0 = wf->coder->thread[0];
    x264_pthread_mutex_lock( &wf->mutex );
    wf->i_gen++;
    wf->b_rollback = 1;
    x264_pthread_cond_broadcast( &wf->cv );
    while( wf->i_active )
        x264_pthread_cond_wait( &wf->cv, &wf->mutex );
    for( int i = 0; i < wf->i_workers; i++ )
    {
        int *rows = wf->worker_rows + i * wf->i_rows;
        for( int k = 0; k < wf->worker_n[i]; k++ )
            if( rows[k] >= y )
            {
                h0->thread[i]->stat.frame = wf->stat_bak[rows[k]];
                wf->worker_n[i] = k;
                break;
            }
    }
    for( int i = y; i < wf->i_rows; i++ )
    {
        WF_STORE_SC( &wf->done[i], 0 );
        WF_STORE_SC( &wf->want[i], INT_MAX );
    }
    wf->i_next = y;
    wf->b_rollback = 0;
    wf->i_decided = X264_MIN( y + wf->i_lag, wf->i_rows );
    for( int i = y; i < wf->i_decided; i++ )
    {
        wf->row_qpm[i] = qpm;
        wf->row_emerg[i] = emerg;
    }
    x264_pthread_cond_broadcast( &wf->cv );
    x264_pthread_mutex_unlock( &wf->mutex );
}

/* mb_qp_delta as x264_cabac_qp_delta codes it */
static void x264_wf_qp_delta( x264_cabac_t *cb, int i_dqp, int ctx )
{
    if( i_dqp != 0 )
    {
        i_dqp *= 2;
        int val = 1 - i_dqp;
        if( val < 0 ) val = i_dqp;
        val--;
        /* dqp is interpreted modulo (QP_MAX_SPEC+1) */
        if( val >= QP_MAX_SPEC && val != QP_MAX_SPEC+1 )
            val = 2*QP_MAX_SPEC+1 - val;
        do
        {
            x264_cabac_encode_decision_c( cb, 60 + ctx, 1 );
            ctx = 2+(ctx>>1);
        } while( --val );
    }
    x264_cabac_encode_decision_c( cb, 60 + ctx, 0 );
}

/* Codes row y's tape. Each decision is resolved in place to state^bin with its
 * context's state, the tape format of x264_cabac_tape_drain, and coded by it in
 * runs between the specials that need the coder: the marks of the mv/tex bit
 * stats and mb_qp_delta. An MB's QP as the bitstream has it (without
 * mb_qp_delta the previous MB's, an empty I_16x16 no higher than it) goes to
 * mb.qp[] for the deblock. Returns the sum of the row's QPs. */
static int x264_wf_code_row( x264_t *c, x264_wf_t *wf, int y )
{
    x264_cabac_t *cb = &c->cabac;
    uint8_t *state = cb->state;
    x264_wf_slot_t *slot = &wf->slot[y % wf->i_slots];
    uint32_t *t = slot->buf;
    uint32_t *rd = t;
    uint32_t *end = t + slot->i_len;
    int mb_xy = y * c->mb.i_mb_stride - 1;
    int qp_sum = 0, dqp = 0, dqp_ctx = 0;
    int pos_hdr = 0, pos_tex = -1;

#define WF_DRAIN()\
    do {\
        c->bsf.cabac_tape_drain( cb, rd, t );\
        rd = t + 1;\
    } while( 0 )

    for( ; t < end; t++ )
    {
        uint32_t e = *t;
        int type = (e >> 10) & 3;
        if( type < 2 )
        {
            int ctx = e & 1023;
            int s = state[ctx];
            state[ctx] = x264_cabac_transition[s][type];
            *t = (s ^ type) | ((e >> 4) & 0xf00) | (e & 0xffff0000);
        }
        else if( type == 2 )
            *t = 0x80 | ((e >> 4) & 0xf00) | (e & 0xffff0000);
        else
        {
            int v = e >> 16;
            switch( e & 15 )
            {
                case X264_WF_TERM:
                    /* the terminal bin 0 is the decision on state 0 */
                    *t = 0;
                    break;
                case X264_WF_MB:
                {
                    if( pos_tex >= 0 )
                    {
                        c->bsf.cabac_tape_drain( cb, rd, t );
                        rd = t;
                        c->stat.frame.i_tex_bits += x264_cabac_pos( cb ) - pos_tex;
                        pos_tex = -1;
                    }
                    /* end_of_slice_flag 0, or nothing */
                    *t = v & 0x400 ? 0 : 0x80;
                    mb_xy++;
                    int qp = v & 0xff;
                    int last = c->mb.i_last_qp;
                    int eff = !(v & 0x100) || ((v & 0x200) && qp > last) ? last : qp;
                    dqp = eff - last;
                    dqp_ctx = c->mb.i_last_dqp && (c->mb.type[c->mb.i_mb_prev_xy] == I_16x16
                                                   || (c->mb.cbp[c->mb.i_mb_prev_xy]&0x3f));
                    c->mb.qp[mb_xy] = eff;
                    c->mb.i_last_dqp = dqp;
                    c->mb.i_last_qp = eff;
                    c->mb.i_mb_prev_xy = mb_xy;
                    qp_sum += eff;
                    break;
                }
                case X264_WF_HDR:
                    WF_DRAIN();
                    pos_hdr = x264_cabac_pos( cb );
                    break;
                case X264_WF_TEX:
                    WF_DRAIN();
                    pos_tex = x264_cabac_pos( cb );
                    c->stat.frame.i_mv_bits += pos_tex - pos_hdr;
                    break;
                case X264_WF_DQP:
                    WF_DRAIN();
                    x264_wf_qp_delta( cb, dqp, dqp_ctx );
                    break;
            }
        }
    }
    c->bsf.cabac_tape_drain( cb, rd, end );
#undef WF_DRAIN
    if( pos_tex >= 0 )
        c->stat.frame.i_tex_bits += x264_cabac_pos( cb ) - pos_tex;
    return qp_sum;
}

/* The coder: the slice NAL, the row ratecontrol, the deblock. */
static intptr_t x264_wf_code( x264_t *c )
{
    x264_wf_t *wf = c->wf;
    int w = wf->i_width;
    int rows = wf->i_rows;
    int b_vbv = !!c->param.rc.i_vbv_buffer_size;
    int skip = 0;
    x264_bs_bak_t bak;

    memset( &c->stat.frame, 0, sizeof(c->stat.frame) );
    c->rc = wf->rc;
    if( b_vbv )
        x264_ratecontrol_slices_start( c );
    c->i_threadslice_nal = c->out.i_nal;
    c->b_threadslice_escaped = 0;

    bs_realign( &c->out.bs );
    x264_nal_start( c, c->i_nal_type, c->i_nal_ref_idc );
    c->out.nal[c->out.i_nal].i_first_mb = c->sh.i_first_mb;
    int starting_bits = bs_pos( &c->out.bs );
    x264_slice_header_write( &c->out.bs, &c->sh, c->i_nal_ref_idc );
    bs_align_1( &c->out.bs );
    x264_cabac_context_init( c, &c->cabac, c->sh.i_type, x264_clip3( c->sh.i_qp-QP_BD_OFFSET, 0, 51 ), c->sh.i_cabac_init_idc );
    x264_cabac_encode_init( &c->cabac, c->out.bs.p, c->out.bs.p_end );
    if( b_vbv )
        x264_ratecontrol_slice_header( c, bs_pos( &c->out.bs ) - starting_bits );
    c->mb.i_last_qp = c->sh.i_qp;
    c->mb.i_last_dqp = 0;
    c->mb.i_mb_prev_xy = -1;
    c->mb.i_vbv_emerg = 0;

    for( int y = 0; y < rows; )
    {
        if( x264_wf_wait_row( wf, y, w, -1 ) < 0 )
            goto fail;
        if( x264_bitstream_check_buffer( c ) )
            goto fail;
        x264_bitstream_backup( c, &bak, 0, 1 );
        int prev_xy = c->mb.i_mb_prev_xy;
        int pos = x264_cabac_pos( &c->cabac );
        int qp_sum = x264_wf_code_row( c, wf, y );
        int bits = x264_cabac_pos( &c->cabac ) - pos;

        c->mb.i_mb_x = w - 1;
        c->mb.i_mb_y = y;
        int first_free = wf->i_decided;
        int ret = x264_ratecontrol_wf_row( c, y, bits, qp_sum, wf->row_qpm, wf->row_emerg, first_free );
        float qpm = x264_ratecontrol_wf_qpm( c );
        if( ret < 0 )
        {
            x264_bitstream_restore( c, &bak, &skip, 1 );
            c->mb.i_mb_prev_xy = prev_xy;
            x264_log( c, X264_LOG_DEBUG, "wavefront: frame %d row %d again at qp %.2f step %d\n",
                      c->fenc->i_frame, y, qpm, c->mb.i_vbv_emerg );
            x264_wf_rollback( wf, y, qpm, c->mb.i_vbv_emerg );
            continue;
        }
        if( ret > 0 )
        {
            x264_log( c, X264_LOG_DEBUG, "wavefront: frame %d rows from %d again at qp %.2f step %d\n",
                      c->fenc->i_frame, y+1, qpm, c->mb.i_vbv_emerg );
            x264_wf_rollback( wf, y+1, qpm, c->mb.i_vbv_emerg );
        }

        x264_pthread_mutex_lock( &wf->mutex );
        wf->i_coded = y + 1;
        if( !ret && first_free < rows )
        {
            wf->row_qpm[first_free] = qpm;
            wf->row_emerg[first_free] = c->mb.i_vbv_emerg;
            wf->i_decided = first_free + 1;
        }
        x264_pthread_cond_broadcast( &wf->cv );
        x264_pthread_mutex_unlock( &wf->mutex );

        x264_fdec_filter_row( c, y + 1, 3 );
        x264_pthread_mutex_lock( &wf->mutex );
        wf->i_deblocked = y + 1;
        x264_pthread_cond_broadcast( &wf->cv );
        x264_pthread_mutex_unlock( &wf->mutex );
        y++;
    }

    x264_cabac_encode_flush( c, &c->cabac );
    c->out.bs.p = c->cabac.p;
    c->out.nal[c->out.i_nal].i_last_mb = c->sh.i_last_mb;
    if( x264_nal_end( c ) )
        goto fail;
    c->stat.frame.i_misc_bits = bs_pos( &c->out.bs )
                              + (c->out.i_nal*NALU_OVERHEAD * 8)
                              - c->stat.frame.i_tex_bits
                              - c->stat.frame.i_mv_bits;
    if( !c->param.nalu_process && !c->param.i_avcintra_class )
        x264_threadslice_escape_nals( c );

    x264_pthread_mutex_lock( &wf->mutex );
    wf->b_done = 1;
    x264_pthread_cond_broadcast( &wf->cv );
    x264_pthread_mutex_unlock( &wf->mutex );
    return 0;
fail:
    x264_pthread_mutex_lock( &wf->mutex );
    wf->b_fail = 1;
    x264_pthread_cond_broadcast( &wf->cv );
    x264_pthread_mutex_unlock( &wf->mutex );
    return -1;
}

/* hpel and the borders of band of bands once its rows are deblocked, as a thread
 * slice's passes 1 and 2: the first row's hpel reads the borders of the band above */
static void x264_wf_hpel_band( x264_t *h, int band, int bands )
{
    x264_wf_t *wf = h->wf;
    int y0 = wf->i_rows * band / bands;
    int y1 = wf->i_rows * (band+1) / bands;
    x264_pthread_mutex_lock( &wf->mutex );
    while( wf->i_deblocked < y1 && !wf->b_fail )
        x264_pthread_cond_wait( &wf->cv, &wf->mutex );
    int b_fail = wf->b_fail;
    x264_pthread_mutex_unlock( &wf->mutex );
    if( !b_fail && y0 < y1 )
    {
        h->i_threadslice_start = y0;
        h->i_threadslice_end = y1;
        for( int mb_y = y0 + 1; mb_y <= y1; mb_y++ )
            x264_fdec_filter_row( h, mb_y, 1 );
    }
    x264_pthread_mutex_lock( &wf->mutex );
    wf->band_done[band] = 1;
    x264_pthread_cond_broadcast( &wf->cv );
    while( band && !wf->band_done[band-1] )
        x264_pthread_cond_wait( &wf->cv, &wf->mutex );
    x264_pthread_mutex_unlock( &wf->mutex );
    if( !b_fail && y0 < y1 && y0 )
        x264_fdec_filter_row( h, y0 + 1, 2 );
}

/* Slice pool worker idx: rows (idx > 0) or the coder (0), then an hpel band. */
static intptr_t x264_wf_pool_job( x264_t *h, int idx, x264_t *snap, struct x264_slicepool_t *pool )
{
    x264_wf_t *wf = h->wf;
    int bands = h->param.i_threads;
    intptr_t ret;
    if( idx )
    {
        x264_threadslice_sync( h, snap );
        x264_stack_align( x264_slicepool_weight, h, pool );
        ret = (intptr_t)x264_stack_align( x264_wf_rows, h, idx );
        x264_stack_align( x264_wf_hpel_band, h, idx - 1, bands );
    }
    else
    {
        ret = (intptr_t)x264_stack_align( x264_wf_code, wf->coder );
        x264_stack_align( x264_wf_hpel_band, wf->coder, bands - 1, bands );
    }
    return ret;
}

static int x264_wf_frame( x264_t *h )
{
    x264_wf_t *wf = h->wf;
    x264_t *c = wf->coder;
    int rows = h->mb.i_mb_height;
    int threads = h->param.i_threads;

    for( int i = 0; i < threads; i++ )
    {
        h->thread[i]->i_threadslice_start = 0;
        h->thread[i]->i_threadslice_end = rows;
    }
    h->sh.i_first_mb = 0;
    h->sh.i_last_mb = rows * h->mb.i_mb_width - 1;
    /* the slice QP before the snapshot: the workers' cabac states start from it */
    h->mb.i_mb_xy = 0;
    h->sh.i_qp = SPEC_QP( x264_ratecontrol_mb_qp( h ) );
    h->sh.i_qp_delta = h->sh.i_qp - h->pps->i_pic_init_qp;
    x264_slicepool_snapshot( h );
    x264_slicepool_weight_init( h );

    c->i_threadslice_start = 0;
    c->i_threadslice_end = rows;
    x264_threadslice_sync( c, h->slicepool->snap );
    /* a short start code after thread 0's NALs */
    c->i_thread_idx = h->out.i_nal > 0;
    bs_init( &c->out.bs, c->out.p_bitstream, c->out.i_bitstream );
    c->out.i_nal = 0;

    float qpm = x264_ratecontrol_wf_qpm( h );
    wf->i_next = wf->i_coded = wf->i_deblocked = wf->i_active = 0;
    wf->b_done = wf->b_fail = wf->b_rollback = 0;
    wf->i_decided = h->param.rc.i_vbv_buffer_size ? X264_MIN( wf->i_lag, rows ) : rows;
    for( int y = 0; y < rows; y++ )
    {
        wf->done[y] = 0;
        wf->want[y] = INT_MAX;
        wf->row_qpm[y] = qpm;
        wf->row_emerg[y] = 0;
    }
    for( int i = 0; i < threads; i++ )
    {
        wf->worker_n[i] = 0;
        wf->band_done[i] = 0;
    }
    /* thread 0 is a row worker meanwhile; the coder has the frame's ratecontrol */
    wf->rc = h->rc;
    h->rc = wf->rc_qpm;

    for( int i = 0; i < threads; i++ )
    {
        h->thread[i]->i_thread_idx = i;
        h->thread[i]->b_thread_active = 1;
    }
    for( int i = 1; i < threads; i++ )
        x264_slicepool_run( h->slicepool, i );
    x264_slicepool_run( h->slicepool, 0 );
    x264_stack_align( x264_slicepool_weight, h, h->slicepool );
    x264_stack_align( x264_wf_rows, h, 0 );

    x264_pthread_mutex_lock( &wf->mutex );
    while( !wf->b_done && !wf->b_fail )
        x264_pthread_cond_wait( &wf->cv, &wf->mutex );
    int b_fail = wf->b_fail;
    x264_pthread_mutex_unlock( &wf->mutex );
    h->rc = wf->rc;
    if( b_fail )
        return -1;

    /* thread 0's NALs before the slice */
    h->stat.frame.i_misc_bits += bs_pos( &h->out.bs ) + h->out.i_nal * NALU_OVERHEAD * 8;
    h->b_nal_escaped = 0;
    if( !h->param.nalu_process && !h->param.i_avcintra_class )
    {
        if( !c->b_threadslice_escaped )
            return -1;
        h->i_nal_escaped = h->out.i_nal;
        h->i_nal_escaped_raw = c->i_threadslice_raw;
        h->b_nal_escaped = 1;
    }
    for( int j = 0; j < c->out.i_nal; j++ )
    {
        h->out.nal[h->out.i_nal] = c->out.nal[j];
        h->out.i_nal++;
        if( x264_nal_check_buffer( h ) )
            return -1;
    }

    for( int i = 1; i <= threads; i++ )
    {
        x264_t *t = i < threads ? h->thread[i] : c;
        /* All entries in stat.frame are ints except for ssd/ssim. */
        for( int j = 0; j < (offsetof(x264_t,stat.frame.i_ssd) - offsetof(x264_t,stat.frame.i_mv_bits)) / sizeof(int); j++ )
            ((int*)&h->stat.frame)[j] += ((int*)&t->stat.frame)[j];
        for( int j = 0; j < 3; j++ )
            h->stat.frame.i_ssd[j] += t->stat.frame.i_ssd[j];
        h->stat.frame.f_ssim += t->stat.frame.f_ssim;
        h->stat.frame.i_ssim_cnt += t->stat.frame.i_ssim_cnt;
    }
    return 0;
}

#else
static int x264_wf_init( x264_t *h ) { return -1; }
static void x264_wf_delete( x264_t *h ) {}
static int x264_wf_frame( x264_t *h ) { return -1; }
#endif
