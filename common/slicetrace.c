/*****************************************************************************
 * slicetrace.c: debug-only rdtsc phase timeline for sliced-thread encoding
 *****************************************************************************
 * Compiled once (SRCS), shared by both bit depths. Empty unless
 * -DX264_SLICETRACE=1. See slicetrace.h.
 *****************************************************************************/

#include "base.h"
#include "slicetrace.h"

#if X264_SLICETRACE

x264_slicetrace_ring_t *x264_slicetrace_rings;
int      x264_slicetrace_nrings;
uint64_t x264_slicetrace_mask;
int      x264_slicetrace_gen;
__thread int x264_slicetrace_tls_ring __attribute__((tls_model("initial-exec")));
__thread int x264_slicetrace_tls_gen  __attribute__((tls_model("initial-exec")));

static int st_next;
static x264_slicetrace_rec_t *st_rec;
static x264_slicetrace_file_t st_hdr;

void x264_slicetrace_init( int i_threads, int i_lookahead_threads, int i_mb_width, int i_mb_height, int b_sliced_threads )
{
    /* One live encoder per process. */
    if( x264_slicetrace_rings )
        return;

    int ring_log2 = 18;
    const char *s = getenv( "X264_SLICETRACE_RING_LOG2" );
    if( s && *s )
        ring_log2 = x264_clip3( atoi( s ), 10, 24 );
    /* slice pool + lookahead pool + API thread + sync lookahead thread + slack */
    int nrings = X264_MIN( i_threads + i_lookahead_threads + 4, 64 );
    size_t cap = (size_t)1 << ring_log2;

    x264_slicetrace_ring_t *rings = calloc( nrings, sizeof(x264_slicetrace_ring_t) );
    x264_slicetrace_rec_t *rec = malloc( nrings * cap * sizeof(x264_slicetrace_rec_t) );
    if( !rings || !rec )
    {
        free( rings );
        free( rec );
        fprintf( stderr, "x264 [slicetrace]: allocation failed, tracing disabled\n" );
        return;
    }
    /* Prefault so the hot path never takes a first-touch page fault. */
    memset( rec, 0, nrings * cap * sizeof(x264_slicetrace_rec_t) );
    for( int i = 0; i < nrings; i++ )
        rings[i].rec = rec + i * cap;

    memset( &st_hdr, 0, sizeof(st_hdr) );
    memcpy( st_hdr.magic, ST_FILE_MAGIC, 8 );
    st_hdr.version = ST_FILE_VERSION;
    st_hdr.rec_size = sizeof(x264_slicetrace_rec_t);
    st_hdr.ring_log2 = ring_log2;
    st_hdr.i_threads = i_threads;
    st_hdr.i_lookahead_threads = i_lookahead_threads;
    st_hdr.i_mb_width = i_mb_width;
    st_hdr.i_mb_height = i_mb_height;
    st_hdr.b_sliced_threads = b_sliced_threads;
    st_hdr.us0 = x264_mdate();
    st_hdr.tsc0 = x264_slicetrace_rdtsc();

    st_rec = rec;
    st_next = 0;
    x264_slicetrace_mask = cap - 1;
    x264_slicetrace_rings = rings;
    x264_slicetrace_nrings = nrings;
    /* Invalidates every thread's cached ring index. */
    x264_slicetrace_gen++;
}

int x264_slicetrace_assign( void )
{
    int r = __atomic_fetch_add( &st_next, 1, __ATOMIC_RELAXED );
    x264_slicetrace_tls_ring = r;
    x264_slicetrace_tls_gen = x264_slicetrace_gen;
    return r;
}

void x264_slicetrace_dump( void )
{
    if( !x264_slicetrace_rings )
        return;

    st_hdr.tsc1 = x264_slicetrace_rdtsc();
    st_hdr.us1 = x264_mdate();
    int nused = X264_MIN( st_next, x264_slicetrace_nrings );
    st_hdr.nrings = nused;
    st_hdr.nthreads_seen = st_next;

    const char *path = getenv( "X264_SLICETRACE_FILE" );
    if( !path || !*path )
        path = "slicetrace.bin";
    FILE *f = x264_fopen( path, "wb" );
    if( f )
    {
        uint64_t cap = x264_slicetrace_mask + 1;
        int ok = fwrite( &st_hdr, sizeof(st_hdr), 1, f ) == 1;
        for( int i = 0; i < nused && ok; i++ )
        {
            x264_slicetrace_ring_t *ring = &x264_slicetrace_rings[i];
            x264_slicetrace_ring_file_t rh;
            rh.ring = i;
            rh.pad = 0;
            rh.pos = ring->pos;
            rh.n = X264_MIN( ring->pos, cap );
            ok &= fwrite( &rh, sizeof(rh), 1, f ) == 1;
            uint64_t first = (ring->pos - rh.n) & x264_slicetrace_mask;
            uint64_t n1 = X264_MIN( rh.n, cap - first );
            uint64_t n2 = rh.n - n1;
            if( n1 )
                ok &= fwrite( ring->rec + first, sizeof(x264_slicetrace_rec_t), n1, f ) == n1;
            if( n2 )
                ok &= fwrite( ring->rec, sizeof(x264_slicetrace_rec_t), n2, f ) == n2;
        }
        ok &= fclose( f ) == 0;
        fprintf( stderr, "x264 [slicetrace]: %s %d rings (%d threads seen) to %s\n",
                 ok ? "wrote" : "FAILED writing", nused, st_next, path );
    }
    else
        fprintf( stderr, "x264 [slicetrace]: cannot open %s\n", path );

    free( st_rec );
    free( x264_slicetrace_rings );
    st_rec = NULL;
    x264_slicetrace_rings = NULL;
    x264_slicetrace_nrings = 0;
    x264_slicetrace_gen++;
}

#endif
