#!/bin/bash
# Verification + A/B for wip/x264-nw-nrbskip (x264-obe, public github).
#   phase 1: non-reference B frames store no full-frame recon and no fdec mv / ref (35df62e0 off, P1 on)
#   phase 2: the thread's per-MB arrays in an MB row ring, every frame (P2OFF off, tip on)
# The recon of a non-ref B is not stored unless --dump-yuv / --psnr / --ssim, so the gate is the
# BITSTREAM md5 across arms. Every arm is a git-archive export (no .git: the same empty version
# string, so the version SEI is identical across shas). Second check: ffmpeg decodes.
# MODES="normal" limits live / time / mbm to the normal cell (phase 2 also changes lowlat).
#   bash nrbskip-ab.sh build | md5 | rep | dec | live | time [rounds] | report | mbm
# Set: TIP (pushed tip sha, full), CLIPS (dir with <clip>.y4m), CORE (one cpu), BOX=core3|rack01.
# Core 3: FRAMES=30 (sgfades 60); rack01: whole clips (FRAMES=0), mbm (resctrl, root) for bytes.
set -u
BOX=${BOX:?core3 or rack01}
W=${W:-$HOME/x264-nrbskip}
CLIPS=${CLIPS:?set CLIPS}
CORE=${CORE:?set CORE}
TIP=${TIP:?set TIP}
REPO=https://github.com/kierank/x264-obe
BRANCH=wip/x264-nw-nrbskip
BASE=4e292d6ac921cde88c587352e1833137ee074ec7     # origin/speed-next before the series
if [ $BOX = core3 ]; then FRAMES=${FRAMES:-30}; WFRAMES=${WFRAMES:-60}; else FRAMES=${FRAMES:-0}; WFRAMES=${WFRAMES:-0}; fi
if [ $BOX = core3 ]; then CLIPLIST=${CLIPLIST:-"tile-chaos-p field-frame-mix-i"}; WCLIPS=${WCLIPS:-"sgfades-p sgfades-i"}
else CLIPLIST=${CLIPLIST:-"fades-p tile-chaos-p pan-fast-p fades-i field-frame-mix-i credits-i"}; WCLIPS=${WCLIPS:-"sgfades-p sgfades-i"}; fi
NORMAL="--subme 6 --me hex --ref 2 --no-mixed-refs --no-chroma-me --trellis 1 --partitions i8x8,i4x4 --psy-rd 1.0:0 --bframes 3 --rc-lookahead 24 --keyint 30 --bitrate 20000 --vbv-maxrate 20000 --vbv-bufsize 20000 --nal-hrd fakevbr --aud --pic-struct --open-gop --profile high --threads 1"
LOWLAT="--preset veryfast --tune zerolatency --intra-refresh --keyint 30 --bitrate 20000 --vbv-maxrate 20000 --vbv-bufsize 667 --nal-hrd fakevbr --aud --pic-struct --open-gop --profile high --threads 1"
# md5 cells: name|mode|extra options|build depth|clip suffix ("" or -422)
CELLS="n|normal||8|
n_pyrnone|normal|--b-pyramid none|8|
n_pyrstrict|normal|--b-pyramid strict|8|
n_t4|normal|--threads 4|8|
n_sliced4|normal|--threads 4 --sliced-threads|8|
n_slices4|normal|--slices 4|8|
n_vbvtight|normal|--vbv-bufsize 1500|8|
n_cavlc|normal|--no-cabac|8|
n_psnr|normal|--psnr|8|
n_ssim|normal|--ssim|8|
n_slicemax|normal|--slice-max-size 1500|8|
n_fake|normal|--fake-interlaced|8|
n_subme0|normal|--subme 0|8|
n_422|normal||8|-422
n_10|normal||10|
n_10_422|normal||10|-422
l|lowlat||8|
l_t4|lowlat|--threads 4|8|
l_422|lowlat||8|-422
l_10|lowlat||10|"

