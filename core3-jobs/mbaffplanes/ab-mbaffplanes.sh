#!/bin/bash
# In-situ A/B of wip/x264-nw-mbaffplanes: MBAFF field planes F/H aliased onto the
# frame planes (memfd double mapping) vs the copy path. Core 3 (AVX2) or rack01 (AVX-512).
# usage: ab-mbaffplanes.sh <base sha = tip~1> <arm sha = tip> [rounds=5]
# env: CLIPS (/home/obe/x264-clips), CPU (taskset cpu, 2), W (work dir, ~/mbaffplanes-ab),
#      NV16 / NV16_10: optional 8-bit / 10-bit 4:2:2 interlaced y4m for the md5 gate,
#      MBM=1: rack01 only, resctrl mounted at /sys/fs/resctrl: L3<->DRAM bytes per encode
#      (mon group per run), ROLE-free (whole process), single encoder.
# Every build has the same version string (x264_config.h rewritten), so recon AND
# bitstream md5 compare across the two shas.
set -e
BASE=$1; ARM=$2; R=${3:-5}
CLIPS=${CLIPS:-/home/obe/x264-clips}; CPU=${CPU:-2}
REPO=${REPO:-https://github.com/kierank/x264-obe.git}
W=${W:-$HOME/mbaffplanes-ab}; mkdir -p $W; cd $W
[ -d src ] || git clone -q $REPO src
git -C src fetch -q origin wip/x264-nw-mbaffplanes
build() { # name sha flavour: t timing, m md5 (no fast-math), s md5 + X264_FLD_STATS, m10 10-bit md5
  local d=$W/b-$1-$3
  [ -x $d/x264 ] && return 0
  rm -rf $d; git -C src worktree add -f --detach $d $2 > /dev/null
  local cf="-fno-pie" bd=8
  case $3 in m|m10) cf="-fno-pie -fno-fast-math -ffp-contract=off";; s) cf="-fno-pie -fno-fast-math -ffp-contract=off -DX264_FLD_STATS";; esac
  [ $3 = m10 ] && bd=10
  (cd $d && ./configure --bit-depth=$bd --disable-opencl --disable-lavf --disable-ffms --disable-gpac --disable-lsmash \
      --extra-cflags="$cf" --extra-ldflags="-no-pie" > cfg.log &&
   sed -i 's/^#define X264_VERSION .*/#define X264_VERSION " mbaffplanes-ab"/; s/^#define X264_POINTVER .*/#define X264_POINTVER "0.164.ab"/' x264_config.h &&
   make -j$(nproc) x264 > make.log 2>&1)
  echo "built $1-$3 $(git -C $d rev-parse --short=8 HEAD): $($d/x264 --version | head -1)"
}
for a in base arm; do s=$BASE; [ $a = arm ] && s=$ARM; for f in t m s; do build $a $s $f; done; done
[ -n "$NV16_10" ] && for a in base arm; do s=$BASE; [ $a = arm ] && s=$ARM; build $a $s m10; done

LOW="--preset veryfast --tune zerolatency --intra-refresh --keyint 30 --bitrate 20000 --vbv-maxrate 20000 --vbv-bufsize 667 --nal-hrd fakevbr --aud --pic-struct --open-gop --profile high --threads 1"
NOR="--subme 6 --me hex --ref 2 --no-mixed-refs --no-chroma-me --trellis 1 --partitions i8x8,i4x4 --psy-rd 1.0:0 --bframes 3 --rc-lookahead 24 --keyint 30 --bitrate 20000 --vbv-maxrate 20000 --vbv-bufsize 20000 --nal-hrd fakevbr --aud --pic-struct --open-gop --profile high --threads 1"
# md5-only cells: frame threads, sliced threads, all-field (subme 0: non-adaptive MBAFF, x264's PAFF-like mode)
NOR_T4="${NOR/--threads 1/--threads 4}"
LOW_T4="${LOW/--threads 1/--threads 4}"
FLD0="${NOR/--subme 6/--subme 0}"
CLIPLIST="field-frame-mix-i credits-i sgfades-i"
frames() { case $1 in sgfades*) echo 60;; *) echo 30;; esac; }

