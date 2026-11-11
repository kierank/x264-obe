#!/bin/sh
# Liveness counter patch for wip/x264-nw-trprep (counter tree only, never timed):
# counts the calls of each new trellis prep / post kernel, printed as TRCNT at encoder close.
set -e
cd "$1"
cat >> common/osdep.h <<'EOF'
extern uint64_t x264_trcnt[8];
static inline int x264_trcnt_hit( int i ) { __atomic_fetch_add( &x264_trcnt[i], 1, __ATOMIC_RELAXED ); return 0; }
EOF
sed -i 's/h->zigzagf\.quant_4x4x4_scan_trellis(/(x264_trcnt_hit(0), h->zigzagf.quant_4x4x4_scan_trellis)(/' encoder/rdo.c
sed -i 's/h->zigzagf\.quant_8x8_scan_trellis(/(x264_trcnt_hit(1), h->zigzagf.quant_8x8_scan_trellis)(/' encoder/rdo.c
sed -i 's/h->zigzagf\.dequant_4x4x4_scan(/(x264_trcnt_hit(2), h->zigzagf.dequant_4x4x4_scan)(/; s/h->zigzagf\.dequant_4x4x4_scan_ac(/(x264_trcnt_hit(3), h->zigzagf.dequant_4x4x4_scan_ac)(/' encoder/macroblock.c
sed -i 's/h->zigzagf\.dequant_8x8_scan(/(x264_trcnt_hit(4), h->zigzagf.dequant_8x8_scan)(/' encoder/macroblock.h
sed -i '/^void    x264_encoder_close  ( x264_t \*h )/,/^{/ s/^{/{\n    fprintf( stderr, "TRCNT prep4x4x4 %llu prep8x8 %llu post4x4x4 %llu post4x4x4ac %llu post8x8 %llu\\n", (unsigned long long)x264_trcnt[0], (unsigned long long)x264_trcnt[1], (unsigned long long)x264_trcnt[2], (unsigned long long)x264_trcnt[3], (unsigned long long)x264_trcnt[4] );/' encoder/encoder.c
sed -i '0,/^#include "common\/common.h"/s//#include "common\/common.h"\nuint64_t x264_trcnt[8];/' encoder/encoder.c
n=$(grep -c "x264_trcnt_hit" encoder/rdo.c encoder/macroblock.c encoder/macroblock.h | awk -F: '{ s += $2 } END { print s }')
[ "$n" = 7 ] || { echo "trcnt: expected 7 hooks, got $n"; exit 1; }
grep -q TRCNT encoder/encoder.c || { echo "trcnt: no print"; exit 1; }
