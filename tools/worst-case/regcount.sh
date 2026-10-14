#!/bin/bash
# one lowlat t4 run per case/format/arm with re-encode-counter builds (M = MAR8/MAR10, S = SER, O = OPR); paced as the matrix
X=/home/obe/rack01-x264u; C=${CLIPS:-/home/obe/rack01-pds/wc/clips2}; O=${OUT:-/home/obe/rack01-pds/wc/reg}/count; mkdir -p $O
CASES=${CASES:-"bcuts dimcuts dipcut flash2 flash4 strobe3 halffade fademotion flicker2 flicker10 ticker static2move textgfx grain xfade shake pfade"}
source <(sed -n '/^obed()/,/^esac; }/p' $X/prof468/run.sh)
source <(sed -n '/^input()/,/^bin()/p' /home/obe/rack01-pds/wc/regmatrix.sh | grep -v '^bin()')
for c in $CASES; do for fm in p422_10 p420_8 i422_10; do for a in M:xencp_MAR8:xencp_MAR10 S:xencp_SER:xencp_SER O:xencp_OPR:xencp_OPR; do
  n=${a%%:*}; r=${a#*:}; b=${r#*:}; [ $fm = p420_8 ] && b=${r%%:*}; f=$O/$c.$fm.ll4.$n
  XENC_LATFILE=$f.lat taskset -c 8-23 $X/qSL2/$b $(input $c $fm) /dev/null $(obed lowlat) --threads 4 $(pir $fm) --sar 1:1 < /dev/null > $f.log 2>&1 || echo "rc $? $f" >> $O/log.txt
done; done; done
touch $O/DONE
