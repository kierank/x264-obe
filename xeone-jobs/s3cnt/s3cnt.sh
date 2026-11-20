#!/bin/bash
# Xeon E (E-2478, Intel AVX2) counter job S3CNT: survey 3 measurement counters, wip/test-x264-survey3-cnt
# (speed-next 322af72b + one test commit, never merged). One sha, two builds: "off" (the plain tree) and
# "cnt" (-DX264_S3CNT=1: C1 refine_qpel skip record, C2 lowlat quadrant reuse, C3 refine_bidir get_ref
# overlap, C4 RD sizing crossing point, C5 trellis-skip decimation proof + shadow check, C6 lowres intra
# passes). Not timed: the counter build runs two shadow C searches per ME call and is several times slower.
# Copyright (C) 2026 Open Broadcast Systems Ltd
#
#   FRAMES=120 bash s3cnt/s3cnt.sh cbuild | cnt | clean
# cbuild: off (md5 flavour) and cnt (md5 flavour + -DX264_S3CNT=1) of $TIP; build window
# cnt:   per cell, off and cnt encodes (pinned, untimed): recon md5 and bitstream md5 off == cnt (same sha, pinned
#        version string, so the bitstreams compare byte for byte), then the counter lines of the cnt run in
#        $W/out/s3_<cell>.txt; prints PASS / FAIL per cell and the C1-C6 summary lines
set -u
JOB=s3cnt; AB=${AB:-}; BRANCHES="speed-next wip/test-x264-survey3-cnt"
TIP=${TIP:-2b8b706d}
BASE=$TIP; ARM=$TIP
SHA_off=$TIP; SHA_cnt=$TIP
CELLS="field-frame-mix-i:lowlat field-frame-mix-i:normal tile-chaos-p:lowlat tile-chaos-p:normal ffm422long-i:normal
       credits-i:lowlat credits-i:normal"
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../lib.sh"
xe_cflags() { [ $1 = cnt ] && echo "-DX264_S3CNT=1"; }

xe_phase_cbuild() {
    mkdir -p $W/out; xe_src
    xe_tree off m || exit 1
    xe_tree cnt c || exit 1
    nm $(xe_bin cnt c) | grep -c ' [TtBbDd] x264_8_s3' | sed 's/^/cnt tree s3 symbols: /'
    nm $(xe_bin off m) | grep -c ' [TtBbDd] x264_8_s3' | sed 's/^/off tree s3 symbols (0 expected): /'
}

xe_phase_cnt() {
    mkdir -p $W/out; local spec a v nr nb
    for spec in $CELLS; do xe_cell $spec
        [ -f $CL ] || { echo "$CN: SKIP (no $CL)"; continue; }
        v=""
        taskset -c $CC $(xe_bin off m) $CO --dump-yuv $W/out/rec_off.yuv -o $W/out/bs_off.264 $CL 2> $W/out/off_$CN.log || v="$v off:rc$?"
        taskset -c $CC $(xe_bin cnt c) $CO --dump-yuv $W/out/rec_cnt.yuv -o $W/out/bs_cnt.264 $CL 2> $W/out/cnt_$CN.log || v="$v cnt:rc$?"
        nr=$(md5sum $W/out/rec_off.yuv $W/out/rec_cnt.yuv | awk '{print $1}' | sort -u | wc -l)
        nb=$(md5sum $W/out/bs_off.264 $W/out/bs_cnt.264 | awk '{print $1}' | sort -u | wc -l)
        grep '^s3cnt' $W/out/cnt_$CN.log > $W/out/s3_$CN.txt
        [ "$nr $nb" = "1 1" ] && [ -z "$v" ] && grep -q '^s3cnt end' $W/out/s3_$CN.txt && v=PASS || v="FAIL$v (recon distinct $nr, bitstream distinct $nb)"
        echo "== $CN: off vs cnt $v; bitstream $(md5sum < $W/out/bs_off.264 | cut -c1-12) recon $(md5sum < $W/out/rec_off.yuv | cut -c1-12); $(grep -c . $W/out/s3_$CN.txt) counter lines"
        grep -E 'C1 summary|C2 P (8x8|16x8|8x16)|C2 P 16x16|C3 refine_bidir 16x16|C4 rd_cost_mb (intra|trd)|C4 summary|C5 (i16ac|luma4|chromaac|block|trellis)|C6 (final|frame_cost)' $W/out/s3_$CN.txt
        rm -f $W/out/rec_*.yuv $W/out/bs_*.264
    done
}
XE_PHASES="cbuild | cnt"
[ -n "${XE_TEST:-}" ] || xe_main "$@"
