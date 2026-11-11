#!/bin/bash
# Core 3 (Raptor Cove, AVX2 + AVX-VNNI, no AVX-512) in-situ A/B for wip/x264-gap-rd8x8 (x264-obe, github).
# Slot: cabac_block_residual_8x8_rd_internal (common/bitstream.c, avx2+bmi2 block).
#   base  = tip~1 (ssse3_lzcnt dispatched; the reworked avx2 kernel assembled, undispatched)
#   arm   = tip   (avx2_bmi2 reworked kernel dispatched)
#   d0    = wip/x264-gap-rd8x8-d0: speed-next + the same dispatch of the ORIGINAL avx2 kernel (fc5cae4a)
#   d0bl  = d0 built with -DRD8_AVX2_BRANCHLESS=1 (original kernel, branchless first level bin)
# Run each part alone, nothing else heavy on the box.
#   bash core3-rd8x8.sh build             # trees, binaries, checkasm8 x3 seeds, 10-bit build
#   bash core3-rd8x8.sh live              # pointer identity + call counts (counting builds), 1 encode per cell
#   bash core3-rd8x8.sh md5               # recon + bitstream md5: base base2 arm arm2 d0 d0bl, every cell
#   bash core3-rd8x8.sh time [rounds] [arms]   # paired rounds (default 10), user time; default arms "base base2 arm arm2"
#   bash core3-rd8x8.sh report [arms]     # per cell paired medians vs base, A/A
# Second A/B (separates the kernel rework from the dispatch): time 10 "base base2 d0 d0bl", report "base base2 d0 d0bl";
# third: time 10 "base base2 arm d0", report "base base2 arm d0" (arm vs d0 directly in the same rounds).
# Clips: 30 frames each (Kieran 11-11: Core 3 is weak, short clips, more rounds).
set -u
W=${W:-$HOME/x264-rd8x8}
CLIPS=${CLIPS:?set CLIPS to the dir holding the Step B clips as .y4m}
CORE=${CORE:-1}
FRAMES=${FRAMES:-30}
REPO=https://github.com/kierank/x264-obe
BASE=af170f99
TIP=e3a52acd
D0=897f3673
CLIPLIST=${CLIPLIST:-"fades-i field-frame-mix-i credits-i tile-chaos-p pan-fast-p"}
COMMON="--aud --pic-struct --bitrate 15000 --vbv-maxrate 15000 --vbv-bufsize 15000 --nal-hrd fakevbr --threads 1 --frames $FRAMES"
LOWLAT="--preset veryfast --tune zerolatency --intra-refresh --keyint 24"
NORMAL="--open-gop --keyint 24 --bframes 3 --rc-lookahead 24 --subme 6 --me hex --ref 2 --no-mixed-refs --no-chroma-me --trellis 1 --partitions i8x8,i4x4 --psy-rd 1.0:0"

