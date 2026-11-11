#!/bin/bash
# In-situ A/B for wip/x264-nw-intrax9 (x264-obe, public github), Step B protocol.
# Run each part alone, nothing else heavy on the box.
#   bash intrax9-ab.sh build        # trees + binaries (base, base2, arm, arm2, basecnt, armcnt) + checkasm
#   bash intrax9-ab.sh live         # counters: x9 MB driver / x9 8x8 fdec / per-block x9 recon calls per cell
#   bash intrax9-ab.sh md5          # gate: recon md5 across all 4 arms; bitstream md5 within one sha only
#   bash intrax9-ab.sh perf         # perf stat instructions:u + cycles:u, base and arm; arm perf record: the new symbols present
#   bash intrax9-ab.sh time [R]     # paired rounds (default 9), perf cycles:u, rotated arm order
#   bash intrax9-ab.sh report       # per-cell paired medians + A/A
# Set: CLIPS (dir with the clips as .y4m), CORE (one cpu), AB; on Core 3 FRAMES=30.
#   AB=i1    item 1, x9 v/h/dc in the hadamard domain:   base = speed-next 42c3f783, arm = ad2e4638
#   AB=i3    item 3, topright in-kernel, edge loads:      base = f6e9a53f, arm = 219b043c
#   AB=tip   items 2 + 4 dispatched (8x8 fdec edge, MB driver): base = tip~1, arm = tip
#   AB=i2    item 2 alone: base = tip~1, arm = tip without the MB driver pointer
#   AB=i4    item 4 alone: base = tip~1, arm = tip without the 8x8 fdec pointer
#   AB=icl   (rack01 / Zen 5) arm = tip with the avx512icl x9 4x4 recon + sa8d x9 (+ fdec) dispatched, base = tip
set -u
AB=${AB:-tip}
W=${W:-$HOME/x264-intrax9-$AB}
CLIPS=${CLIPS:?set CLIPS to the clip dir}
CORE=${CORE:?set CORE to one cpu}
REPO=https://github.com/kierank/x264-obe
BRANCH=wip/x264-nw-intrax9
SN=42c3f783
C1=ad2e4638
C2=f6e9a53f
C3=219b043c
TIP=76142791
TIP1=5cdbdd1c
PFILE=""; PATCH=""
case $AB in
i1)  BASE=$SN;   ARM=$C1 ;;
i3)  BASE=$C2;   ARM=$C3 ;;
tip) BASE=$TIP1; ARM=$TIP ;;
i2)  BASE=$TIP1; ARM=$TIP; PFILE=common/dct.c;   PATCH="/intra_satd_x9_4x4_mb *= x264_intra_satd_x9_4x4_mb_f[a-z]*_avx2;/d" ;;
i4)  BASE=$TIP1; ARM=$TIP; PFILE=common/pixel.c; PATCH="/pixf->intra_sa8d_x9_8x8_fdec = x264_intra_sa8d_x9_8x8_fdec_avx2;/d" ;;
icl) BASE=$TIP;  ARM=$TIP; PFILE=common/pixel.c ;;
*) echo "unknown AB $AB"; exit 1 ;;
esac
# Core 3: FRAMES=30 (>= 1 interlaced and 1 progressive clip); rack01: whole clips
if [ -n "${FRAMES:-}" ]; then
    CLIPLIST=${CLIPLIST:-"tile-chaos-p field-frame-mix-i"}; FR="--frames $FRAMES"
else
    CLIPLIST=${CLIPLIST:-"fades-p tile-chaos-p pan-fast-p fades-i field-frame-mix-i credits-i"}; FR=""
fi
COMMON="--aud --pic-struct --bitrate 20000 --vbv-maxrate 20000 --nal-hrd fakevbr --open-gop --profile high --keyint 30 --threads 1"
LOWLAT="--preset veryfast --tune zerolatency --intra-refresh --vbv-bufsize 667"
NORMAL="--subme 6 --me hex --ref 2 --no-mixed-refs --no-chroma-me --trellis 1 --partitions i8x8,i4x4 --psy-rd 1.0:0 --bframes 3 --rc-lookahead 24 --vbv-bufsize 20000"

