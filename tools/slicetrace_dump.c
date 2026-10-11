/*****************************************************************************
 * slicetrace_dump.c: text dumper for X264_SLICETRACE phase timelines
 *****************************************************************************
 * Standalone host tool, not part of the x264 build:
 *     cc -O2 -o slicetrace_dump tools/slicetrace_dump.c -lm
 *     ./slicetrace_dump [-s] [-r] [slicetrace.bin]
 *         -s  summary only (no per-frame blocks)
 *         -r  omit per-row cycles from the per-frame blocks
 *
 * Per frame: serial prologue points, per-slice start/end/rows/row cycles,
 * main-thread wakes, frame_end points, hpel pass1/pass2 ends. Times are us
 * relative to that call's x264_encoder_encode entry; row costs are kcycles.
 * Summary: per-phase stats, prologue share, slice imbalance,
 * dispatch->slice-start latency per slice, last-slice-end->main-wake latency.
 *****************************************************************************/

#define X264_SLICETRACE_EVENTS 1
#include "../common/slicetrace.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

typedef struct
{
    uint64_t tsc;
    uint32_t seq;
    uint16_t frame;
    uint16_t arg;
    uint8_t  event;
    uint8_t  thread;
    uint16_t ring;
} ev_t;

typedef struct
{
    uint64_t sw_start, slice_start, slice_end, deblock_end;
    uint64_t pass1_end, pass2_wait_end, pass2_end, sw_end;
    int first_row, last_row, nslices, nrows, reenc;
    int pend;               /* pending row + 1, 0 = none */
    uint64_t pend_tsc;
    uint64_t *rowcyc;       /* indexed by row - first_row */
    int rowcap;
} slice_t;

typedef struct
{
    uint64_t t[ST_EVENT_MAX];   /* first occurrence of each main-thread event, 0 = absent */
    int frame;                  /* encode frame (low 16 bits) from ST_LA_GET_START, -1 = none */
    uint64_t *disp;             /* per slice thread */
    uint64_t *wake;             /* per slice thread */
    slice_t *s;                 /* per slice thread */
    int la_fanouts, la_jobs;
    uint64_t la_fan_sum, la_fan_first, la_fan_last, la_pend, la_job_max;
} call_t;

typedef struct
{
    double *v;
    int n, cap;
} vec_t;

static double tpu;  /* tsc ticks per microsecond */

static void *xcalloc( size_t n, size_t sz )
{
    void *p = calloc( n ? n : 1, sz );
    if( !p )
    {
        fprintf( stderr, "out of memory\n" );
        exit( 1 );
    }
    return p;
}

static void vpush( vec_t *v, double x )
{
    if( v->n == v->cap )
    {
        v->cap = v->cap ? v->cap * 2 : 256;
        v->v = realloc( v->v, v->cap * sizeof(double) );
        if( !v->v )
        {
            fprintf( stderr, "out of memory\n" );
            exit( 1 );
        }
    }
    v->v[v->n++] = x;
}

static int cmp_d( const void *a, const void *b )
{
    double x = *(const double*)a;
    double y = *(const double*)b;
    return x < y ? -1 : x > y;
}

static double pct( const double *s, int n, double q )
{
    int i = (int)ceil( q * n ) - 1;
    if( i < 0 )
        i = 0;
    if( i >= n )
        i = n - 1;
    return s[i];
}

static void vstat( const char *name, const vec_t *v, const char *unit )
{
    if( !v->n )
    {
        printf( "  %-36s n=0\n", name );
        return;
    }
    double *s = xcalloc( v->n, sizeof(double) );
    memcpy( s, v->v, v->n * sizeof(double) );
    qsort( s, v->n, sizeof(double), cmp_d );
    double sum = 0;
    for( int i = 0; i < v->n; i++ )
        sum += s[i];
    printf( "  %-36s n=%-6d mean=%10.2f p50=%10.2f p99=%10.2f max=%10.2f %s\n",
            name, v->n, sum / v->n, pct( s, v->n, 0.50 ), pct( s, v->n, 0.99 ), s[v->n-1], unit );
    free( s );
}