tree() { # name sha branch [cnt|bl]
    local d=$W/$1
    [ -x $d/x264 ] && return 0
    rm -rf $d && git clone -q $REPO $d && cd $d && git fetch -q origin $3 && git checkout -q $2 || exit 1
    test "$(git rev-parse --short=8 HEAD)" = "${2:0:8}" || { echo "WRONG TREE $1"; exit 1; }
    [ "${4:-}" = cnt ] && { livepatch || exit 1; }
    ./configure --bit-depth=8 --enable-static --disable-opencl --extra-cflags="-fno-fast-math -ffp-contract=off -fno-pie" --extra-ldflags="-no-pie" > cfg.log 2>&1 || exit 1
    [ "${4:-}" = bl ] && { sed -i 's/^ASFLAGS=\(.*\)$/ASFLAGS=\1 -DRD8_AVX2_BRANCHLESS=1/' config.mak; grep -q RD8_AVX2_BRANCHLESS=1 config.mak || exit 1; }
    make -j"$(nproc)" x264 checkasm8 > make.log 2>&1 || { tail make.log; exit 1; }
}
livepatch() { # counting wrapper on the 8x8 rd slot, plus which kernel it wraps
    sed -i 's/^void x264_bitstream_init( int cpu, x264_bitstream_function_t \*pf )$/static void bitstream_init_real( int cpu, x264_bitstream_function_t *pf )/' common/bitstream.c
    grep -q '^static void bitstream_init_real' common/bitstream.c || return 1
    cat >> common/bitstream.c <<'EOF'
static void (*rd8_real)( dctcoef *, int, intptr_t, x264_cabac_t * );
static long rd8_calls;
static void rd8_count( dctcoef *l, int i, intptr_t c, x264_cabac_t *cb ) { rd8_calls++; rd8_real( l, i, c, cb ); }
static void rd8_report( void ) { fprintf( stderr, "RD8LIVE calls %ld\n", rd8_calls ); }
void x264_bitstream_init( int cpu, x264_bitstream_function_t *pf )
{
    bitstream_init_real( cpu, pf );
    const char *n = "other";
#if HAVE_MMX && ARCH_X86_64
    if( pf->cabac_block_residual_8x8_rd_internal == x264_cabac_block_residual_8x8_rd_internal_avx2_bmi2 ) n = "avx2_bmi2";
    if( pf->cabac_block_residual_8x8_rd_internal == x264_cabac_block_residual_8x8_rd_internal_ssse3_lzcnt ) n = "ssse3_lzcnt";
#endif
    if( !rd8_real ) { rd8_real = pf->cabac_block_residual_8x8_rd_internal; atexit( rd8_report ); fprintf( stderr, "RD8LIVE pointer %s\n", n ); }
    pf->cabac_block_residual_8x8_rd_internal = rd8_count;
}
EOF
}

case "$1" in
build)
    mkdir -p $W
    tree base $BASE wip/x264-gap-rd8x8; tree base2 $BASE wip/x264-gap-rd8x8
    tree arm $TIP wip/x264-gap-rd8x8; tree arm2 $TIP wip/x264-gap-rd8x8
    tree d0 $D0 wip/x264-gap-rd8x8-d0; tree d0bl $D0 wip/x264-gap-rd8x8-d0 bl
    tree basecnt $BASE wip/x264-gap-rd8x8 cnt; tree armcnt $TIP wip/x264-gap-rd8x8 cnt; tree d0cnt $D0 wip/x264-gap-rd8x8-d0 cnt
    md5sum $W/{base,base2,arm,arm2,d0,d0bl}/x264 | sed "s|$W/||"   # base == base2, arm == arm2
    # checkasm at the tip, 3 seeds (8x8_rd avx2 at the AVX2/BMI2 level, rd2 avx512icl skipped here: no AVX-512)
    cd $W/arm
    for s in 1001 2002 3003; do taskset -c $CORE ./checkasm8 $s > $W/ck_$s.txt 2>&1; echo "checkasm8 seed $s: $(tail -1 $W/ck_$s.txt)"; done
    grep -h "cabac residual" $W/ck_1001.txt
    for s in 1001 2002 3003; do taskset -c $CORE ./checkasm8 --bench=cabac_block_residual_8x8_rd $s > $W/bench_$s.txt 2>&1; done
    grep -h "8x8_rd\|^nop" $W/bench_1001.txt | head -40
    # the 10-bit build still builds (the avx2 8x8 kernel is 8-bit only)
    rm -rf $W/ten && git clone -q $REPO $W/ten && cd $W/ten && git fetch -q origin wip/x264-gap-rd8x8 && git checkout -q $TIP \
        && ./configure --bit-depth=10 --enable-static --disable-opencl --extra-cflags="-fno-pie" --extra-ldflags="-no-pie" > cfg.log 2>&1 && make -j"$(nproc)" x264 checkasm10 > make.log 2>&1 \
        && taskset -c $CORE ./checkasm10 1001 > $W/ck10.txt 2>&1; echo "10-bit: $(tail -1 $W/ck10.txt)"
    ;;
enc) # arm clip mode tag: one encode, user seconds to stdout
    a=$2; c=$3; m=$4; t=$5
    il=""; case $c in *-i) il="--tff";; esac
    opt=$LOWLAT; [ $m = normal ] && opt=$NORMAL
    perf stat -x, -e cycles:u,instructions:u -o $W/out/$t.perf -- taskset -c $CORE $W/$a/x264 $COMMON $opt $il ${DUMP:-} -o $W/out/$t.264 $CLIPS/$c.y4m 2> $W/out/$t.log
    awk -F, '/cycles:u/{print $1}' $W/out/$t.perf > $W/out/$t.time; awk -F, '/instructions:u/{print $1}' $W/out/$t.perf > $W/out/$t.insn   # .time holds cycles:u (Core 3 standard 11-11)
    cat $W/out/$t.time
    ;;
