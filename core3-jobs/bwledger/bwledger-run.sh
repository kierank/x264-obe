#!/bin/bash
# Copyright (C) 2026 Open Broadcast Systems Ltd
# DRAM byte ledger runs for wip/x264-nw-bwledger (x264-obe, public github). Core 3 or rack01.
# Arms (git-archive exports, so every tree has the same empty version string):
#   base = BASE (speed-next), off = TIP built normally, on = TIP built with -DX264_BWLEDGER=1
# Gate first: recon md5 of base / off / on identical in every cell (the ledger is counters only,
# and its build takes the C paths of the asm-only composite kernels), bitstream md5 too.
#   bash bwledger-run.sh build | md5 | ledger | report
# Set: TIP (full pushed sha of wip/x264-nw-bwledger), CLIPS (dir of <clip>.y4m), CORE (one cpu).
# Optional: BASE (default 4e292d6a), FRAMES (default 30), CLIPLIST, CLIP422 (an 8-bit 4:2:2 y4m:
# adds the 4:2:2 cell), W (work dir).
set -u
W=${W:-$HOME/x264-bwledger}
CLIPS=${CLIPS:?set CLIPS}
CORE=${CORE:?set CORE}
TIP=${TIP:?set TIP}
BASE=${BASE:-4e292d6a}
FRAMES=${FRAMES:-30}
REPO=https://github.com/kierank/x264-obe
CLIPLIST=${CLIPLIST:-"field-frame-mix-i tile-chaos-p"}
# the Core 3 command lines (brief), --tff on -i clips; cells: A = -i normal (1080i MBAFF),
# B = -i lowlat, C = -p normal
LOWLAT="--preset veryfast --tune zerolatency --intra-refresh --keyint 30 --bitrate 20000 --vbv-maxrate 20000 --vbv-bufsize 667 --nal-hrd fakevbr --aud --pic-struct --open-gop --profile high --threads 1"
NORMAL="--subme 6 --me hex --ref 2 --no-mixed-refs --no-chroma-me --trellis 1 --partitions i8x8,i4x4 --psy-rd 1.0:0 --bframes 3 --rc-lookahead 24 --keyint 30 --bitrate 20000 --vbv-maxrate 20000 --vbv-bufsize 20000 --nal-hrd fakevbr --aud --pic-struct --open-gop --profile high --threads 1"
FR="--frames $FRAMES"; [ "$FRAMES" = 0 ] && FR=""

tree() { # name sha [cflags]
    local d=$W/$1 sha
    [ -x $d/x264 ] && return 0
    [ -d $W/repo ] || git clone -q $REPO $W/repo || exit 1
    (cd $W/repo && git fetch -q origin wip/x264-nw-bwledger speed-next) || exit 1
    [ "$(cd $W/repo && git rev-parse --verify "$TIP^{commit}")" = "$TIP" ] || { echo "TIP must be the full pushed sha"; exit 1; }
    sha=$(cd $W/repo && git rev-parse --verify "$2^{commit}") || exit 1
    rm -rf $d && mkdir -p $d && (cd $W/repo && git archive $sha) | tar -x -C $d && cd $d && echo "$1 $sha ${3:-}" > SHA || exit 1
    ./configure --bit-depth=8 --enable-static --disable-opencl \
        --extra-cflags="-fno-fast-math -ffp-contract=off -fno-pie ${3:-}" --extra-ldflags="-no-pie" > cfg.log 2>&1 || exit 1
    make -j"$(nproc)" x264 > make.log 2>&1 || { tail make.log; exit 1; }
}
cells() { # clip mode pairs
    for c in $CLIPLIST; do
        case $c in *-i) echo "$c normal"; echo "$c lowlat";; *) echo "$c normal";; esac
    done
    [ -n "${CLIP422:-}" ] && echo "422 normal"
}
enc() { # arm clip mode tag
    local a=$1 c=$2 m=$3 t=$4 il="" in=$CLIPS/$2.y4m opt=$NORMAL
    [ $c = 422 ] && in=$CLIP422
    case $c in *-i) il="--tff";; esac
    [ $m = lowlat ] && opt=$LOWLAT
    case $c in 422) opt="${opt/--profile high/--profile high422} --output-csp i422";; esac
    taskset -c $CORE $W/$a/x264 $opt $il $FR --no-progress ${DUMP:-} -o $W/out/$t.264 $in 2> $W/out/$t.log
}

case "$1" in
build)
    mkdir -p $W
    tree base $BASE; tree off $TIP; tree on $TIP -DX264_BWLEDGER=1
    for a in base off on; do echo "$(cat $W/$a/SHA): $($W/$a/x264 --version | head -1)"; done
    echo "ledger symbols in on: $(nm $W/on/x264 | grep -c 'x264_bwl_'), in off: $(nm $W/off/x264 | grep -c 'x264_bwl_') (expect >0, 0)"
    ;;
md5)
    mkdir -p $W/out
    cells | while read c m; do
        for a in base off on; do DUMP="--dump-yuv $W/out/rec_$a.yuv" enc $a $c $m md5_${a}_${c}_$m; done
        r=$(md5sum $W/out/rec_{base,off,on}.yuv | awk '{print $1}' | sort -u | wc -l)
        b=$(md5sum $W/out/md5_{base,off,on}_${c}_$m.264 | awk '{print $1}' | sort -u | wc -l)
        echo "$c $m: recon md5 distinct $r, bitstream md5 distinct $b (1 and 1 = pass)"
        rm -f $W/out/rec_*.yuv
    done
    ;;
ledger)
    mkdir -p $W/out
    cells | while read c m; do
        enc on $c $m led_${c}_$m
        grep '^BWLINFO' $W/out/led_${c}_$m.log | sed "s/^/$c $m: /"
    done
    ;;
report)
    cells | while read c m; do
        echo "=== $c $m ($FRAMES frames, --threads 1) ==="
        awk -f $(dirname $0)/bwl-report.awk $W/out/led_${c}_$m.log
        awk -f $(dirname $0)/bwl-report.awk -v table=frames $W/out/led_${c}_$m.log > $W/out/frames_${c}_$m.tsv
        echo "per-frame table: $W/out/frames_${c}_$m.tsv"
    done
    ;;
*)  echo "usage: $0 build | md5 | ledger | report"; exit 1;;
esac
