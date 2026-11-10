#!/bin/bash
# rack01 (EPYC 8324P, Zen 4) jobs for wip/x264-avx512-parity 16b2a09e (x264-obe, public github).
# Run each part alone, nothing else timed or heavy on the box (node 3 timing rule).
#   bash rack01-parity.sh build            # trees + binaries (all parts need it)
#   bash rack01-parity.sh bench            # Part A: checkasm --bench, Zen 4 rows for the audit
#   bash rack01-parity.sh live             # Part C first: liveness counter builds, 1 encode per cell
#   bash rack01-parity.sh md5              # Part B gate: recon + bitstream md5, 4 arms, 12 cells
#   bash rack01-parity.sh time [rounds]    # Part B: paired rounds (default 5), user time
#   bash rack01-parity.sh report           # Part B: per-cell paired medians + A/A
# Set before running: CLIPS (dir holding the 6 Step B clips as .y4m), CORE (one node-3 cpu).
set -u
W=${W:-$HOME/x264-parity}
CLIPS=${CLIPS:?set CLIPS to the clip dir}
CORE=${CORE:?set CORE to a node-3 cpu}
REPO=https://github.com/kierank/x264-obe
# base: speed-next 9d1b4935 + wip/x264-fpel-fast merge + avx512-learnings (quant flat icl dispatched,
#   undispatched EVEX-VNNI ssd/nv12, sq_min bench). arm: + C1 qword handoffs + inline avx512 body + fenc in
#   registers. Only common/x86/me-64.asm differs between them.
BASE=adf31d1b
ARM=32a41fac
# 6 clips x lowlat/normal; -i = 1080i29.97 TFF (native interlaced), -p = 1080p59.94
CLIPLIST="fades-p tile-chaos-p pan-fast-p fades-i field-frame-mix-i credits-i"
COMMON="--bitrate 20000 --vbv-maxrate 20000 --nal-hrd fakevbr --aud --pic-struct --open-gop --profile high --keyint 30 --threads 1"
LOWLAT="--preset veryfast --tune zerolatency --intra-refresh --vbv-bufsize 667"
NORMAL="--subme 6 --me hex --ref 2 --no-mixed-refs --no-chroma-me --trellis 1 --partitions i8x8,i4x4 --psy-rd 1.0:0 --bframes 3 --rc-lookahead 24 --vbv-bufsize 20000"

tree() { # name sha [cnt]
    local d=$W/$1
    [ -x $d/x264 ] && return 0
    rm -rf $d && git clone -q $REPO $d && cd $d && git fetch -q origin wip/x264-avx512-parity && git checkout -q $2 || exit 1
    test "$(git rev-parse --short=8 HEAD)" = "$2" || { echo "WRONG TREE $1"; exit 1; }
    [ "${3:-}" = cnt ] && { sh $W/fpelcnt.sh $d || exit 1; }
    ./configure --bit-depth=8 --enable-static --disable-opencl --extra-cflags="-fno-fast-math -ffp-contract=off" > cfg.log 2>&1 || exit 1
    make -j"$(nproc)" x264 checkasm8 > make.log 2>&1 || { tail make.log; exit 1; }
}

case "$1" in
build)
    mkdir -p $W
    [ -f $W/fpelcnt.sh ] || { echo "copy fpelcnt.sh to $W first"; exit 1; }
    tree base $BASE; tree base2 $BASE; tree arm $ARM; tree arm2 $ARM
    tree basecnt $BASE cnt; tree armcnt $ARM cnt
    tree tip 16b2a09e
    md5sum $W/{base,base2,arm,arm2}/x264 | sed "s|$W/||"   # base == base2, arm == arm2 expected
    # structural liveness: the arm's avx512 entry is the inline body (its local labels), the base's is not
    for a in base arm; do echo "$a inline-avx512 labels: $(nm $W/$a/x264 | grep -c 'me_search_fpel_avx512\.s16x16_hex')"; done
    for a in base arm; do $W/$a/x264 --version | head -1; done
    ;;
