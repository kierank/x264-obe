#!/bin/bash
# In-situ A/B for wip/x264-gap-idct8 (x264-obe, public github), Step B protocol.
# Run each part alone, nothing else heavy on the box.
#   bash idct8-ab.sh build        # trees + binaries for the chosen AB (all parts need it)
#   bash idct8-ab.sh live         # counter builds: calls per site + the pointer each site called
#   bash idct8-ab.sh md5          # gate: recon + bitstream md5, 4 arms, every cell
#   bash idct8-ab.sh time [R]     # paired rounds (default 9), user time, rotated arm order
#   bash idct8-ab.sh report       # per-cell paired medians + A/A
# Set: CLIPS (dir with the clips as .y4m), CORE (one cpu), AB, and on Core 3 FRAMES=30.
#   AB=ptr     (Core 3, default) base = tip~1 (add8x8_idct8 avx), arm = tip (add8x8_idct8_avx2 dispatched)
#   AB=batch   (Core 3 / rack01) base = tip~2, arm = tip~1 (all-four-coded inter 8x8 -> one add16x16_idct8)
#   AB=zen4    (rack01)  base = tip (AVX512ICL keeps avx), arm = tip with AVX512ICL -> ${ZFN:-avx2}
#              (ZFN=avx512icl for the EVEX pairs kernel)
#   AB=zen4p16 (rack01)  base = tip, arm = tip with the AVX512ICL add16x16_idct8 line removed (avx2 on Zen 4)
set -u
AB=${AB:-ptr}
W=${W:-$HOME/x264-idct8-$AB}
CLIPS=${CLIPS:?set CLIPS to the clip dir}
CORE=${CORE:?set CORE to one cpu}
REPO=https://github.com/kierank/x264-obe
BRANCH=wip/x264-gap-idct8
TIP=76dda80b
TIP1=d0fa61cd
TIP2=c134a6bb
case $AB in
ptr)     BASE=$TIP1; ARM=$TIP; PATCH="" ;;
batch)   BASE=$TIP2; ARM=$TIP1; PATCH="" ;;
zen4)    BASE=$TIP; ARM=$TIP; PATCH="s/^        dctf->add8x8_idct8     = x264_add8x8_idct8_avx;$/        dctf->add8x8_idct8     = x264_add8x8_idct8_${ZFN:-avx2};/" ;;
zen4p16) BASE=$TIP; ARM=$TIP; PATCH="/^        dctf->add16x16_idct8   = x264_add16x16_idct8_avx512icl;$/d" ;;
*) echo "unknown AB $AB"; exit 1 ;;
esac
# Core 3: FRAMES=30 and the 5 clips below (>= 1 interlaced and 1 progressive); rack01: whole clips, all 6
if [ -n "${FRAMES:-}" ]; then
    CLIPLIST=${CLIPLIST:-"fades-i field-frame-mix-i credits-i tile-chaos-p pan-fast-p"}; FR="--frames $FRAMES"
else
    CLIPLIST=${CLIPLIST:-"fades-p tile-chaos-p pan-fast-p fades-i field-frame-mix-i credits-i"}; FR=""
fi
# -i = 1080i29.97 TFF (native interlaced), -p = 1080p59.94
COMMON="--aud --pic-struct --bitrate 15000 --vbv-maxrate 15000 --vbv-bufsize 15000 --nal-hrd fakevbr --threads 1"
LOWLAT="--preset veryfast --tune zerolatency --intra-refresh --keyint 24"
NORMAL="--open-gop --keyint 24 --bframes 3 --rc-lookahead 24 --subme 6 --me hex --ref 2 --no-mixed-refs --no-chroma-me --trellis 1 --partitions i8x8,i4x4 --psy-rd 1.0:0"

