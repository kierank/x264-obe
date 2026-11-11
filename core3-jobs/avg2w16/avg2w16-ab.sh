#!/bin/bash
# In-situ A/B for wip/x264-gap-avg2w16 (x264-obe, public github). Step B protocol: base / base2 / arm / arm2,
# paired rounds (arm order rotated), per-cell median, A/A controls, recon + bitstream md5, liveness.
#   BOX=core3  (Intel AVX2): base = tip~1, arm = tip (Intel dispatch: VEX avg2 w8/w12/w16, get_ref asm)
#   BOX=rack01 (Zen 4): base = tip, arm = tip + the Intel block enabled on AVX-512 (perl, checked)
# Run each part alone, nothing else timed on the box.
#   bash avg2w16-ab.sh build | live | md5 | time [rounds] | report
# Set: TIP (pushed tip sha), CLIPS (dir with <clip>.y4m), CORE (one cpu).
# Core 3: FRAMES=30 (default there), rack01: whole clips (FRAMES=0 default there).
set -u
BOX=${BOX:?core3 or rack01}
W=${W:-$HOME/x264-avg2w16}
CLIPS=${CLIPS:?set CLIPS}
CORE=${CORE:?set CORE}
TIP=${TIP:?set TIP}
REPO=https://github.com/kierank/x264-obe
if [ $BOX = core3 ]; then FRAMES=${FRAMES:-30}; else FRAMES=${FRAMES:-0}; fi
FR=""; [ "$FRAMES" != 0 ] && FR="--frames $FRAMES"
CLIPLIST=${CLIPLIST:-"fades-i field-frame-mix-i credits-i tile-chaos-p pan-fast-p"}
COMMON="--aud --pic-struct --bitrate 15000 --vbv-maxrate 15000 --vbv-bufsize 15000 --nal-hrd fakevbr --threads 1"
LOWLAT="--preset veryfast --tune zerolatency --intra-refresh --keyint 24"
NORMAL="--open-gop --keyint 24 --bframes 3 --rc-lookahead 24 --subme 6 --me hex --ref 2 --no-mixed-refs --no-chroma-me --trellis 1 --partitions i8x8,i4x4 --psy-rd 1.0:0"

zen4arm() { # enable the Intel avg2 / get_ref block on AVX-512 too
    perl -0pi -e 's/    if\( !\(cpu&X264_CPU_AVX512\) \)\n    \{\n        pf->get_ref = get_ref_avx2_intel;/    if( 1 )\n    {\n        pf->get_ref = get_ref_avx2_intel;/ or die "zen4arm: no match\n"' common/x86/mc-c.c
}
cntpatch() { # liveness counters: calls through the arm's get_ref / mc_luma pointers
    awk '/^void x264_mc_init_mmx\( int cpu, x264_mc_functions_t \*pf \)$/ {
      print "static uint64_t avg2_cnt[3];"
      print "static void __attribute__((destructor)) avg2_cnt_print( void )"
      print "{ fprintf( stderr, \"AVG2_CNT get_ref_avx2_asm unweighted %llu weighted %llu mc_luma_avx2_intel %llu\\n\","
      print "           (unsigned long long)avg2_cnt[0], (unsigned long long)avg2_cnt[1], (unsigned long long)avg2_cnt[2] ); }"
      print "static pixel *get_ref_cnt( pixel *d, intptr_t *ds, pixel *s[4], intptr_t ss, int mx, int my, int w, int h, const x264_weight_t *wt )"
      print "{ __atomic_fetch_add( &avg2_cnt[!!wt->weightfn], 1, __ATOMIC_RELAXED ); return get_ref_avx2_asm( d, ds, s, ss, mx, my, w, h, wt ); }"
      print "static void mc_luma_cnt( pixel *d, intptr_t ds, pixel *s[4], intptr_t ss, int mx, int my, int w, int h, const x264_weight_t *wt )"
      print "{ __atomic_fetch_add( &avg2_cnt[2], 1, __ATOMIC_RELAXED ); mc_luma_avx2_intel( d, ds, s, ss, mx, my, w, h, wt ); }"
    } { print }' common/x86/mc-c.c > mcc.new && mv mcc.new common/x86/mc-c.c
    sed -i 's/^            pf->get_ref = get_ref_avx2_asm;$/            pf->get_ref = get_ref_cnt;/; s/^        pf->mc_luma = mc_luma_avx2_intel;$/        pf->mc_luma = mc_luma_cnt;/' common/x86/mc-c.c
    [ "$(grep -c 'get_ref_cnt;' common/x86/mc-c.c)" = 1 ] || { echo "cntpatch did not apply"; return 1; }
}
nomcl() { # NOMCL=1: arms without the mc_luma switch (get_ref only)
    sed -i '/^        pf->mc_luma = mc_luma_avx2_intel;$/d' common/x86/mc-c.c
    ! grep -q 'pf->mc_luma = mc_luma_avx2_intel;' common/x86/mc-c.c
}
tree() { # name sha [zen4] [cnt] [arm]: a git-archive export (no .git: every tree has the same empty
         # version string, so the SEI and RC are identical across arms)
    local d=$W/$1 sha
    [ -x $d/x264 ] && return 0
    [ -d $W/repo ] || git clone -q $REPO $W/repo || exit 1
    (cd $W/repo && git fetch -q origin wip/x264-gap-avg2w16) || exit 1
    sha=$(cd $W/repo && git rev-parse --verify "$2^{commit}") || exit 1
    [ "$(cd $W/repo && git rev-parse --verify "$TIP^{commit}")" = "$TIP" ] || { echo "TIP must be the full pushed sha"; exit 1; }
    rm -rf $d && mkdir -p $d && (cd $W/repo && git archive $sha) | tar -x -C $d && cd $d && echo "$1 $sha" > SHA || exit 1
    case " $* " in *" zen4 "*) zen4arm || exit 1;; esac
    case " $* " in *" arm "*) [ -n "${NOMCL:-}" ] && { nomcl || exit 1; };; esac
    case " $* " in *" cnt "*) cntpatch || exit 1;; esac
    ./configure --bit-depth=8 --enable-static --disable-opencl --extra-cflags="-fno-fast-math -ffp-contract=off -fno-pie" --extra-ldflags="-no-pie" > cfg.log 2>&1 || exit 1
    make -j"$(nproc)" x264 checkasm8 > make.log 2>&1 || { tail make.log; exit 1; }
}
if [ $BOX = core3 ]; then B=$TIP~1; A=$TIP; AX=""; else B=$TIP; A=$TIP; AX=zen4; fi