live)
    # pointer identity and call count of the 8x8 rd slot: base/d0 cnt must say ssse3_lzcnt / avx2_bmi2, arm avx2_bmi2,
    # calls equal in all three (same decisions)
    mkdir -p $W/out
    for c in $CLIPLIST; do for m in lowlat normal; do for a in basecnt armcnt d0cnt; do
        bash $0 enc $a $c $m live_${a}_${c}_$m > /dev/null
        echo "$a $c $m: $(grep RD8LIVE $W/out/live_${a}_${c}_$m.log | tr '\n' ' ')"
    done; done; done
    ;;
md5)
    mkdir -p $W/out
    for c in $CLIPLIST; do for m in lowlat normal; do
        for a in base base2 arm arm2 d0 d0bl; do DUMP="--dump-yuv $W/out/rec_$a.yuv" bash $0 enc $a $c $m md5_${a}_${c}_$m > /dev/null; done
        r=$(md5sum $W/out/rec_{base,base2,arm,arm2,d0,d0bl}.yuv | awk '{print $1}' | sort -u | wc -l)
        b=""; for p in "base base2" "arm arm2" "d0 d0bl"; do set -- $p   # bitstreams only within one sha (version SEI)
            b="$b $1=$2:$(md5sum $W/out/md5_$1_${c}_$m.264 $W/out/md5_$2_${c}_$m.264 | awk '{print $1}' | sort -u | wc -l)"; done
        echo "$c $m: recon md5 distinct across all 6 arms $r (1 = pass); bitstream distinct within sha$b (1 each = pass)"
        rm -f $W/out/rec_*.yuv
    done; done
    ;;
time)
    # paired rounds: per cell, the four arms in a rotated order each round
    R=${2:-10}; ARMS=(${3:-base base2 arm arm2}); mkdir -p $W/out; tag=$(echo ${ARMS[*]} | tr ' ' '-')
    for r in $(seq 1 $R); do for c in $CLIPLIST; do for m in lowlat normal; do
        for k in 0 1 2 3; do a=${ARMS[$(( (k + r) % 4 ))]}
            echo "$r $c $m $a $(bash $0 enc $a $c $m t_${r}_${a}_${c}_$m)" >> $W/times_$tag.txt
        done
    done; done; done
    ;;
report)
    # per cell: median over rounds of (X-base)/base for arms 3 and 4, A/A (arm 2 vs base)
    ARMS=(${2:-base base2 arm arm2}); tag=$(echo ${ARMS[*]} | tr ' ' '-')
    awk -v A1=${ARMS[0]} -v A2=${ARMS[1]} -v A3=${ARMS[2]} -v A4=${ARMS[3]} '{ t[$2" "$3" "$1" "$4] = $5; cells[$2" "$3] = 1; if( $1 > R ) R = $1 }
    function med( v, n,   i, j, x ) { for( i = 1; i <= n; i++ ) for( j = i+1; j <= n; j++ ) if( v[j] < v[i] ) { x = v[i]; v[i] = v[j]; v[j] = x }
                                    return n % 2 ? v[(n+1)/2] : (v[n/2] + v[n/2+1]) / 2 }
    END { for( c in cells ) { n = 0
            for( r = 1; r <= R; r++ ) { k = c" "r; if( !((k" "A1) in t) ) continue; n++
              d3[n] = 100*(t[k" "A3]/t[k" "A1]-1); d4[n] = 100*(t[k" "A4]/t[k" "A2]-1); aa[n] = 100*(t[k" "A2]/t[k" "A1]-1)
              w += (t[k" "A3] < t[k" "A1]) }
            printf "%-26s %s-%s %+.2f %%  %s-%s %+.2f %%  A/A %s-%s %+.2f %%  (%d rounds)\n", c, A3, A1, med(d3,n), A4, A2, med(d4,n), A2, A1, med(aa,n), n }
          printf "rounds with %s faster than %s: %d\n", A3, A1, w }' $W/times_$tag.txt | sort
    ;;
esac
