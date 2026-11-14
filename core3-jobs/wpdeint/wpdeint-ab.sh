#!/bin/bash
# In-situ A/B for wip/x264-nw-wpdeint (x264-obe, public github), Step B protocol.
# Run each part alone, nothing else heavy on the box.
#   bash wpdeint-ab.sh build        # trees + binaries for the chosen AB (every part needs it)
#   bash wpdeint-ab.sh live         # counter build of the arm: chroma weightp analyses, ref rows mvs / no mvs
#   bash wpdeint-ab.sh md5          # gate: recon md5 across 4 arms, bitstream md5 within a sha, every cell
#   bash wpdeint-ab.sh time [R]     # paired rounds (default 9), rotated arm order
#   bash wpdeint-ab.sh report       # per-cell paired medians (user+sys CPU and elapsed) + A/A
# Set: CLIPS (dir with the clips as .y4m), CORE (one cpu), AB, optionally CLIP422 (an 8-bit 4:2:2 .y4m in
# CLIPS, without .y4m; adds the 422 cells).
#   AB=all    base = 4e292d6a (origin/speed-next 4e292d6a), arm = 5ed57f11: the whole series (C use site,
#             row-major chroma passes, dispatch). Core 3 and rack01.
#   AB=disp   base = 562fc1af (tip~1, undispatched), arm = 5ed57f11: the dispatch alone. Only the REACH cells
#             run the kernel (see below), so only they can move.
#   AB=row    base = bc895207 (tip~2), arm = 562fc1af (tip~1): the row-major chroma init passes alone
#             (C, all cpus; production cells: the mc_chroma path).
# Cells: lowlat + normal (production; weightp 1 / 2, ABR: the ref rows always have lowres mvs, so the
# fused kernel never runs there; the row-major passes do) and REACH: CQP, no scenecut, no B, no lookahead,
# the only way to reach the no-mvs path (weightp 2). `live` shows which path each cell takes.
set -u
AB=${AB:-all}
W=${W:-$HOME/x264-wpdeint-$AB}
CLIPS=${CLIPS:?set CLIPS to the clip dir}
CORE=${CORE:?set CORE to one cpu}
REPO=https://github.com/kierank/x264-obe
BRANCH=wip/x264-nw-wpdeint
case $AB in
all)  BASE=4e292d6a; ARM=5ed57f11 ;;
disp) BASE=562fc1af; ARM=5ed57f11 ;;
row)  BASE=bc895207; ARM=562fc1af ;;
*) echo "unknown AB $AB"; exit 1 ;;
esac
# Core 3: 30 frames of tile-chaos-p and field-frame-mix-i, 60 of the weighted sgfades-p / sgfades-i
# (weightp only triggers there). rack01: FRAMES30= FRAMES60= (empty) for whole clips, and
# CLIPLIST="fades-p tile-chaos-p pan-fast-p fades-i field-frame-mix-i credits-i sgfades-p sgfades-i".
FRAMES30=${FRAMES30-30}; FRAMES60=${FRAMES60-60}
CLIPLIST=${CLIPLIST:-"tile-chaos-p field-frame-mix-i sgfades-p sgfades-i"}
CLIP422=${CLIP422:-}
LOWLAT="--preset veryfast --tune zerolatency --intra-refresh --keyint 30 --bitrate 20000 --vbv-maxrate 20000 --vbv-bufsize 667 --nal-hrd fakevbr --aud --pic-struct --open-gop --profile high --threads 1"
NORMAL="--subme 6 --me hex --ref 2 --no-mixed-refs --no-chroma-me --trellis 1 --partitions i8x8,i4x4 --psy-rd 1.0:0 --bframes 3 --rc-lookahead 24 --keyint 30 --bitrate 20000 --vbv-maxrate 20000 --vbv-bufsize 20000 --nal-hrd fakevbr --aud --pic-struct --open-gop --profile high --threads 1"
REACH="--preset veryfast --tune zerolatency --qp 26 --no-scenecut --weightp 2 --keyint 30 --aud --profile high --threads 1"
P422="--profile high422 --output-csp i422"

tree() { # name sha
    local d=$W/$1
    if [ -x $d/x264 ]; then # an existing tree is reused only after the same sha check
        test "$(git -C $d rev-parse --short=8 HEAD)" = "$2" && return 0
        echo "stale tree $1 (not $2): rebuilding"
    fi
    rm -rf $d && git clone -q $REPO $d && cd $d && git fetch -q origin $BRANCH && git checkout -q $2 || exit 1
    test "$(git rev-parse --short=8 HEAD)" = "$2" || { echo "WRONG TREE $1"; exit 1; }
    case "$1" in *cnt) sh $W/wpcnt.sh $d || exit 1 ;; esac
    ./configure --bit-depth=8 --enable-static --disable-opencl --extra-cflags="-fno-fast-math -ffp-contract=off -fno-pie" --extra-ldflags="-no-pie" > cfg.log 2>&1 || exit 1
    # pin the version string: the SEI carries it, and a different length moves tight-VBV rate control and recon
    sed -i -e "s|^#define X264_VERSION .*|#define X264_VERSION \" rpinned\"|" -e "s|^#define X264_POINTVER .*|#define X264_POINTVER \"0.0.pinned\"|" x264_config.h
    grep -q "0.0.pinned" x264_config.h || { echo "version pin failed $1"; exit 1; }
    make -j"$(nproc)" x264 checkasm8 > make.log 2>&1 || { tail make.log; exit 1; }
}

