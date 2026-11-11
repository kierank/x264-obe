#!/bin/bash
# In-situ A/B of wip/x264-nw-trellis (Step B). Core 3 (AVX2) or rack01 (AVX-512).
# usage: ab-insitu.sh <base sha> <arm sha> <liveness symbol> [rounds=5]
#   Core 3, 8x8 nodes:      ab-insitu.sh <tip~2> <tip~1> x264_8_trellis_cabac_8x8_nodes_avx2
#   Core 3, 4x4/dc nodes:   ab-insitu.sh <tip~1> <tip>   x264_8_trellis_cabac_4x4_nodes_avx2
#   rack01, icl 4x4/dc (Z1): ARMPATCH=z1 ab-insitu.sh <tip> <tip> x264_8_trellis_cabac_4x4_avx512icl
# env: CLIPS (dir, default /home/obe/x264-clips), FRAMES (30), CPU (taskset cpu, 2),
#      ARMPATCH=z1: the arm is <arm sha> with the avx512icl 4x4/dc trellis dispatched (one sed)
#      ARMAS="-DTRELLIS_AVX2_AHEAD=1": extra asflags for the arm only; CLIPLIST (default tile-chaos-p field-frame-mix-i)
#   Core 3, AHEAD:          ARMAS=-DTRELLIS_AVX2_AHEAD=1 ab-insitu.sh <tip> <tip> x264_8_trellis_cabac_8x8_nodes_avx2
set -e
BASE=$1; ARM=$2; SYM=$3; R=${4:-5}
CLIPS=${CLIPS:-/home/obe/x264-clips}; FRAMES=${FRAMES:-30}; CPU=${CPU:-2}
REPO=${REPO:-https://github.com/kierank/x264-obe.git}
W=${W:-$HOME/nwtr-ab}; mkdir -p $W; cd $W
[ -d src ] || git clone -q $REPO src
git -C src fetch -q origin wip/x264-nw-trellis
build() { # name sha flavour(t|m)
  local d=$W/b-$1-$3
  [ -x $d/x264 ] && return 0
  rm -rf $d; git -C src worktree add -f --detach $d $2 > /dev/null
  if [ "$1" = arm ] && [ "$ARMPATCH" = z1 ]; then
    # dispatch the existing avx512icl 4x4/4x4_psy/dc/422_dc trellis next to the 8x8 ones (both bit depths)
    sed -i 's|^\(\s*\)pf->trellis_cabac_8x8_psy = x264_trellis_cabac_8x8_psy_avx512icl;|&\n\1pf->trellis_cabac_4x4 = x264_trellis_cabac_4x4_avx512icl;\n\1pf->trellis_cabac_4x4_psy = x264_trellis_cabac_4x4_psy_avx512icl;\n\1pf->trellis_cabac_dc = x264_trellis_cabac_dc_avx512icl;\n\1pf->trellis_cabac_chroma_422_dc = x264_trellis_cabac_chroma_422_dc_avx512icl;|' $d/common/quant.c
    grep -c "trellis_cabac_4x4 = x264_trellis_cabac_4x4_avx512icl" $d/common/quant.c
  fi
  local cf="-fno-pie"; [ $3 = m ] && cf="-fno-pie -fno-fast-math -ffp-contract=off"
  local as=""; [ "$1" = arm ] && as="$ARMAS"
  (cd $d && ./configure --bit-depth=8 --disable-opencl --disable-lavf --disable-ffms --disable-gpac --disable-lsmash \
      --extra-cflags="$cf" --extra-ldflags="-no-pie" ${as:+--extra-asflags="$as"} > cfg.log && make -j$(nproc) x264 > make.log 2>&1)
}
for a in base arm; do s=$BASE; [ $a = arm ] && s=$ARM; build $a $s t; build $a $s m; done

LOW="--preset veryfast --tune zerolatency --intra-refresh --keyint 30 --bitrate 20000 --vbv-maxrate 20000 --vbv-bufsize 667 --nal-hrd fakevbr --aud --pic-struct --open-gop --profile high --threads 1"
NOR="--subme 6 --me hex --ref 2 --no-mixed-refs --no-chroma-me --trellis 1 --partitions i8x8,i4x4 --psy-rd 1.0:0 --bframes 3 --rc-lookahead 24 --keyint 30 --bitrate 20000 --vbv-maxrate 20000 --vbv-bufsize 20000 --nal-hrd fakevbr --aud --pic-struct --open-gop --profile high --threads 1"
CLIPLIST=${CLIPLIST:-"tile-chaos-p field-frame-mix-i"}
opts() { case $1 in *-i) echo "--tff";; esac; }

