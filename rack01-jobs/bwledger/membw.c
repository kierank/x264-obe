/*****************************************************************************
 * membw.c: DRAM bandwidth calibration (read / write / copy / triad)
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

/* gcc -O2 -pthread -o membw membw.c
 * membw <threads> [MB per thread, default 256] [cpu list "0,2,4,..."]
 * Per kernel: best-of-5 GB/s over all threads, and the bytes the program moves
 * (plain stores: the DRAM sees about one more read per written line, RFO), so
 * IMC counter totals taken around a run calibrate against these. */
#define _GNU_SOURCE
#include <pthread.h>
#include <sched.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static int nthreads;
static size_t n;          /* uint64 per array */
static int cpus[256], ncpus;
static pthread_barrier_t bar;
static double t_start[8], t_end[8];
static uint64_t sink;

static double now( void )
{
    struct timespec t;
    clock_gettime( CLOCK_MONOTONIC, &t );
    return t.tv_sec + t.tv_nsec * 1e-9;
}

static void *worker( void *arg )
{
    int id = (int)(intptr_t)arg;
    if( ncpus )
    {
        cpu_set_t set;
        CPU_ZERO( &set );
        CPU_SET( cpus[id % ncpus], &set );
        pthread_setaffinity_np( pthread_self(), sizeof(set), &set );
    }
    uint64_t *a = aligned_alloc( 4096, n * 8 ), *b = aligned_alloc( 4096, n * 8 ), *c = aligned_alloc( 4096, n * 8 );
    for( size_t i = 0; i < n; i++ )
        a[i] = b[i] = c[i] = i;
    uint64_t s = 0;
    for( int k = 0; k < 4; k++ )
        for( int rep = 0; rep < 5; rep++ )
        {
            pthread_barrier_wait( &bar );
            if( !id )
                t_start[k] = now();
            switch( k )
            {
                case 0: for( size_t i = 0; i < n; i++ ) s += a[i]; break;                 /* read */
                case 1: for( size_t i = 0; i < n; i++ ) a[i] = rep; break;                /* write */
                case 2: for( size_t i = 0; i < n; i++ ) a[i] = b[i]; break;               /* copy */
                case 3: for( size_t i = 0; i < n; i++ ) a[i] = b[i] + 3*c[i]; break;      /* triad */
            }
            __asm__ volatile( "" ::: "memory" );
            pthread_barrier_wait( &bar );
            if( !id )
            {
                double t = now() - t_start[k];
                if( !rep || t < t_end[k] )
                    t_end[k] = t;
            }
        }
    __atomic_fetch_add( &sink, s, __ATOMIC_RELAXED );
    free( a ); free( b ); free( c );
    return NULL;
}

int main( int argc, char **argv )
{
    nthreads = argc > 1 ? atoi( argv[1] ) : 1;
    size_t mb = argc > 2 ? strtoul( argv[2], NULL, 10 ) : 256;
    if( argc > 3 )
        for( char *p = strtok( argv[3], "," ); p && ncpus < 256; p = strtok( NULL, "," ) )
            cpus[ncpus++] = atoi( p );
    n = mb * 1024 * 1024 / 8;
    pthread_barrier_init( &bar, NULL, nthreads );
    pthread_t th[256];
    for( int i = 0; i < nthreads; i++ )
        pthread_create( &th[i], NULL, worker, (void*)(intptr_t)i );
    for( int i = 0; i < nthreads; i++ )
        pthread_join( th[i], NULL );
    static const char *const name[4] = { "read", "write", "copy", "triad" };
    static const int rd[4] = { 1, 0, 1, 2 }, wr[4] = { 0, 1, 1, 1 };
    for( int k = 0; k < 4; k++ )
    {
        double bytes = (double)nthreads * n * 8;
        printf( "membw threads %d %-5s %8.2f GB/s program (rd %d + wr %d arrays); with RFO %8.2f GB/s; %.0f MB per pass\n",
                nthreads, name[k], bytes * (rd[k] + wr[k]) / t_end[k] / 1e9, rd[k], wr[k],
                bytes * (rd[k] + 2*wr[k]) / t_end[k] / 1e9, bytes * (rd[k] + wr[k]) / 1e6 );
    }
    return 0;
}
