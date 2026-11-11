#!/bin/bash
# In-situ A/B for wip/x264-nw-lapipe (x264-obe, github kierank/x264-obe), Step B protocol.
# Run each part alone, nothing else heavy on the box.
#   bash lapipe-ab.sh build        # trees + binaries for the chosen AB (every part needs it)
#   bash lapipe-ab.sh md5          # gate: recon md5 across base/base2/arm/arm2, bitstream within a sha, every cell
#   bash lapipe-ab.sh nondet [N]   # N (default 20) repeats of base and arm per threaded cell: distinct bitstreams
#   bash lapipe-ab.sh traffic      # AB=grp only: lowres plane traffic model + group liveness, base vs arm (counter builds)
#   bash lapipe-ab.sh time [R]     # paired rounds (default 9), rotated arm order
#   bash lapipe-ab.sh report       # per-cell paired medians (user+sys CPU and elapsed) + A/A
#   bash lapipe-ab.sh quality      # AB=fpel only: bitrate / PSNR / SSIM of base vs arm per lowlat cell (no md5 gate)
# Set: CLIPS (dir with the clips as .y4m), CORES (cpu list: one cpu for t1 cells, 4 for the
# threaded ones, e.g. CORES=2-5; t1 cells run on the first), AB.
#   AB=grp   item 3, bit-exact: base = 4e292d6a (speed-next), arm = b1d57371 (wip tip: refactor, b-adapt
#            group, mbtree group, lookahead_fpel off). Cells t1, t4, t4la4 (obed's 4 lookahead threads).
#            The schedule change is in NORMAL (b-adapt, mbtree); LOWLAT must be md5-identical too.
#   AB=refac / badapt / mbtree: one commit each (refactor alone, b-adapt group, mbtree group), same cells.
#   AB=fpel  item 8, output-changing: base = b1d57371, arm = 271581f8 (test/x264-nw-lapipe-fpel-on: the
#            switch on by default). LOWLAT changes (quality + time); NORMAL must stay md5-identical
#            (B-frames validate it off).
# Counter builds (AB=grp traffic): base = 2cdb8175 (counter on the refactor, serial schedule),
# arm = 0ea63421 (counter + b-adapt + mbtree groups), branch test/x264-nw-lapipe-traffic,
# built with -DX264_LOWRES_TRAFFIC=1. The counter build of the base must give the same recon md5.
set -u
AB=${AB:-grp}
W=${W:-$HOME/x264-lapipe-$AB}
CLIPS=${CLIPS:?set CLIPS to the clip dir}
CORES=${CORES:?set CORES to a cpu list, eg 2-5}
CORE1=${CORES%%[-,]*}
REPO=https://github.com/kierank/x264-obe
BRANCHES="wip/x264-nw-lapipe test/x264-nw-lapipe-traffic test/x264-nw-lapipe-fpel-on"
SN=4e292d6a
case $AB in
grp)  BASE=$SN;      ARM=b1d57371; CELLS=${CELLS:-"t1 t4 t4la4"}; MODES=${MODES:-"normal lowlat"} ;;
fpel) BASE=b1d57371; ARM=271581f8; CELLS=${CELLS:-"t1 t4"};       MODES=${MODES:-"lowlat normal"} ;;
refac) BASE=$SN;      ARM=10443289; CELLS=${CELLS:-"t1 t4la4"}; MODES=${MODES:-"normal lowlat"} ;;
badapt) BASE=10443289; ARM=435424dd; CELLS=${CELLS:-"t1 t4la4"}; MODES=${MODES:-"normal"} ;;
mbtree) BASE=435424dd; ARM=dc9122e0; CELLS=${CELLS:-"t1 t4la4"}; MODES=${MODES:-"normal"} ;;
*) echo "unknown AB $AB"; exit 1 ;;
esac
# Core 3: 30 frames of tile-chaos-p and field-frame-mix-i, 60 of the weighted sgfades-p / sgfades-i
# (lookahead + weightp). rack01: FRAMES30= FRAMES60= (empty) for whole clips, CLIPLIST of the 6.
FRAMES30=${FRAMES30-30}; FRAMES60=${FRAMES60-60}
CLIPLIST=${CLIPLIST:-"tile-chaos-p field-frame-mix-i sgfades-p sgfades-i"}
LOWLAT="--preset veryfast --tune zerolatency --intra-refresh --keyint 30 --bitrate 20000 --vbv-maxrate 20000 --vbv-bufsize 667 --nal-hrd fakevbr --aud --pic-struct --open-gop --profile high"
NORMAL="--subme 6 --me hex --ref 2 --no-mixed-refs --no-chroma-me --trellis 1 --partitions i8x8,i4x4 --psy-rd 1.0:0 --bframes 3 --rc-lookahead 24 --keyint 30 --bitrate 20000 --vbv-maxrate 20000 --vbv-bufsize 20000 --nal-hrd fakevbr --aud --pic-struct --open-gop --profile high"

