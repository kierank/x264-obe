#!/bin/bash
# In-situ A/B for wip/x264-nw-infra (x264-obe, public github), Step B protocol.
# Run each part alone, nothing else heavy on the box.
#   bash nwinfra-ab.sh build        # trees + binaries for the chosen AB (every part needs it)
#   bash nwinfra-ab.sh live         # counter build of the arm: calls of each new path per cell
#   bash nwinfra-ab.sh md5          # gate: recon + bitstream md5, 4 arms, every cell
#   bash nwinfra-ab.sh nondet [N]   # AB=thr: N (default 20) repeats of base and arm per threaded cell, distinct md5s
#   bash nwinfra-ab.sh time [R]     # paired rounds (default 9), rotated arm order
#   bash nwinfra-ab.sh report       # per-cell paired medians (user+sys CPU and elapsed) + A/A
# Set: CLIPS (dir with the clips as .y4m), CORES (cpu list: one cpu for t1 cells, 4 for the
# threaded ones, e.g. CORES=2-5; t1 cells run on the first), AB.
#   AB=thr    base = 42c3f783 (speed-next), arm = 790c3e79 (threadpool signal, keyframe analysis
#             outside ofbuf.mutex, slice 0 on the caller). Cells: t1, t4, t4la4 (obed's 4 lookahead threads).
#   AB=asm    base = 8df5d016 (all kernels assembled, undispatched), arm = tip 2464038e (hpel dual/copy_vc,
#             lowres pad, expand_border_sides, hpel side pads dispatched). Cells: t1.
#   AB=hpel   base = 8df5d016, arm = a27a3925 (hpel_filter_dual + copy_vc only)
#   AB=lowres base = a27a3925, arm = 60e2dd6c (frame_init_lowres_core_pad only)
#   AB=sides  base = 60e2dd6c, arm = fbcb12be (expand_border_sides only)
#   AB=hpelpad base = fbcb12be, arm = 2464038e (hpel_filter_pad: hpel writes the filtered side pads)
#   rack01 (Zen 4): the same modes; AB=asm there is the Zen 4 dispatch (lowres pad avx512icl, the rest avx2).
set -u
AB=${AB:-asm}
W=${W:-$HOME/x264-nwinfra-$AB}
CLIPS=${CLIPS:?set CLIPS to the clip dir}
CORES=${CORES:?set CORES to a cpu list, eg 2-5}
CORE1=${CORES%%[-,]*}
REPO=https://github.com/kierank/x264-obe
BRANCH=wip/x264-nw-infra
SN=42c3f783
case $AB in
thr)    BASE=$SN;      ARM=790c3e79; CELLS=${CELLS:-"t1 t4 t4la4"} ;;
asm)    BASE=8df5d016;    ARM=2464038e; CELLS=${CELLS:-"t1"} ;;
hpel)   BASE=8df5d016;    ARM=a27a3925;  CELLS=${CELLS:-"t1"} ;;
lowres) BASE=a27a3925;     ARM=60e2dd6c;  CELLS=${CELLS:-"t1"} ;;
sides)  BASE=60e2dd6c;     ARM=fbcb12be; CELLS=${CELLS:-"t1"} ;;
hpelpad) BASE=fbcb12be;    ARM=2464038e; CELLS=${CELLS:-"t1"} ;;
*) echo "unknown AB $AB"; exit 1 ;;
esac
# Core 3: 30 frames of tile-chaos-p and field-frame-mix-i, 60 of the weighted sgfades-p / sgfades-i
# (the lookahead and weightp are touched). rack01: set FRAMES30= FRAMES60= (empty) for whole clips.
FRAMES30=${FRAMES30-30}; FRAMES60=${FRAMES60-60}
CLIPLIST=${CLIPLIST:-"tile-chaos-p field-frame-mix-i sgfades-p sgfades-i"}
LOWLAT="--preset veryfast --tune zerolatency --intra-refresh --keyint 30 --bitrate 20000 --vbv-maxrate 20000 --vbv-bufsize 667 --nal-hrd fakevbr --aud --pic-struct --open-gop --profile high"
NORMAL="--subme 6 --me hex --ref 2 --no-mixed-refs --no-chroma-me --trellis 1 --partitions i8x8,i4x4 --psy-rd 1.0:0 --bframes 3 --rc-lookahead 24 --keyint 30 --bitrate 20000 --vbv-maxrate 20000 --vbv-bufsize 20000 --nal-hrd fakevbr --aud --pic-struct --open-gop --profile high"

