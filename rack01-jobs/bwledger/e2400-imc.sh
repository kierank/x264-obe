#!/bin/bash
# Copyright (C) 2026 Open Broadcast Systems Ltd
# Xeon E-2400 (8C/16T Raptor Cove, 2 DDR5 channels; NOT YET AVAILABLE): measured DRAM bytes from the
# IMC free-running counters, calibrated with membw (own STREAM-like kernels), then 1/2/4/8 concurrent
# encodes on 1 and 2 DIMMs (DIMMS says which; moving a DIMM is Kieran's).
#   check                 no root: CPU, flags, PMU / IMC / resctrl presence, what needs Kieran
#   build                 x264 tree (SHA, git-archive export, -fno-pie) + membw
#   calib                 membw at 1/2/4/8/16 threads inside perf stat -a on the IMC counters
#   enc [rounds]          NS concurrent encodes x CELLS, IMC bytes around each batch
#   stage                 per-symbol L3-miss / RFO / streaming-store attribution (event names checked)
#   report
# Set: DIMMS (1 or 2), CLIPS, SHA (full sha on BRANCH, default speed-next). Optional: W, FRAMES (0 = whole
# clip), NS ("1 2 4 8"), PLACE (core = encoder i on core i's SMT pair; free = all cpus), TH (3).
# Needs: perf_event_paranoid <= 0 (or root) for system-wide uncore counting.
set -u
W=${W:-$HOME/x264-e2400}
REPO=https://github.com/kierank/x264-obe
BRANCH=${BRANCH:-speed-next}
FRAMES=${FRAMES:-0}
NS=${NS:-"1 2 4 8"}
PLACE=${PLACE:-core}
TH=${TH:-3}
CELLS=${CELLS:-"il-normal il-lowlat p-normal"}
CLIPS_IL=${CLIPS_IL:-"field-frame-mix-i fades-i credits-i"}
CLIPS_P=${CLIPS_P:-"tile-chaos-p pan-fast-p fades-p"}
COMMON="--bitrate 20000 --vbv-maxrate 20000 --nal-hrd fakevbr --aud --pic-struct --open-gop --profile high --keyint 30"
LOWLAT="--preset veryfast --tune zerolatency --intra-refresh --vbv-bufsize 667"
NORMAL="--subme 6 --me hex --ref 2 --no-mixed-refs --no-chroma-me --trellis 1 --partitions i8x8,i4x4 --psy-rd 1.0:0 --bframes 3 --rc-lookahead 24 --vbv-bufsize 20000"

imc_events() { # every free-running IMC unit's data_read and data_write
    local d u e=""
    for d in /sys/bus/event_source/devices/uncore_imc_free_running_*; do
        [ -d $d ] || continue; u=${d##*/}
        [ -e $d/events/data_read ] && e="$e,$u/data_read/"
        [ -e $d/events/data_write ] && e="$e,$u/data_write/"
    done
    echo ${e#,}
}
# perf stat -x, output -> total MiB read and written (the events are scaled to MiB)
imc_sum() { awk -F, '$3 ~ /data_read/ { r += $1 } $3 ~ /data_write/ { w += $1 } END { printf "%.1f %.1f\n", r, w }' $1; }
cores() { for c in /sys/devices/system/cpu/cpu[0-9]*; do cat $c/topology/thread_siblings_list; done | sort -u -t, -k1,1n; }

case "${1:-}" in
check)
    lscpu | grep -E 'Model name|^CPU\(s\)|Thread|Core|Socket|L2|L3|NUMA node\(s\)'
    for f in avx2 avx_vnni gfni bmi2 rdt_a cqm_llc cqm_mbm_total cat_l3 mba; do printf "  %-14s %s\n" $f "$(grep -m1 -c -w $f /proc/cpuinfo)"; done
    echo "perf_event_paranoid: $(cat /proc/sys/kernel/perf_event_paranoid) (<= 0 needed for uncore, or root: Kieran)"
    echo "IMC free-running events: $(imc_events)"
    perf list 2>/dev/null | grep -i -E 'imc|mem_load_retired.l3_miss|ocr.demand_rfo.l3_miss|ocr.streaming_wr' | head -20
    [ -d /sys/fs/resctrl/info ] && echo "resctrl mounted: $(ls /sys/fs/resctrl/info | tr '\n' ' ')" || echo "resctrl: not mounted / not present"
    echo "DIMMs: needs root: sudo dmidecode -t memory | grep -E 'Size|Locator|Speed|Configured' (Kieran)"
    echo "physical cores (sibling lists): $(cores | paste -sd' ')"
    ;;
build)
    mkdir -p $W
    SHA=${SHA:?set SHA}
    if [ ! -x $W/x264/x264 ]; then
        [ -d $W/repo ] || git clone -q $REPO $W/repo || exit 1
        (cd $W/repo && git fetch -q origin $BRANCH && git rev-parse --verify "$SHA^{commit}") > /dev/null || exit 1
        rm -rf $W/x264 && mkdir -p $W/x264 && (cd $W/repo && git archive $SHA) | tar -x -C $W/x264 && cd $W/x264 || exit 1
        ./configure --bit-depth=8 --enable-static --disable-opencl --extra-cflags="-fno-fast-math -ffp-contract=off -fno-pie" \
            --extra-ldflags="-no-pie" > cfg.log 2>&1 && make -j"$(nproc)" x264 > make.log 2>&1 || { tail $W/x264/make.log; exit 1; }
    fi
    gcc -O2 -pthread -o $W/membw $(dirname $0)/membw.c || exit 1
    $W/x264/x264 --version | head -1
    ;;