static int cmp_ev( const void *a, const void *b )
{
    const ev_t *x = a;
    const ev_t *y = b;
    if( x->tsc != y->tsc )
        return x->tsc < y->tsc ? -1 : 1;
    if( x->ring != y->ring )
        return x->ring < y->ring ? -1 : 1;
    return x->seq < y->seq ? -1 : x->seq > y->seq;
}

/* b - a in us, signed */
static double us( uint64_t a, uint64_t b )
{
    return (double)(int64_t)(b - a) / tpu;
}

static void prt( const char *name, uint64_t t, uint64_t base )
{
    if( t && base )
        printf( " %s=%+.1f", name, us( base, t ) );
    else
        printf( " %s=-", name );
}

static void row_close( slice_t *s, uint64_t tsc )
{
    if( s->pend && s->rowcyc )
    {
        int r = s->pend - 1 - s->first_row;
        if( r >= 0 && r < s->rowcap )
            s->rowcyc[r] += tsc - s->pend_tsc;
    }
    s->pend = 0;
}

/* Ordered timeline points of one call; phases are consecutive pairs. */
enum
{
    P_ENTRY, P_COPY, P_AQ, P_LOWRES, P_LA_START, P_LA_END, P_WAITALL, P_RC_START,
    P_TSW, P_SYNC, P_DISP0, P_DISPN, P_WAKEN, P_MERGE, P_TSW_END, P_FE_START,
    P_ENCAP, P_FE_END, P_MAX
};
static const char *const pname[P_MAX] =
{
    "entry", "copy", "aq", "lowres", "la_get_start", "la_get_end", "waitall", "rc_start",
    "tsw_start", "tsw_sync", "dispatch0", "dispatchN", "wakeN", "merge_rc", "tsw_end", "fe_start",
    "encap", "fe_end"
};

