#!/bin/bash
# Xeon E (E-2478, Intel AVX2) in-situ split A/B of job O (la2): which of b81cae5e's three AVX2 pointers loses
# field-frame-mix-i lowlat (+0.40 %, 0/9, insn -0.06 %), and the fix. wip/x264-me2-la2-split, all on 5db22450.
# Copyright (C) 2026 Open Broadcast Systems Ltd
#
# Install as xeone-jobs/la2split/la2split-ab.sh next to lib.sh (wip/x264-core3-jobs), then per AB:
#   AB=c bash la2split-ab.sh build      # build window
#   AB=c bash la2split-ab.sh live       # LIVE_RE samples every cell + the call counters (counter trees, untimed)
#   AB=c bash la2split-ab.sh prof       # perf record ffm-i lowlat, base vs arm: top symbols, shares, deltas
#   AB=c bash la2split-ab.sh md5
#   AB=c bash la2split-ab.sh time 9; AB=c bash la2split-ab.sh report
#   AB=c bash la2split-ab.sh layout     # x264_8_pixel_init size, code shift vs base, hot symbols mod 64
# Run order: c, fix, a, b, then cfix / lay if c or fix still lose. ffm-i lowlat decides every AB.
# Branch (each sha vs 5db22450 is one arm): 5a47d2ef a -> d956198b b -> 4c000a1c c -> f3116fd1 (kernel v1) ->
#   9c531856 (v1 + full dispatch) -> 0c47ef53 (kernel v2 = the fix, full dispatch, tip).
# AB (base 5db22450 = kernels assembled, nothing dispatched, unless noted):
#   a     arm 5a47d2ef: lowres_i_mbs avx2 alone
#   b     arm d956198b: lowres_b_mbs avx2 alone
#   c     arm 4c000a1c: intra_satd_lowres_tf avx2 alone (the intra estimate of lowres_p_mbs and the C paths)
#   fix   arm 0c47ef53: b81cae5e's dispatch (same common/pixel.c) on the fixed kernels (V/DC constants in m8/m13/m14,
#         V and DC scored first, tf without a stack frame)
#   cfix  arm 0c47ef53 with lowres_i_mbs / lowres_b_mbs undispatched (xe_patch): c on the fixed kernel
#   fix1  arm 9c531856: the v1 fix (edge filter after P; slower than v2 on Zen 5), only on request
#   lay   base 5db22450, arm b81cae5e, both trees with -falign-functions=64: layout control (diagnostic only).
#         If b81cae5e's ffm-i loss is code placement (pixel_init grows, every later 8-bit object moves by a
#         non-multiple of 64), it disappears here.
# Why ffm-i lowlat sees only the intra pointer: lowlat has no B frames and weightp 1. weights_analyse's intra
#   pre-pass (lowres_i_mbs) runs only when the luma mean/variance test fails; on ffm-i it passes, so the P frame's
#   intra estimate runs inside lowres_p_mbs, through pixf.intra_satd_lowres, once per lowres MB per P frame
#   (120x68 = 8160 MBs, all of them: VBV sets do_edges): 29 frames x 8160 = 236640 calls at 30 frames if no
#   pre-pass ran. The counters print the exact numbers. Lowres is the frame's (stride 1024 at 1080), not fields.
# Expected instructions:u, base -> arm, per counted intra call (LA2_CNT intra calls; both kernels branch-free):
#   (entry to ret, laptop gcc 15 / nasm 3.01 objects; the layout phase prints the Xeon E builds' own counts)
#   c:    tf 460 - intra_satd_lowres_avx2 469 = -9 per call, lowres_p_mbs and C slicetype_mb_cost calls alike.
#   cfix: 457 - 469 = -12 per call.
#   fix:  -12 per LA2_CNT intra call, plus lowres_i_mbs / lowres_b_mbs (not constant per MB: check the sign).
#   a: the C intra loop's cost (slicetype_mb_cost prologue + copy + fenc_pre call + intra call) minus
#      lowres_i_mbs's per MB: not a constant; check sign and the LA2_CNT i_mbs MB count only.
set -u
export LC_ALL=C
JOB=la2split; AB=${AB:-c}; BRANCHES="wip/x264-me2-la2-split wip/x264-me2-la2"
case $AB in
a)    BASE=5db22450; ARM=5a47d2ef ;;
b)    BASE=5db22450; ARM=d956198b ;;
c)    BASE=5db22450; ARM=4c000a1c ;;
cfix) BASE=5db22450; ARM=0c47ef53 ;;
fix)  BASE=5db22450; ARM=0c47ef53 ;;
fix1) BASE=5db22450; ARM=9c531856 ;;
lay)  BASE=5db22450; ARM=b81cae5e ;;
*) echo "unknown AB $AB"; exit 1 ;;
esac
BITDEPTH=all
CELLS="field-frame-mix-i:lowlat tile-chaos-p:lowlat field-frame-mix-i:normal fades-p:normal:60"
MD5CELLS="ffm422-i:lowlat ffm422-i:normal fades-i:normal:60 field-frame-mix-i:normal@10 ffm422p10-i:lowlat@10"
LIVE_RE='lowres_[ibp]_mbs|intra_satd_lowres|slicetype_mb_cost|slicetype_slice_cost|satd_fenc_pre|satd_pre_8x8|me_search'
COUNT_TREES="basecnt armcnt"; COUNT_RE=LA2_CNT
PROFCELL=${PROFCELL:-field-frame-mix-i:lowlat}; PROF_RUNS=${PROF_RUNS:-3}; PROF_PERIOD=${PROF_PERIOD:-200003}
XE_PHASES="prof | layout"
. "$(dirname "$0")/../lib.sh"

