#!/bin/sh
# Liveness counters for wip/x264-nw-mbtree: patches common/x86/mc-c.c of the tree in $1 so the
# strip wrappers count, and print at exit:
#   NWCNT flush_calls <strip folds = list calls> rows <rows folded> direct <entries on the |dy| > 3 path> list2 <fused B rows>
set -e
f=$1/common/x86/mc-c.c
grep -q '^static void mbtree_list_direct(' $f
grep -q '^static void mbtree_strip_flush( x264_t \*h' $f
awk '
/^static void mbtree_list_direct\(/ && !a {
    print "static uint64_t nwmb_cnt[4];"
    print "static void nwmb_print( void )"
    print "{"
    print "    fprintf( stderr, \"NWCNT flush_calls %llu rows %llu direct %llu list2 %llu\\n\", (unsigned long long)nwmb_cnt[0],"
    print "             (unsigned long long)nwmb_cnt[1], (unsigned long long)nwmb_cnt[2], (unsigned long long)nwmb_cnt[3] );"
    print "}"
    print "static void nwmb_count( int k )"
    print "{"
    print "    static int reg;"
    print "    if( !__atomic_exchange_n( &reg, 1, __ATOMIC_RELAXED ) )"
    print "        atexit( nwmb_print );"
    print "    __atomic_fetch_add( &nwmb_cnt[k], 1, __ATOMIC_RELAXED );"
    print "}"
    a = 1
}
{ print }
/^static void mbtree_strip_flush\( x264_t \*h/ { f = 1 }
f && /^{$/ { print "    nwmb_count( 0 );"; f = 0 }
/^        if\( dirty&1 \)$/ { r = 1 }
r && /^        {$/ { print "            nwmb_count( 1 );"; r = 0 }
/^        int16_t w\[18\];$/ { print "        nwmb_count( 2 );" }
/^    int32_t \*out1 = out0 \+ 5\*\(\(len\+15\)&~15\);\\$/ { print "    nwmb_count( 3 );\\" }
' $f > $f.cnt && mv $f.cnt $f
test "$(grep -c 'nwmb_count( [0-3] );' $f)" -eq 4 || { echo "nwmbcnt: patch did not apply"; exit 1; }
echo "nwmbcnt: patched $f"
