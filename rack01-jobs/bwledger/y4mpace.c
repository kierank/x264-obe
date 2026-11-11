/*****************************************************************************
 * y4mpace.c: copy a y4m file to stdout at its own frame rate
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

/* gcc -O2 -o y4mpace y4mpace.c; y4mpace clip.y4m [fps] | x264 --demuxer y4m - ...
 * Frame k is written at start + k/fps (absolute deadlines, no drift); a late
 * frame is written at once. 8-bit 4:2:0 / 4:2:2 / 4:4:4 from the C tag. */
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

int main( int argc, char **argv )
{
    if( argc < 2 )
    {
        fprintf( stderr, "usage: y4mpace clip.y4m [fps]\n" );
        return 1;
    }
    FILE *f = fopen( argv[1], "rb" );
    if( !f )
        return 1;
    char hdr[1024];
    if( !fgets( hdr, sizeof(hdr), f ) || strncmp( hdr, "YUV4MPEG2", 9 ) )
        return 1;
    int w = 0, h = 0, fn = 0, fd = 1;
    double num = 2.0, den = 2.0; /* bytes per luma pixel x 2: 4:2:0 = 3/2 */
    for( char *p = strtok( hdr, " \n" ); p; p = strtok( NULL, " \n" ) )
    {
        if( *p == 'W' ) w = atoi( p+1 );
        else if( *p == 'H' ) h = atoi( p+1 );
        else if( *p == 'F' ) sscanf( p+1, "%d:%d", &fn, &fd );
        else if( *p == 'C' )
            num = !strncmp( p+1, "422", 3 ) ? 4.0 : !strncmp( p+1, "444", 3 ) ? 6.0 : 3.0;
    }
    if( num == 2.0 )
        num = 3.0;
    double fps = argc > 2 ? atof( argv[2] ) : (double)fn / fd;
    size_t fsize = (size_t)(w * (size_t)h * num / den);
    if( !w || !h || fps <= 0 )
        return 1;
    /* re-emit the header as read */
    rewind( f );
    if( !fgets( hdr, sizeof(hdr), f ) )
        return 1;
    fputs( hdr, stdout );
    char *buf = malloc( fsize + 256 );
    struct timespec t0, t;
    clock_gettime( CLOCK_MONOTONIC, &t0 );
    for( long k = 0; ; k++ )
    {
        char line[256];
        if( !fgets( line, sizeof(line), f ) || strncmp( line, "FRAME", 5 ) )
            break;
        if( fread( buf, 1, fsize, f ) != fsize )
            break;
        double due = k / fps;
        long long ns = (long long)t0.tv_sec * 1000000000LL + t0.tv_nsec + (long long)(due * 1e9);
        t.tv_sec = ns / 1000000000LL;
        t.tv_nsec = ns % 1000000000LL;
        clock_nanosleep( CLOCK_MONOTONIC, TIMER_ABSTIME, &t, NULL );
        fputs( line, stdout );
        if( fwrite( buf, 1, fsize, stdout ) != fsize )
            break;
        fflush( stdout );
    }
    free( buf );
    fclose( f );
    return 0;
}