tree() { # name sha patch? cnt?
    local d=$W/$1
    [ -x $d/x264 ] && return 0
    rm -rf $d && git clone -q $REPO $d && cd $d && git fetch -q origin $BRANCH && git checkout -q $2 || exit 1
    test "$(git rev-parse --short=8 HEAD)" = "$2" || { echo "WRONG TREE $1"; exit 1; }
    if [ "$3" = patch ] && [ -n "$PATCH" ]; then
        sed -i "$PATCH" common/dct.c
        git diff --stat | grep -q "common/dct.c | 2\|common/dct.c | 1" || { echo "ARM PATCH DID NOT APPLY ($1)"; git diff --stat; exit 1; }
        git diff common/dct.c | grep '^[-+] '
    fi
    [ "${4:-}" = cnt ] && { sh $W/idct8cnt.sh $d || exit 1; }
    ./configure --bit-depth=8 --enable-static --disable-opencl --extra-cflags="-fno-fast-math -ffp-contract=off -fno-pie" --extra-ldflags="-no-pie" > cfg.log 2>&1 || exit 1
    make -j"$(nproc)" x264 checkasm8 > make.log 2>&1 || { tail make.log; exit 1; }
}

case "$1" in
build)
    mkdir -p $W
    [ -f $W/idct8cnt.sh ] || { echo "copy idct8cnt.sh to $W first"; exit 1; }
    tree base $BASE nopatch; tree base2 $BASE nopatch; tree arm $ARM patch; tree arm2 $ARM patch
    tree basecnt $BASE nopatch cnt; tree armcnt $ARM patch cnt
    md5sum $W/{base,base2,arm,arm2}/x264 | sed "s|$W/||"   # base == base2, arm == arm2 expected
    for a in base arm; do (cd $W/$a && for s in 1001 2002 3003; do taskset -c $CORE ./checkasm8 $s > $W/ck_${a}_$s.txt 2>&1; echo "$a checkasm8 seed $s rc $? $(grep -c FAILED $W/ck_${a}_$s.txt) fails"; done); done
    # checkasm rows for the slot (laptop units: T = (printed + nop/4)/10)
    (cd $W/arm && taskset -c $CORE ./checkasm8 --bench=add8x8_idct8 1001 | grep -E "idct8|nop"; taskset -c $CORE ./checkasm8 --bench=add16x16_idct8 1001 | grep -E "idct8|nop")
    ;;
enc) # arm clip mode tag: one encode, user seconds to stdout
    a=$2; c=$3; m=$4; t=$5
    il=""; case $c in *-i) il="--tff";; esac
    opt=$LOWLAT; [ $m = normal ] && opt=$NORMAL
    /usr/bin/time -f "%U" -o $W/out/$t.time taskset -c $CORE $W/$a/x264 $COMMON $opt $il $FR ${DUMP:-} -o $W/out/$t.264 $CLIPS/$c.y4m 2> $W/out/$t.log
    cat $W/out/$t.time
    ;;
live)
    # liveness: the pointer each site called (map it with nm; arm must be the new kernel, base the old),
    # calls per site (base and arm equal: same encode)
    mkdir -p $W/out
    for a in basecnt armcnt; do echo "$a: $(nm $W/$a/x264 | grep -E ' (x264_8_add8x8_idct8|x264_8_add16x16_idct8)_' | awk '{printf "%s=%s ", $3, $1}')"; done
    for c in $CLIPLIST; do for m in lowlat normal; do for a in basecnt armcnt; do
        bash $0 enc $a $c $m live_${a}_${c}_$m > /dev/null
        echo "$a $c $m: $(grep IDCT8_CNT $W/out/live_${a}_${c}_$m.log)"
    done; done; done
    ;;
md5)
    mkdir -p $W/out
    for c in $CLIPLIST; do for m in lowlat normal; do
        for a in base base2 arm arm2; do DUMP="--dump-yuv $W/out/rec_$a.yuv" bash $0 enc $a $c $m md5_${a}_${c}_$m > /dev/null; done
        r=$(md5sum $W/out/rec_{base,base2,arm,arm2}.yuv | awk '{print $1}' | sort -u | wc -l)
        # arms at different shas differ in the version SEI: compare bitstreams within a sha only
        bb=$(md5sum $W/out/md5_{base,base2}_${c}_$m.264 | awk '{print $1}' | sort -u | wc -l)
        ba=$(md5sum $W/out/md5_{arm,arm2}_${c}_$m.264 | awk '{print $1}' | sort -u | wc -l)
        echo "$c $m: recon md5 distinct $r (1 = pass); bitstream distinct base/base2 $bb, arm/arm2 $ba (1 and 1 = deterministic)"
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