tree() { # name sha cnt?
    local d=$W/$1
    [ -x $d/x264 ] && return 0
    rm -rf $d && git clone -q $REPO $d && cd $d && git fetch -q origin $BRANCH && git checkout -q $2 || exit 1
    test "$(git rev-parse --short=8 HEAD)" = "$2" || { echo "WRONG TREE $1"; exit 1; }
    [ "${3:-}" = cnt ] && { sh $W/nwcnt.sh $d || exit 1; }
    ./configure --bit-depth=8 --enable-static --disable-opencl --extra-cflags="-fno-fast-math -ffp-contract=off -fno-pie" --extra-ldflags="-no-pie" > cfg.log 2>&1 || exit 1
    make -j"$(nproc)" x264 checkasm8 > make.log 2>&1 || { tail make.log; exit 1; }
}

case "$1" in
build)
    mkdir -p $W
    [ -f $W/nwcnt.sh ] || { echo "copy nwcnt.sh to $W first"; exit 1; }
    tree base $BASE; tree base2 $BASE; tree arm $ARM; tree arm2 $ARM; tree armcnt 2464038e cnt   # counters on the whole series (tip), any AB
    md5sum $W/{base,base2,arm,arm2}/x264 | sed "s|$W/||"   # base == base2, arm == arm2 expected
    for a in base arm; do (cd $W/$a && for s in 1001 2002 3003; do taskset -c $CORE1 ./checkasm8 $s > $W/ck_${a}_$s.txt 2>&1; echo "$a checkasm8 seed $s rc $? $(grep -c FAILED $W/ck_${a}_$s.txt) fails"; done); done
    (cd $W/arm && taskset -c $CORE1 ./checkasm8 --bench=hpel 1001 | grep -E "^hpel|nop"; taskset -c $CORE1 ./checkasm8 --bench=lowres 1001 | grep -E "^lowres"; taskset -c $CORE1 ./checkasm8 --bench=expand_border 1001 | grep -E "^expand")
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
live)
    # liveness: per-cell call counts of each new path, counter build of the tip (whole series) (NWCNT line at exit); 0 where the
    # cell can't reach it (eg dual/vc at -p, the keyframe-analysis-outside-lock count at t1)
    mkdir -p $W/out
    for c in $CLIPLIST; do for m in lowlat normal; do for cell in $CELLS t4la4; do
        bash $0 enc armcnt $c $m $cell live_${c}_${m}_$cell > /dev/null
        echo "$c $m $cell: $(grep NWCNT $W/out/live_${c}_${m}_$cell.log)"
    done; done; done
    ;;
md5)
    mkdir -p $W/out
    for c in $CLIPLIST; do for m in lowlat normal; do for cell in $CELLS; do
        for a in base base2 arm arm2; do DUMP="--dump-yuv $W/out/rec_$a.yuv" bash $0 enc $a $c $m $cell md5_${a}_${c}_${m}_$cell > /dev/null; done
        r=$(md5sum $W/out/rec_{base,base2,arm,arm2}.yuv | awk '{print $1}' | sort -u | wc -l)
        b=$(md5sum $W/out/md5_{base,base2}_${c}_${m}_$cell.264 | awk '{print $1}' | sort -u | wc -l)
        b2=$(md5sum $W/out/md5_{arm,arm2}_${c}_${m}_$cell.264 | awk '{print $1}' | sort -u | wc -l)
        # bitstreams only within a sha: the version SEI differs between shas
        echo "$c $m $cell: recon md5 distinct across 4 arms $r, bitstream distinct base/base2 $b arm/arm2 $b2 (1 1 1 = pass)"
        rm -f $W/out/rec_*.yuv
    done; done; done
    ;;
nondet)
    N=${2:-20}; mkdir -p $W/out
    for c in $CLIPLIST; do for m in lowlat normal; do for cell in t4 t4la4; do
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
time)
    R=${2:-9}; mkdir -p $W/out; arms=(base base2 arm arm2)
    for r in $(seq 1 $R); do for c in $CLIPLIST; do for m in lowlat normal; do for cell in $CELLS; do
        for k in 0 1 2 3; do a=${arms[$(( (k + r) % 4 ))]}
            echo "$r ${c}_${m}_$cell $a $(bash $0 enc $a $c $m $cell t_${r}_${a})" >> $W/times.txt
        done
    done; done; done; done
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