cntpatch() { # call counters: pixf.intra_satd_lowres (every non-inline intra estimate), lowres_[ipb]_mbs calls and MBs
    sed -i 's/^void x264_pixel_init( int cpu, x264_pixel_function_t \*pixf )$/static void pixel_init_real( int cpu, x264_pixel_function_t *pixf )/' common/pixel.c
    grep -q '^static void pixel_init_real' common/pixel.c || return 1
    cat >> common/pixel.c <<'EOF'
#if !HIGH_BIT_DEPTH && HAVE_MMX && ARCH_X86_64 && !defined(_WIN32)
#include "encoder/lowres.h"
static int (*cnt_intra_real)( void *, pixel *, intptr_t );
static void (*cnt_i_real)( x264_lowres_i_t * );
static void (*cnt_b_real)( x264_lowres_b_t * );
static void (*cnt_p_real)( x264_lowres_p_t * );
static uint64_t cnt[12];
#define CNT_ADD( i, n ) __atomic_fetch_add( &cnt[i], n, __ATOMIC_RELAXED )
static uint64_t cnt_mbs( int sx, int ex, int sy, int ey ) { return sx >= ex && sy >= ey ? (uint64_t)(sx - ex + 1) * (sy - ey + 1) : 0; }
static int cnt_intra( void *f, pixel *s, intptr_t st ) { CNT_ADD( 0, 1 ); return cnt_intra_real( f, s, st ); }
static void cnt_i( x264_lowres_i_t *c )
{ int k = c->output_intra ? 1 : 3; CNT_ADD( k, 1 ); CNT_ADD( k+1, cnt_mbs( c->start_x, c->end_x, c->start_y, c->end_y ) ); cnt_i_real( c ); }
static void cnt_b( x264_lowres_b_t *c )
{ int k = c->output_intra ? 5 : 7; CNT_ADD( k, 1 ); CNT_ADD( k+1, cnt_mbs( c->start_x, c->end_x, c->start_y, c->end_y ) ); cnt_b_real( c ); }
static void cnt_p( x264_lowres_p_t *c )
{ CNT_ADD( 9, 1 ); CNT_ADD( c->output_intra ? 10 : 11, cnt_mbs( c->start_x, c->end_x, c->start_y, c->end_y ) ); cnt_p_real( c ); }
static const char *cnt_name( void *f )
{
    if( !f ) return "NULL";
    if( f == (void*)x264_intra_satd_lowres_avx2 ) return "intra_satd_lowres_avx2";
    if( f == (void*)x264_intra_satd_lowres_tf_avx2 ) return "intra_satd_lowres_tf_avx2";
    if( f == (void*)x264_intra_satd_lowres_tf_avx512icl ) return "intra_satd_lowres_tf_avx512icl";
    return "other";
}
static void cnt_report( void )
{
    fprintf( stderr, "LA2_CNT intra %s calls %llu | lowres_i_mbs %s: with intra %llu calls %llu MBs, copy only %llu calls %llu MBs"
             " | lowres_b_mbs %s: with intra %llu calls %llu MBs, without %llu calls %llu MBs | lowres_p_mbs %s: %llu calls,"
             " MBs with intra %llu, without %llu\n", cnt_name( (void*)cnt_intra_real ), (unsigned long long)cnt[0],
             cnt_i_real ? "asm" : "NULL", (unsigned long long)cnt[1], (unsigned long long)cnt[2], (unsigned long long)cnt[3],
             (unsigned long long)cnt[4], cnt_b_real ? "asm" : "NULL", (unsigned long long)cnt[5], (unsigned long long)cnt[6],
             (unsigned long long)cnt[7], (unsigned long long)cnt[8], cnt_p_real ? "asm" : "NULL", (unsigned long long)cnt[9],
             (unsigned long long)cnt[10], (unsigned long long)cnt[11] );
}
void x264_pixel_init( int cpu, x264_pixel_function_t *pixf )
{
    static int inited;
    pixel_init_real( cpu, pixf );
    if( !inited )
    {
        inited = 1;
        cnt_intra_real = pixf->intra_satd_lowres;
        cnt_i_real = pixf->lowres_i_mbs;
        cnt_b_real = pixf->lowres_b_mbs;
        cnt_p_real = pixf->lowres_p_mbs;
        atexit( cnt_report );
    }
    if( cnt_intra_real && pixf->intra_satd_lowres == cnt_intra_real ) pixf->intra_satd_lowres = cnt_intra;
    if( cnt_i_real && pixf->lowres_i_mbs == cnt_i_real ) pixf->lowres_i_mbs = cnt_i;
    if( cnt_b_real && pixf->lowres_b_mbs == cnt_b_real ) pixf->lowres_b_mbs = cnt_b;
    if( cnt_p_real && pixf->lowres_p_mbs == cnt_p_real ) pixf->lowres_p_mbs = cnt_p;
}
#else
void x264_pixel_init( int cpu, x264_pixel_function_t *pixf ) { pixel_init_real( cpu, pixf ); }
#endif
EOF
}
cfixpatch() { # the fix tree with only intra_satd_lowres_tf dispatched
    sed -i -e '/^        pixf->lowres_i_mbs = x264_lowres_i_mbs_avx2;$/d' -e '/^        pixf->lowres_b_mbs = x264_lowres_b_mbs_avx2;$/d' common/pixel.c
    ! grep -qE 'lowres_[ib]_mbs = x264_lowres_[ib]_mbs_avx2;' common/pixel.c && grep -q 'intra_satd_lowres = x264_intra_satd_lowres_tf_avx2;' common/pixel.c
}
xe_patch() {
    case $1 in arm*) [ $AB = cfix ] && { cfixpatch || { echo "cfixpatch did not apply"; return 1; }; } ;; esac
    case $1 in *cnt) cntpatch || { echo "cntpatch did not apply"; return 1; } ;; esac
    return 0
}
xe_cflags() { [ $AB = lay ] && echo "-falign-functions=64"; return 0; }
xe_bench() { (cd $(xe_dir arm t) && taskset -c $CORE ./checkasm8 --bench=lowres 1001 | grep -E 'intra_satd_lowres|lowres_[ib]_mbs|nop'); }

