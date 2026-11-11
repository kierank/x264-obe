#!/bin/bash
# In-situ A/B for wip/x264-422-dcrd (x264-obe, github kierank): the 4:2:2 chroma dc rd coder.
# Copyright (C) 2026 Open Broadcast Systems Ltd
#
# MODE (env) picks the machine and the arms; DEPTH (8 or 10) the build. Revisions: tN = N back
# from the wip/x264-422-dcrd tip (tip = avx2 dispatch, tip~1 = the kernels, not dispatched),
# zen5/... = the tip of that branch (tip + one dispatch commit). The script prints the shas.
#   avx2 (Xeon E, native AVX2; Intel AVX2 production view): base = tip~1 (C), arm = tip (avx2_bmi2)
#   icl  (rack01 Zen 4): base = tip (AVX-512 keeps the C), a2 = zen5/x264-422-dcrd-avx2 (avx2_bmi2
#        on AVX-512), i2 = zen5/x264-422-dcrd-icl2 (avx512icl rd2), i1 = zen5/x264-422-dcrd-icl1
#        (the avx512icl kernel of 54f7ee3e)
# Every arm is built twice (X and X2) for A/A; Xcnt counts the calls of the rd pointer.
#   bash ab-422-dcrd.sh build | live | md5 | time [rounds] | report
# Env: CLIPI (1080i 4:2:2 y4m of the depth), CLIPP (progressive 4:2:2 y4m), FRAMES (60), CORE.
set -u
MODE=${MODE:?set MODE to avx2 or icl}
DEPTH=${DEPTH:?set DEPTH to 8 or 10}
W=${W:-$HOME/x264-422-dcrd-$MODE-$DEPTH}
CLIPI=${CLIPI:?}; CLIPP=${CLIPP:?}; CORE=${CORE:?}; FRAMES=${FRAMES:-60}
REPO=https://github.com/kierank/x264-obe BR=wip/x264-422-dcrd
case $MODE in
  avx2) ARMS="base:t1 arm:t0";;
  icl)  ARMS="base:t0 a2:zen5/x264-422-dcrd-avx2 i2:zen5/x264-422-dcrd-icl2 i1:zen5/x264-422-dcrd-icl1";;
esac
COMMON="--output-csp i422 --profile high422 --threads 1 --frames $FRAMES"
LOWLAT="--preset veryfast --tune zerolatency --intra-refresh --keyint 30 --bitrate 50000 --vbv-maxrate 50000 --vbv-bufsize 1667 --nal-hrd fakevbr"
NORMAL="--subme 6 --me hex --ref 2 --no-mixed-refs --no-chroma-me --trellis 1 --partitions i8x8,i4x4 --psy-rd 1.0:0 --bframes 3 --rc-lookahead 24 --keyint 30 --bitrate 50000 --vbv-maxrate 50000 --vbv-bufsize 50000 --nal-hrd fakevbr"

livepatch() { # call counter on the 4:2:2 dc rd pointer, and its name
    sed -i 's/^void x264_bitstream_init( int cpu, x264_bitstream_function_t \*pf )$/static void bitstream_init_real( int cpu, x264_bitstream_function_t *pf )/' common/bitstream.c
    grep -q '^static void bitstream_init_real' common/bitstream.c || return 1
    cat >> common/bitstream.c <<'EOF'
typedef void (*cabres_fn)( dctcoef *, int, intptr_t, x264_cabac_t * );
static cabres_fn live_real;
static long live_calls;
static void live0( dctcoef *l, int i, intptr_t c, x264_cabac_t *cb ) { live_calls++; live_real( l, i, c, cb ); }
static void live_report( void ) { fprintf( stderr, "DCRDLIVE calls 422dc_rd %ld\n", live_calls ); }
static const char *live_name( cabres_fn f )
{
#if HAVE_MMX && ARCH_X86_64
    if( f == x264_cabac_block_residual_422_dc_rd_internal_avx2_bmi2 ) return "avx2_bmi2";
    if( f == x264_cabac_block_residual_422_dc_rd_internal_avx512icl ) return "avx512icl (54f7ee3e)";
    if( f == x264_cabac_block_residual_422_dc_rd2_internal_avx512icl ) return "rd2_avx512icl";
#endif
    return f ? "other" : "C (not counted)";
}
void x264_bitstream_init( int cpu, x264_bitstream_function_t *pf )
{
    static int done;
    bitstream_init_real( cpu, pf );
    if( !done )
    {
        done = 1;
        live_real = pf->cabac_block_residual_422_dc_rd_internal;
        fprintf( stderr, "DCRDLIVE 422dc_rd %s\n", live_name( live_real ) );
        atexit( live_report );
    }
    if( live_real ) pf->cabac_block_residual_422_dc_rd_internal = live0;
}
EOF
}
tree() { # dir rev (tN = N back from the branch tip, or a branch) variant...
    local d=$W/$1 s=$2; shift 2
    [ -x $d/x264 ] && return 0
    rm -rf $d && git clone -q $REPO $d && cd $d || exit 1
    case $s in
        t[0-9]) git fetch -q origin $BR && s=$(git rev-parse --short=8 FETCH_HEAD~${s#t});;
        *)      git fetch -q origin $s && s=$(git rev-parse --short=8 FETCH_HEAD);;
    esac
    git checkout -q $s && test "$(git rev-parse --short=8 HEAD)" = "${s:0:8}" || { echo "WRONG TREE $d"; exit 1; }
    echo "$(basename $d): $(git log -1 --format="%h %s")"
    for v in "$@"; do [ $v = cnt ] && { livepatch || { echo "PATCH FAILED"; exit 1; }; }; done
    ./configure --bit-depth=$DEPTH --enable-static --disable-opencl --extra-cflags="-fno-fast-math -ffp-contract=off -fno-pie" --extra-ldflags="-no-pie" > cfg.log 2>&1 || exit 1
    make -j"$(nproc)" x264 checkasm$DEPTH > make.log 2>&1 || { tail make.log; exit 1; }
}
armlist() { for a in $ARMS; do echo ${a%%:*}; done; }
enc() { # arm clip(i|p) mode tag
    local il="" clip=$CLIPP; [ $2 = i ] && { il="--tff"; clip=$CLIPI; }
    local opt=$LOWLAT; [ $3 = normal ] && opt=$NORMAL
    taskset -c $CORE perf stat -x, -e cycles:u,instructions:u -o $W/out/$4.perf -- \
        taskset -c $CORE $W/$1/x264 $COMMON $opt $il ${DUMP:-} -o $W/out/$4.264 $clip 2> $W/out/$4.log
    awk -F, '/cycles/{c=$1} /instructions/{i=$1} END{print c, i}' $W/out/$4.perf
}
case "$1" in
build)
    mkdir -p $W
    for a in $ARMS; do IFS=: read n s <<< "$a"
        tree $n $s; tree ${n}2 $s; tree ${n}cnt $s cnt; done
    for n in $(armlist); do md5sum $W/$n/x264 $W/${n}2/x264 | sed "s|$W/||"; done   # X == X2 expected
    for n in $(armlist); do cd $W/$n; for s in 1 2 3 4 5; do taskset -c $CORE ./checkasm$DEPTH $s > $W/ck_${n}_$s.txt 2>&1; echo "$n checkasm$DEPTH seed $s: $(tail -1 $W/ck_${n}_$s.txt)"; done; done
    ;;
