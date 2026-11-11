#!/bin/sh
# Liveness-counter patch for COUNTER builds only (never timed, never merged).
# Usage: sh idct8cnt.sh <x264-obe tree>. At exit the encoder prints to stderr:
#   IDCT8_CNT i8x8 <n> inter8x8 <n> p8x8 <n> inter16x16 <n> add8x8_idct8 <addr> add16x16_idct8 <addr>
# i8x8: x264_mb_encode_i8x8 (intra analysis, final encode, RD refine); inter8x8: macroblock_encode_internal
# per coded 8x8; p8x8: x264_macroblock_encode_p8x8 (RD); inter16x16: the all-four-coded batch (trees
# with the batch commit). <addr> is the pointer called; map it with nm x264 | grep idct8.
set -e
cd "$1"
if grep -q idct8_cnt encoder/macroblock.c; then echo "already patched"; exit 0; fi
# externs right after the include, before the static inline x264_mb_encode_i8x8 that uses them
sed -i 's|^#include "common/macroblock.h"$|&\nextern uint64_t idct8_cnt[4];\nextern void *idct8_ptr[2];\nextern uint64_t idct8_cbp[16];|' encoder/macroblock.h
grep -q "^extern uint64_t idct8_cnt" encoder/macroblock.h || { echo "extern patch did not apply"; exit 1; }
cat >> encoder/macroblock.c <<'EOF'
uint64_t idct8_cnt[4];
void *idct8_ptr[2];
uint64_t idct8_cbp[16];
static void __attribute__((destructor)) idct8_cnt_print( void )
{
    fprintf( stderr, "IDCT8_CNT i8x8 %llu inter8x8 %llu p8x8 %llu inter16x16 %llu add8x8_idct8 %p add16x16_idct8 %p\n",
             (unsigned long long)idct8_cnt[0], (unsigned long long)idct8_cnt[1], (unsigned long long)idct8_cnt[2],
             (unsigned long long)idct8_cnt[3], idct8_ptr[0], idct8_ptr[1] );
    uint64_t f = idct8_cbp[15], pr = 0, o = 0;
    for( int i = 1; i < 15; i++ ) { if( (i&3) == 3 || (i&12) == 12 ) pr += idct8_cbp[i]; else o += idct8_cbp[i]; }
    fprintf( stderr, "IDCT8_CBP inter8x8 planes: all4 %llu with-a-pair %llu other %llu\n",
             (unsigned long long)f, (unsigned long long)pr, (unsigned long long)o );
}
EOF
sed -i 's|^        h->dctf.add8x8_idct8( p_dst, dct8x8 );$|        __atomic_fetch_add( \&idct8_cnt[0], 1, __ATOMIC_RELAXED ); idct8_ptr[0] = (void*)h->dctf.add8x8_idct8;\n&|' encoder/macroblock.h
sed -i 's|^\( *\)h->dctf.add8x8_idct8( &h->mb.pic.p_fdec\[p\]\[8\*(idx&1) + 8\*(idx>>1)\*FDEC_STRIDE\], dct8x8\[idx\] );$|\1__atomic_fetch_add( \&idct8_cnt[1], 1, __ATOMIC_RELAXED ); idct8_ptr[0] = (void*)h->dctf.add8x8_idct8;\n&|' encoder/macroblock.c
sed -i 's|^\( *\)h->dctf.add8x8_idct8( p_fdec, dct8x8 );$|\1__atomic_fetch_add( \&idct8_cnt[2], 1, __ATOMIC_RELAXED ); idct8_ptr[0] = (void*)h->dctf.add8x8_idct8;\n&|' encoder/macroblock.c
sed -i 's|^\( *\)h->dctf.add16x16_idct8( h->mb.pic.p_fdec\[p\], dct8x8 );$|\1__atomic_fetch_add( \&idct8_cnt[3], 1, __ATOMIC_RELAXED ); idct8_ptr[1] = (void*)h->dctf.add16x16_idct8;\n&|' encoder/macroblock.c
# cbp histogram: the first plane_cbp merge is the 8x8-transform inter path (the second is 4x4)
awk '!d && /^ *h->mb.i_cbp_luma \|= plane_cbp;$/ { print; print "                    idct8_cbp[plane_cbp]++;"; d = 1; next } { print }' encoder/macroblock.c > encoder/mb.tmp && mv encoder/mb.tmp encoder/macroblock.c
grep -q "idct8_cbp\[plane_cbp\]++" encoder/macroblock.c || { echo "cbp patch did not apply"; exit 1; }
n=$(grep -c "idct8_cnt\[" encoder/macroblock.c encoder/macroblock.h | awk -F: '{s+=$2} END {print s}')
# lines: 3 sites + the batch site when present, the definition, 2 printer lines, the extern
b=$(grep -c "add16x16_idct8( h->mb.pic.p_fdec\[p\], dct8x8 )" encoder/macroblock.c || true)
[ "$n" = $((7 + b)) ] || { echo "patch did not apply ($n, batch $b)"; exit 1; }
echo "idct8cnt patched (batch site: $b)"