# entry-to-ret instruction count of a branch-free asm function in a tree's object
la2_icount() { objdump -d --no-show-raw-insn --disassemble=$3 $(xe_dir $1 t)/$2 2>/dev/null | grep -P '^\s+[0-9a-f]+:' | awk '{ n++ } /\tret/ { print n; exit }'; }

xe_phase_layout() { # code placement of the timing builds: does the arm move the hot code of the 8-bit objects?
    local a nm
    for a in base arm; do nm -S --numeric-sort $(xe_bin $a t) | grep -i ' t ' > $W/out/nm_$a.txt; done
    echo "x264_8_pixel_init size: base $(awk '$4 == "x264_8_pixel_init" { print strtonum( "0x"$2 ) }' $W/out/nm_base.txt)" \
         "arm $(awk '$4 == "x264_8_pixel_init" { print strtonum( "0x"$2 ) }' $W/out/nm_arm.txt) bytes"
    echo "intra kernels, entry to ret: intra_satd_lowres_avx2 $(la2_icount base common/x86/pixel-a-8.o x264_8_intra_satd_lowres_avx2)," \
         "tf_avx2 base $(la2_icount base common/x86/lowres-a-8.o x264_8_intra_satd_lowres_tf_avx2) arm $(la2_icount arm common/x86/lowres-a-8.o x264_8_intra_satd_lowres_tf_avx2)"
    echo "functions by address shift arm - base (bytes:count, top 6):"
    awk 'NR == FNR { a[$4] = strtonum( "0x"$1 ); next } ($4 in a) { n[strtonum( "0x"$1 ) - a[$4]]++ }
         END { for( d in n ) print d, n[d] }' $W/out/nm_base.txt $W/out/nm_arm.txt | sort -k2 -nr | head -6 | awk '{ printf "  %+d: %d functions\n", $1, $2 }'
    if [ -s $W/out/prof_base.txt ]; then
        echo "hot symbols (prof base, top 20): address mod 64 base / arm"
        awk '$1 ~ /%$/ { print $NF }' $W/out/prof_base.txt | head -20 | while read s; do
            printf "  %-48s %s / %s\n" $s "$(awk -v s=$s '$4 == s { print strtonum( "0x"$1 ) % 64 }' $W/out/nm_base.txt)" \
                "$(awk -v s=$s '$4 == s { print strtonum( "0x"$1 ) % 64 }' $W/out/nm_arm.txt)"
        done
    fi
}

