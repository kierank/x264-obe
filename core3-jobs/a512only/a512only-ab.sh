#!/bin/bash
# In-situ A/B for wip/x264-gap-a512only (x264-obe, public github). Step B protocol: base / base2 / arm / arm2,
# paired rounds (arm order rotated), per-cell median, A/A controls, recon md5 across arms (bitstream md5
# only within one sha: the version SEI differs between shas), liveness counter.
# One dispatch commit per run: ARM = that dispatch commit, BASE = ARM~1 (default).
#   BOX=core3  (Intel AVX2): the dispatch commits themselves
#   BOX=rack01 (Zen 4): ARM with the kernel under test forced over the AVX512ICL pointer (perl, checked)
# Run each part alone, nothing else timed on the box.
#   bash a512only-ab.sh build | live | md5 | time [rounds] | report
# Set: ARM (sha), CLIPS (dir with <clip>.y4m), CORE (one cpu), KIND, optional BASE, CLIPLIST, FRAMES.
#   KIND: pcd (plane_copy_deinterleave avx2), zmm (its zmm icl twin, rack01), il (residual writer),
#         oc (optimize_chroma_2x4_dc avx2, 4:2:2), cl8 (coeff_last8 avx2_lzcnt, 4:2:2)
#   4:2:2 kinds (oc, cl8) encode CLIP422 (the clip name, no .y4m) with --output-csp i422; IL=1 adds --tff
#   when its name does not end in -i.
# Core 3: FRAMES=30 (default there), rack01: whole clips (FRAMES=0 default there).
set -u
BOX=${BOX:?core3 or rack01}
KIND=${KIND:?pcd zmm il oc or cl8}
W=${W:-$HOME/x264-a512only-$KIND}
CLIPS=${CLIPS:?set CLIPS}
CORE=${CORE:?set CORE}
ARM=${ARM:?set ARM}
BASE=${BASE:-$ARM~1}
REPO=https://github.com/kierank/x264-obe
if [ $BOX = core3 ]; then FRAMES=${FRAMES:-30}; else FRAMES=${FRAMES:-0}; fi
FR=""; [ "$FRAMES" != 0 ] && FR="--frames $FRAMES"
CSP=""
case $KIND in
oc|cl8) CLIPLIST=${CLIPLIST:-${CLIP422:?set CLIP422}}; CSP="--output-csp i422" ;;
*) CLIPLIST=${CLIPLIST:-"fades-i field-frame-mix-i credits-i tile-chaos-p pan-fast-p"} ;;
esac
COMMON="--aud --pic-struct --bitrate 15000 --vbv-maxrate 15000 --vbv-bufsize 15000 --nal-hrd fakevbr --threads 1"
LOWLAT="--preset veryfast --tune zerolatency --intra-refresh --keyint 24"
NORMAL="--open-gop --keyint 24 --bframes 3 --rc-lookahead 24 --subme 6 --me hex --ref 2 --no-mixed-refs --no-chroma-me --trellis 1 --partitions i8x8,i4x4 --psy-rd 1.0:0"

