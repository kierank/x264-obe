#!/bin/bash
# Xeon E (E-2478, Intel AVX2) in-situ A/B, job HP10: R's hpel / pad passes at 10-bit (wip/x264-nw-10b-hpelpad).
# base = speed-next b3490174, arm = 5f6c927c (10-bit hpel_filter copy / copy_vc / dual / _pad, lowres pad,
# expand_border_sides at AVX2). Gate: .44 G18. 10-bit 4:2:2 interlaced decides; 10-bit progressive gets only the
# frame-pass pads (a smaller effect, or overhead from the pad stores).
# Copyright (C) 2026 Open Broadcast Systems Ltd
#
#   AB=full | lay  bash hp10/hp10-ab.sh build | live | md5 | time 9 | report   (FRAMES=120)
set -u
JOB=hp10; AB=${AB:-full}; BRANCHES="speed-next wip/x264-nw-10b-hpelpad"
BASE=b3490174; ARM=5f6c927c
BITDEPTH=10
CELLS="ffm422p10long-i:normal ffm422p10long-i:lowlat tc422p10-p:normal tc422p10-p:lowlat"
NULLCELLS=""
MD5CELLS=""
LIVE_RE='hpel_filter|frame_init_lowres|expand_border|memcpy|memset'
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../lib.sh"
xe_cflags() { [ $AB = lay ] && echo "-falign-functions=64"; }
[ -n "${XE_TEST:-}" ] || xe_main "$@"