live) # pointer name and call count per arm; counts equal across the asm arms (same decisions)
    mkdir -p $W/out
    for c in i p; do for m in lowlat normal; do for n in $(armlist); do
        enc ${n}cnt $c $m live_${n}_${c}_$m > /dev/null
        echo "$n $c $m: $(grep DCRDLIVE $W/out/live_${n}_${c}_$m.log | tr '\n' ' ')"
    done; done; done
    ;;
md5)
    mkdir -p $W/out
    for c in i p; do for m in lowlat normal; do
        all=""; for n in $(armlist); do for x in $n ${n}2; do DUMP="--dump-yuv $W/out/rec_$x.yuv" enc $x $c $m md5_${x}_${c}_$m > /dev/null; all="$all $W/out/rec_$x.yuv"; done; done
        r=$(md5sum $all | awk '{print $1}' | sort -u | wc -l)
        b=""; for n in $(armlist); do b="$b $n:$(md5sum $W/out/md5_${n}_${c}_$m.264 $W/out/md5_${n}2_${c}_$m.264 | awk '{print $1}' | sort -u | wc -l)"; done
        echo "$c $m: recon md5 distinct across all arms $r (1 = pass); bitstream distinct within sha$b (1 each = pass)"
        rm -f $W/out/rec_*.yuv
    done; done
    ;;
time) # paired rounds, rotating order; >= 9 rounds; lowlat makes no calls (null control)
    R=${2:-9}; mkdir -p $W/out; arms=(); for n in $(armlist); do arms+=($n ${n}2); done; k=${#arms[@]}
    for r in $(seq 1 $R); do for c in i p; do for m in lowlat normal; do
        for j in $(seq 0 $((k-1))); do a=${arms[$(( (j + r) % k ))]}
            echo "$r $c $m $a $(enc $a $c $m t_${r}_${a}_${c}_$m)" >> $W/times.txt
        done
    done; done; done
    ;;
report) # paired median of cycles:u vs base (and base2) per cell, A/A, instructions:u delta
    awk -v ARMS="$(armlist | tr '\n' ' ')" '{ cy[$2" "$3" "$1" "$4] = $5; in_[$2" "$3" "$1" "$4] = $6; cells[$2" "$3] = 1; if( $1 > R ) R = $1 }
    function med( v, n,   i, j, x ) { for( i = 1; i <= n; i++ ) for( j = i+1; j <= n; j++ ) if( v[j] < v[i] ) { x = v[i]; v[i] = v[j]; v[j] = x }
                                    return n % 2 ? v[(n+1)/2] : (v[n/2] + v[n/2+1]) / 2 }
    END { na = split( ARMS, A, " " )
      for( c in cells ) {
        n = 0; for( r = 1; r <= R; r++ ) { k = c" "r; if( !((k" base") in cy) ) continue; n++; aa[n] = 100*(cy[k" base2"]/cy[k" base"]-1) }
        printf "%-10s A/A base2-base %+.2f %% (%d rounds)\n", c, med(aa,n), n
        for( q = 2; q <= na; q++ ) { x = A[q]; n = 0; w = 0
          for( r = 1; r <= R; r++ ) { k = c" "r; if( !((k" base") in cy) ) continue; n++
            d1[n] = 100*(cy[k" "x]/cy[k" base"]-1); d2[n] = 100*(cy[k" "x"2"]/cy[k" base2"]-1); di[n] = in_[k" "x] - in_[k" base"]; w += cy[k" "x] < cy[k" base"] }
          printf "%-10s %-6s vs base: %+.2f %% / %+.2f %% (X2 vs base2), faster in %d/%d, instructions:u delta median %.0f\n", c, x, med(d1,n), med(d2,n), w, n, med(di,n) }
      } }' $W/times.txt | sort
    echo "per-call instructions:u: divide the delta by the 422dc_rd call count from 'live'"
    ;;
esac