int main( int argc, char **argv )
{
    int summary_only = 0;
    int no_rows = 0;
    const char *path = "slicetrace.bin";
    for( int i = 1; i < argc; i++ )
    {
        if( !strcmp( argv[i], "-s" ) )
            summary_only = 1;
        else if( !strcmp( argv[i], "-r" ) )
            no_rows = 1;
        else if( argv[i][0] == '-' )
        {
            fprintf( stderr, "usage: %s [-s] [-r] [slicetrace.bin]\n", argv[0] );
            return 1;
        }
        else
            path = argv[i];
    }

    FILE *f = fopen( path, "rb" );
    if( !f )
    {
        perror( path );
        return 1;
    }
    x264_slicetrace_file_t hdr;
    if( fread( &hdr, sizeof(hdr), 1, f ) != 1 || memcmp( hdr.magic, ST_FILE_MAGIC, 8 ) ||
        hdr.version != ST_FILE_VERSION || hdr.rec_size != sizeof(x264_slicetrace_rec_t) )
    {
        fprintf( stderr, "%s: not a slicetrace v%d file\n", path, ST_FILE_VERSION );
        return 1;
    }
    if( hdr.us1 > hdr.us0 && hdr.tsc1 > hdr.tsc0 )
        tpu = (double)(hdr.tsc1 - hdr.tsc0) / (double)(hdr.us1 - hdr.us0);
    else
    {
        fprintf( stderr, "warning: no usable tsc calibration, assuming 1 GHz\n" );
        tpu = 1000.0;
    }

    ev_t *ev = NULL;
    size_t nev = 0;
    uint64_t t_valid = 0;
    for( uint32_t r = 0; r < hdr.nrings; r++ )
    {
        x264_slicetrace_ring_file_t rh;
        if( fread( &rh, sizeof(rh), 1, f ) != 1 )
        {
            fprintf( stderr, "%s: truncated at ring %u header\n", path, r );
            return 1;
        }
        if( !rh.n )
            continue;
        ev = realloc( ev, (nev + rh.n) * sizeof(ev_t) );
        if( !ev )
        {
            fprintf( stderr, "out of memory\n" );
            return 1;
        }
        for( uint64_t i = 0; i < rh.n; i++ )
        {
            x264_slicetrace_rec_t rec;
            if( fread( &rec, sizeof(rec), 1, f ) != 1 )
            {
                fprintf( stderr, "%s: truncated in ring %u\n", path, r );
                return 1;
            }
            ev_t *e = &ev[nev++];
            e->tsc    = rec.tsc;
            e->seq    = (uint32_t)i;
            e->frame  = rec.frame;
            e->arg    = rec.arg;
            e->event  = rec.event;
            e->thread = rec.thread;
            e->ring   = (uint16_t)r;
            /* A wrapped ring only covers the tail of the run: ignore calls before its oldest record. */
            if( !i && rh.pos > rh.n && rec.tsc > t_valid )
                t_valid = rec.tsc;
        }
        if( rh.pos > rh.n )
            fprintf( stderr, "note: ring %u wrapped, %llu oldest records lost\n",
                     r, (unsigned long long)(rh.pos - rh.n) );
    }
    fclose( f );
    if( hdr.nthreads_seen > hdr.nrings )
        fprintf( stderr, "note: %u threads asked for a ring, only %u had one; their stamps are missing\n",
                 hdr.nthreads_seen, hdr.nrings );
    if( !nev )
    {
        fprintf( stderr, "%s: no records\n", path );
        return 1;
    }
    qsort( ev, nev, sizeof(ev_t), cmp_ev );

    int nthr = hdr.i_threads > 0 ? (int)hdr.i_threads : 1;
    if( nthr > ST_THREAD_LA_JOB )
        nthr = ST_THREAD_LA_JOB;
    int mbh = hdr.i_mb_height > 0 ? (int)hdr.i_mb_height : 1;

    int ncalls = 0;
    for( size_t i = 0; i < nev; i++ )
        if( ev[i].thread == ST_THREAD_MAIN && ev[i].event == ST_ENTRY )
            ncalls++;
    call_t *calls = xcalloc( ncalls, sizeof(call_t) );
    for( int k = 0; k < ncalls; k++ )
    {
        calls[k].frame = -1;
        calls[k].disp = xcalloc( nthr, sizeof(uint64_t) );
        calls[k].wake = xcalloc( nthr, sizeof(uint64_t) );
        calls[k].s = xcalloc( nthr, sizeof(slice_t) );
    }
    uint64_t *job_pend = xcalloc( hdr.nrings, sizeof(uint64_t) );

    /* Single pass in tsc order: calls are opened by ST_ENTRY; slice events are
     * matched to the latest recent call with the same frame whose anchor
     * (tsw_start, or rc_start without sliced threads) precedes them. */
    int cur = -1;
    long unmatched = 0;
    for( size_t i = 0; i < nev; i++ )
    {
        ev_t *e = &ev[i];
        if( e->thread == ST_THREAD_MAIN )
        {
            if( e->event == ST_ENTRY )
            {
                cur++;
                calls[cur].t[ST_ENTRY] = e->tsc;
                continue;
            }
            if( cur < 0 )
                continue;
            call_t *c = &calls[cur];
            if( e->event == ST_DISPATCH || e->event == ST_WAKE )
            {
                uint64_t *a = e->event == ST_DISPATCH ? c->disp : c->wake;
                if( e->arg < nthr && !a[e->arg] )
                    a[e->arg] = e->tsc;
            }
            else if( e->event < ST_EVENT_MAX && !c->t[e->event] )
            {
                c->t[e->event] = e->tsc;
                if( e->event == ST_LA_GET_START )
                    c->frame = e->frame;
            }
            continue;
        }
        if( e->thread == ST_THREAD_LA || e->thread == ST_THREAD_LA_JOB )
        {
            if( cur < 0 )
                continue;
            call_t *c = &calls[cur];
            switch( e->event )
            {
                case ST_LA_FANOUT_START:
                    c->la_pend = e->tsc;
                    if( !c->la_fan_first )
                        c->la_fan_first = e->tsc;
                    break;
                case ST_LA_FANOUT_END:
                    if( c->la_pend )
                    {
                        c->la_fan_sum += e->tsc - c->la_pend;
                        c->la_fanouts++;
                        c->la_pend = 0;
                    }
                    c->la_fan_last = e->tsc;
                    break;
                case ST_LA_JOB_START:
                    job_pend[e->ring] = e->tsc;
                    break;
                case ST_LA_JOB_END:
                    if( job_pend[e->ring] )
                    {
                        uint64_t d = e->tsc - job_pend[e->ring];
                        if( d > c->la_job_max )
                            c->la_job_max = d;
                        c->la_jobs++;
                        job_pend[e->ring] = 0;
                    }
                    break;
                default:
                    break;
            }
            continue;
        }

        if( e->thread >= nthr )
        {
            unmatched++;
            continue;
        }
        call_t *c = NULL;
        for( int k = cur; k >= 0 && k > cur - 8; k-- )
        {
            uint64_t anchor = calls[k].t[ST_TSW_START] ? calls[k].t[ST_TSW_START] : calls[k].t[ST_RC_START];
            if( anchor && anchor <= e->tsc && calls[k].frame == e->frame )
            {
                c = &calls[k];
                break;
            }
        }
        if( !c )
        {
            unmatched++;
            continue;
        }
        slice_t *s = &c->s[e->thread];
        switch( e->event )
        {
            case ST_SW_START:
                if( !s->sw_start )
                    s->sw_start = e->tsc;
                break;
            case ST_SLICE_START:
                if( !s->slice_start )
                {
                    s->slice_start = e->tsc;
                    s->first_row = e->arg;
                }
                s->nslices++;
                if( !s->rowcyc )
                {
                    s->rowcap = mbh - s->first_row;
                    if( s->rowcap < 1 )
                        s->rowcap = 1;
                    s->rowcyc = xcalloc( s->rowcap, sizeof(uint64_t) );
                }
                break;
            case ST_ROW_START:
                row_close( s, e->tsc );
                s->pend = (e->arg & 0x7FFF) + 1;
                s->pend_tsc = e->tsc;
                if( !(e->arg & ST_ARG_REENCODE) )
                    s->nrows++;
                break;
            case ST_VBV_REENCODE:
                s->reenc++;
                break;
            case ST_SLICE_END:
                row_close( s, e->tsc );
                s->slice_end = e->tsc;
                s->last_row = e->arg;
                break;
            case ST_DEBLOCK_END:
                s->deblock_end = e->tsc;
                break;
            case ST_PASS1_END:
                s->pass1_end = e->tsc;
                break;
            case ST_PASS2_WAIT_END:
                s->pass2_wait_end = e->tsc;
                break;
            case ST_PASS2_END:
                s->pass2_end = e->tsc;
                break;
            case ST_SW_END:
                s->sw_end = e->tsc;
                break;
            default:
                break;
        }
    }

    vec_t v_phase[P_MAX] = {{0}};
    vec_t v_wall = {0}, v_period = {0}, v_pro = {0}, v_share = {0};
    vec_t v_imb = {0}, v_imb_us = {0}, v_lastwake = {0}, v_tail = {0};
    vec_t v_lafan = {0}, v_lajob = {0};
    vec_t *v_disp = xcalloc( nthr, sizeof(vec_t) );
    vec_t *v_work = xcalloc( nthr, sizeof(vec_t) );
    int nframes = 0, fr_reenc = 0, skipped = 0;
    long tot_reenc = 0;

    for( int k = 0; k <= cur; k++ )
    {
        call_t *c = &calls[k];
        uint64_t en = c->t[ST_ENTRY];
        if( c->frame < 0 )
            continue;
        if( en < t_valid )
        {
            skipped++;
            continue;
        }
        int sliced = c->t[ST_TSW_START] != 0;
        nframes++;

        uint64_t dispn = 0, waken = 0, end_max = 0, hpel_max = 0;
        for( int t = 0; t < nthr; t++ )
        {
            if( c->disp[t] > dispn )
                dispn = c->disp[t];
            if( c->wake[t] > waken )
                waken = c->wake[t];
            if( c->s[t].deblock_end > end_max )
                end_max = c->s[t].deblock_end;
            if( c->s[t].pass1_end > hpel_max )
                hpel_max = c->s[t].pass1_end;
            if( c->s[t].pass2_end > hpel_max )
                hpel_max = c->s[t].pass2_end;
        }

        uint64_t P[P_MAX];
        P[P_ENTRY]    = en;
        P[P_COPY]     = c->t[ST_COPY_END];
        P[P_AQ]       = c->t[ST_AQ_END];
        P[P_LOWRES]   = c->t[ST_LOWRES_END];
        P[P_LA_START] = c->t[ST_LA_GET_START];
        P[P_LA_END]   = c->t[ST_LA_GET_END];
        P[P_WAITALL]  = c->t[ST_WAITALL_END];
        P[P_RC_START] = c->t[ST_RC_START];
        P[P_TSW]      = c->t[ST_TSW_START];
        P[P_SYNC]     = c->t[ST_TSW_SYNC_END];
        P[P_DISP0]    = c->disp[0];
        P[P_DISPN]    = dispn;
        P[P_WAKEN]    = waken;
        P[P_MERGE]    = c->t[ST_MERGE_RC_END];
        P[P_TSW_END]  = c->t[ST_TSW_END];
        P[P_FE_START] = c->t[ST_FE_START];
        P[P_ENCAP]    = c->t[ST_FE_ENCAP_END];
        P[P_FE_END]   = c->t[ST_FE_END];

        if( !summary_only )
        {
            printf( "frame %d (call %d)%s", c->frame, k, sliced ? "" : " [not sliced]" );
            if( P[P_FE_END] )
                printf( " wall %.1f us", us( en, P[P_FE_END] ) );
            if( k < cur && calls[k+1].t[ST_ENTRY] )
                printf( " period %.1f us", us( en, calls[k+1].t[ST_ENTRY] ) );
            printf( "\n  prologue:" );
            prt( "copy", P[P_COPY], en );
            prt( "aq", P[P_AQ], en );
            prt( "lowres", P[P_LOWRES], en );
            prt( "la_get", P[P_LA_START], en );
            prt( "la_fan_start", c->la_fan_first, en );
            prt( "la_fan_end", c->la_fan_last, en );
            printf( " fanouts=%d fan_sum=%.1f jobs=%d job_max=%.1f",
                    c->la_fanouts, c->la_fan_sum / tpu, c->la_jobs, c->la_job_max / tpu );
            prt( "la_get_end", P[P_LA_END], en );
            prt( "waitall", P[P_WAITALL], en );
            prt( "rc_start", P[P_RC_START], en );
            prt( "tsw", P[P_TSW], en );
            prt( "sync", P[P_SYNC], en );
            prt( "disp0", P[P_DISP0], en );
            prt( "dispN", P[P_DISPN], en );
            printf( "\n" );
            for( int t = 0; t < nthr; t++ )
            {
                slice_t *s = &c->s[t];
                if( !s->sw_start && !s->slice_start )
                    continue;
                printf( "  slice %d: rows %d-%d n=%d slices=%d vbv_reenc=%d", t, s->first_row, s->last_row,
                        s->nrows, s->nslices, s->reenc );
                if( c->disp[t] && s->sw_start )
                    printf( " disp->start=%.1f", us( c->disp[t], s->sw_start ) );
                prt( "disp", c->disp[t], en );
                prt( "sw_start", s->sw_start, en );
                prt( "start", s->slice_start, en );
                prt( "end", s->slice_end, en );
                prt( "deblock", s->deblock_end, en );
                prt( "wake", c->wake[t], en );
                prt( "pass1", s->pass1_end, en );
                prt( "pass2_wait", s->pass2_wait_end, en );
                prt( "pass2", s->pass2_end, en );
                prt( "sw_end", s->sw_end, en );
                printf( "\n" );
                if( !no_rows && s->rowcyc )
                {
                    int nr = s->last_row >= s->first_row ? s->last_row - s->first_row + 1 : s->rowcap;
                    if( nr > s->rowcap )
                        nr = s->rowcap;
                    printf( "    row kcyc:" );
                    for( int r = 0; r < nr; r++ )
                        printf( " %.1f", s->rowcyc[r] / 1000.0 );
                    printf( "\n" );
                }
            }
            printf( "  main:" );
            for( int t = 0; t < nthr; t++ )
            {
                char nm[32];
                snprintf( nm, sizeof(nm), "wake%d", t );
                if( c->wake[t] )
                    prt( nm, c->wake[t], en );
            }
            prt( "merge_rc", P[P_MERGE], en );
            prt( "tsw_end", P[P_TSW_END], en );
            prt( "fe_start", P[P_FE_START], en );
            prt( "encap", P[P_ENCAP], en );
            prt( "fe_end", P[P_FE_END], en );
            printf( "\n" );
        }

        for( int p = 0; p + 1 < P_MAX; p++ )
            if( P[p] && P[p+1] )
                vpush( &v_phase[p], us( P[p], P[p+1] ) );
        if( P[P_FE_END] )
            vpush( &v_wall, us( en, P[P_FE_END] ) );
        if( k < cur && calls[k+1].t[ST_ENTRY] )
            vpush( &v_period, us( en, calls[k+1].t[ST_ENTRY] ) );
        uint64_t pro_end = sliced ? c->disp[0] : c->s[0].sw_start;
        if( pro_end )
        {
            vpush( &v_pro, us( en, pro_end ) );
            if( P[P_FE_END] && P[P_FE_END] > en )
                vpush( &v_share, 100.0 * us( en, pro_end ) / us( en, P[P_FE_END] ) );
        }
        if( c->la_fanouts )
            vpush( &v_lafan, c->la_fan_sum / tpu );
        if( c->la_jobs )
            vpush( &v_lajob, c->la_job_max / tpu );

        int reenc = 0;
        int nwork = 0, nstart = 0;
        double wsum = 0, wmax = 0;
        for( int t = 0; t < nthr; t++ )
        {
            slice_t *s = &c->s[t];
            reenc += s->reenc;
            if( c->disp[t] && s->sw_start )
                vpush( &v_disp[t], us( c->disp[t], s->sw_start ) );
            nstart += !!s->sw_start;
            if( s->sw_start && s->deblock_end )
            {
                double w = us( s->sw_start, s->deblock_end );
                vpush( &v_work[t], w );
                wsum += w;
                if( w > wmax )
                    wmax = w;
                nwork++;
            }
        }
        tot_reenc += reenc;
        fr_reenc += reenc > 0;
        if( sliced && nwork > 1 && nwork == nstart && wsum > 0 )
        {
            vpush( &v_imb, wmax / (wsum / nwork) );
            vpush( &v_imb_us, wmax - wsum / nwork );
        }
        if( waken && end_max )
            vpush( &v_lastwake, us( end_max, waken ) );
        if( waken && hpel_max )
            vpush( &v_tail, us( waken, hpel_max ) );
    }

    printf( "\nsummary: %d frames (%d calls, %d before wrapped-ring cutoff, %ld unmatched slice events)\n",
            nframes, cur + 1, skipped, unmatched );
    printf( "  tsc %.1f MHz, threads %u, lookahead threads %u, sliced %u, mb %ux%u, rings %u\n",
            tpu, hdr.i_threads, hdr.i_lookahead_threads, hdr.b_sliced_threads,
            hdr.i_mb_width, hdr.i_mb_height, hdr.nrings );
    printf( "  vbv row re-encodes: %ld in %d frames\n", tot_reenc, fr_reenc );
    printf( "phases (main thread, consecutive points):\n" );
    for( int p = 0; p + 1 < P_MAX; p++ )
    {
        char nm[64];
        snprintf( nm, sizeof(nm), "%s->%s", pname[p], pname[p+1] );
        vstat( nm, &v_phase[p], "us" );
    }
    printf( "frame:\n" );
    vstat( "wall entry->fe_end", &v_wall, "us" );
    vstat( "period entry->next entry", &v_period, "us" );
    vstat( "serial prologue entry->dispatch0", &v_pro, "us" );
    vstat( "serial prologue share of wall", &v_share, "%" );
    vstat( "lookahead fan-out sum per frame", &v_lafan, "us" );
    vstat( "lookahead job max per frame", &v_lajob, "us" );
    printf( "slices:\n" );
    vstat( "imbalance max/mean (sw_start->deblock)", &v_imb, "x" );
    vstat( "imbalance max-mean", &v_imb_us, "us" );
    vstat( "last slice end->main wake", &v_lastwake, "us" );
    vstat( "hpel tail past main wake", &v_tail, "us" );
    for( int t = 0; t < nthr; t++ )
    {
        char nm[64];
        snprintf( nm, sizeof(nm), "slice %d dispatch->start", t );
        vstat( nm, &v_disp[t], "us" );
    }
    for( int t = 0; t < nthr; t++ )
    {
        char nm[64];
        snprintf( nm, sizeof(nm), "slice %d work sw_start->deblock", t );
        vstat( nm, &v_work[t], "us" );
    }
    return 0;
}
