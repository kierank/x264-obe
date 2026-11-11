# .44 (Xeon Gold 6238R) in-situ A/B of wip/x264-10b-me, Intel AVX2 view (--asm cap), 10-bit 4:2:2.
# base = tip~1 (10-bit AVX2: C me_search_ref + refine_subpel), arm = tip (x264_10_me_search_fpel_avx2).
# usage: FOOT=<football 1080i25 10-bit 422 y4m> ATEME=<ATEME 1080p59.94 10-bit 422 y4m> ROUNDS=9 CORE=4 bash dot44.sh
set -e
R=/dev/shm/x264j; SRC=$R/x264-obe; ROUNDS=${ROUNDS:-9}; CORE=${CORE:-4}
cd $SRC && git fetch -q origin wip/x264-10b-me
for v in base arm; do
  rev=$([ $v = base ] && echo FETCH_HEAD~1 || echo FETCH_HEAD)
  D=$R/me10-$v; rm -rf $D; mkdir -p $D
  git -C $SRC archive $rev | tar -x -C $D
  (cd $D && ./configure --bit-depth=10 --chroma-format=all --enable-static --disable-opencl --disable-lavf --disable-ffms --disable-gpac --disable-lsmash \
      --extra-cflags="-fno-pie -fno-fast-math -ffp-contract=off" --extra-ldflags="-no-pie" >/dev/null && make -j16 x264 >/dev/null)
  echo "$v: $(git -C $SRC rev-parse --short $rev)"
done
ASM='MMX2,SSE,SSE2,SSE3,SSSE3,SSE4.1,SSE4.2,AVX,FMA3,BMI1,BMI2,LZCNT,AVX2'
COM="--asm $ASM --output-csp i422 --profile high422 --threads 1 --frames 60"
LL="--preset veryfast --tune zerolatency --intra-refresh --keyint 30 --bitrate 50000 --vbv-maxrate 50000 --vbv-bufsize 1667 --nal-hrd fakevbr"
NM="--subme 6 --me hex --ref 2 --no-mixed-refs --no-chroma-me --trellis 1 --partitions i8x8,i4x4 --psy-rd 1.0:0 --bframes 3 --rc-lookahead 24 --keyint 30 --bitrate 50000 --vbv-maxrate 50000 --vbv-bufsize 50000 --nal-hrd fakevbr"
# cells: name|clip|extra; ll_dia is the null control (--me dia: the fused search makes zero calls)
CELLS="fi_ll|$FOOT|--tff $LL
fi_nm|$FOOT|--tff $NM
ap_ll|$ATEME|$LL
ap_nm|$ATEME|$NM
fi_ll_dia|$FOOT|--tff $LL --me dia"
O=$R/me10-out; rm -rf $O; mkdir -p $O
run() { # arm cell round
  IFS='|' read -r name clip extra <<< "$2"
  taskset -c $CORE perf stat -x, -e cycles:u,instructions:u -o $O/$1.$name.$3.stat -- \
    taskset -c $CORE $R/me10-${1%2}/x264 $COM $extra -o $O/$1.$name.$3.264 --dump-yuv $O/$1.$name.$3.yuv "$clip" 2>/dev/null
  md5sum < $O/$1.$name.$3.yuv | cut -c1-32 > $O/$1.$name.$3.rmd5; rm -f $O/$1.$name.$3.yuv
  md5sum < $O/$1.$name.$3.264 | cut -c1-32 > $O/$1.$name.$3.bmd5
}
for r in $(seq 1 $ROUNDS); do
  while IFS= read -r c; do for a in base arm arm2 base2; do run $a "$c" $r; done; done <<< "$CELLS"
done
# report: per cell paired median of arm/base - 1 (cycles, instructions) over rounds (base,arm and base2,arm2 pairs),
# recon md5 across all arms and rounds, bitstream md5 within each sha
while IFS= read -r c; do
  name=${c%%|*}
  for k in cycles instructions; do
    for r in $(seq 1 $ROUNDS); do for p in "base arm" "base2 arm2"; do set -- $p
      b=$(grep "$k:u" $O/$1.$name.$r.stat | cut -d, -f1); a=$(grep "$k:u" $O/$2.$name.$r.stat | cut -d, -f1)
      echo "$a $b" | awk '{printf "%.6f\n", $1/$2-1}'; done; done | sort -g | awk -v n=$name -v k=$k '{v[NR]=$1} END{m=(NR%2)?v[(NR+1)/2]:(v[NR/2]+v[NR/2+1])/2; f=0; for(i=1;i<=NR;i++) f+=v[i]<0; printf "%-10s %-12s median %+.3f%%  arm faster in %d/%d pairs  [min %+.3f%% max %+.3f%%]\n", n, k, 100*m, f, NR, 100*v[1], 100*v[NR]}'
  done
  echo "$name recon md5 distinct: $(cat $O/*.$name.*.rmd5 | sort -u | wc -l) (must be 1)"
  echo "$name bitstream md5 distinct: base $(cat $O/base*.$name.*.bmd5 | sort -u | wc -l) arm $(cat $O/arm*.$name.*.bmd5 | sort -u | wc -l) (each must be 1)"
done <<< "$CELLS"
# liveness (one run each, arm and base, lowlat football): the fused entry replaces me_search_ref / refine_subpel
for v in base arm; do
  taskset -c $CORE perf record -q -o $O/$v.perf.data -- $R/me10-$v/x264 $COM --tff $LL -o /dev/null "$FOOT" 2>/dev/null
  echo "== $v"; perf report -i $O/$v.perf.data --sort sym --stdio 2>/dev/null | grep -E "me_search|refine_subpel|sad_x[34]_min|satd_subpel" | head -8
done
