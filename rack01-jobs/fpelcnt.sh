#!/bin/sh
# Liveness-counter patch for rack01 COUNTER builds only (never timed, never merged).
# Usage: sh fpelcnt.sh <x264-obe tree>. At exit the encoder prints to stderr:
#   FPEL_CNT fused <n> refine_after <n> me_search_ref <n> fused_16x16/16x8/8x16/8x8 <a>/<b>/<c>/<d>
# fused: x264_me_search_ref took pixf.me_search_fpel; refine_after: it returned 1 (refine_subpel in C);
# me_search_ref: the C path (weighted refs at subme >= 3, non-HEX methods, partitions below 8x8).
set -e
cd "$1"
if grep -q fpel_cnt encoder/me.c; then echo "already patched"; exit 0; fi
awk '/^void x264_me_search_ref\( x264_t \*h, x264_me_t \*m, int16_t \(\*mvc\)\[2\], int i_mvc, int \*p_halfpel_thresh \)$/ {
  print "static uint64_t fpel_cnt[7];"
  print "static void __attribute__((destructor)) fpel_cnt_print( void )"
  print "{"
  print "    fprintf( stderr, \"FPEL_CNT fused %llu refine_after %llu me_search_ref %llu fused_16x16/16x8/8x16/8x8 %llu/%llu/%llu/%llu\\n\","
  print "             (unsigned long long)fpel_cnt[0], (unsigned long long)fpel_cnt[1], (unsigned long long)fpel_cnt[2],"
  print "             (unsigned long long)fpel_cnt[3], (unsigned long long)fpel_cnt[4], (unsigned long long)fpel_cnt[5],"
  print "             (unsigned long long)fpel_cnt[6] );"
  print "}"
} { print }' encoder/me.c > encoder/me.c.new && mv encoder/me.c.new encoder/me.c
sed -i 's|^        if( h->pixf.me_search_fpel( &c ) )$|        __atomic_fetch_add( \&fpel_cnt[0], 1, __ATOMIC_RELAXED );\n        __atomic_fetch_add( \&fpel_cnt[3+i_pixel], 1, __ATOMIC_RELAXED );\n        if( h->pixf.me_search_fpel( \&c ) )|' encoder/me.c
sed -i 's|^            refine_subpel( h, m, hpel, qpel, p_halfpel_thresh, 0 );$|        {\n            __atomic_fetch_add( \&fpel_cnt[1], 1, __ATOMIC_RELAXED );\n            refine_subpel( h, m, hpel, qpel, p_halfpel_thresh, 0 );\n        }|' encoder/me.c
sed -i 's|^    me_search_ref( h, m, mvc, i_mvc, p_halfpel_thresh );$|    __atomic_fetch_add( \&fpel_cnt[2], 1, __ATOMIC_RELAXED );\n    me_search_ref( h, m, mvc, i_mvc, p_halfpel_thresh );|' encoder/me.c
n=$(grep -c "fpel_cnt\[" encoder/me.c); [ "$n" = 8 ] || { echo "patch did not apply ($n)"; exit 1; }
echo "fpelcnt patched"