patch_icl() { # dispatch the undispatched avx512icl x9 kernels in the AVX512ICL block of pixel.c and dct.c
    perl -0pi -e 's|(    if\( cpu&X264_CPU_AVX512ICL \)\n    \{\n#if ARCH_X86_64\n)|$1        pixf->intra_satd_x9_4x4 = x264_intra_satd_x9_4x4_avx512icl;\n        pixf->intra_sa8d_x9_8x8 = x264_intra_sa8d_x9_8x8_avx512icl;\n        pixf->intra_sa8d_x9_8x8_fdec = x264_intra_sa8d_x9_8x8_fdec_avx512icl;\n|' common/pixel.c
    perl -0pi -e 's|(        pf_progressive->intra_satd_x9_4x4_mb = x264_intra_satd_x9_4x4_mb_frame_avx2;\n)|$1        if( cpu&X264_CPU_AVX512ICL )\n        {\n            pf_interlaced->intra_satd_x9_4x4_recon  = x264_intra_satd_x9_4x4_recon_field_avx512icl;\n            pf_progressive->intra_satd_x9_4x4_recon = x264_intra_satd_x9_4x4_recon_frame_avx512icl;\n            pf_interlaced->intra_satd_x9_4x4_recon_notr  = x264_intra_satd_x9_4x4_recon_field_notr_avx512icl;\n            pf_progressive->intra_satd_x9_4x4_recon_notr = x264_intra_satd_x9_4x4_recon_frame_notr_avx512icl;\n        }\n|' common/dct.c
    n=$(git diff --stat | grep -cE 'common/(pixel|dct).c')
    [ "$n" = 2 ] || { echo "ICL PATCH DID NOT APPLY"; git diff --stat; exit 1; }
}

cnt_patch() { # counters in x264_mb_analyse_intra, printed at exit as X9_CNT
    perl -0pi -e 's|(static void x264_mb_analyse_intra\( x264_t \*h)|#include <stdio.h>\nstatic unsigned long long x9cnt[3];\n__attribute__((destructor)) static void x9cnt_print( void ) { fprintf( stderr, "X9_CNT mb %llu fdec8x8 %llu recon4x4 %llu\\n", x9cnt[0], x9cnt[1], x9cnt[2] ); }\n$1|' encoder/analyse.c
    perl -pi -e 's/^(\s+)(idx = h->zigzagf\.intra_satd_x9_4x4_mb\()/$1x9cnt[0]++, $2/; s/^(\s+)(i_best = x9_fdec\()/$1x9cnt[1]++, $2/; s/^(\s+)(i_best = (x9_recon|\(b_notr && x9_recon_notr \? x9_recon_notr : x9_recon\))\()/$1x9cnt[2]++, $2/' encoder/analyse.c
    [ $(grep -c 'x9cnt\[[012]\]++' encoder/analyse.c) -ge 1 ] || { echo "CNT SITES NOT FOUND"; exit 1; }
    grep -q 'X9_CNT' encoder/analyse.c || { echo "CNT PATCH DID NOT APPLY"; exit 1; }
}

tree() { # name sha patch? cnt?
    local d=$W/$1
    [ -x $d/x264 ] && return 0
    rm -rf $d && git clone -q $REPO $d && cd $d && git fetch -q origin $BRANCH && git checkout -q $2 || exit 1
    test "$(git rev-parse --short=8 HEAD)" = "$2" || { echo "WRONG TREE $1"; exit 1; }
    if [ "$3" = patch ]; then
        if [ $AB = icl ]; then patch_icl
        elif [ -n "$PATCH" ]; then
            sed -i "$PATCH" $PFILE
            git diff --stat | grep -qE "$PFILE \| +[12] " || { echo "ARM PATCH DID NOT APPLY ($1)"; git diff --stat; exit 1; }
        fi
        git diff | grep '^[-+] '
    fi
    [ "${4:-}" = cnt ] && cnt_patch
    ./configure --bit-depth=8 --enable-static --disable-opencl --extra-cflags="-fno-fast-math -ffp-contract=off -fno-pie" --extra-ldflags="-no-pie" > cfg.log 2>&1 || exit 1
    make -j"$(nproc)" x264 checkasm8 > make.log 2>&1 || { tail make.log; exit 1; }
}

