/*****************************************************************************
 * slicetrace.h: debug-only rdtsc phase timeline for sliced-thread encoding
 *****************************************************************************
 * Enabled only by -DX264_SLICETRACE=1. Each OS thread writes into its own
 * preallocated wrapping ring; no locks, no allocation, no I/O when stamping.
 * Rings are written to $X264_SLICETRACE_FILE (default slicetrace.bin) by
 * x264_encoder_close. Decode with tools/slicetrace_dump.c.
 *
 * Not templated: compiled once (common/slicetrace.c is in SRCS) and shared
 * by the 8-bit and 10-bit encoder objects.
 *****************************************************************************/

#ifndef X264_SLICETRACE_H
#define X264_SLICETRACE_H

#if X264_SLICETRACE || defined(X264_SLICETRACE_EVENTS)

#include <stdint.h>

/* Event ids. tools/slicetrace_dump.c includes this header with
 * X264_SLICETRACE_EVENTS defined; append new ids at the end. */
enum
{
    /* main (API) thread, x264_encoder_encode */
    ST_ENTRY = 1,           /* arg: pic_in != NULL */
    ST_COPY_END,            /* after x264_frame_copy_picture */
    ST_AQ_END,              /* after adaptive quant / mbtree read */
    ST_LOWRES_END,          /* after x264_frame_init_lowres */
    ST_LA_GET_START,        /* before x264_lookahead_get_frames */
    ST_LA_GET_END,          /* after x264_lookahead_get_frames */
    ST_WAITALL_END,         /* after x264_threadpool_wait_all */
    ST_RC_START,            /* before x264_ratecontrol_start */
    /* main thread, x264_threaded_slices_write */
    ST_TSW_START,
    ST_TSW_SYNC_END,        /* after per-thread context memcpy loop */
    ST_DISPATCH,            /* before threadpool_run, arg: slice thread index */
    ST_WAKE,                /* after cond wait 1, arg: slice thread index */
    ST_MERGE_RC_END,        /* after x264_threads_merge_ratecontrol */
    ST_TSW_END,
    /* main thread, x264_encoder_frame_end */
    ST_FE_START,
    ST_FE_ENCAP_END,        /* after x264_encoder_encapsulate_nals */
    ST_FE_END,
    /* slice threads, thread = h->i_thread_idx */
    ST_SW_START,            /* x264_slices_write entry, arg: i_threadslice_start */
    ST_SLICE_START,         /* x264_slice_write entry, arg: first mb row */
    ST_ROW_START,           /* arg: mb row, | ST_ARG_REENCODE if h->mb.b_reencode_mb */
    ST_VBV_REENCODE,        /* row VBV re-encode, arg: mb row */
    ST_SLICE_END,           /* after x264_nal_end, arg: last mb row */
    ST_DEBLOCK_END,         /* last deblock row done, just before cond broadcast 1 */
    ST_PASS1_END,           /* hpel pass 1 done, just before cond broadcast 2 */
    ST_PASS2_WAIT_END,      /* after cond wait 2 on the previous slice thread */
    ST_PASS2_END,           /* hpel pass 2 (first row) done */
    ST_SW_END,              /* x264_slices_write return, arg: i_threadslice_end */
    /* lookahead x264_slicetype_frame_cost fan-out */
    ST_LA_FANOUT_START,     /* dispatcher, arg: (b-p0)<<8 | (p1-b) */
    ST_LA_FANOUT_END,       /* dispatcher, after all waits */
    ST_LA_JOB_START,        /* pool job, arg: i_threadslice_start */
    ST_LA_JOB_END,          /* pool job, arg: i_threadslice_end */
    ST_EVENT_MAX
};

#define ST_ARG_REENCODE 0x8000

/* Values of the record's thread field for non-slice actors. */
#define ST_THREAD_MAIN    0xFF
#define ST_THREAD_LA      0xFE
#define ST_THREAD_LA_JOB  0xFD

/* On-disk record, native little-endian, 16 bytes. */
typedef struct
{
    uint64_t tsc;
    uint16_t frame;
    uint8_t  event;
    uint8_t  thread;
    uint16_t arg;
    uint16_t pad;
} x264_slicetrace_rec_t;

/* File: one file header, then per ring a ring header followed by n records,
 * oldest first. tsc0/us0 sampled at init, tsc1/us1 at dump (us: x264_mdate). */
#define ST_FILE_MAGIC   "X264STR1"
#define ST_FILE_VERSION 1

typedef struct
{
    char     magic[8];
    uint32_t version;
    uint32_t rec_size;
    uint32_t nrings;            /* ring headers that follow */
    uint32_t ring_log2;
    uint32_t i_threads;
    uint32_t i_lookahead_threads;
    uint32_t i_mb_width;
    uint32_t i_mb_height;
    uint32_t b_sliced_threads;
    uint32_t nthreads_seen;     /* OS threads that asked for a ring; > nrings means some were dropped */
    uint64_t tsc0;
    uint64_t tsc1;
    int64_t  us0;
    int64_t  us1;
} x264_slicetrace_file_t;

typedef struct
{
    uint32_t ring;
    uint32_t pad;
    uint64_t pos;               /* records ever written; pos > n means the ring wrapped */
    uint64_t n;                 /* records that follow */
} x264_slicetrace_ring_file_t;

#endif

#if X264_SLICETRACE

static inline uint64_t x264_slicetrace_rdtsc( void )
{
    uint32_t lo, hi;
    __asm__ __volatile__( "rdtsc" : "=a"(lo), "=d"(hi) );
    return ((uint64_t)hi << 32) | lo;
}

typedef struct
{
    x264_slicetrace_rec_t *rec;
    uint64_t pos;               /* records ever written; owned by one thread */
    uint8_t  pad[64 - sizeof(void*) - sizeof(uint64_t)];
} x264_slicetrace_ring_t;

extern x264_slicetrace_ring_t *x264_slicetrace_rings;
extern int      x264_slicetrace_nrings;
extern uint64_t x264_slicetrace_mask;
extern int      x264_slicetrace_gen;
extern __thread int x264_slicetrace_tls_ring __attribute__((tls_model("initial-exec")));
extern __thread int x264_slicetrace_tls_gen  __attribute__((tls_model("initial-exec")));

void x264_slicetrace_init( int i_threads, int i_lookahead_threads, int i_mb_width, int i_mb_height, int b_sliced_threads );
int  x264_slicetrace_assign( void );
void x264_slicetrace_dump( void );

static inline void x264_slicetrace_stamp( int event, int thread, int frame, int arg )
{
    int r = x264_slicetrace_tls_ring;
    if( x264_slicetrace_tls_gen != x264_slicetrace_gen )
        r = x264_slicetrace_assign();
    if( (unsigned)r >= (unsigned)x264_slicetrace_nrings )
        return;
    x264_slicetrace_ring_t *ring = &x264_slicetrace_rings[r];
    x264_slicetrace_rec_t *e = &ring->rec[ring->pos & x264_slicetrace_mask];
    ring->pos++;
    e->tsc    = x264_slicetrace_rdtsc();
    e->frame  = (uint16_t)frame;
    e->event  = (uint8_t)event;
    e->thread = (uint8_t)thread;
    e->arg    = (uint16_t)arg;
    e->pad    = 0;
}

#define SLICETRACE( event, thread, frame, arg ) x264_slicetrace_stamp( event, thread, frame, arg )

#else

#define SLICETRACE( event, thread, frame, arg ) do {} while( 0 )

#endif

#endif
