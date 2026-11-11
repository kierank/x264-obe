#!/bin/bash
# Xeon E (E-2478, Intel AVX2) in-situ A/B, job O: wip/x264-me2-la2, the lookahead's intra and B frame cost loops
# in one asm call per slice (lowres_i_mbs / lowres_b_mbs avx2) and intra_satd_lowres with V/DC through the
# transform (intra_satd_lowres_tf avx2), all three dispatched at AVX2 by b81cae5e.
# Copyright (C) 2026 Open Broadcast Systems Ltd
#
#   bash la2-ab.sh build     # build window: 8 trees (base, base', arm, arm' x timing/md5 flavour), checkasm8 + 10
#   bash la2-ab.sh live      # perf samples: lowres_{i,b,p}_mbs, intra_satd_lowres(_tf), slicetype_mb_cost
#   bash la2-ab.sh md5       # gate, incl. 8-bit 4:2:2 interlaced and the 10-bit (LA8 lookahead) cells
#   bash la2-ab.sh time 9    # timing block
#   bash la2-ab.sh report
# AB=avx2 (only one here): base = 5db22450 (tip~2: every kernel assembled, nothing dispatched), arm = b81cae5e
#   (tip~1: avx2 dispatch). The tip 0877c420 only adds the avx512icl dispatch: on this AVX2-only cpu it runs the
#   same pointers as b81cae5e, so it is not an arm here (rack01 decides it).
# Builds are --bit-depth=all: 10-bit encodes run the lookahead on 8-bit copies (LA8, default on), and lowres8's
#   B path now goes through satd_bi / satd_bi4; the @10 cells check it (md5 only).
# Cells: normal (B frames: lowres_b_mbs + the searches through lowres_p_mbs), lowlat (no B frames: only the
#   intra estimate inside lowres_p_mbs, expected live through intra_satd_lowres_tf; no zero-call cell exists),
#   fades-p normal 60 frames (weightp engages: weights_analyse's intra pre-pass = lowres_i_mbs).
set -u
JOB=la2; AB=${AB:-avx2}; BRANCHES=wip/x264-me2-la2
case $AB in
avx2) BASE=5db22450; ARM=b81cae5e ;;
*) echo "unknown AB $AB"; exit 1 ;;
esac
BITDEPTH=all
CELLS="tile-chaos-p:lowlat tile-chaos-p:normal field-frame-mix-i:lowlat field-frame-mix-i:normal fades-p:normal:60"
MD5CELLS="ffm422-i:lowlat ffm422-i:normal fades-i:normal:60
          tile-chaos-p:normal@10 field-frame-mix-i:normal@10 tc422p10-p:normal@10 ffm422p10-i:normal@10 ffm422p10-i:lowlat@10"
LIVE_RE='lowres_[ibp]_mbs|intra_satd_lowres|slicetype_mb_cost|slicetype_slice_cost|me_search_ref|satd_bi'
. "$(dirname "$0")/../lib.sh"
xe_bench() { (cd $(xe_dir arm t) && taskset -c $CORE ./checkasm8 --bench=lowres 1001 | grep -E 'lowres_[ib]_mbs|intra_satd_lowres|nop'); }
[ -n "${XE_TEST:-}" ] || xe_main "$@"