calib)
    DIMMS=${DIMMS:?set DIMMS to 1 or 2}; E=$(imc_events); [ -n "$E" ] || { echo "no IMC free-running PMU"; exit 1; }
    # threads on distinct physical cores first, then the SMT siblings
    order=$( (cores | cut -d, -f1; cores | cut -s -d, -f2) | paste -sd,)
    for t in 1 2 4 8 16; do
        perf stat -a -x, -e $E -o $W/calib_${DIMMS}d_$t.imc $W/membw $t 256 $order > $W/calib_${DIMMS}d_$t.txt
        echo "dimms $DIMMS threads $t: IMC MiB read/write $(imc_sum $W/calib_${DIMMS}d_$t.imc)"; cat $W/calib_${DIMMS}d_$t.txt
    done
    ;;
enc)
    DIMMS=${DIMMS:?set DIMMS to 1 or 2}; E=$(imc_events); RR=${2:-3}
    CL=($(cores)); fr=""; [ "$FRAMES" != 0 ] && fr="--frames $FRAMES"
    for r in $(seq 1 $RR); do for cell in $CELLS; do for n in $NS; do
        case $cell in il-*) clips=($CLIPS_IL); il="--tff";; *) clips=($CLIPS_P); il="";; esac
        case $cell in *-lowlat) opt=$LOWLAT;; *) opt=$NORMAL;; esac
        t=$W/out/${DIMMS}d_${r}_${cell}_$n; mkdir -p $t
        : > $t/run.sh
        for i in $(seq 0 $((n-1))); do
            c=${clips[$(( i % ${#clips[@]} ))]}
            cpu="0-$(($(nproc)-1))"; [ $PLACE = core ] && cpu=${CL[$i]}
            echo "taskset -c $cpu /usr/bin/time -f '%e %U %S' -o $t/time_$i $W/x264/x264 $COMMON $opt $il $fr --threads $TH" \
                 "--no-progress -o /dev/null $CLIPS/$c.y4m 2> $t/log_$i &" >> $t/run.sh
        done
        echo wait >> $t/run.sh
        perf stat -a -x, -e $E -o $t/imc bash $t/run.sh
        read rmib wmib < <(imc_sum $t/imc)
        fsum=0; for i in $(seq 0 $((n-1))); do f=$(grep -o 'encoded [0-9]* frames' $t/log_$i | awk '{print $2}'); fsum=$((fsum + ${f:-0}))
            read e u s < $t/time_$i; echo "$DIMMS $r $cell $n $i ${f:-0} $e $u $s" >> $W/enc_frames.txt; done
        echo "$DIMMS $r $cell $n $fsum $rmib $wmib" >> $W/enc_imc.txt
        echo "dimms $DIMMS round $r $cell n=$n: $(awk -v r=$rmib -v w=$wmib -v f=$fsum 'BEGIN { printf "%.1f MB/f per encoder (rd %.1f wr %.1f)", (r+w)*1.048576/f, r*1.048576/f, w*1.048576/f }')"
    done; done; done
    ;;
stage)
    # per symbol, one encoder alone and one of 8: L3-miss loads, RFO misses, streaming (NT) stores
    ev=""; for e in mem_load_retired.l3_miss ocr.demand_rfo.l3_miss ocr.streaming_wr.any_response; do
        perf list 2>/dev/null | grep -q -w $e && ev="$ev,$e"; done
    [ -n "$ev" ] || { echo "none of the attribution events exist here; perf list | grep -i -E 'l3_miss|rfo|streaming'"; exit 1; }
    c=${CLIPS_IL%% *}
    perf record -q -e ${ev#,} -c 5003 -o $W/stage.data $W/x264/x264 $COMMON $NORMAL --tff --threads $TH --no-progress -o /dev/null $CLIPS/$c.y4m
    perf report -q --stdio --no-children --sort event,sym -i $W/stage.data 2>/dev/null | head -60
    ;;
report)
    echo "calibration: IMC bytes vs program bytes per membw run (files $W/calib_*)"
    for f in $W/calib_*d_*.imc; do echo "  ${f##*/}: IMC MiB rd/wr $(imc_sum $f)"; done
    awk '{ k = $1"d "$3" n="$4; s[k] += ($6 + $7) * 1.048576 / $5; c[k]++ } END { for( k in s ) printf "%-26s %.2f MB/f per encoder (mean of %d rounds)\n", k, s[k]/c[k], c[k] }' $W/enc_imc.txt | sort
    awk '$6 > 0 { k = $1"d "$3" n="$4; ms[k] += ($8 + $9) * 1000 / $6; fps = $6 / $7; if( !(k in w) || fps < w[k] ) w[k] = fps; c[k]++ }
         END { for( k in ms ) printf "%-26s core-ms/f %.2f  worst fps %.2f\n", k, ms[k]/c[k], w[k] }' $W/enc_frames.txt | sort
    ;;
*)  echo "usage: $0 check | build | calib | enc [rounds] | stage | report"; exit 1;;
esac
