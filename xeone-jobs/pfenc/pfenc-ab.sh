#!/bin/bash
# Xeon E (E-2478, Intel AVX2) in-situ A/B, job PF: what prefetch_fenc_422 buys at 10-bit 4:2:2.
# The speed-next b3490174 profile shows x264_10_prefetch_fenc_422_mmx2 at 2.23 % of 10-bit 4:2:2 1080i normal.
# At 10-bit a 64-byte line holds 2 MBs, so each call issues 8 luma + 8 chroma prefetcht0 (8-bit 4:2:0: 4 + 2).
# Hypothesis: the samples are fenc DRAM latency (fill-buffer waits) landing on the prefetches, not code cost.
# arm = the same sha with prefetch_fenc_422 left at the C init's prefetch_fenc_null (no prefetch).
# If arm == base in cycles, the prefetch is neutral; if arm is slower, it helps; if faster, it hurts.
# Copyright (C) 2026 Open Broadcast Systems Ltd
#
#   bash pfenc/pfenc-ab.sh build | live | md5 | time 9 | report      (FRAMES=120 for time)
set -u
JOB=pfenc; AB=${AB:-off}; BRANCHES="speed-next"
BASE=b3490174; ARM=b3490174
BITDEPTH=10
CELLS="ffm422p10long-i:normal ffm422p10long-i:lowlat tc422p10-p:normal"
NULLCELLS=""
MD5CELLS=""
LIVE_RE='prefetch_fenc|get_frame|macroblock_cache_load'
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../lib.sh"
xe_patch() { # tree flavour (in the tree): arm drops the 422 prefetch dispatch
    case $1 in arm*)
        grep -q '^    pf->prefetch_fenc_422 = x264_prefetch_fenc_422_mmx2;$' common/x86/mc-c.c || { echo "pfenc: no dispatch line"; return 1; }
        sed -i 's/^    pf->prefetch_fenc_422 = x264_prefetch_fenc_422_mmx2;$/    \/* pfenc arm: no 4:2:2 fenc prefetch *\//' common/x86/mc-c.c
        git diff --stat ;;
    esac
}
[ -n "${XE_TEST:-}" ] || xe_main "$@"
