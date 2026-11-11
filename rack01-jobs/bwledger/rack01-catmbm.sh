#!/bin/bash
# Copyright (C) 2026 Open Broadcast Systems Ltd
# rack01 (EPYC 8324P, Zen 4c, 8 CCX x 4 cores, kernel 5.15): the cheapest E-2400 proxy.
# Two CCXs (EMU_DOMS, 8 cores / 16 threads, like the E-2400's 8C/16T) run 8 concurrent encodes;
# resctrl CAT shrinks their L3 to the E-2400 share (TARGET_MB per encoder, default 3), optionally
# an MBA cap, and MBM gives DRAM bytes (L3 <-> DRAM, reads + write-backs) per encoder.
#   check             no root needed: what exists / is mounted, topology, cache geometry
#   setup-cmds        PRINTS the root commands (mount, groups, masks, chown) for Kieran to run
#   teardown-cmds     PRINTS the root teardown
#   build             trees: BASE / ARM (ab) and PLACE_SHA (place), git-archive exports, -fno-pie
#   md5               ab gate: recon md5 base vs arm at --threads 1, bitstream too (archive trees)
#   ab [rounds]       8x, base vs arm, placement PLACE (default ccx), CAT group GROUP (default bwlsh)
#   place [rounds]    item 9: placement arms (PLACE_ARMS), one binary, CAT group GROUP
#   report            per arm and cell: MB/f per encoder (MBM), core-ms/f, fps (worst encoder)
# Set: CLIPS (dir of the Step B clips <clip>.y4m). Optional: W, FRAMES (0 = whole clip), BRANCH, BASE,
# ARM, PLACE_SHA, EMU_DOMS ("2 3"), TARGET_MB (3), MBA_GBS (per-domain cap, empty = none), PACE (1 =
# feed in real time through y4mpace), GROUP (bwlsh = shared CAT mask, bwlfull = no CAT, bwlp = private).
# Rack01 rules: decoders stay stopped for timing; nothing else heavy on ANY node while this runs.
set -u
W=${W:-$HOME/x264-catmbm}
REPO=https://github.com/kierank/x264-obe
BRANCH=${BRANCH:-speed-next}
R=/sys/fs/resctrl
EMU_DOMS=${EMU_DOMS:-"2 3"}
TARGET_MB=${TARGET_MB:-3}
GROUP=${GROUP:-bwlsh}
FRAMES=${FRAMES:-0}
NENC=8
CELLS=${CELLS:-"il-normal il-lowlat p-normal"}
CLIPS_IL=${CLIPS_IL:-"field-frame-mix-i fades-i credits-i"}
CLIPS_P=${CLIPS_P:-"tile-chaos-p pan-fast-p fades-p"}
PLACE_ARMS=${PLACE_ARMS:-"ccx ccx-auto free core core-t2 core-t4"}
TH=${TH:-3}
COMMON="--bitrate 20000 --vbv-maxrate 20000 --nal-hrd fakevbr --aud --pic-struct --open-gop --profile high --keyint 30"
LOWLAT="--preset veryfast --tune zerolatency --intra-refresh --vbv-bufsize 667"
NORMAL="--subme 6 --me hex --ref 2 --no-mixed-refs --no-chroma-me --trellis 1 --partitions i8x8,i4x4 --psy-rd 1.0:0 --bframes 3 --rc-lookahead 24 --vbv-bufsize 20000"

