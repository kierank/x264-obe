#!/bin/bash
# In-situ A/B for wip/x264-nw-mbtree (x264-obe, public github), Step B protocol.
# Run each part alone, nothing else heavy on the box.
#   bash nwmbtree-ab.sh build        # trees + binaries for the chosen AB (every part needs it)
#   bash nwmbtree-ab.sh live         # counter build of the arm: strip folds, rows folded, |dy| > 3 entries, fused B rows
#   bash nwmbtree-ab.sh md5          # gate: recon + bitstream md5, 4 arms, every clip
#   bash nwmbtree-ab.sh time [R]     # paired rounds (default 9), rotated arm order
#   bash nwmbtree-ab.sh report       # per-clip paired medians (user+sys CPU and elapsed) + A/A
# Set: CLIPS (dir with the clips as .y4m), CORE (one cpu), AB.
#   AB=avx2   Core 3 (Intel AVX2): base = 8f852830 (all kernels assembled, undispatched), arm = f017bec6 (AVX2 dispatch:
#             mbtree_propagate_list / list2 = strip_asm_avx2). On AVX2-only cpus 0b09bab8 = f017bec6.
#   AB=cstrip Core 3, optional: base = 8f852830, arm = 8f852830 with the C strip (old internal kernel + C int32 strip,
#             commits 1-3) dispatched by a sed of mc-c.c. Separates the C tail from the strip kernels.
#   AB=avx512 rack01 (Zen 4): base = f017bec6 (AVX-512 machines still on the old avx512 wrapper), arm = 0b09bab8
#             (mbtree_propagate_list / list2 = strip_asm_avx512).
# Only the normal cell: the lowlat cell has no mbtree.
set -u
AB=${AB:-avx2}
W=${W:-$HOME/x264-nwmbtree-$AB}
CLIPS=${CLIPS:?set CLIPS to the clip dir}
CORE=${CORE:?set CORE to one cpu}
REPO=https://github.com/kierank/x264-obe
BRANCH=wip/x264-nw-mbtree
case $AB in
avx2)   BASE=8f852830; ARM=f017bec6 ;;
cstrip) BASE=8f852830; ARM=8f852830 ;;
avx512) BASE=f017bec6;  ARM=0b09bab8 ;;
*) echo "unknown AB $AB"; exit 1 ;;
esac
# Core 3: 30 frames of tile-chaos-p and field-frame-mix-i, 60 of the weighted sgfades-p / sgfades-i
# (mbtree is in the lookahead). rack01: FRAMES30= FRAMES60= (empty) for whole clips, and
# CLIPLIST="fades-p tile-chaos-p pan-fast-p fades-i field-frame-mix-i credits-i sgfades-p sgfades-i".
FRAMES30=${FRAMES30-30}; FRAMES60=${FRAMES60-60}
CLIPLIST=${CLIPLIST:-"tile-chaos-p field-frame-mix-i sgfades-p sgfades-i"}
NORMAL="--subme 6 --me hex --ref 2 --no-mixed-refs --no-chroma-me --trellis 1 --partitions i8x8,i4x4 --psy-rd 1.0:0 --bframes 3 --rc-lookahead 24 --keyint 30 --bitrate 20000 --vbv-maxrate 20000 --vbv-bufsize 20000 --nal-hrd fakevbr --aud --pic-struct --open-gop --profile high --threads 1"

tree() { # name sha [cnt|cstrip]
    local d=$W/$1
    [ -x $d/x264 ] && return 0
    rm -rf $d && git clone -q $REPO $d && cd $d && git fetch -q origin $BRANCH && git checkout -q $2 || exit 1
    test "$(git rev-parse --short=8 HEAD)" = "$2" || { echo "WRONG TREE $1"; exit 1; }
    if [ "${3:-}" = cstrip ] || [ "$AB" = cstrip -a "${1#arm}" != "$1" ]; then
        # dispatch the C strip at the AVX2 level (the AVX512 block still overrides list on AVX-512 cpus)
        grep -q '^    pf->mbtree_propagate_list = x264_mbtree_propagate_list_avx2;$' common/x86/mc-c.c || { echo "cstrip: no avx2 line"; exit 1; }
        sed -i 's/^    pf->mbtree_propagate_list = x264_mbtree_propagate_list_avx2;$/    pf->mbtree_propagate_list = x264_mbtree_propagate_list_strip_avx2;\n    pf->mbtree_propagate_list2 = x264_mbtree_propagate_list2_strip_avx2;/' common/x86/mc-c.c
        git diff --stat
    fi
    case "$1" in *cnt) sh $W/nwmbcnt.sh $d || exit 1 ;; esac
    ./configure --bit-depth=8 --enable-static --disable-opencl --extra-cflags="-fno-fast-math -ffp-contract=off -fno-pie" --extra-ldflags="-no-pie" > cfg.log 2>&1 || exit 1
    make -j"$(nproc)" x264 checkasm8 > make.log 2>&1 || { tail make.log; exit 1; }
}

