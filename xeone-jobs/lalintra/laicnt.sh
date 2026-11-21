#!/bin/sh
# laicnt.sh <tree>: counter patch for lalintra (never committed). encoder/slicetype.c gets per-process counters,
# printed at exit as one "LAICNT" line on stderr:
#   passes I / P / B: computed x264_slicetype_frame_cost passes by kind, "intra/all" = those whose slices take the
#   lowres intra cost (b_intra_calculated 0 when the slices run) / all computed passes;
#   lowres_p: x264_lowres_p_run calls unweighted / weighted (the weighted ones run the old entry in the arm).
# Copyright (C) 2026 Open Broadcast Systems Ltd
set -e
cd "$1"
f=encoder/slicetype.c
grep -q '^#include "weightp.h"$' $f || { echo "laicnt: no include anchor"; exit 1; }
[ "$(grep -c '^            if( h->param.i_lookahead_threads > 1 )$' $f)" = 1 ] || { echo "laicnt: no pass anchor"; exit 1; }
[ "$(grep -c '^        x264_lowres_p_run( h, &c );$' $f)" = 1 ] || { echo "laicnt: no lowres_p anchor"; exit 1; }
anchor=$(grep -n '^#include "weightp.h"$' $f | cut -d: -f1)
sed -i "${anchor}a\\
static uint64_t lai_pass[3][2], lai_p[2];\\
static void __attribute__((destructor)) lai_print( void )\\
{\\
    if( lai_pass[0][1] + lai_pass[1][1] + lai_pass[2][1] )\\
        fprintf( stderr, \"LAICNT %d-bit passes I %llu/%llu P %llu/%llu B %llu/%llu (intra/all) lowres_p %llu/%llu (unweighted/weighted)\\\\n\", BIT_DEPTH,\\
                 (unsigned long long)lai_pass[0][0], (unsigned long long)lai_pass[0][1], (unsigned long long)lai_pass[1][0],\\
                 (unsigned long long)lai_pass[1][1], (unsigned long long)lai_pass[2][0], (unsigned long long)lai_pass[2][1],\\
                 (unsigned long long)lai_p[0], (unsigned long long)lai_p[1] );\\
}" $f
sed -i 's/^            if( h->param.i_lookahead_threads > 1 )$/            { int k = p0 == p1 ? 0 : b == p1 ? 1 : 2; __atomic_fetch_add( \&lai_pass[k][1], 1, __ATOMIC_RELAXED ); if( !fenc->b_intra_calculated ) __atomic_fetch_add( \&lai_pass[k][0], 1, __ATOMIC_RELAXED ); }\n            if( h->param.i_lookahead_threads > 1 )/' $f
sed -i 's/^        x264_lowres_p_run( h, &c );$/        __atomic_fetch_add( \&lai_p[!!c.weighted], 1, __ATOMIC_RELAXED );\n        x264_lowres_p_run( h, \&c );/' $f
grep -c 'lai_pass\|lai_p\[' $f | sed 's/^/laicnt: lines /'