# ---- topology (sysfs, no root) ----
dom_of() { cat /sys/devices/system/cpu/cpu$1/cache/index3/id; }
dom_cpus() { # dom -> its cpus, comma list
    for c in /sys/devices/system/cpu/cpu[0-9]*; do n=${c##*cpu}; [ "$(dom_of $n)" = $1 ] && echo $n; done | sort -n | paste -sd,
}
dom_cores() { # dom -> one "a,b" sibling list per physical core
    for c in $(dom_cpus $1 | tr , ' '); do cat /sys/devices/system/cpu/cpu$c/topology/thread_siblings_list; done | sort -u -t, -k1,1n
}
l3_mb() { awk '{ v = $1; if( v ~ /K$/ ) v /= 1024; else sub( /M$/, "", v ); print v + 0 }' /sys/devices/system/cpu/cpu0/cache/index3/size; }
cbm_bits() {
    local m=$((16#$(cat $R/info/L3/cbm_mask 2>/dev/null || echo ffff))) n=0
    while [ $m -gt 0 ]; do n=$((n + (m & 1))); m=$((m >> 1)); done
    echo $n
}
ways_mask() { # nways from the top -> hex
    printf "%x" $(( ((1 << $1) - 1) << ($(cbm_bits) - $1) ))
}

case "${1:-}" in
check)
    echo "== kernel $(uname -r); $(grep -m1 'model name' /proc/cpuinfo)"
    for f in cat_l3 mba cqm_mbm_total cqm_mbm_local cqm_llc; do printf "%-14s %s\n" $f "$(grep -c -w $f /proc/cpuinfo)"; done
    mount | grep -q " $R " && echo "resctrl: mounted" || echo "resctrl: NOT mounted (Kieran: see setup-cmds)"
    [ -d $R/info ] && for f in L3/cbm_mask L3/num_closids L3/min_cbm_bits MB/min_bandwidth MB/bandwidth_gran MB/delay_linear L3_MON/num_rmids L3_MON/mon_features; do
        printf "  %-22s %s\n" $f "$(cat $R/info/$f 2>/dev/null | tr '\n' ' ')"; done
    echo "== L3 $(l3_mb) MB per domain; domains: $(cat /sys/devices/system/cpu/cpu*/cache/index3/id | sort -un | paste -sd' ')"
    for d in $EMU_DOMS; do echo "  emulator dom $d: cpus $(dom_cpus $d); cores: $(dom_cores $d | paste -sd' ')"; done
    for g in bwlsh bwlfull bwlp0; do [ -d $R/$g ] && echo "  group $g: $(tr '\n' ' ' < $R/$g/schemata); tasks writable: $([ -w $R/$g/tasks ] && echo yes || echo NO)"; done
    systemctl is-active obdd 2>/dev/null | grep -q '^active' && echo "WARNING: obdd is active; decoders must be stopped for timing" || echo "obdd: not active"
    ;;
setup-cmds)
    # shared: the 4 encoders of a domain share TARGET_MB x 4 of its L3 (the E-2400 shares one L3);
    # private: each encoder gets TARGET_MB alone (bwlp0..7). bwlfull: full L3, the CAT-off control.
    mbw=$(awk -v l=$(l3_mb) -v b=$(cbm_bits) 'BEGIN { print l / b }')
    sh=$(awk -v t=$TARGET_MB -v w=$mbw -v b=$(cbm_bits) 'BEGIN { n = int( 4*t/w + 0.5 ); if( n > b ) n = b; if( n < 1 ) n = 1; print n }')
    pr=$(awk -v t=$TARGET_MB -v w=$mbw 'BEGIN { n = int( t/w + 0.5 ); if( n < 1 ) n = 1; print n }')
    echo "# rack01, as root (sudo), once per boot. L3 $(l3_mb) MB / $(cbm_bits) ways = $mbw MB/way;"
    echo "# shared: $sh ways per emulator domain (4 encoders, $(awk -v a=$sh -v w=$mbw 'BEGIN{print a*w/4}') MB each); private: $pr ways per encoder"
    echo "mountpoint -q $R || mount -t resctrl resctrl $R"
    l3sh=""; l3full=""
    for d in $EMU_DOMS; do l3sh="$l3sh;$d=$(ways_mask $sh)"; l3full="$l3full;$d=$(ways_mask $(cbm_bits))"; done
    echo "mkdir -p $R/bwlsh $R/bwlfull"
    echo "echo 'L3:${l3sh#;}' > $R/bwlsh/schemata"
    echo "echo 'L3:${l3full#;}' > $R/bwlfull/schemata"
    if [ -n "${MBA_GBS:-}" ]; then
        # AMD MBA: absolute, 1/8 GB/s units, 2048 = unthrottled (check info/MB/bandwidth_gran)
        v=$(awk -v g=$MBA_GBS 'BEGIN { print int( g*8 ) }'); mb=""; for d in $EMU_DOMS; do mb="$mb;$d=$v"; done
        echo "echo 'MB:${mb#;}' > $R/bwlsh/schemata   # $MBA_GBS GB/s per domain"
    fi
    echo "for g in bwlsh bwlfull; do for i in \$(seq 0 $((NENC-1))); do mkdir -p $R/\$g/mon_groups/e\$i; done; done"
    i=0; for d in $EMU_DOMS; do for k in 0 1 2 3; do
        lo=$(( $(cbm_bits) - (k+1)*pr )); [ $lo -lt 0 ] && { echo "# private: $pr ways x 4 do not fit"; break; }
        echo "mkdir -p $R/bwlp$i && echo 'L3:$d=$(printf %x $(( ((1 << pr) - 1) << lo )))' > $R/bwlp$i/schemata"
        i=$((i+1)); done; done
    echo "# let the obe user move its own encoders into the groups (write permission on the tasks files)"
    echo "chown -R $(id -un) $R/bwlsh $R/bwlfull $R/bwlp*"
    echo "# if chown is refused on resctrl, give $(id -un) NOPASSWD for: /usr/bin/tee $R/bwl*/tasks, $R/bwl*/mon_groups/*/tasks"
    ;;
teardown-cmds)
    echo "rmdir $R/bwlsh/mon_groups/e* $R/bwlfull/mon_groups/e* 2>/dev/null; rmdir $R/bwlsh $R/bwlfull $R/bwlp* 2>/dev/null"
    echo "umount $R   # only if nothing else uses resctrl (the hpel6 group from 11-01 may still be there)"
    ;;