tree() { # name sha [cflags]
    local d=$W/$1
    [ -x $d/x264 ] && return 0
    rm -rf $d && git clone -q $REPO $d && cd $d || exit 1
    for b in $BRANCHES; do git fetch -q origin $b; done
    git checkout -q $2 || exit 1
    test "$(git rev-parse --short=8 HEAD)" = "$2" || { echo "WRONG TREE $1"; exit 1; }
    ./configure --bit-depth=8 --enable-static --disable-opencl --extra-cflags="-fno-fast-math -ffp-contract=off -fno-pie ${3:-}" --extra-ldflags="-no-pie" > cfg.log 2>&1 || exit 1
    make -j"$(nproc)" x264 > make.log 2>&1 || { tail make.log; exit 1; }
}

case "$1" in
build)
    mkdir -p $W
    tree base $BASE; tree base2 $BASE; tree arm $ARM; tree arm2 $ARM
    [ $AB = grp ] && { tree cntbase 2cdb8175 -DX264_LOWRES_TRAFFIC=1; tree cntarm 0ea63421 -DX264_LOWRES_TRAFFIC=1; }
    md5sum $W/{base,base2,arm,arm2}/x264 | sed "s|$W/||"   # base == base2, arm == arm2 expected
    ;;
enc) # arm clip mode cell tag: one encode; prints "user+sys elapsed"
    a=$2; c=$3; m=$4; cell=$5; t=$6
    il=""; case $c in *-i) il="--tff";; esac
    fr=$FRAMES30; case $c in sgfades-*) fr=$FRAMES60;; esac
    [ -n "$fr" ] && fr="--frames $fr"
    opt=$LOWLAT; [ $m = normal ] && opt=$NORMAL
    case $cell in
    t1)    thr="--threads 1"; cpus=$CORE1 ;;
    t4)    thr="--threads 4"; cpus=$CORES ;;
    t4la4) thr="--threads 4 --lookahead-threads 4"; cpus=$CORES ;;
    esac
    perf stat -x, -e cycles:u,instructions:u -o $W/out/$t.perf -- /usr/bin/time -f "%e" -o $W/out/$t.wall taskset -c $cpus $W/$a/x264 $opt $thr $il $fr ${DUMP:-} -o $W/out/$t.264 $CLIPS/$c.y4m 2> $W/out/$t.log
    echo "$(awk -F, '/cycles:u/{print $1}' $W/out/$t.perf) 0 $(cat $W/out/$t.wall)" > $W/out/$t.time; awk -F, '/instructions:u/{print $1}' $W/out/$t.perf > $W/out/$t.insn   # col1 = cycles:u (Core 3 standard 11-11), col3 = elapsed s
    awk '{ printf "%.3f %.3f\n", $1+$2, $3 }' $W/out/$t.time
    ;;