echo "== recon + bitstream md5 (no-fast-math builds, same version string)"
md5cell() { # flavour clip-path frames cell-name opts
  local f=$1 clip=$2 n=$3 cell=$4; shift 4
  for a in base arm; do
    $W/b-$a-$f/x264 "$@" --tff --frames $n -o $W/bs-$a.264 --dump-yuv $W/rec-$a.yuv $clip 2> /dev/null
    eval r_$a=$(md5sum < $W/rec-$a.yuv | cut -c1-32); eval s_$a=$(md5sum < $W/bs-$a.264 | cut -c1-32)
  done
  echo "$(basename $clip .y4m) $cell recon $r_base/$r_arm $([ $r_base = $r_arm ] && echo SAME || echo DIFFER) bitstream $s_base/$s_arm $([ $s_base = $s_arm ] && echo SAME || echo DIFFER)"
}
for c in $CLIPLIST; do for cell in LOW NOR NOR_T4 LOW_T4 FLD0; do
  eval o=\$$cell; md5cell m $CLIPS/$c.y4m $(frames $c) $cell $o
done; done
[ -n "$NV16" ] && for cell in LOW NOR; do eval o=\$$cell; md5cell m $NV16 30 "$cell-nv16" $o --output-csp i422 --profile high422; done
[ -n "$NV16_10" ] && for cell in LOW NOR; do eval o=\$$cell; md5cell m10 $NV16_10 30 "$cell-nv16-10bit" $o --output-csp i422 --profile high422; done

echo "== field-plane writes (X264_FLD_STATS builds): base = copy path, arm = aliased"
for c in $CLIPLIST; do for cell in LOW NOR; do eval o=\$$cell
  for a in base arm; do
    l=$($W/b-$a-s/x264 $o --tff --frames $(frames $c) -o /dev/null $CLIPS/$c.y4m 2>&1 | grep "field-plane writes")
    echo "$c $cell $a: ${l#*writes }"
  done
done; done

echo "== liveness (arm): memfd mappings while encoding, hpel_filter_vc calls (5 frames)"
c=field-frame-mix-i
$W/b-arm-t/x264 $NOR --tff --frames 30 -o /dev/null $CLIPS/$c.y4m 2>/dev/null & pid=$!
sleep 2; echo "memfd:x264-fld mappings in arm: $(grep -c 'x264-fld' /proc/$pid/maps || true)"; wait $pid
$W/b-base-t/x264 $NOR --tff --frames 30 -o /dev/null $CLIPS/$c.y4m 2>/dev/null & pid=$!
sleep 2; echo "memfd:x264-fld mappings in base: $(grep -c 'x264-fld' /proc/$pid/maps || true)"; wait $pid
for a in base arm; do for cell in LOW NOR; do eval o=\$$cell
  sym=$(nm $W/b-$a-t/x264 | grep -o 'x264_8_hpel_filter_vc_avx2' | head -1)
  [ -z "$sym" ] && { echo "$a $cell: no hpel_filter_vc_avx2 symbol"; continue; }
  n=$(gdb -batch -ex "break $sym" -ex 'ignore 1 1000000000' -ex run -ex 'info breakpoints' \
      --args $W/b-$a-t/x264 $o --tff --frames 5 -o /dev/null $CLIPS/$c.y4m 2>/dev/null | grep -o 'already hit [0-9]* time' || echo "0 (not hit)")
  echo "$a $cell $sym: $n"
done; done