esac

# ---- trees ----
tree() { # name sha
    local d=$W/$1
    [ -x $d/x264 ] && return 0
    [ -d $W/repo ] || git clone -q $REPO $W/repo || exit 1
    (cd $W/repo && git fetch -q origin $BRANCH) || exit 1
    [ "$(cd $W/repo && git rev-parse --verify "$2^{commit}")" = "$2" ] || { echo "$1: give the full sha"; exit 1; }
    rm -rf $d && mkdir -p $d && (cd $W/repo && git archive $2) | tar -x -C $d && cd $d && echo "$1 $2" > SHA || exit 1
    ./configure --bit-depth=8 --enable-static --disable-opencl --extra-cflags="-fno-fast-math -ffp-contract=off -fno-pie" \
        --extra-ldflags="-no-pie" > cfg.log 2>&1 || exit 1
    make -j"$(nproc)" x264 > make.log 2>&1 || { tail make.log; exit 1; }
}

# ---- one 8x run ----
mbm() { # group dir -> total bytes over its domains
    cat $1/mon_data/mon_L3_*/mbm_total_bytes 2>/dev/null | awk '{ s += $1 } END { printf "%.0f\n", s }'
}
grpdir() { # encoder index -> resctrl dir it is counted in
    case $GROUP in
        bwlp) echo $R/bwlp$1;;
        *) echo $R/$GROUP/mon_groups/e$1;;
    esac
}
cpus_for() { # arm encoder -> cpu list
    local D=($EMU_DOMS) cores
    cores=($(for d in $EMU_DOMS; do dom_cores $d; done))
    case $1 in
        free) for d in $EMU_DOMS; do dom_cpus $d; done | paste -sd,;;
        ccx*) dom_cpus ${D[$(( $2 / 4 ))]};;
        core*) echo ${cores[$2]};;
    esac
}
threads_for() { case $1 in *-t2) echo 2;; *-t4) echo 4;; *-auto) echo auto;; *) echo $TH;; esac; }
run8() { # binary-arm placement cell round
    local a=$1 pl=$2 cell=$3 r=$4 t i c il opt clips in
    case $cell in il-*) clips=($CLIPS_IL); il="--tff";; *) clips=($CLIPS_P); il="";; esac
    case $cell in *-lowlat) opt=$LOWLAT;; *) opt=$NORMAL;; esac
    local fr=""; [ "$FRAMES" != 0 ] && fr="--frames $FRAMES"
    local th=$(threads_for $pl)
    t=$W/out/${r}_${a}_${pl}_$cell; mkdir -p $t
    for i in $(seq 0 $((NENC-1))); do mbm $(grpdir $i) > $t/mbm0_$i; done
    mbm $R/$GROUP > $t/mbmg0 2>/dev/null
    for i in $(seq 0 $((NENC-1))); do
        c=${clips[$(( i % ${#clips[@]} ))]}; in=$CLIPS/$c.y4m
        (
            echo $BASHPID > $(grpdir $i)/tasks || exit 97
            if [ "${PACE:-0}" = 1 ]; then
                $W/y4mpace $in | exec taskset -c $(cpus_for $pl $i) /usr/bin/time -f "%e %U %S" -o $t/time_$i \
                    $W/$a/x264 $COMMON $opt $il $fr --threads $th --no-progress --demuxer y4m -o $t/out_$i.264 - 2> $t/log_$i
            else
                exec taskset -c $(cpus_for $pl $i) /usr/bin/time -f "%e %U %S" -o $t/time_$i \
                    $W/$a/x264 $COMMON $opt $il $fr --threads $th --no-progress -o $t/out_$i.264 $in 2> $t/log_$i
            fi
        ) &
    done
    wait
    for i in $(seq 0 $((NENC-1))); do mbm $(grpdir $i) > $t/mbm1_$i; done
    mbm $R/$GROUP > $t/mbmg1 2>/dev/null
    for i in $(seq 0 $((NENC-1))); do
        f=$(grep -o 'encoded [0-9]* frames' $t/log_$i | awk '{print $2}')
        read e u s < $t/time_$i
        echo "$r $a $pl $cell $i ${f:-0} $e $u $s $(( $(cat $t/mbm1_$i) - $(cat $t/mbm0_$i) )) $(md5sum < $t/out_$i.264 | cut -c1-12)" >> $W/runs.txt
    done
    rm -f $t/out_*.264
}
need_groups() {
    for i in $(seq 0 $((NENC-1))); do [ -w $(grpdir $i)/tasks ] || { echo "$(grpdir $i)/tasks not writable: run setup-cmds as root first"; exit 1; }; done
}

case "${1:-}" in
check|setup-cmds|teardown-cmds) ;;
build)
    mkdir -p $W
    [ -n "${BASE:-}" ] && tree base $BASE
    [ -n "${ARM:-}" ] && tree arm $ARM
    [ -n "${PLACE_SHA:-}" ] && tree place $PLACE_SHA
    [ -x $W/y4mpace ] || gcc -O2 -o $W/y4mpace $(dirname $0)/y4mpace.c || exit 1
    for a in base arm place; do [ -x $W/$a/x264 ] && echo "$(cat $W/$a/SHA): $($W/$a/x264 --version | head -1)"; done
    ;;
md5)
    mkdir -p $W/out
    for cell in $CELLS; do
        case $cell in il-*) clips=($CLIPS_IL); il="--tff";; *) clips=($CLIPS_P); il="";; esac
        case $cell in *-lowlat) opt=$LOWLAT;; *) opt=$NORMAL;; esac
        for c in ${clips[@]}; do
            for a in base arm; do
                $W/$a/x264 $COMMON $opt $il --threads 1 --no-progress --dump-yuv $W/out/rec_$a.yuv -o $W/out/md5_$a.264 $CLIPS/$c.y4m 2> /dev/null
            done
            echo "$cell $c: recon md5 distinct $(md5sum $W/out/rec_{base,arm}.yuv | awk '{print $1}' | sort -u | wc -l)," \
                 "bitstream md5 distinct $(md5sum $W/out/md5_{base,arm}.264 | awk '{print $1}' | sort -u | wc -l) (1 and 1 = pass)"
            rm -f $W/out/rec_*.yuv
        done
    done
    ;;
