#!/bin/bash
# Copyright (C) 2026 Open Broadcast Systems Ltd
# Core 3 (Raptor Cove, 1 DIMM, kernel 5.15 generic PMU): LLC-miss attribution per symbol, A/B
# DIRECTION ONLY. "cache-misses" here is the generic LLC-miss event (demand + RFO + L2-prefetch
# fills); NT stores and write-backs are not counted, so this never gives absolute DRAM bytes
# (take those from the ledger build, or MBM / IMC counters). Needs perf_event_paranoid <= 1 (set).
#   bash llcmiss.sh build | stat [rounds] | record | report
# Set: ARMS="name=sha ..." (2+ arms, full shas), BRANCH (where the shas live), CLIPS.
# Optional: FRAMES (30), CLIPLIST ("field-frame-mix-i tile-chaos-p"), MODES ("lowlat normal"),
# NS ("1 2" concurrent encodes, each on its own physical core), W, CG (e.g. "--call-graph lbr").
set -u
W=${W:-$HOME/x264-llcmiss}
CLIPS=${CLIPS:?set CLIPS}
ARMS=${ARMS:?set ARMS="base=<sha> arm=<sha>"}
BRANCH=${BRANCH:?set BRANCH}
FRAMES=${FRAMES:-30}
CLIPLIST=${CLIPLIST:-"field-frame-mix-i tile-chaos-p"}
MODES=${MODES:-"lowlat normal"}
NS=${NS:-"1 2"}
REPO=https://github.com/kierank/x264-obe
LOWLAT="--preset veryfast --tune zerolatency --intra-refresh --keyint 30 --bitrate 20000 --vbv-maxrate 20000 --vbv-bufsize 667 --nal-hrd fakevbr --aud --pic-struct --open-gop --profile high --threads 1"
NORMAL="--subme 6 --me hex --ref 2 --no-mixed-refs --no-chroma-me --trellis 1 --partitions i8x8,i4x4 --psy-rd 1.0:0 --bframes 3 --rc-lookahead 24 --keyint 30 --bitrate 20000 --vbv-maxrate 20000 --vbv-bufsize 20000 --nal-hrd fakevbr --aud --pic-struct --open-gop --profile high --threads 1"
# first hardware thread of each physical core
CPUS=($(for c in /sys/devices/system/cpu/cpu[0-9]*; do cat $c/topology/thread_siblings_list; done | sort -u | sed 's/[,-].*//' | sort -n))
arms() { for x in $ARMS; do echo ${x%%=*}; done; }
shaof() { for x in $ARMS; do [ ${x%%=*} = $1 ] && echo ${x#*=}; done; }

tree() { # name sha
    local d=$W/$1
    [ -x $d/x264 ] && return 0
    [ -d $W/repo ] || git clone -q $REPO $W/repo || exit 1
    (cd $W/repo && git fetch -q origin $BRANCH) || exit 1
    [ "$(cd $W/repo && git rev-parse --verify "$2^{commit}")" = "$2" ] || { echo "$1: give the full sha"; exit 1; }
    rm -rf $d && mkdir -p $d && (cd $W/repo && git archive $2) | tar -x -C $d && cd $d || exit 1
    ./configure --bit-depth=8 --enable-static --disable-opencl --extra-cflags="-fno-fast-math -ffp-contract=off -fno-pie" \
        --extra-ldflags="-no-pie" > cfg.log 2>&1 || exit 1
    make -j"$(nproc)" x264 > make.log 2>&1 || { tail make.log; exit 1; }
}
opts() { # clip mode
    local il=""; case $1 in *-i) il="--tff";; esac
    if [ $2 = lowlat ]; then echo "$LOWLAT $il --frames $FRAMES"; else echo "$NORMAL $il --frames $FRAMES"; fi
}
# N concurrent encodes of one arm, encoder j on core CPUS[j]; PERFCMD gets the output name
run_n() { # arm clip mode n tag
    local j
    for j in $(seq 0 $(($4 - 1))); do
        taskset -c ${CPUS[$j]} $PERFCMD$W/out/$5_$j $W/$1/x264 $(opts $2 $3) --no-progress -o /dev/null $CLIPS/$2.y4m \
            2> $W/out/$5_$j.log &
    done
    wait
}

case "$1" in
build)
    mkdir -p $W/out
    for a in $(arms); do tree $a $(shaof $a); echo "$a $(shaof $a): $($W/$a/x264 --version | head -1)"; done
    echo "cores used (first thread each): ${CPUS[*]}"
    ;;