zen4arm() { # rack01 arm: the kernel under test also on AVX512ICL
    case $KIND in
    pcd) perl -0pi -e 's/(        pf->plane_copy_deinterleave = x264_plane_copy_deinterleave_)avx512icl;/${1}avx2;/g or die "zen4arm: no match\n"' common/x86/mc-c.c ;;
    zmm) perl -0pi -e 's/(        pf->plane_copy_deinterleave = x264_plane_copy_deinterleave_)avx512icl;/${1}zmm_avx512icl;/g or die "zen4arm: no match\n"' common/x86/mc-c.c ;;
    *) echo "no rack01 arm for $KIND"; return 1 ;;
    esac
}
cntpatch() { # liveness: calls through the pointer under test (> 0 = live)
    local F INIT FIELD K RET ARGS CALL
    case $KIND in
    pcd|zmm) F=common/x86/mc-c.c; INIT=x264_mc_init_mmx; FIELD=plane_copy_deinterleave; RET=void
             ARGS="pixel *a, intptr_t b, pixel *c, intptr_t d, pixel *e, intptr_t f, int g, int h"; CALL="a, b, c, d, e, f, g, h"
             K=x264_plane_copy_deinterleave_avx2
             [ $BOX = rack01 ] && [ $KIND = zmm ] && K=x264_plane_copy_deinterleave_zmm_avx512icl ;;
    il)  F=common/bitstream.c; INIT=x264_bitstream_init; FIELD=cabac_block_residual_internal; RET=void
         ARGS="dctcoef *l, int i, intptr_t c, x264_cabac_t *cb"; CALL="l, i, c, cb"
         K=x264_cabac_block_residual_internal_il_avx2_bmi2 ;;
    oc)  F=common/quant.c; INIT=x264_quant_init; FIELD=optimize_chroma_2x4_dc; RET=int
         ARGS="dctcoef *d, int m"; CALL="d, m"; K=x264_optimize_chroma_2x4_dc_avx2 ;;
    cl8) F=common/quant.c; INIT=x264_quant_init; FIELD=coeff_last8; RET=int
         ARGS="dctcoef *d"; CALL="d"; K=x264_coeff_last8_avx2_lzcnt ;;
    esac
    INIT="$INIT" FIELD="$FIELD" K="$K" RET="$RET" ARGS="$ARGS" CALL="$CALL" perl -0pi -e '
        my $w = "static uint64_t ab_cnt;\n"
              . "static void __attribute__((destructor)) ab_cnt_print( void ) { fprintf( stderr, \"AB_CNT $ENV{K} %llu\\n\", (unsigned long long)ab_cnt ); }\n"
              . "static $ENV{RET} ab_wrap( $ENV{ARGS} ) { __atomic_fetch_add( &ab_cnt, 1, __ATOMIC_RELAXED ); "
              . ($ENV{RET} eq "void" ? "" : "return ") . "$ENV{K}( $ENV{CALL} ); }\n";
        s/^(void \Q$ENV{INIT}\E\()/$w$1/m or die "cntpatch: no $ENV{INIT}\n";
        s/(pf->\Q$ENV{FIELD}\E = )\Q$ENV{K}\E;/${1}ab_wrap;/g or die "cntpatch: no $ENV{FIELD} = $ENV{K}\n";' $F
}
tree() { # name sha [zen4] [cnt]
    local d=$W/$1
    [ -x $d/x264 ] && return 0
    rm -rf $d && git clone -q $REPO $d && cd $d && git fetch -q origin wip/x264-gap-a512only && git checkout -q $2 || exit 1
    test "$(git rev-parse HEAD)" = "$(git rev-parse $2)" || { echo "WRONG TREE $1"; exit 1; }
    case " $* " in *" zen4 "*) zen4arm || exit 1;; esac
    case " $* " in *" cnt "*) cntpatch || exit 1;; esac
    ./configure --bit-depth=8 --enable-static --disable-opencl --extra-cflags="-fno-fast-math -ffp-contract=off -fno-pie" --extra-ldflags="-no-pie" > cfg.log 2>&1 || exit 1
    make -j"$(nproc)" x264 checkasm8 > make.log 2>&1 || { tail make.log; exit 1; }
}
if [ $BOX = core3 ]; then B=$BASE; A=$ARM; AX=""; else B=$ARM; A=$ARM; AX=zen4; fi

case "$1" in
patch) # apply the arm edits in the current tree (a dry check): patch [zen4] [cnt]
    case " $* " in *" zen4 "*) zen4arm || exit 1;; esac
    case " $* " in *" cnt "*) cntpatch || exit 1;; esac
    ;;
build)
    mkdir -p $W
    tree base $B; tree base2 $B; tree arm $A $AX; tree arm2 $A $AX; tree armcnt $A $AX cnt
    md5sum $W/base/x264 $W/base2/x264 $W/arm/x264 $W/arm2/x264 | sed "s|$W/||"   # base == base2, arm == arm2
    for a in base arm armcnt; do (cd $W/$a && for s in 1001 2002 3003; do echo "$a checkasm8 $s: $(./checkasm8 $s 2>&1 | grep -E 'random seed|FAILED|All tests' | tr '\n' ' ')"; done); done
    for a in base arm; do $W/$a/x264 --version | head -1; done   # same version string, no "M"
    ;;