cells() { # clip x cell
    for c in $CLIPLIST; do for m in lowlat normal reach; do echo "$c $m"; done; done
    [ -n "$CLIP422" ] && for m in lowlat normal reach; do echo "$CLIP422 ${m}422"; done
}

case "$1" in
build)
    mkdir -p $W
    [ -f $W/wpcnt.sh ] || { echo "copy wpcnt.sh to $W first"; exit 1; }
    tree base $BASE; tree base2 $BASE; tree arm $ARM; tree arm2 $ARM; tree armcnt $ARM
    md5sum $W/{base,base2,arm,arm2}/x264 | sed "s|$W/||"   # base == base2, arm == arm2 expected
    for a in base arm; do (cd $W/$a && for s in 1001 2002 3003; do taskset -c $CORE ./checkasm8 $s > $W/ck_${a}_$s.txt 2>&1; echo "$a checkasm8 seed $s rc $? $(grep -c FAILED $W/ck_${a}_$s.txt) fails"; done); done
    (cd $W/arm && taskset -c $CORE ./checkasm8 --bench=weightp_deint 1001 | grep -E "^weightp_deint|nop")
    ;;
enc) # arm clip cell tag: one encode; prints "user+sys elapsed"
    a=$2; c=$3; m=$4; t=$5
    il=""; case $c in *-i) il="--tff";; esac
    fr=$FRAMES30; case $c in sgfades-*) fr=$FRAMES60;; esac
    [ -n "$fr" ] && fr="--frames $fr"
    case $m in lowlat*) o=$LOWLAT;; normal*) o=$NORMAL;; reach*) o=$REACH;; esac
    case $m in *422) o="$o $P422";; esac
    /usr/bin/time -f "%U %S %e" -o $W/out/$t.time taskset -c $CORE $W/$a/x264 $o $il $fr ${DUMP:-} -o $W/out/$t.264 $CLIPS/$c.y4m 2> $W/out/$t.log
    awk '{ printf "%.3f %.3f\n", $1+$2, $3 }' $W/out/$t.time
    ;;
live)
    # per cell: weightp analyses (decide / lookahead), chroma inits, ref rows on mc_chroma (mvs) / on the copy (no mvs)
    mkdir -p $W/out
    cells | while read c m; do
        bash $0 enc armcnt $c $m live_${c}_$m > /dev/null
        echo "$c $m: $(grep WPCNT $W/out/live_${c}_$m.log)"
    done
    ;;
md5)
    mkdir -p $W/out
    cells | while read c m; do
        rm -f $W/out/rec_*.yuv $W/out/md5_*_${c}_$m.264
        for a in base base2 arm arm2; do DUMP="--dump-yuv $W/out/rec_$a.yuv" bash $0 enc $a $c $m md5_${a}_${c}_$m > /dev/null; done
        e=""; for f in $W/out/rec_{base,base2,arm,arm2}.yuv $W/out/md5_{base,base2,arm,arm2}_${c}_$m.264; do [ -s $f ] || e="$e $(basename $f)"; done
        [ -n "$e" ] && { echo "$c $m: FAIL: EMPTY or missing output:$e"; continue; }
        r=$(md5sum $W/out/rec_{base,base2,arm,arm2}.yuv | awk '{print $1}' | sort -u | wc -l)
        bb=$(md5sum $W/out/md5_{base,base2}_${c}_$m.264 | awk '{print $1}' | sort -u | wc -l)
        ba=$(md5sum $W/out/md5_{arm,arm2}_${c}_$m.264 | awk '{print $1}' | sort -u | wc -l)
        # bitstreams differ across shas (version SEI): compare them only within one sha
        echo "$c $m: recon md5 distinct across 4 arms $r, bitstream distinct base/base2 $bb arm/arm2 $ba (1 1 1 = pass)"
        rm -f $W/out/rec_*.yuv
    done
    ;;
time)
    R=${2:-9}; mkdir -p $W/out; arms=(base base2 arm arm2)
    for r in $(seq 1 $R); do cells | while read c m; do
        for k in 0 1 2 3; do a=${arms[$(( (k + r) % 4 ))]}
            echo "$r ${c}_$m $a $(bash $0 enc $a $c $m t_${r}_${a})" >> $W/times.txt
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
            printf "%-30s arm-base %+.2f %%  arm2-base2 %+.2f %%  A/A base %+.2f %%  A/A arm %+.2f %%  arm faster %d/%d\n", c, med(d1,n), med(d2,n), med(a1,n), med(a2,n), w, n } }' $W/times.txt | sort
    done
    ;;
esac