xe_phase_prof() { # perf record PROFCELL, base and arm, PROF_RUNS runs each (rotated), summed per symbol
    mkdir -p $W/out; local a r f
    xe_cell $PROFCELL; [ -f $CL ] || xe_die "no $CL"
    for a in base arm; do : > $W/out/prof_$a.raw; done
    for r in $(seq $PROF_RUNS); do for a in base arm; do f=$W/out/prof_${a}_$r.data
        taskset -c $CC perf record -q -e cycles:u -c $PROF_PERIOD -o $f -- $(xe_bin $a t) $CO -o /dev/null $CL 2> /dev/null
        perf report -q -n --stdio -i $f --sort sym 2> /dev/null | awk '$2 ~ /^[0-9]+$/ { print $NF, $2 }' >> $W/out/prof_$a.raw
    done; done
    for a in base arm; do
        awk '{ n[$1] += $2; t += $2 } END { for( s in n ) printf "%6.2f%% %8d %s\n", 100*n[s]/t, n[s], s; print "TOTAL", t > "/dev/stderr" }' \
            $W/out/prof_$a.raw 2> $W/out/prof_$a.tot | sort -k2 -nr > $W/out/prof_$a.txt
    done
    echo "== $CN, $PROF_RUNS runs each, cycles:u period $PROF_PERIOD: base $(awk '{ print $2 }' $W/out/prof_base.tot) samples, arm $(awk '{ print $2 }' $W/out/prof_arm.tot)"
    echo "-- lowres / slicetype / intra symbols (share, samples), base | arm"
    join -a1 -a2 -e0 -o 0,1.2,1.3,2.2,2.3 <(awk '{ print $3, $1, $2 }' $W/out/prof_base.txt | sort) <(awk '{ print $3, $1, $2 }' $W/out/prof_arm.txt | sort) |
        grep -E "$LIVE_RE|weight|frame_init_lowres|lookahead" | sort -k3 -nr | awk '{ printf "  %-48s %7s %8s | %7s %8s\n", $1, $2, $3, $4, $5 }'
    echo "-- top 25 symbols by base samples, base | arm | arm-base samples"
    join -a1 -a2 -e0 -o 0,1.2,1.3,2.2,2.3 <(awk '{ print $3, $1, $2 }' $W/out/prof_base.txt | sort) <(awk '{ print $3, $1, $2 }' $W/out/prof_arm.txt | sort) |
        sort -k3 -nr | head -25 | awk '{ printf "  %-48s %7s %8s | %7s %8s | %+7d\n", $1, $2, $3, $4, $5, $5 - $3 }'
    echo "-- largest moves (arm - base samples; the cycles:u loss is where the sum lands)"
    join -a1 -a2 -e0 -o 0,1.3,2.3 <(awk '{ print $3, $2 }' $W/out/prof_base.txt | sort) <(awk '{ print $3, $2 }' $W/out/prof_arm.txt | sort) |
        awk '{ d = $3 - $2; print (d < 0 ? -d : d), d, $1 }' | sort -k1 -nr | head -15 | awk '{ printf "  %+7d %s\n", $2, $3 }'
}

[ -n "${XE_TEST:-}" ] || xe_main "$@"