case "$1" in
build)
    mkdir -p $W
    tree base $BASE nopatch; tree base2 $BASE nopatch; tree arm $ARM patch; tree arm2 $ARM patch
    tree basecnt $BASE nopatch cnt; tree armcnt $ARM patch cnt
    md5sum $W/{base,base2,arm,arm2}/x264 | sed "s|$W/||"   # base == base2, arm == arm2 expected
    for a in base arm; do (cd $W/$a && for s in 1001 2002 3003; do taskset -c $CORE ./checkasm8 $s > $W/ck_${a}_$s.txt 2>&1; echo "$a checkasm8 seed $s rc $? $(grep -c FAILED $W/ck_${a}_$s.txt) fails: $(grep -E 'x9|all tests' $W/ck_${a}_$s.txt | tr -s ' ' | tr '\n' ' ')"; done); done
    (cd $W/arm && taskset -c $CORE ./checkasm8 --bench=intra_s 1001 | grep -E "x9|nop")
    ;;
enc) # arm clip mode tag: one encode, cycles:u to stdout
    a=$2; c=$3; m=$4; t=$5
    il=""; case $c in *-i) il="--tff";; esac
    opt=$LOWLAT; [ $m = normal ] && opt=$NORMAL
    taskset -c $CORE perf stat -x, -e cycles:u -o $W/out/$t.time -- $W/$a/x264 $COMMON $opt $il $FR ${DUMP:-} -o $W/out/$t.264 $CLIPS/$c.y4m 2> $W/out/$t.log
    awk -F, '/cycles/ {print $1}' $W/out/$t.time
    ;;
live)
    mkdir -p $W/out
    for c in $CLIPLIST; do for m in lowlat normal; do for a in basecnt armcnt; do
        bash $0 enc $a $c $m live_${a}_${c}_$m > /dev/null
        echo "$a $c $m: $(grep X9_CNT $W/out/live_${a}_${c}_$m.log)"
    done; done; done
    ;;
perf) # instructions:u / cycles:u per cell for base and arm, then the x9 symbols of the arm profile
    mkdir -p $W/out
    for c in $CLIPLIST; do for m in lowlat normal; do
        il=""; case $c in *-i) il="--tff";; esac
        opt=$LOWLAT; [ $m = normal ] && opt=$NORMAL
        for a in base arm; do
            taskset -c $CORE perf stat -x, -e instructions:u,cycles:u -o $W/out/perf_${a}_${c}_$m.txt -- \
                $W/$a/x264 $COMMON $opt $il $FR -o /dev/null $CLIPS/$c.y4m 2> /dev/null
            echo "$a $c $m: $(grep -E 'instructions|cycles' $W/out/perf_${a}_${c}_$m.txt | cut -d, -f1,3 | paste -sd' ')"
        done
        perf record -q -o $W/out/rec_${c}_$m.data taskset -c $CORE $W/arm/x264 $COMMON $opt $il $FR -o /dev/null $CLIPS/$c.y4m 2> /dev/null
        echo "arm $c $m x9 symbols:"
        perf report -q -i $W/out/rec_${c}_$m.data --sort sym 2> /dev/null | grep -E 'x9_4x4|x9_8x8|analyse_intra'
    done; done
    ;;
md5)
    mkdir -p $W/out
    for c in $CLIPLIST; do for m in lowlat normal; do
        for a in base base2 arm arm2; do DUMP="--dump-yuv $W/out/rec_$a.yuv" bash $0 enc $a $c $m md5_${a}_${c}_$m > /dev/null; done
        r=$(md5sum $W/out/rec_{base,base2,arm,arm2}.yuv | awk '{print $1}' | sort -u | wc -l)
        b1=$(md5sum $W/out/md5_{base,base2}_${c}_$m.264 | awk '{print $1}' | sort -u | wc -l)
        b2=$(md5sum $W/out/md5_{arm,arm2}_${c}_$m.264 | awk '{print $1}' | sort -u | wc -l)
        echo "$c $m: recon md5 distinct across 4 arms $r; bitstream distinct base/base2 $b1, arm/arm2 $b2 (1 1 1 = pass)"
        rm -f $W/out/rec_*.yuv
    done; done
    ;;
time)
    R=${2:-9}; mkdir -p $W/out; arms=(base base2 arm arm2)
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