echo "== timing: base / base' / arm / arm' per round, taskset -c $CPU, perf stat cycles:u"
EV=cycles:u,instructions:u,cycles:k,task-clock,page-faults
t() { # arm opts clip frames -> "cycles_u instr_u cycles_k taskclock_ms faults [mbm_bytes]"
  local mb=""
  if [ "$MBM" = 1 ]; then
    local g=/sys/fs/resctrl/mon_groups/mbaffab; mkdir -p $g 2>/dev/null || true
    local b0=$(cat $g/mon_data/mon_L3_*/mbm_total_bytes | awk '{s+=$1} END{print s}')
    perf stat -x, -e $EV -o $W/ps.txt -- sh -c "echo \$\$ > $g/tasks; exec taskset -c $CPU $W/b-$1-t/x264 $2 --frames $4 -o /dev/null $3" 2>/dev/null
    local b1=$(cat $g/mon_data/mon_L3_*/mbm_total_bytes | awk '{s+=$1} END{print s}')
    mb=" $((b1-b0))"
  else
    perf stat -x, -e $EV -o $W/ps.txt taskset -c $CPU $W/b-$1-t/x264 $2 --frames $4 -o /dev/null $3 2>/dev/null
  fi
  awk -F, '/cycles:u/{cu=$1} /instructions:u/{iu=$1} /cycles:k/{ck=$1} /task-clock/{tc=$1} /page-faults/{pf=$1} END{printf "%s %s %s %.1f %s", cu, iu, ck, tc, pf}' $W/ps.txt
  echo -n "$mb"
}
for c in $CLIPLIST; do for cell in LOW NOR; do eval o="\$$cell --tff"; n=$(frames $c)
  t base "$o" $CLIPS/$c.y4m $n > /dev/null   # warm-up
  for r in $(seq 1 $R); do
    b1=$(t base "$o" $CLIPS/$c.y4m $n); b2=$(t base "$o" $CLIPS/$c.y4m $n)
    a1=$(t arm "$o" $CLIPS/$c.y4m $n);  a2=$(t arm "$o" $CLIPS/$c.y4m $n)
    echo "$c $cell round $r | base $b1 | base' $b2 | arm $a1 | arm' $a2"
  done
done; done | tee $W/times.txt
# line: clip cell round r | base <cu iu ck tc pf [mbm]> | base' <...> | arm <...> | arm' <...>
# group j (0 base, 1 base', 2 arm, 3 arm') value idx (0 cu, 1 iu, 2 ck, 3 tc, 4 pf, 5 mbm) = $(6 + j*g + idx), g = 6 + MBM
for c in $CLIPLIST; do for cell in LOW NOR; do
  grep "^$c $cell " $W/times.txt | tr -d '|' | awk -v m=${MBM:-0} -v n=$(frames $c) -v c=$c -v cell=$cell '
    function v(j, i) { return $(6 + j*(6+m) + i) }
    function dd(i) { return (v(2,i) + v(3,i) - v(0,i) - v(1,i)) / 2 }
    { d[NR]=dd(0); aa[NR]=v(1,0)-v(0,0); bs+=(v(0,0)+v(1,0))/2; f+=(v(2,0)+v(3,0) < v(0,0)+v(1,0));
      di[NR]=dd(1); dk[NR]=dd(2); dpf[NR]=dd(4); if(m){ dm[NR]=dd(5); bm+=(v(0,5)+v(1,5))/2 } }
    function med(a, N,  i,j,t,b){ for(i=1;i<=N;i++) b[i]=a[i]; for(i=1;i<=N;i++) for(j=i+1;j<=N;j++) if(b[j]<b[i]){t=b[i];b[i]=b[j];b[j]=t}; return b[int((N+1)/2)] }
    END{ N=NR; printf "%s %s: cycles:u median arm-base %+.3f%% (A/A %+.3f%%), arm faster %d/%d; instr:u %+.0f/f; cycles:k %+.0f/f; page-faults %+.0f",
           c, cell, 100*med(d,N)/(bs/N), 100*med(aa,N)/(bs/N), f, N, med(di,N)/n, med(dk,N)/n, med(dpf,N);
         if(m) printf "; MBM %+.3f MB/f of %.2f MB/f", med(dm,N)/n/1048576, bm/N/n/1048576; printf "\n" }'
done; done