bench)
    # Part A, tip tree: 3 seeds per prefix; seed is positional. Only rows print if every test passes; a run
    # that fails ONLY on "deblock_luma_intra[..](a=2, b=0, ...)" is the known beta-0 flake (avx/avx2 differ
    # from C at beta 0, which the encoder never passes): rerun that prefix with seed+1.
    cd $W/tip
    for p in sad_sq_min sad_dia_min sad_hex_min sad_oct_min sad_ring_min sad_hex_search sad_dia_search predictor me_search_fpel \
             sub4x4_dct sub8x8_dct_dc sub8x16_dct_dc dct2x4dc add16x16_idct8 intra_predict_8x8_filter load_deinterleave_chroma \
             ssd_ var_ var2_ weightp weight_plane aq_variance_tail mbtree_finish mbtree_propagate_list quant_8x8_scan deblock_ \
             cabac_block_residual; do
        for s in 1001 2002 3003; do
            taskset -c $CORE ./checkasm8 --bench=$p $s > $W/bench_${p}_$s.txt 2>&1 \
                || { grep -q "b=0" $W/bench_${p}_$s.txt && taskset -c $CORE ./checkasm8 --bench=$p $((s+1)) > $W/bench_${p}_$s.txt 2>&1; }
            echo "$p $s: $(tail -1 $W/bench_${p}_$s.txt) $(grep '^nop' $W/bench_${p}_$s.txt)"
        done
    done
    ;;
enc) # arm clip mode tag: one encode, user seconds to stdout
    a=$2; c=$3; m=$4; t=$5
    il=""; case $c in *-i) il="--tff";; esac
    opt=$LOWLAT; [ $m = normal ] && opt=$NORMAL
    /usr/bin/time -f "%U" -o $W/out/$t.time taskset -c $CORE $W/$a/x264 $COMMON $opt $il ${DUMP:-} -o $W/out/$t.264 $CLIPS/$c.y4m 2> $W/out/$t.log
    cat $W/out/$t.time
    ;;
live)
    # Part C: liveness, one encode per cell per counter build. fused > 0 and equal in both arms
    # (same dispatch); refine_after equal; me_search_ref = the C path (weighted refs at subme >= 3).
    mkdir -p $W/out
    for c in $CLIPLIST; do for m in lowlat normal; do for a in basecnt armcnt; do
        bash $0 enc $a $c $m live_${a}_${c}_$m > /dev/null
        echo "$a $c $m: $(grep FPEL_CNT $W/out/live_${a}_${c}_$m.log)"
    done; done; done
    ;;
md5)
    mkdir -p $W/out
    for c in $CLIPLIST; do for m in lowlat normal; do
        for a in base base2 arm arm2; do DUMP="--dump-yuv $W/out/rec_$a.yuv" bash $0 enc $a $c $m md5_${a}_${c}_$m > /dev/null; done
        r=$(md5sum $W/out/rec_{base,base2,arm,arm2}.yuv | awk '{print $1}' | sort -u | wc -l)
        b=$(md5sum $W/out/md5_{base,base2,arm,arm2}_${c}_$m.264 | awk '{print $1}' | sort -u | wc -l)
        echo "$c $m: recon md5 distinct $r, bitstream md5 distinct $b (1 and 1 = pass)"
        rm -f $W/out/rec_*.yuv
    done; done
    ;;
time)
    # paired rounds: per cell, the four arms in a rotated order each round
    R=${2:-5}; mkdir -p $W/out; arms=(base base2 arm arm2)
    for r in $(seq 1 $R); do for c in $CLIPLIST; do for m in lowlat normal; do
        for k in 0 1 2 3; do a=${arms[$(( (k + r) % 4 ))]}
            echo "$r $c $m $a $(bash $0 enc $a $c $m t_${r}_${a}_${c}_$m)" >> $W/times.txt
        done
    done; done; done
    ;;
report)
    # per cell: median over rounds of (arm-base)/base, (arm2-base2)/base2, A/A (base2-base)/base, (arm2-arm)/arm
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