case "$1" in
build)
    mkdir -p $W
    tree base $B; tree base2 $B; tree arm $A $AX arm; tree arm2 $A $AX arm; tree armcnt $A $AX arm cnt
    md5sum $W/base/x264 $W/base2/x264 $W/arm/x264 $W/arm2/x264 | sed "s|$W/||"   # base == base2, arm == arm2
    for a in base arm armcnt; do (cd $W/$a && echo "$(cat SHA) checkasm8: $(./checkasm8 2>&1 | tail -1)"); done
    for a in base arm; do $W/$a/x264 --version | head -1; done   # identical strings (no git info)
    ;;
enc) # arm clip mode tag: one encode, user seconds to stdout
    a=$2; c=$3; m=$4; t=$5
    il=""; case $c in *-i) il="--tff";; esac
    opt=$LOWLAT; [ $m = normal ] && opt=$NORMAL
    /usr/bin/time -f "%U" -o $W/out/$t.time taskset -c $CORE ${PERF:-} $W/$a/x264 $COMMON $opt $il $FR ${DUMP:-} -o $W/out/$t.264 $CLIPS/$c.y4m 2> $W/out/$t.log
    cat $W/out/$t.time
    ;;
live)
    # counters: calls through the arm's pointers (> 0 = live). perf, where allowed: the arm's samples in
    # get_ref_noweight_avx2 / avg2_w*_avx, the base's in get_ref_avx2 / avg2_w16_sse2 / avg2_w8_mmx2
    mkdir -p $W/out
    for c in $CLIPLIST; do for m in lowlat normal; do
        bash $0 enc armcnt $c $m live_${c}_$m > /dev/null
        echo "$c $m: $(grep AVG2_CNT $W/out/live_${c}_$m.log)"
    done; done
    if perf stat -e cycles true > /dev/null 2>&1; then for a in base arm; do
        c=${CLIPLIST%% *}
        PERF="perf record -q -F 4999 -o $W/out/perf_$a.data" bash $0 enc $a $c normal perf_$a > /dev/null
        echo "$a $c normal perf: $(perf report -q --stdio -i $W/out/perf_$a.data --sort sym 2>/dev/null | grep -E 'avg2_w|get_ref' | awk '{printf "%s %s; ", $1, $NF}')"
    done; fi
    ;;
md5)
    mkdir -p $W/out
    for c in $CLIPLIST; do for m in lowlat normal; do
        for a in base base2 arm arm2; do DUMP="--dump-yuv $W/out/rec_$a.yuv" bash $0 enc $a $c $m md5_${a}_${c}_$m > /dev/null; done
        r=$(md5sum $W/out/rec_base.yuv $W/out/rec_base2.yuv $W/out/rec_arm.yuv $W/out/rec_arm2.yuv | awk '{print $1}' | sort -u | wc -l)
        b=$(md5sum $W/out/md5_base_${c}_$m.264 $W/out/md5_base2_${c}_$m.264 $W/out/md5_arm_${c}_$m.264 $W/out/md5_arm2_${c}_$m.264 | awk '{print $1}' | sort -u | wc -l)
        echo "$c $m: recon md5 distinct $r, bitstream md5 distinct $b (1 and 1 = pass)"
        rm -f $W/out/rec_*.yuv
    done; done
    ;;
time)
    R=${2:-5}; mkdir -p $W/out; arms=(base base2 arm arm2)
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