echo "== recon md5 (no-fast-math builds), $FRAMES frames"
for c in $CLIPLIST; do for cell in LOW NOR; do
  for a in base arm; do
    eval o=\$$cell
    $W/b-$a-m/x264 $o $(opts $c) --frames $FRAMES -o /dev/null --dump-yuv $W/rec-$a.yuv $CLIPS/$c.y4m 2> /dev/null
    eval md5_$a=$(md5sum < $W/rec-$a.yuv | cut -c1-32)
  done
  echo "$c $cell base $md5_base arm $md5_arm $([ "$md5_base" = "$md5_arm" ] && echo SAME || echo DIFFER)"
done; done

echo "== liveness: calls of $SYM in the arm (5 frames, each cell)"
for c in $CLIPLIST; do for cell in LOW NOR; do eval o=\$$cell
  n=$(gdb -batch -ex "break $SYM" -ex 'ignore 1 1000000000' -ex run -ex 'info breakpoints' \
      --args $W/b-arm-t/x264 $o $(opts $c) --frames 5 -o /dev/null $CLIPS/$c.y4m 2>/dev/null | grep -o 'already hit [0-9]* time' || echo "0 (not hit)")
  echo "$c $cell $SYM: $n"
done; done

echo "== timing: base / base' / arm / arm' per round, taskset -c $CPU, $FRAMES frames, cycles:u"
t() { perf stat -x, -e cycles:u -o $W/t.txt -- taskset -c $CPU $W/b-$1-t/x264 $2 --frames $FRAMES -o /dev/null $3 2>/dev/null; awk -F, '/cycles:u/{printf "%d", $1}' $W/t.txt; }   # cycles:u (Core 3 standard 11-11)
for c in $CLIPLIST; do for cell in LOW NOR; do eval o="\$$cell $(opts $c)"
  t base "$o" $CLIPS/$c.y4m > /dev/null   # warm-up
  for r in $(seq 1 $R); do
    b1=$(t base "$o" $CLIPS/$c.y4m); b2=$(t base "$o" $CLIPS/$c.y4m)
    a1=$(t arm "$o" $CLIPS/$c.y4m);  a2=$(t arm "$o" $CLIPS/$c.y4m)
    echo "$c $cell round $r base $b1 base' $b2 arm $a1 arm' $a2"
  done
done; done | tee $W/times.txt
# paired median: per round arm-base = (a1+a2-b1-b2)/2; A/A = b2-b1
for c in $CLIPLIST; do for cell in LOW NOR; do
  grep "^$c $cell " $W/times.txt > $W/k.txt
  md=$(awk '{print ($10+$12-$6-$8)/2}' $W/k.txt | sort -n | awk '{v[NR]=$1} END{print v[int((NR+1)/2)]}')
  ma=$(awk '{print $8-$6}' $W/k.txt | sort -n | awk '{v[NR]=$1} END{print v[int((NR+1)/2)]}')
  bm=$(awk '{s+=($6+$8)/2} END{print s/NR}' $W/k.txt)
  fa=$(awk '{if($10+$12<$6+$8) f++} END{print f+0"/"NR}' $W/k.txt)
  echo "$c $cell: median arm-base $md ms of base $bm ms ($(awk -v a=$md -v b=$bm 'BEGIN{printf "%+.2f%%", 100*a/b}')), median A/A $ma ms, arm faster in $fa rounds"
done; done