counters() { # liveness + traffic counters (patched into the export): bytes stored to the fdec planes and
             # fdec mv / ref, MBs by frame kind, b_nrb MBs, ring wraps, thread-ring MBs
    local f=common/macroblock.c
    awk '{ print } /^#include "common.h"$/ && !done {
      print "static unsigned long long nrbc[12];"
      print "static void __attribute__((destructor)) nrbc_print( void )"
      print "{ fprintf( stderr, \"NRBCNT plane_bytes %llu mvref_bytes %llu mbs_I %llu mbs_P %llu mbs_Bref %llu mbs_Bnonref %llu nrb_mbs %llu ring_wraps %llu thread_ring_mbs %llu\\n\","
      print "  nrbc[0], nrbc[1], nrbc[2], nrbc[3], nrbc[4], nrbc[5], nrbc[6], nrbc[7], nrbc[8] ); }"
      print "#define NRBC( i, n ) __atomic_fetch_add( &nrbc[i], (n), __ATOMIC_RELAXED )"
      done = 1 }' $f > $f.new && mv $f.new $f
    perl -0pi -e 's/(static void ALWAYS_INLINE x264_macroblock_store_pic\( x264_t \*h, int mb_x, int mb_y, int i, int b_chroma, int b_mbaff \)\n\{\n    int height = b_chroma \? 16>>CHROMA_V_SHIFT : 16;\n)/$1    NRBC( 0, (b_chroma ? 16*height : 256) * sizeof(pixel) );\n/ or die "store_pic\n"' $f
    perl -0pi -e 's/(    if\( h->sh.i_type != SLICE_TYPE_I \)\n    \{\n        int16_t \(\*mv0\)\[2\] = &h->mb.mv\[0\]\[i_mb_4x4\];\n)/    NRBC( h->sh.i_type == SLICE_TYPE_I ? 2 : h->sh.i_type == SLICE_TYPE_P ? 3 : h->fdec->b_kept_as_ref ? 4 : 5, 1 );\n    if( h->sh.i_type != SLICE_TYPE_I && h->mb.mv[0] == h->fdec->mv[0] )\n        NRBC( 1, (h->sh.i_type == SLICE_TYPE_B ? 2 : 1) * (16*4 + 4) );\n$1/ or die "mvref\n"' $f
    if grep -q 'x264_macroblock_store_col( h, h->mb.i_mb_x, h->mb.i_mb_y, 0, 0, b_mbaff );' $f; then
        perl -0pi -e 's/(        x264_macroblock_store_col\( h, h->mb.i_mb_x, h->mb.i_mb_y, 0, 0, b_mbaff \);\n)/$1        NRBC( 6, 1 );\n/ or die "nrb\n"' $f
        perl -0pi -e 's/(        \/\* keep the unit above \*\/\n)/$1        NRBC( 7, 1 );\n/ or die "wrap\n"' $f
    fi
    if grep -q 'b_thread;' common/common.h; then
        perl -0pi -e 's/(    h->mb.type\[i_mb_xy\] = i_mb_type;\n)/    if( h->mbring.b_active && h->mbring.b_thread ) NRBC( 8, 1 );\n$1/ or die "thread\n"' $f
    fi
}
tree() { # name sha depth [cnt]
    local d=$W/$1 sha
    [ -x $d/x264 ] && return 0
    [ -d $W/repo ] || git clone -q $REPO $W/repo || exit 1
    (cd $W/repo && git fetch -q origin $BRANCH speed-next) || exit 1
    [ "$(cd $W/repo && git rev-parse --verify "$TIP^{commit}")" = "$TIP" ] || { echo "TIP must be the full pushed sha"; exit 1; }
    sha=$(cd $W/repo && git rev-parse --verify "$2^{commit}") || exit 1
    rm -rf $d && mkdir -p $d && (cd $W/repo && git archive $sha) | tar -x -C $d && cd $d && echo "$1 $sha" > SHA || exit 1
    case " $* " in *" cnt "*) counters || exit 1;; esac
    ./configure --bit-depth=$3 --enable-static --disable-opencl --extra-cflags="-fno-fast-math -ffp-contract=off -fno-pie" --extra-ldflags="-no-pie" > cfg.log 2>&1 || exit 1
    make -j"$(nproc)" x264 > make.log 2>&1 || { tail make.log; exit 1; }
}
# commits of the series (first parent from TIP): P2 = TIP, P2OFF = TIP~1, P1 = TIP~2, P1OFF = TIP~3, TIP~4 = BASE
arms_sha() {
    P2=$TIP; P2OFF=$TIP~1; P1=$TIP~2; P1OFF=$TIP~3
    [ "$(cd $W/repo && git rev-parse $TIP~4)" = $BASE ] || { echo "TIP~4 is not $BASE"; exit 1; }
}
enc() { # arm clip mode extra tag: one encode, perf stat -x to $W/out/<tag>.perf
    local a=$1 c=$2 m=$3 x=$4 t=$5 il="" fr=$FRAMES opt
    case $c in *-i|*-i-422) il="--tff";; esac
    case $c in sgfades*) fr=$WFRAMES;; esac
    opt=$LOWLAT; [ $m = normal ] && opt=$NORMAL
    local FR=""; [ "$fr" != 0 ] && FR="--frames $fr"
    taskset -c ${CPUS:-$CORE} perf stat -x, -e cycles:u,instructions:u,task-clock -o $W/out/$t.perf \
        $W/$a/x264 $opt $x $il $FR ${DUMP:-} -o $W/out/$t.264 $W/clips/$c.y4m 2> $W/out/$t.log < /dev/null
}
clips() { # links to the clips, 4:2:2 copies of the md5 clips
    mkdir -p $W/clips
    for c in $CLIPLIST $WCLIPS; do ln -sf $CLIPS/$c.y4m $W/clips/$c.y4m; done
    for c in $CLIPLIST; do [ -s $W/clips/$c-422.y4m ] && continue
        local n=""; [ "$FRAMES" != 0 ] && n="-frames:v $FRAMES"
        ffmpeg -nostdin -v error -i $CLIPS/$c.y4m $n -pix_fmt yuv422p -strict -1 -f yuv4mpegpipe $W/clips/$c-422.y4m || exit 1
    done
}
md5of() { md5sum "$@" | awk '{print $1}' | sort -u | wc -l; }

