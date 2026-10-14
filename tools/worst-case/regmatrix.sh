#!/bin/bash
# rack01 per-frame regression matrix: production master vs speed-next tip (and optional extra arms) on the gen2.sh stress suite.
# Modes: obed lowest latency (20 Mb/s, one-frame VBV = maxrate*fps_den/fps_num, --intra-refresh, keyint 48 p / 24 i, lookahead-threads 4 for p,
#        t4 and t8, paced: p422_10 at 60 fps (59.94 class), p420_8 at 50, i422_10 at 25) and obed normal (t8, unpaced).
# Arms: ARMS="name:bin8:bin10 ..." (xencp binaries in $X/qSL2; master is single-depth, so separate 8/10-bit binaries).
#   default: M = master 12933898 (xencp_MA8 / xencp_MA10), S = speed-next ea75e2b0 (xencp_SEA), O = option 2 8612b4bc (xencp_OPT2, lowlat only)
# usage: OUT=dir ROUNDS=3 CASES="..." ARMS="..." NWARMS="M S" regmatrix.sh ; writes $OUT/<case>.<fmt>.<mode>.<arm>.r<r>.{lat,log,264}; DONE marker.
X=/home/obe/rack01-x264u; C=${CLIPS:-/home/obe/rack01-pds/wc/clips2}; O=${OUT:-/home/obe/rack01-pds/wc/reg}; R=${ROUNDS:-3}; mkdir -p $O
CASES=${CASES:-"bcuts dimcuts dipcut flash2 flash4 strobe3 halffade fademotion flicker2 flicker10 ticker static2move textgfx grain xfade shake pfade"}
ARMS=${ARMS:-"M:xencp_MA8:xencp_MA10 S:xencp_SEA:xencp_SEA O:xencp_OPT2:xencp_OPT2"}; NWARMS=${NWARMS:-"M S"}
[ "$(pgrep -c -x obdd)" = 0 ] && [ "$(pgrep -c -x obd)" = 0 ] || { echo "decoder running, abort"; exit 1; }
source <(sed -n '/^obed()/,/^esac; }/p' $X/prof468/run.sh)
input(){ case $2 in p422_10) echo "$C/$1_p422_10.yuv raw10_422 1920 1080 200 60";; p420_8) echo "$C/$1_p420_8.y4m y4m8 1920 1080 200 50";; i422_10) echo "$C/$1_i422_10.yuv raw10_422 1920 1080 100 25";; esac; }
pir(){ case $1 in p422_10) echo "--bitrate 20000 --vbv-maxrate 20000 --vbv-bufsize 333 --intra-refresh --keyint 48 --lookahead-threads 4";;
  p420_8) echo "--bitrate 20000 --vbv-maxrate 20000 --vbv-bufsize 400 --intra-refresh --keyint 48 --lookahead-threads 4";;
  i422_10) echo "--bitrate 20000 --vbv-maxrate 20000 --vbv-bufsize 800 --intra-refresh --keyint 24 --tff";; esac; }
bin(){ for a in $ARMS; do [ "${a%%:*}" = $1 ] || continue; r=${a#*:}; [ $2 = p420_8 ] && echo ${r%%:*} || echo ${r#*:}; done; }
names=$(for a in $ARMS; do echo -n "${a%%:*} "; done)
for r in $(seq 1 $R); do for c in $CASES; do for fm in p422_10 p420_8 i422_10; do
  il=""; [ $fm = i422_10 ] && il="--tff"
  rot=$(echo $names | awk -v r=$r '{n=NF; for(i=0;i<n;i++) printf "%s ", $(1+(i+r-1)%n)}')
  for t in 4 8; do for a in $rot; do f=$O/$c.$fm.ll$t.$a.r$r
    XENC_LATFILE=$f.lat taskset -c 8-23 $X/qSL2/$(bin $a $fm) $(input $c $fm) $f.264 $(obed lowlat) --threads $t $(pir $fm) --sar 1:1 < /dev/null > $f.log 2>&1 || echo "rc $? $f" >> $O/log.txt
  done; done
  rotn=$(echo $NWARMS | awk -v r=$r '{n=NF; for(i=0;i<n;i++) printf "%s ", $(1+(i+r-1)%n)}')
  for a in $rotn; do f=$O/$c.$fm.nw8.$a.r$r
    XENC_UNPACED=1 XENC_LATFILE=$f.lat taskset -c 8-23 $X/qSL2/$(bin $a $fm) $(input $c $fm) $f.264 $(obed normal) --threads 8 $il --sar 1:1 < /dev/null > $f.log 2>&1 || echo "rc $? $f" >> $O/log.txt
  done
done; done; echo "$(date -u +%T) round $r done" >> $O/log.txt; done
touch $O/DONE
