#!/bin/sh
# Liveness counters for wip/x264-nw-wpdeint: patches encoder/slicetype.c of the tree in $1 and
# prints at exit:
#   WPCNT analyse_decide <x264_weights_analyse calls, b_lookahead 0> analyse_la <b_lookahead 1>
#         chroma_init <x264_weight_cost_init_chroma calls> rows_mvs <ref rows on mc_chroma>
#         rows_nomvs <ref rows on the copy: weightp_deint_stats8 on the arm>
set -e
f=$1/encoder/slicetype.c
grep -q '^void x264_weight_chroma_ref_rows( x264_t \*h, x264_weight_src_t \*s, int mb_y0, int mb_y1 )$' $f
grep -q '^static NOINLINE void x264_weight_cost_init_chroma( ' $f
grep -q '^void x264_weights_analyse( x264_t \*h, x264_frame_t \*fenc, x264_frame_t \*ref, int b_lookahead )$' $f
awk '
/^void x264_weight_chroma_fenc_rows\(/ && !a {
    print "static uint64_t wpcnt[5];"
    print "static void wpcnt_print( void )"
    print "{"
    print "    fprintf( stderr, \"WPCNT analyse_decide %llu analyse_la %llu chroma_init %llu rows_mvs %llu rows_nomvs %llu\\n\","
    print "             (unsigned long long)wpcnt[0], (unsigned long long)wpcnt[1], (unsigned long long)wpcnt[2],"
    print "             (unsigned long long)wpcnt[3], (unsigned long long)wpcnt[4] );"
    print "}"
    print "static void wpcnt_add( int k, int v )"
    print "{"
    print "    static int reg;"
    print "    if( !__atomic_exchange_n( &reg, 1, __ATOMIC_RELAXED ) )"
    print "        atexit( wpcnt_print );"
    print "    __atomic_fetch_add( &wpcnt[k], v, __ATOMIC_RELAXED );"
    print "}"
    print ""
    a = 1
}
{ print }
/^void x264_weight_chroma_ref_rows\( x264_t \*h, x264_weight_src_t \*s, int mb_y0, int mb_y1 \)$/ { r = 1 }
r && /^{$/ { print "    wpcnt_add( s->mvs ? 3 : 4, mb_y1 - mb_y0 );"; r = 0 }
/^static NOINLINE void x264_weight_cost_init_chroma\( / { c = 1 }
c && /^{$/ { print "    wpcnt_add( 2, 1 );"; c = 0 }
/^void x264_weights_analyse\( x264_t \*h, x264_frame_t \*fenc, x264_frame_t \*ref, int b_lookahead \)$/ { w = 1 }
w && /^{$/ { print "    wpcnt_add( !!b_lookahead, 1 );"; w = 0 }
' $f > $f.cnt && mv $f.cnt $f
test "$(grep -c 'wpcnt_add( ' $f)" -eq 4 || { echo "wpcnt: patch did not apply"; exit 1; }
echo "wpcnt: patched $f"