case "$1" in
build)
    mkdir -p $W
    [ -f $W/nwmbcnt.sh ] || { echo "copy nwmbcnt.sh to $W first"; exit 1; }
    tree base $BASE; tree base2 $BASE; tree arm $ARM; tree arm2 $ARM; tree armcnt $ARM
    md5sum $W/{base,base2,arm,arm2}/x264 | sed "s|$W/||"   # base == base2, arm == arm2 expected
    for a in base arm; do (cd $W/$a && for s in 1001 2002 3003; do taskset -c $CORE ./checkasm8 $s > $W/ck_${a}_$s.txt 2>&1; echo "$a checkasm8 seed $s rc $? $(grep -c FAILED $W/ck_${a}_$s.txt) fails"; done); done
    (cd $W/arm && taskset -c $CORE ./checkasm8 --bench=mbtree_propagate_list 1001 | grep -E "^mbtree_propagate_list|nop")
    ;;
enc) # arm clip tag: one encode; prints "user+sys elapsed"
    a=$2; c=$3; t=$4
    il=""; case $c in *-i) il="--tff";; esac
    fr=$FRAMES30; case $c in sgfades-*) fr=$FRAMES60;; esac
    [ -n "$fr" ] && fr="--frames $fr"
    perf stat -x, -e cycles:u,instructions:u -o $W/out/$t.perf -- /usr/bin/time -f "%e" -o $W/out/$t.wall taskset -c $CORE $W/$a/x264 $NORMAL $il $fr ${DUMP:-} -o $W/out/$t.264 $CLIPS/$c.y4m 2> $W/out/$t.log
    echo "$(awk -F, '/cycles:u/{print $1}' $W/out/$t.perf) 0 $(cat $W/out/$t.wall)" > $W/out/$t.time; awk -F, '/instructions:u/{print $1}' $W/out/$t.perf > $W/out/$t.insn   # col1 = cycles:u (Core 3 standard 11-11), col3 = elapsed s
    awk '{ printf "%.3f %.3f\n", $1+$2, $3 }' $W/out/$t.time
    ;;
live)
    # per clip: strip folds (= list calls), rows folded, entries on the direct path, fused B rows (list2)
    mkdir -p $W/out
    for c in $CLIPLIST; do
        bash $0 enc armcnt $c live_$c > /dev/null
        echo "$c: $(grep NWCNT $W/out/live_$c.log)"
    done
    ;;
md5)
    mkdir -p $W/out
    for c in $CLIPLIST; do
        for a in base base2 arm arm2; do DUMP="--dump-yuv $W/out/rec_$a.yuv" bash $0 enc $a $c md5_${a}_$c > /dev/null; done
        r=$(md5sum $W/out/rec_{base,base2,arm,arm2}.yuv | awk '{print $1}' | sort -u | wc -l)
        bb=$(md5sum $W/out/md5_{base,base2}_$c.264 | awk '{print $1}' | sort -u | wc -l)
        ba=$(md5sum $W/out/md5_{arm,arm2}_$c.264 | awk '{print $1}' | sort -u | wc -l)
        # bitstreams differ across shas (version SEI): compare them only within one sha
        echo "$c normal: recon md5 distinct across 4 arms $r, bitstream distinct base/base2 $bb arm/arm2 $ba (1 1 1 = pass)"
        rm -f $W/out/rec_*.yuv
    done
    ;;
time)
    R=${2:-9}; mkdir -p $W/out; arms=(base base2 arm arm2)
    for r in $(seq 1 $R); do for c in $CLIPLIST; do
        for k in 0 1 2 3; do a=${arms[$(( (k + r) % 4 ))]}
            echo "$r ${c}_normal $a $(bash $0 enc $a $c t_${r}_${a})" >> $W/times.txt
        done
    done; done
    ;;
report)
    for col in 4 5; do
    [ $col = 4 ] && echo "== CPU (user+sys)" || echo "== elapsed"
    awk -v col=$col '{ t[$2" "$1" "$3] = $col; cells[$2] = 1; if( $1 > R ) R = $1 }
    function med( v, n,   i, j, x ) { for( i = 1; i <= n; i++ ) for( j = i+1; j <= n; j++ ) if( v[j] < v[i] ) { x = v[i]; v[i] = v[j]; v[j] = x }
                                    return n % 2 ? v[(n+1)/2] : (v[n/2] + v[n/2+1]) / 2 }
    END { for( c in cells ) { n = 0; w = 0
            for( r = 1; r <= R; r++ ) { k = c" "r; if( !((k" base") in t) ) continue; n++
              d1[n] = 100*(t[k" arm"]/t[k" base"]-1); d2[n] = 100*(t[k" arm2"]/t[k" base2"]-1)
              a1[n] = 100*(t[k" base2"]/t[k" base"]-1); a2[n] = 100*(t[k" arm2"]/t[k" arm"]-1); w += (t[k" arm"] < t[k" base"]) }
            printf "%-26s arm-base %+.2f %%  arm2-base2 %+.2f %%  A/A base %+.2f %%  A/A arm %+.2f %%  arm faster %d/%d\n", c, med(d1,n), med(d2,n), med(a1,n), med(a2,n), w, n } }' $W/times.txt | sort
    done
    ;;
esac