case "$1" in
build)
    mkdir -p $W/out; tree base $BASE 8; arms_sha
    tree base2 $BASE 8; tree p1off $P1OFF 8; tree p1 $P1 8; tree p2off $P2OFF 8; tree p2 $P2 8; tree p2b $P2 8
    tree base10 $BASE 10; tree p110 $P1 10; tree p210 $P2 10
    tree cntbase $BASE 8 cnt; tree cntp1 $P1 8 cnt; tree cntp2 $P2 8 cnt
    for a in base base2 p1off p1 p2off p2 p2b base10 p110 p210 cntbase cntp1 cntp2; do echo "$(cat $W/$a/SHA) $(md5sum < $W/$a/x264 | cut -c1-8) $($W/$a/x264 --version | head -1)"; done
    clips
    ;;
md5) # bitstream md5 across arms, every cell; recon (dump-yuv: b_nrb off, the phase 2 ring on) for n / l
    mkdir -p $W/out
    echo "$CELLS" | while IFS='|' read cell m x bd sfx; do
        for c in $CLIPLIST; do
            if [ $cell = n_fake ]; then case $c in *-i) continue;; esac; fi
            if [ $bd = 10 ]; then arms="base10 p110 p210"; else arms="base p1 p2"; fi
            [ $cell = n ] || [ $cell = l ] && arms="base p1off p1 p2off p2"
            f=""; for a in $arms; do enc $a $c$sfx $m "$x" md5_${a}_${cell}_$c; f="$f $W/out/md5_${a}_${cell}_$c.264"; done
            r=""; if [ $cell = n ] || [ $cell = l ]; then g=""
                for a in $arms; do DUMP="--dump-yuv $W/out/rec_$a.yuv" enc $a $c$sfx $m "$x" rec_${a}_${cell}_$c; g="$g $W/out/rec_$a.yuv"; done
                r=" recon distinct $(md5of $g)"; rm -f $W/out/rec_*.yuv; fi
            echo "$cell $c ($arms): bitstream distinct $(md5of $f)$r  (1 = pass) bytes $(stat -c %s $W/out/md5_base*_${cell}_$c.264 | head -1)"
        done
    done
    for c in $WCLIPS; do for m in normal lowlat; do f=""
        for a in base p1 p2; do enc $a $c $m "" md5_${a}_w${m}_$c; f="$f $W/out/md5_${a}_w${m}_$c.264"; done
        echo "w$m $c (base p1 p2): bitstream distinct $(md5of $f)  (1 = pass)"
    done; done
    ;;
