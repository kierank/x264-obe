#!/bin/bash
# In-situ A/B for wip/x264-gap-a512only (x264-obe, public github). Step B protocol: base / base2 / arm / arm2,
# paired rounds (arm order rotated), per-cell median, A/A controls, recon + bitstream md5, liveness counters.
# One dispatch commit per run: ARM = that dispatch commit, BASE = ARM~1 (default).
#   BOX=core3  (Intel AVX2): the dispatch commits themselves
#   BOX=rack01 (Zen 4): ARM gets ZEN4 applied (perl, checked): the AVX2 / zmm kernel forced over the icl pointer
# Run each part alone, nothing else timed on the box.
#   bash a512only-ab.sh build | live | md5 | time [rounds] | report
# Set: ARM (sha), CLIPS (dir with <clip>.y4m), CORE (one cpu), KIND (pcd | il | zmm), optional BASE.
# Core 3: FRAMES=30 (default there), rack01: whole clips (FRAMES=0 default there).
set -u
BOX=${BOX:?core3 or rack01}
KIND=${KIND:?pcd il or zmm}
W=${W:-$HOME/x264-a512only-$KIND}
CLIPS=${CLIPS:?set CLIPS}
CORE=${CORE:?set CORE}
ARM=${ARM:?set ARM}
BASE=${BASE:-$ARM~1}
REPO=https://github.com/kierank/x264-obe
if [ $BOX = core3 ]; then FRAMES=${FRAMES:-30}; else FRAMES=${FRAMES:-0}; fi
FR=""; [ "$FRAMES" != 0 ] && FR="--frames $FRAMES"
CLIPLIST=${CLIPLIST:-"fades-i field-frame-mix-i credits-i tile-chaos-p pan-fast-p"}
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
    case $KIND in
    pcd|zmm)
        F=common/x86/mc-c.c
        if [ $BOX = core3 ]; then K=x264_plane_copy_deinterleave_avx2; else K=x264_plane_copy_deinterleave_$( [ $KIND = zmm ] && echo zmm_avx512icl || echo avx2 ); fi
        perl -0pi -e 's/^void x264_mc_init_mmx\( int cpu, x264_mc_functions_t \*pf \)\n/static uint64_t ab_cnt;\nstatic void __attribute__((destructor)) ab_cnt_print( void ) { fprintf( stderr, "AB_CNT KERNEL %llu\\n", (unsigned long long)ab_cnt ); }\nstatic void ab_wrap( pixel *a, intptr_t b, pixel *c, intptr_t d, pixel *e, intptr_t f, int g, int h ) { __atomic_fetch_add( &ab_cnt, 1, __ATOMIC_RELAXED ); KERNEL( a, b, c, d, e, f, g, h ); }\n$&/m or die' $F
        sed -i "s/KERNEL/$K/g" $F
        perl -0pi -e "s/(        pf->plane_copy_deinterleave = )$K;/\${1}ab_wrap;/g or die \"cntpatch: no match\\n\"" $F ;;
    il)
        F=common/bitstream.c; K=x264_cabac_block_residual_internal_il_avx2_bmi2
        perl -0pi -e 's/^void x264_bitstream_init\( int cpu, x264_bitstream_function_t \*pf \)\n/static uint64_t ab_cnt;\nstatic void __attribute__((destructor)) ab_cnt_print( void ) { fprintf( stderr, "AB_CNT KERNEL %llu\\n", (unsigned long long)ab_cnt ); }\nstatic void ab_wrap( dctcoef *l, int i, intptr_t c, x264_cabac_t *cb ) { __atomic_fetch_add( &ab_cnt, 1, __ATOMIC_RELAXED ); KERNEL( l, i, c, cb ); }\n$&/m or die' $F
        sed -i "s/KERNEL/$K/g" $F
        perl -0pi -e "s/(            pf->cabac_block_residual_internal = )$K;/\${1}ab_wrap;/ or die \"cntpatch: no match\\n\"" $F ;;
    esac
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
    il=""; case $c in *-i) il="--tff";; esac
    opt=$LOWLAT; [ $m = normal ] && opt=$NORMAL
    /usr/bin/time -f "%U" -o $W/out/$t.time taskset -c $CORE ${PERF:-} $W/$a/x264 $COMMON $opt $il $FR ${DUMP:-} -o $W/out/$t.264 $CLIPS/$c.y4m 2> $W/out/$t.log
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
        # arms at different shas (or a patched tree) differ in the version SEI: compare bitstreams within a sha only
        bb=$(md5sum $W/out/md5_base_${c}_$m.264 $W/out/md5_base2_${c}_$m.264 | awk '{print $1}' | sort -u | wc -l)
        ba=$(md5sum $W/out/md5_arm_${c}_$m.264 $W/out/md5_arm2_${c}_$m.264 | awk '{print $1}' | sort -u | wc -l)
        echo "$c $m: recon md5 distinct $r (1 = pass); bitstream distinct base/base2 $bb, arm/arm2 $ba (1 and 1 = deterministic)"
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