ab)
    need_groups; RR=${2:-6}; A=(base arm arm base)
    for r in $(seq 1 $RR); do for cell in $CELLS; do
        for k in 0 1 2 3; do run8 ${A[$(( (k + r) % 4 ))]} ${PLACE:-ccx} $cell $r; done   # A B B A, rotated
    done; done
    ;;
place)
    need_groups; RR=${2:-6}; P=($PLACE_ARMS)
    for r in $(seq 1 $RR); do for cell in $CELLS; do
        for k in $(seq 0 $((${#P[@]} - 1))); do run8 place ${P[$(( (k + r) % ${#P[@]} ))]} $cell $r; done
    done; done
    ;;
report)
    # runs.txt: round arm placement cell enc frames wall user sys mbm_bytes md5
    awk 'function med( v, n,   i, j, x ) { for( i = 1; i <= n; i++ ) for( j = i+1; j <= n; j++ ) if( v[j] < v[i] ) { x = v[i]; v[i] = v[j]; v[j] = x }
                                        return n % 2 ? v[(n+1)/2] : (v[n/2] + v[n/2+1]) / 2 }
    $6 > 0 { k = $2" "$3" "$4; rk = k" "$1; K[k] = 1; RK[rk] = k
             mb[rk] += $10 / $6 / 1e6; ms[rk] += ($8 + $9) * 1000 / $6; ne[rk]++
             fps = $6 / $7; if( !(rk in wf) || fps < wf[rk] ) wf[rk] = fps; md5[k" "$5" "$11] = 1 }
    END { for( rk in RK ) { k = RK[rk]; n = ++N[k]; M[k" "n] = mb[rk] / ne[rk]; C[k" "n] = ms[rk] / ne[rk]; F[k" "n] = wf[rk] }
          printf "%-34s %8s %10s %10s %6s\n", "arm placement cell", "MB/f/enc", "core-ms/f", "worst fps", "rounds"
          for( k in K ) { n = N[k]; for( i = 1; i <= n; i++ ) { x[i] = M[k" "i]; y[i] = C[k" "i]; z[i] = F[k" "i] }
                          printf "%-34s %8.2f %10.2f %10.2f %6d\n", k, med( x, n ), med( y, n ), med( z, n ), n } }' $W/runs.txt | sort -k3,3 -k1,2
    echo "distinct output md5 per (arm placement cell encoder) over rounds (1 = deterministic):"
    awk '{ k = $2" "$3" "$4" "$5; if( !((k" "$11) in s) ) { s[k" "$11] = 1; n[k]++ } } END { for( k in n ) if( n[k] > 1 ) print "  " k ": " n[k]; print "  (others: 1)" }' $W/runs.txt
    ;;
*)  echo "usage: $0 check | setup-cmds | teardown-cmds | build | md5 | ab [rounds] | place [rounds] | report"; exit 1;;
esac