rep) # frame threads, 20 repeats per arm: distinct md5 within and across arms
    R=${2:-20}; mkdir -p $W/out
    for c in $CLIPLIST; do all=""; for a in base p1 p2; do f=""
        for r in $(seq 1 $R); do enc $a $c normal "--threads 4" rep_${a}_${r}_$c; f="$f $W/out/rep_${a}_${r}_$c.264"; done
        echo "threads 4 $c $a: $R repeats, distinct $(md5of $f)"; all="$all $f"
        done; echo "threads 4 $c all arms: distinct $(md5of $all)  (1 = pass)"; rm -f $W/out/rep_*_$c.264
    done
    ;;
dec) # ffmpeg decodes of the md5 bitstreams (run after md5): every arm against base; base decode vs base recon
    for p in $W/out/md5_base_*.264 $W/out/md5_base10_*.264; do [ -e "$p" ] || continue
        t=${p#$W/out/md5_base}; t=${t#10}; ref=$(ffmpeg -nostdin -v error -i $p -f rawvideo - | md5sum | cut -c1-32)
        res=""; for q in $W/out/md5_*$t; do [ $q = $p ] && continue
            res="$res $(basename $q .264 | cut -d_ -f2):$([ "$(ffmpeg -nostdin -v error -i $q -f rawvideo - | md5sum | cut -c1-32)" = $ref ] && echo same || echo DIFF)"; done
        echo "decode ${t%.264}: base $ref$res"
    done
    for cell in n l; do for c in $CLIPLIST; do # informational: does the decoder reproduce the base recon?
        m=normal; [ $cell = l ] && m=lowlat
        DUMP="--dump-yuv $W/out/rec.yuv" enc base $c $m "" decrec_$c
        echo "base $cell $c: recon $(md5sum < $W/out/rec.yuv | cut -c1-8) decode $(ffmpeg -nostdin -v error -i $W/out/decrec_$c.264 -f rawvideo - | md5sum | cut -c1-8)"
        rm -f $W/out/rec.yuv
    done; done
    ;;
live) # counters: frames by kind, b_nrb MBs, ring wraps, thread-ring MBs; bytes stored to fdec planes / mv / ref
    mkdir -p $W/out
    for c in $CLIPLIST $WCLIPS; do for m in ${MODES:-normal lowlat}; do for a in cntbase cntp1 cntp2; do
        enc $a $c $m "" live_${a}_${m}_$c
        echo "$c $m $a: $(grep NRBCNT $W/out/live_${a}_${m}_$c.log | cut -d' ' -f2-)  $(grep -o 'frame [IPB]:[ 0-9]*' $W/out/live_${a}_${m}_$c.log | tr -s ' ' | tr '\n' ' ')"
    done; done; done
    ;;
time) # paired rounds, arm order rotated: base base2 p1 p2 p2b; cycles:u from perf stat -x
    R=${2:-5}; mkdir -p $W/out; arms=(base base2 p1 p2 p2b)
    for r in $(seq 1 $R); do for c in $CLIPLIST $WCLIPS; do for m in ${MODES:-normal lowlat}; do
        for k in 0 1 2 3 4; do a=${arms[$(( (k + r) % 5 ))]}
            enc $a $c $m "" t_${r}_${a}_${c}_$m
            echo "$r $c $m $a $(awk -F, '$3 ~ /^cycles/ {cy=$1} $3 ~ /^instructions/ {ins=$1} $3 ~ /^task-clock/ {tc=$1} END {print cy, ins, tc}' $W/out/t_${r}_${a}_${c}_$m.perf)" >> $W/times.txt
        done
    done; done; done
    ;;
