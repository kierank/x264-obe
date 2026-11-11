#!/bin/bash
# Xeon E (E-2478, Intel AVX2) in-situ A/B + twin check: wip/x264-mvpred-c, x264_mb_predict_mv_ref16x16 in C.
#   c1 970be01c: the frame's temporal scales (h->mb.mvref.tscale, x264_mvpred_ref16x16_init in slice_init)
#   c2 c234b4b1: MBAFF only, the per-mb neighbour shifts and collocated mvs once per mb (mvref_mb_init)
# Copy into the wip/x264-core3-jobs checkout as xeone-jobs/mvpredc/ (it sources ../lib.sh).
# Copyright (C) 2026 Open Broadcast Systems Ltd
#
#   bash mvpredc-ab.sh build      (8 trees + the 2 twin trees, checkasm)        -> build window
#   bash mvpredc-ab.sh twin       (twin trees: old beside new, abort on any difference; prints the counts)
#   bash mvpredc-ab.sh live | md5 | time 9 | report
# AB (default all): all = 44754802 -> c234b4b1; c1 = 44754802 -> 970be01c; c2 = 970be01c -> c234b4b1
# No zero-call cell: ref16x16 runs in every P/B mb. For c2 the progressive cells are near-null (one dropped
# b_tconv test per call); its change is in the -i cells.
set -u
JOB=mvpredc; AB=${AB:-all}; BRANCHES="speed-next wip/x264-mvpred-c test/x264-mvpred-c-twin test/x264-mvpred-c-twin1"
case $AB in
all) BASE=44754802; ARM=c234b4b1 ;;
c1)  BASE=44754802; ARM=970be01c ;;
c2)  BASE=970be01c; ARM=c234b4b1 ;;
*) echo "unknown AB $AB"; exit 1 ;;
esac
BITDEPTH=all   # mvpred.c is a shared C path: the 10-bit 4:2:2 md5 cells
CELLS="tile-chaos-p:lowlat tile-chaos-p:normal field-frame-mix-i:lowlat field-frame-mix-i:normal ffm422-i:lowlat ffm422-i:normal"
MD5CELLS="ffm422p10-i:lowlat@10 ffm422p10-i:normal@10"
LIVE_RE='predict_mv_ref16x16|mvref_mb_init|mvpred_ref16x16_init'
# twin trees (md5 flavour): a2abd958 = old beside c234b4b1, 9f158ea7 = old beside 970be01c
COUNT_TREES="twin twin1"; SHA_twin=a2abd958; SHA_twin1=9f158ea7; COUNT_RE='mvpred-twin'; COUNTCELLS=field-frame-mix-i:normal
. "$(dirname "$0")/../lib.sh"
# twin extras, each with the 3 clips: frame threads, sliced threads, and medium (b-pyramid, temporal direct
# off by default -> --direct temporal, weightp 2 dupes, 3 refs)
MODE_normalft="${NORMAL/--threads 1/--threads 2}"
MODE_normalst="${NORMAL/--threads 1/--threads 2 --sliced-threads}"
MODE_medium="--preset medium --direct temporal --weightp 2 --ref 3 --bitrate 20000 --vbv-maxrate 20000 --vbv-bufsize 20000 --keyint 30 --threads 1"
TWINCELLS="$CELLS $MD5CELLS"
for c in tile-chaos-p field-frame-mix-i ffm422-i; do TWINCELLS="$TWINCELLS $c:normalft $c:normalst $c:medium"; done
TWINCELLS="$TWINCELLS ffm422p10-i:normalft@10 ffm422p10-i:medium@10"
XE_PHASES=twin
xe_phase_twin() {
    mkdir -p $W/out; local n spec rc
    for n in twin twin1; do for spec in $TWINCELLS; do xe_cell $spec
        [ -f $CL ] || { echo "$CN: SKIP (no $CL)"; continue; }
        xe_run $n c $spec tw_${n}_$CN; rc=$?
        echo "$n $CN rc $rc: $(grep -E 'mvpred-twin' $W/out/tw_${n}_$CN.log | tr '\n' ' ')"
        rm -f $W/out/tw_${n}_$CN.264
    done; done
}
[ -n "${XE_TEST:-}" ] || xe_main "$@"