enc) # arm clip mode tag: one encode, user seconds to stdout
    a=$2; c=$3; m=$4; t=$5
    il=""; case $c in *-i) il="--tff";; esac; [ "${IL:-0}" = 1 ] && il="--tff"
    opt=$LOWLAT; [ $m = normal ] && opt=$NORMAL
    perf stat -x, -e cycles:u,instructions:u -o $W/out/$t.perf -- taskset -c $CORE ${PERF:-} $W/$a/x264 $COMMON $opt $il $CSP $FR ${DUMP:-} -o $W/out/$t.264 $CLIPS/$c.y4m 2> $W/out/$t.log
    awk -F, '/cycles:u/{print $1}' $W/out/$t.perf > $W/out/$t.time; awk -F, '/instructions:u/{print $1}' $W/out/$t.perf > $W/out/$t.insn   # .time = cycles:u (Core 3 standard 11-11)
    cat $W/out/$t.time
    ;;
live)
    mkdir -p $W/out
    for c in $CLIPLIST; do for m in lowlat normal; do
        bash $0 enc armcnt $c $m live_${c}_$m > /dev/null
        echo "$c $m: $(grep AB_CNT $W/out/live_${c}_$m.log)"
    done; done
    ;;
md5)
    mkdir -p $W/out
    for c in $CLIPLIST; do for m in lowlat normal; do
        for a in base base2 arm arm2; do DUMP="--dump-yuv $W/out/rec_$a.yuv" bash $0 enc $a $c $m md5_${a}_${c}_$m > /dev/null; done
        r=$(md5sum $W/out/rec_base.yuv $W/out/rec_base2.yuv $W/out/rec_arm.yuv $W/out/rec_arm2.yuv | awk '{print $1}' | sort -u | wc -l)
        bb=$(md5sum $W/out/md5_base_${c}_$m.264 $W/out/md5_base2_${c}_$m.264 | awk '{print $1}' | sort -u | wc -l)
        ba=$(md5sum $W/out/md5_arm_${c}_$m.264 $W/out/md5_arm2_${c}_$m.264 | awk '{print $1}' | sort -u | wc -l)
        echo "$c $m: recon md5 distinct across the 4 arms $r; bitstream distinct base/base2 $bb, arm/arm2 $ba (1, 1, 1 = pass)"
        rm -f $W/out/rec_*.yuv
    done; done
    ;;
time)
    R=${2:-5}; mkdir -p $W/out; arms=(base base2 arm arm2)
    for r in $(seq 1 $R); do for c in $CLIPLIST; do for m in lowlat normal; do
        for k in 0 1 2 3; do a=${arms[$(( (k + r) % 4 ))]}
            echo "$r $c $m $a $(bash $0 enc $a $c $m t_${r}_${a}_${c}_$m)" >> $W/times.txt
        done
    done; done; done
    ;;
report)
    awk '{ t[$2" "$3" "$1" "$4] = $5; cells[$2" "$3] = 1; if( $1 > R ) R = $1 }
    function med( v, n,   i, j, x ) { for( i = 1; i <= n; i++ ) for( j = i+1; j <= n; j++ ) if( v[j] < v[i] ) { x = v[i]; v[i] = v[j]; v[j] = x }
                                    return n % 2 ? v[(n+1)/2] : (v[n/2] + v[n/2+1]) / 2 }
    END { for( c in cells ) { n = 0
            for( r = 1; r <= R; r++ ) { k = c" "r; if( !((k" base") in t) ) continue; n++
              d1[n] = 100*(t[k" arm"]/t[k" base"]-1); d2[n] = 100*(t[k" arm2"]/t[k" base2"]-1)
              a1[n] = 100*(t[k" base2"]/t[k" base"]-1); a2[n] = 100*(t[k" arm2"]/t[k" arm"]-1); w += (t[k" arm"] < t[k" base"]) }
            printf "%-24s arm-base %+.2f %%  arm2-base2 %+.2f %%  A/A base %+.2f %%  A/A arm %+.2f %%  (%d rounds)\n", c, med(d1,n), med(d2,n), med(a1,n), med(a2,n), n }
          printf "rounds with arm faster than base: %d\n", w }' $W/times.txt | sort
    ;;
esac
