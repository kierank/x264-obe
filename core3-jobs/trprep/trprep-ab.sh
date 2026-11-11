#!/bin/bash
# In-situ A/B for wip/x264-nw-trprep (x264-obe, public github), Step B protocol.
# Run each part alone, nothing else heavy on the box.
#   bash trprep-ab.sh build        # trees + binaries (every part needs it); checkasm 3 seeds + bench
#   bash trprep-ab.sh live         # counter tree of the arm: calls of each new kernel per cell (TRCNT)
#   bash trprep-ab.sh md5          # gate: recon md5 across the 4 arms, bitstream md5 within a sha
#   bash trprep-ab.sh time [R]     # paired rounds (default 9), rotated arm order
#   bash trprep-ab.sh report       # per-cell paired medians (user+sys CPU and elapsed) + A/A
# Set: CLIPS (dir with the clips as .y4m), CORE (one cpu), AB.
#   AB=tip  base = 40527133 (tip~1: kernels assembled, callers in place, all NULL), arm = tip 2534f770
#           (AVX2 trellis prep + post dispatched; AVX-512 machines run the same avx2 pointers)
#   AB=icl  (rack01 / Zen 5 only) base = 2534f770, arm = 2534f770 + icl-dispatch.patch (the avx512icl
#           kernels dispatched; copy icl-dispatch.patch to $W first)
#   AB=post8 (Core 3) base = 2534f770, arm = 2534f770 + post8-dispatch.patch (dequant_8x8_scan avx2 dispatched:
#           the 8x8 trellis post, a loss/neutral on the laptop; copy post8-dispatch.patch to $W first)
# The change is reached only with trellis >= 1 (NORMAL, and NORMAL7 = production's subme 7 for B-frame RD);
# LOWLAT is trellis 0, a null control: identical md5 and ~0 time delta expected.
set -u
AB=${AB:-tip}
W=${W:-$HOME/x264-trprep-$AB}
CLIPS=${CLIPS:?set CLIPS to the clip dir}
CORE=${CORE:?set CORE to one cpu, eg 2}
REPO=https://github.com/kierank/x264-obe
case $AB in
tip)   BASE=40527133; ARM=2534f770; BR=wip/x264-nw-trprep; PATCH= ;;
icl)   BASE=2534f770; ARM=2534f770; BR=wip/x264-nw-trprep; PATCH=icl-dispatch.patch ;;
post8) BASE=2534f770; ARM=2534f770; BR=wip/x264-nw-trprep; PATCH=post8-dispatch.patch ;;
*) echo "unknown AB $AB"; exit 1 ;;
esac
# Core 3: 30 frames. rack01: FRAMES30= (empty) for whole clips, and
# CLIPLIST="fades-p tile-chaos-p pan-fast-p fades-i field-frame-mix-i credits-i".
FRAMES30=${FRAMES30-30}
CLIPLIST=${CLIPLIST:-"tile-chaos-p field-frame-mix-i"}
MODES=${MODES:-"normal normal7 lowlat"}
LOWLAT="--preset veryfast --tune zerolatency --intra-refresh --keyint 30 --bitrate 20000 --vbv-maxrate 20000 --vbv-bufsize 667 --nal-hrd fakevbr --aud --pic-struct --open-gop --profile high --threads 1"
NORMAL="--subme 6 --me hex --ref 2 --no-mixed-refs --no-chroma-me --trellis 1 --partitions i8x8,i4x4 --psy-rd 1.0:0 --bframes 3 --rc-lookahead 24 --keyint 30 --bitrate 20000 --vbv-maxrate 20000 --vbv-bufsize 20000 --nal-hrd fakevbr --aud --pic-struct --open-gop --profile high --threads 1"
NORMAL7=${NORMAL/--subme 6/--subme 7}

tree() { # name sha cnt?
    local d=$W/$1
    [ -x $d/x264 ] && return 0
    rm -rf $d && git clone -q $REPO $d && cd $d && git fetch -q origin $BR && git checkout -q $2 || exit 1
    test "$(git rev-parse --short=8 HEAD)" = "$2" || { echo "WRONG TREE $1"; exit 1; }
    [ -n "$PATCH" ] && case $1 in arm*) git apply $W/$PATCH || exit 1 ;; esac
    [ "${3:-}" = cnt ] && { sh $W/trcnt.sh $d || exit 1; }
    ./configure --bit-depth=8 --enable-static --disable-opencl --extra-cflags="-fno-fast-math -ffp-contract=off -fno-pie" --extra-ldflags="-no-pie" > cfg.log 2>&1 || exit 1
    make -j"$(nproc)" x264 checkasm8 > make.log 2>&1 || { tail make.log; exit 1; }
}