stat)
    R=${2:-5}; mkdir -p $W/out; A=($(arms))
    for r in $(seq 1 $R); do for n in $NS; do for c in $CLIPLIST; do for m in $MODES; do
        for k in $(seq 0 $((${#A[@]} - 1))); do a=${A[$(( (k + r) % ${#A[@]} ))]}
            t=st_${r}_${n}_${a}_${c}_$m
            PERFCMD="perf stat -x, -e cycles:u,instructions:u,cache-references,cache-misses -o " run_n $a $c $m $n $t
            for j in $(seq 0 $((n - 1))); do
                awk -F, -v k="$r $n $c $m $a $j" '$3 ~ /^(cycles|instructions|cache-references|cache-misses)/ { split( $3, e, ":" ); v[e[1]] = $1 }
                    END { print k, v["cycles"], v["instructions"], v["cache-references"], v["cache-misses"] }' $W/out/${t}_$j >> $W/stat.txt
            done
        done
    done; done; done; done
    ;;
record)
    mkdir -p $W/out
    for n in $NS; do for c in $CLIPLIST; do for m in $MODES; do for a in $(arms); do
        t=rec_${n}_${a}_${c}_$m
        PERFCMD="perf record -q -e cache-misses -c 20011 ${CG:-} -o " run_n $a $c $m $n $t
        # encoder 0's samples: symbol, MB/f = samples x 20011 x 64 / frames
        perf report -q --stdio --no-children -F overhead,sample,sym -i $W/out/${t}_0 2>/dev/null \
            | awk -v f=$FRAMES '$1 ~ /%$/ { pct = $1; sub( /%/, "", pct ); n = $2; $1 = ""; $2 = ""; sym = $0; gsub( /^ +/, "", sym )
                                          printf "%s\t%.3f\t%s\n", pct, n * 20011 * 64 / f / 1e6, sym }' \
            | sort -t$'\t' -k1,1gr | head -25 > $W/out/$t.sym
        echo "$t: top LLC-miss symbols (share %, MB/f-equivalent, symbol) in $W/out/$t.sym"
    done; done; done; done
    ;;
report)
    # per (n, clip, mode): median over rounds and encoders of cache-misses x 64 / frame, and of cycles / frame,
    # each arm against the first
    awk -v f=$FRAMES -v first=$(arms | head -1) '
    function med( v, n,   i, j, x ) { for( i = 1; i <= n; i++ ) for( j = i+1; j <= n; j++ ) if( v[j] < v[i] ) { x = v[i]; v[i] = v[j]; v[j] = x }
                                    return n % 2 ? v[(n+1)/2] : (v[n/2] + v[n/2+1]) / 2 }
    { k = $2" "$3" "$4; a = $5; cell[k] = 1; arm[a] = 1; i = ++cnt[k" "a]
      cm[k" "a" "i] = $10 * 64 / f / 1e6; cy[k" "a" "i] = $7 / f; ipc[k" "a" "i] = $8 / $7 }
    END { for( k in cell ) for( a in arm ) { n = cnt[k" "a]
            for( i = 1; i <= n; i++ ) { x[i] = cm[k" "a" "i]; y[i] = cy[k" "a" "i]; z[i] = ipc[k" "a" "i] }
            M[k" "a] = med( x, n ); C[k" "a] = med( y, n ); P[k" "a] = med( z, n ) }
          for( k in cell ) for( a in arm )
            printf "n=%s %-26s %-8s LLC-miss %.2f MB/f-eq (%+.1f %%)  cycles/f %.0f (%+.2f %%)  IPC %.3f\n", substr( k, 1, 1 ), substr( k, 3 ), a,
                   M[k" "a], 100 * (M[k" "a] / M[k" "first] - 1), C[k" "a], 100 * (C[k" "a] / C[k" "first] - 1), P[k" "a] }' $W/stat.txt | sort
    ;;
*)  echo "usage: $0 build | stat [rounds] | record | report"; exit 1;;
esac