report) # per cell: median paired cycles delta, A/A controls
    awk '{ t[$2" "$3" "$1" "$4] = $5; ins[$2" "$3" "$1" "$4] = $6; cells[$2" "$3] = 1; if( $1 > R ) R = $1 }
    function med( v, n,   i, j, x ) { for( i = 1; i <= n; i++ ) for( j = i+1; j <= n; j++ ) if( v[j] < v[i] ) { x = v[i]; v[i] = v[j]; v[j] = x }
                                    return n % 2 ? v[(n+1)/2] : (v[n/2] + v[n/2+1]) / 2 }
    END { for( c in cells ) { n = 0; w1 = w2 = 0
            for( r = 1; r <= R; r++ ) { k = c" "r; if( !((k" base") in t) ) continue; n++
              d1[n] = 100*(t[k" p1"]/t[k" base"]-1); d2[n] = 100*(t[k" p2"]/t[k" p1"]-1); d3[n] = 100*(t[k" p2"]/t[k" base"]-1)
              a1[n] = 100*(t[k" base2"]/t[k" base"]-1); a2[n] = 100*(t[k" p2b"]/t[k" p2"]-1)
              i1[n] = 100*(ins[k" p1"]/ins[k" base"]-1); i2[n] = 100*(ins[k" p2"]/ins[k" p1"]-1)
              w1 += t[k" p1"] < t[k" base"]; w2 += t[k" p2"] < t[k" p1"] }
            printf "%-22s cycles p1-base %+.2f %% (%d/%d) p2-p1 %+.2f %% (%d/%d) p2-base %+.2f %%  A/A base %+.2f %% p2 %+.2f %%  instr p1 %+.2f %% p2 %+.2f %%\n",
                   c, med(d1,n), w1, n, med(d2,n), w2, n, med(d3,n), med(a1,n), med(a2,n), med(i1,n), med(i2,n) } }' $W/times.txt | sort
    ;;
mbm) # rack01, root: L3 external bytes per encode by resctrl MBM, NPAR concurrent encodes on CPUS_LIST.
     # Optional L3MASK (+ L3ID) puts the encodes in a CAT group with that way mask (E-2400 share, e.g. 0x3).
    R=${2:-3}; NPAR=${NPAR:-1}; CL=(${CPUS_LIST:-$CORE}); mkdir -p $W/out
    [ -d /sys/fs/resctrl/info ] || { echo "mount -t resctrl resctrl /sys/fs/resctrl first"; exit 1; }
    P=/sys/fs/resctrl
    if [ -n "${L3MASK:-}" ]; then mkdir -p $P/nrbctl && echo "L3:${L3ID:-0}=$L3MASK" > $P/nrbctl/schemata && P=$P/nrbctl; fi
    for r in $(seq 1 $R); do for c in $CLIPLIST $WCLIPS; do for m in ${MODES:-normal lowlat}; do for a in base p1 p2; do
        G=$P/mon_groups/nrb_$a; mkdir -p $G
        b0=$(cat $G/mon_data/mon_L3_*/mbm_total_bytes | awk '{s+=$1} END {print s}')
        for j in $(seq 0 $((NPAR-1))); do
            ( echo $BASHPID > $G/tasks; CPUS=${CL[$j]} enc $a $c $m "" mbm_${a}_${j}_${c}_$m ) &
        done; wait
        b1=$(cat $G/mon_data/mon_L3_*/mbm_total_bytes | awk '{s+=$1} END {print s}')
        fr=$(grep -o 'encoded [0-9]* frames' $W/out/mbm_${a}_0_${c}_$m.log | awk '{print $2}')
        echo "$r $c $m $a $(( (b1 - b0) / NPAR )) $fr" | tee -a $W/mbm.txt
    done; done; done; done
    awk '{ k = $2" "$3" "$4; s[k] += $5 / $6; n[k]++ } END { for( k in s ) printf "%-32s %.2f MB/f per encode\n", k, s[k]/n[k]/1e6 }' $W/mbm.txt | sort
    ;;
esac