case "$1" in
build)
    mkdir -p $W
    [ -f $W/trcnt.sh ] || { echo "copy trcnt.sh to $W first"; exit 1; }
    tree base $BASE; tree base2 $BASE; tree arm $ARM; tree arm2 $ARM; tree armcnt $ARM cnt
    md5sum $W/{base,base2,arm,arm2}/x264 | sed "s|$W/||"   # base == base2, arm == arm2 expected
    for a in base arm; do (cd $W/$a && for s in 1001 2002 3003; do taskset -c $CORE ./checkasm8 $s > $W/ck_${a}_$s.txt 2>&1; echo "$a checkasm8 seed $s rc $? $(grep -c FAILED $W/ck_${a}_$s.txt) fails, $(grep 'trellis scan' $W/ck_${a}_$s.txt)"; done); done
    # per call: T = (printed + nop/4) / 10; _split = the calls each kernel replaces, same blocks
    (cd $W/arm && for p in quant_4x4x4_scan_trellis quant_8x8_scan_trellis dequant_4x4x4_scan dequant_8x8_scan; do
        taskset -c $CORE ./checkasm8 --bench=$p 1001 | grep -E "nop:|_flat" | grep -v cqm; done)
    ;;
enc) # arm clip mode tag: one encode; prints "user+sys elapsed"
    a=$2; c=$3; m=$4; t=$5
    il=""; case $c in *-i) il="--tff";; esac
    fr=""; [ -n "$FRAMES30" ] && fr="--frames $FRAMES30"
    case $m in lowlat) opt=$LOWLAT ;; normal) opt=$NORMAL ;; normal7) opt=$NORMAL7 ;; esac
    perf stat -x, -e cycles:u,instructions:u -o $W/out/$t.perf -- /usr/bin/time -f "%e" -o $W/out/$t.wall taskset -c $CORE $W/$a/x264 $opt $il $fr ${DUMP:-} -o $W/out/$t.264 $CLIPS/$c.y4m 2> $W/out/$t.log
    echo "$(awk -F, '/cycles:u/{print $1}' $W/out/$t.perf) 0 $(cat $W/out/$t.wall)" > $W/out/$t.time; awk -F, '/instructions:u/{print $1}' $W/out/$t.perf > $W/out/$t.insn   # col1 = cycles:u (Core 3 standard 11-11), col3 = elapsed s
    awk '{ printf "%.3f %.3f\n", $1+$2, $3 }' $W/out/$t.time
    ;;
live)
    mkdir -p $W/out
    for c in $CLIPLIST; do for m in $MODES; do
        bash $0 enc armcnt $c $m live_${c}_$m > /dev/null
        echo "$c $m: $(grep TRCNT $W/out/live_${c}_$m.log)"   # lowlat: all 0 (trellis 0)
    done; done
    ;;
md5)
    mkdir -p $W/out
    for c in $CLIPLIST; do for m in $MODES; do
        for a in base base2 arm arm2; do DUMP="--dump-yuv $W/out/rec_$a.yuv" bash $0 enc $a $c $m md5_${a}_${c}_$m > /dev/null; done
        r=$(md5sum $W/out/rec_{base,base2,arm,arm2}.yuv | awk '{print $1}' | sort -u | wc -l)
        b=$(md5sum $W/out/md5_{base,base2}_${c}_$m.264 | awk '{print $1}' | sort -u | wc -l)
        b2=$(md5sum $W/out/md5_{arm,arm2}_${c}_$m.264 | awk '{print $1}' | sort -u | wc -l)
        # bitstreams only within a sha: the version SEI differs between shas
        echo "$c $m: recon md5 distinct across 4 arms $r, bitstream distinct base/base2 $b arm/arm2 $b2 (1 1 1 = pass)"
        rm -f $W/out/rec_*.yuv
    done; done
    ;;
time)
    R=${2:-9}; mkdir -p $W/out; arms=(base base2 arm arm2)
    for r in $(seq 1 $R); do for c in $CLIPLIST; do for m in $MODES; do
        for k in 0 1 2 3; do a=${arms[$(( (k + r) % 4 ))]}
            echo "$r ${c}_$m $a $(bash $0 enc $a $c $m t_${r}_${a})" >> $W/times.txt
        done
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
            printf "%-30s arm-base %+.2f %%  arm2-base2 %+.2f %%  A/A base %+.2f %%  A/A arm %+.2f %%  arm faster %d/%d\n", c, med(d1,n), med(d2,n), med(a1,n), med(a2,n), w, n } }' $W/times.txt | sort
    done
    ;;
esac
