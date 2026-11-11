#!/bin/bash
# In-situ A/B for wip/x264-10b-cabac (x264-obe, github kierank), 10-bit 4:2:2.
# Copyright (C) 2026 Open Broadcast Systems Ltd
#
# MODE (env) picks the machine view and the arms. Revisions are relative to the branch tip
# (tip = Zen 4/5 rd2 dispatch, tip~1 = AVX-512-without-ICL 8x8, tip~2 = 10-bit avx2 dispatch,
# tip~3 = the kernels, not dispatched); the script prints the resolved shas.
#   avx2 (.44, Intel AVX2 production view, --asm cap): base = tip~3, arm = tip~2,
#        port = tip~2 with RD4_AVX2_LEVELS_MIN 17 (the 4x4 port without the level pass)
#   a512 (.44 default, AVX-512 without ICL):          base = tip~3, arm = tip~2, noicl = tip~1
#   icl  (rack01 Zen 4):                              base = tip~1, arm = tip (rd2 4x4),
#        arm8 = tip + the 8x8 rd2 dispatched at AVX512ICL (sed)
# Every arm is built twice (X and X2) for A/A. Run each part alone on an idle box.
#   bash ab-10b-cabac.sh build | live | md5 | time [rounds] | report
# Env: CLIPI (1080i25 10-bit 4:2:2 y4m, e.g. football), CLIPP (1080p59.94, e.g. ATEME), FRAMES (60), CORE.
set -u
MODE=${MODE:?set MODE to avx2, a512 or icl}
W=${W:-$HOME/x264-10b-cabac-$MODE}
CLIPI=${CLIPI:?}; CLIPP=${CLIPP:?}; CORE=${CORE:?}; FRAMES=${FRAMES:-60}
REPO=https://github.com/kierank/x264-obe BR=wip/x264-10b-cabac
CAP=""; [ $MODE = avx2 ] && CAP='--asm MMX2,SSE,SSE2,SSE3,SSSE3,SSE4.1,SSE4.2,AVX,FMA3,BMI1,BMI2,LZCNT,AVX2'
case $MODE in
  avx2) ARMS="base:t3 arm:t2 port:t2:port";;
  a512) ARMS="base:t3 arm:t2 noicl:t1";;
  icl)  ARMS="base:t1 arm:t0 arm8:t0:rd8";;
esac
COMMON="--output-csp i422 --profile high422 --threads 1 --frames $FRAMES"
LOWLAT="--preset veryfast --tune zerolatency --intra-refresh --keyint 30 --bitrate 50000 --vbv-maxrate 50000 --vbv-bufsize 1667 --nal-hrd fakevbr"
NORMAL="--subme 6 --me hex --ref 2 --no-mixed-refs --no-chroma-me --trellis 1 --partitions i8x8,i4x4 --psy-rd 1.0:0 --bframes 3 --rc-lookahead 24 --keyint 30 --bitrate 50000 --vbv-maxrate 50000 --vbv-bufsize 50000 --nal-hrd fakevbr"