md5)
    mkdir -p $W/out
    for c in $CLIPLIST; do for m in $MODES; do for cell in $CELLS; do
        for a in base base2 arm arm2; do DUMP="--dump-yuv $W/out/rec_$a.yuv" bash $0 enc $a $c $m $cell md5_${a}_${c}_${m}_$cell > /dev/null; done
        r=$(md5sum $W/out/rec_{base,base2,arm,arm2}.yuv | awk '{print $1}' | sort -u | wc -l)
        b=$(md5sum $W/out/md5_{base,base2}_${c}_${m}_$cell.264 | awk '{print $1}' | sort -u | wc -l)
        b2=$(md5sum $W/out/md5_{arm,arm2}_${c}_${m}_$cell.264 | awk '{print $1}' | sort -u | wc -l)
        # bitstreams only within a sha: the version SEI differs between shas
        echo "$c $m $cell: recon md5 distinct across 4 arms $r, bitstream distinct base/base2 $b arm/arm2 $b2 (1 1 1 = pass; AB=fpel lowlat: 2 1 1 expected)"
        rm -f $W/out/rec_*.yuv
    done; done; done
    ;;
nondet)
    N=${2:-20}; mkdir -p $W/out
    for c in $CLIPLIST; do for m in $MODES; do for cell in t4 t4la4; do
        for a in base arm; do
            DUMP="--dump-yuv $W/out/ndrec_$a.yuv" bash $0 enc $a $c $m $cell nd_${a}_1 > /dev/null
            for i in $(seq 2 $N); do bash $0 enc $a $c $m $cell nd_${a}_${i} > /dev/null; done
        done
        nb=$(md5sum $W/out/nd_base_*.264 | awk '{print $1}' | sort -u | wc -l)
        na=$(md5sum $W/out/nd_arm_*.264 | awk '{print $1}' | sort -u | wc -l)
        same=$(md5sum $W/out/ndrec_base.yuv $W/out/ndrec_arm.yuv | awk '{print $1}' | sort -u | wc -l)
        echo "$c $m $cell: $N runs per arm, distinct bitstreams within base $nb within arm $na, recon base vs arm distinct $same (1 1 1 = pass)"
        rm -f $W/out/nd_* $W/out/ndrec_*
    done; done; done
    ;;
traffic)
    # LOWRES_TRAFFIC line at exit of the counter builds: bytes the lookahead touches in the lowres planes and
    # the misses of a 1 MB / 2 MB per-thread LRU (cleared per slicetype_analyse); groups/members/cancelled =
    # liveness of the new schedule (0 groups in cntbase). Divide by the frame count for MB/f.
    mkdir -p $W/out
    for c in $CLIPLIST; do for cell in t1 t4la4; do
        for a in cntbase cntarm; do
            DUMP="--dump-yuv $W/out/trrec_$a.yuv" bash $0 enc $a $c normal $cell tr_${a} > /dev/null
            echo "$c normal $cell $a: $(grep LOWRES_TRAFFIC $W/out/tr_${a}.log)"
        done
        echo "$c normal $cell: counter-build recon distinct $(md5sum $W/out/trrec_cnt{base,arm}.yuv | awk '{print $1}' | sort -u | wc -l) (1 = pass)"
        rm -f $W/out/trrec_*
    done; done
    ;;
time)
    R=${2:-9}; mkdir -p $W/out; arms=(base base2 arm arm2)
    for r in $(seq 1 $R); do for c in $CLIPLIST; do for m in $MODES; do for cell in $CELLS; do
        for k in 0 1 2 3; do a=${arms[$(( (k + r) % 4 ))]}
            echo "$r ${c}_${m}_$cell $a $(bash $0 enc $a $c $m $cell t_${r}_${a})" >> $W/times.txt
        done
    done; done; done; done
    ;;
quality)
    mkdir -p $W/out
    for c in $CLIPLIST; do for cell in t1 t4; do for a in base arm; do
        bash $0 enc $a $c lowlat $cell q_${a} > /dev/null
        echo "$c lowlat $cell $a: $(grep -E '^x264 \[info\]: (kb/s|PSNR Mean|SSIM Mean)|encoded' $W/out/q_${a}.log | tr '\n' ' ') opt:$(strings $W/out/q_${a}.264 | grep -o 'lookahead_fpel=1' | head -1)"
    done; done; done
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
            printf "%-34s arm-base %+.2f %%  arm2-base2 %+.2f %%  A/A base %+.2f %%  A/A arm %+.2f %%  arm faster %d/%d\n", c, med(d1,n), med(d2,n), med(a1,n), med(a2,n), w, n } }' $W/times.txt | sort
    done
    ;;
esac
