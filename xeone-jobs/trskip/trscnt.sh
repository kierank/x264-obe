#!/bin/bash
# Xeon E (E-2478, Intel AVX2) counter job TRSCNT: wip/x264-nw-trskip 1e7584d3 + trskip-shadow.patch (the test
# commit d82790cb of wip/test-x264-trskip-shadow, never merged) built -DX264_TRSKIP_SHADOW=1. Untimed.
# Per skip category (luma-mb, luma-8x8-deferred, chroma-ac, i16-ac, p8x8): units, skipped units, trellis DPs,
# skipped DPs, and shadow_fail (every skipped group's trellis is run on a copy and must give the decimation it
# was skipped for: 0 expected); per block, trellis output score > round-to-nearest score split by rtn 9 / < 9
# (the survey 3 C5 flag; < 9 must be 0) and frame / field MB.
# Copyright (C) 2026 Open Broadcast Systems Ltd
#
#   FRAMES=120 bash trskip/trscnt.sh cbuild | cnt
# cbuild: off (md5 flavour, the plain tip) and cnt (md5 flavour, patched, -DX264_TRSKIP_SHADOW=1)
# cnt:   per cell, off and cnt encodes (pinned, untimed): recon and bitstream md5 off == cnt (the patch changes
#        no output and the version string is the same sha), then the trs lines of the cnt run in $W/out/trs_<cell>.txt
set -u
JOB=trscnt; AB=${AB:-}; BRANCHES="wip/x264-nw-trskip"
TIP=${TIP:-1e7584d3}
BASE=$TIP; ARM=$TIP
SHA_off=$TIP; SHA_cnt=$TIP
BITDEPTH=all
CELLS="field-frame-mix-i:normal tile-chaos-p:normal ffm422long-i:normal credits-i:normal ffm422long-i:normal@10
       field-frame-mix-i:normaltr2 tile-chaos-p:normaltr2 field-frame-mix-i:lowlat"
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../lib.sh"
# trellis 2: the RD-time encodes (rd_cost_mb, p8x8 partition encodes) take the same skips
MODE_normaltr2="${NORMAL/--trellis 1/--trellis 2} --partitions all --subme 8"
xe_patch() { case $1 in cnt) git apply $HERE/trskip-shadow.patch || return 1; git diff --stat ;; esac; }
xe_cflags() { [ $1 = cnt ] && echo "-DX264_TRSKIP_SHADOW=1"; }

xe_phase_cbuild() {
    mkdir -p $W/out; xe_src
    xe_tree off m || exit 1
    xe_tree cnt c || exit 1
    nm $(xe_bin cnt c) | grep -c ' [TtBbDd] x264_[0-9]*_trs' | sed 's/^/cnt tree trs symbols: /'
    nm $(xe_bin off m) | grep -c ' [TtBbDd] x264_[0-9]*_trs' | sed 's/^/off tree trs symbols (0 expected): /'
}

xe_phase_cnt() {
    mkdir -p $W/out; local spec v nr nb
    for spec in $CELLS; do xe_cell $spec
        [ -f $CL ] || { echo "$CN: SKIP (no $CL)"; continue; }
        v=""
        taskset -c $CC $(xe_bin off m) $CO --dump-yuv $W/out/rec_off.yuv -o $W/out/bs_off.264 $CL 2> $W/out/off_$CN.log || v="$v off:rc$?"
        taskset -c $CC $(xe_bin cnt c) $CO --dump-yuv $W/out/rec_cnt.yuv -o $W/out/bs_cnt.264 $CL 2> $W/out/cnt_$CN.log || v="$v cnt:rc$?"
        nr=$(md5sum $W/out/rec_off.yuv $W/out/rec_cnt.yuv | awk '{print $1}' | sort -u | wc -l)
        nb=$(md5sum $W/out/bs_off.264 $W/out/bs_cnt.264 | awk '{print $1}' | sort -u | wc -l)
        grep '^trs' $W/out/cnt_$CN.log > $W/out/trs_$CN.txt
        [ "$nr $nb" = "1 1" ] && [ -z "$v" ] && grep -q 'dp_calls' $W/out/trs_$CN.txt && v=PASS || v="FAIL$v (recon distinct $nr, bitstream distinct $nb)"
        echo "== $CN: off vs cnt $v; bitstream $(md5sum < $W/out/bs_off.264 | cut -c1-12) recon $(md5sum < $W/out/rec_off.yuv | cut -c1-12)"
        cat $W/out/trs_$CN.txt
        rm -f $W/out/rec_*.yuv $W/out/bs_*.264
    done
}
XE_PHASES="cbuild | cnt"
[ -n "${XE_TEST:-}" ] || xe_main "$@"