patchtree() { # variant
    case $1 in
    port) sed -i 's/^    %define RD4_AVX2_LEVELS_MIN 2$/    %define RD4_AVX2_LEVELS_MIN 17/' common/x86/cabac-a.asm
          grep -q 'RD4_AVX2_LEVELS_MIN 17' common/x86/cabac-a.asm;;
    rd8)  sed -i 's/= x264_cabac_block_residual_8x8_rd_internal_avx512icl;/= x264_cabac_block_residual_8x8_rd2_internal_avx512icl;/' common/bitstream.c
          grep -q "= x264_cabac_block_residual_8x8_rd2_internal_avx512icl;" common/bitstream.c;;
    cnt)  livepatch;;
    esac
}
livepatch() { # call counters on the three slots, and the pointer names
    sed -i 's/^void x264_bitstream_init( int cpu, x264_bitstream_function_t \*pf )$/static void bitstream_init_real( int cpu, x264_bitstream_function_t *pf )/' common/bitstream.c
    grep -q '^static void bitstream_init_real' common/bitstream.c || return 1
    cat >> common/bitstream.c <<'EOF'
typedef void (*cabres_fn)( dctcoef *, int, intptr_t, x264_cabac_t * );
static cabres_fn live_real[3];
static long live_calls[3];
static void live0( dctcoef *l, int i, intptr_t c, x264_cabac_t *cb ) { live_calls[0]++; live_real[0]( l, i, c, cb ); }
static void live1( dctcoef *l, int i, intptr_t c, x264_cabac_t *cb ) { live_calls[1]++; live_real[1]( l, i, c, cb ); }
static void live2( dctcoef *l, int i, intptr_t c, x264_cabac_t *cb ) { live_calls[2]++; if( live_real[2] ) live_real[2]( l, i, c, cb ); }
static void live_report( void ) { fprintf( stderr, "CABLIVE calls rd4 %ld rd8 %ld 422dc_writer %ld\n", live_calls[0], live_calls[1], live_calls[2] ); }
static const char *live_name( cabres_fn f )
{
#if HAVE_MMX && ARCH_X86_64
    if( f == x264_cabac_block_residual_rd_internal_ssse3_lzcnt || f == x264_cabac_block_residual_8x8_rd_internal_ssse3_lzcnt ) return "ssse3_lzcnt";
    if( f == x264_cabac_block_residual_rd_internal_avx2_bmi2 || f == x264_cabac_block_residual_8x8_rd_internal_avx2_bmi2 ||
        f == x264_cabac_block_residual_422_dc_internal_avx2_bmi2 ) return "avx2_bmi2";
    if( f == x264_cabac_block_residual_8x8_rd_internal_avx512 ) return "avx512";
    if( f == x264_cabac_block_residual_rd_internal_avx512icl || f == x264_cabac_block_residual_8x8_rd_internal_avx512icl ||
        f == x264_cabac_block_residual_422_dc_internal_avx512icl ) return "avx512icl";
    if( f == x264_cabac_block_residual_rd2_internal_avx512icl || f == x264_cabac_block_residual_8x8_rd2_internal_avx512icl ) return "rd2_avx512icl";
#endif
    return f ? "other" : "C";
}
void x264_bitstream_init( int cpu, x264_bitstream_function_t *pf )
{
    bitstream_init_real( cpu, pf );
    if( !live_real[0] )
    {
        live_real[0] = pf->cabac_block_residual_rd_internal;
        live_real[1] = pf->cabac_block_residual_8x8_rd_internal;
        live_real[2] = pf->cabac_block_residual_422_dc_internal;
        fprintf( stderr, "CABLIVE rd4 %s rd8 %s 422dc_writer %s\n", live_name( live_real[0] ), live_name( live_real[1] ), live_name( live_real[2] ) );
        atexit( live_report );
    }
    pf->cabac_block_residual_rd_internal = live0;
    pf->cabac_block_residual_8x8_rd_internal = live1;
    if( live_real[2] ) pf->cabac_block_residual_422_dc_internal = live2; /* NULL = the C writer, not counted */
}
EOF
}
tree() { # dir rev (tN = N back from the branch tip, or a sha) variant...
    local d=$W/$1 s=$2; shift 2
    [ -x $d/x264 ] && return 0
    rm -rf $d && git clone -q $REPO $d && cd $d && git fetch -q origin $BR || exit 1
    case $s in t[0-9]) s=$(git rev-parse --short=8 FETCH_HEAD~${s#t});; esac
    git checkout -q $s && test "$(git rev-parse --short=8 HEAD)" = "${s:0:8}" || { echo "WRONG TREE $d"; exit 1; }
    echo "$(basename $d): $(git log -1 --format="%h %s")"
    for v in "$@"; do patchtree $v || { echo "PATCH $v FAILED"; exit 1; }; done
    ./configure --bit-depth=10 --enable-static --disable-opencl --extra-cflags="-fno-fast-math -ffp-contract=off -fno-pie" --extra-ldflags="-no-pie" > cfg.log 2>&1 || exit 1
    make -j"$(nproc)" x264 checkasm10 > make.log 2>&1 || { tail make.log; exit 1; }
}
armlist() { for a in $ARMS; do echo ${a%%:*}; done; }
enc() { # arm clip(i|p) mode tag
    local il="" clip=$CLIPP; [ $2 = i ] && { il="--tff"; clip=$CLIPI; }
    local opt=$LOWLAT; [ $3 = normal ] && opt=$NORMAL
    taskset -c $CORE perf stat -x, -e cycles:u,instructions:u -o $W/out/$4.perf -- \
        taskset -c $CORE $W/$1/x264 $CAP $COMMON $opt $il ${DUMP:-} -o $W/out/$4.264 $clip 2> $W/out/$4.log
    awk -F, '/cycles/{c=$1} /instructions/{i=$1} END{print c, i}' $W/out/$4.perf
}
case "$1" in
build)
    mkdir -p $W
    for a in $ARMS; do IFS=: read n s v <<< "$a"
        tree $n $s $v; tree ${n}2 $s $v; tree ${n}cnt $s $v cnt; done
    for n in $(armlist); do md5sum $W/$n/x264 $W/${n}2/x264 | sed "s|$W/||"; done   # X == X2 expected
    for n in $(armlist); do cd $W/$n; for s in 1 2 3 4 5; do taskset -c $CORE ./checkasm10 $s > $W/ck_${n}_$s.txt 2>&1; echo "$n checkasm10 seed $s: $(tail -1 $W/ck_${n}_$s.txt)"; done; done
    ;;
live) # pointer names and call counts per arm; counts equal across arms (same decisions)
    mkdir -p $W/out
    for c in i p; do for m in lowlat normal; do for n in $(armlist); do
        enc ${n}cnt $c $m live_${n}_${c}_$m > /dev/null
        echo "$n $c $m: $(grep CABLIVE $W/out/live_${n}_${c}_$m.log | tr '\n' ' ')"
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
time) # paired rounds, rotating order; >= 9 rounds
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
    echo "per-call instructions:u: divide the delta by the call counts from 'live' (rd4 + rd8 + 422dc_writer)"
    ;;
esac
