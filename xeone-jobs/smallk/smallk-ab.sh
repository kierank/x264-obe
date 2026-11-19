#!/bin/bash
# Xeon E (E-2478, Intel AVX2) in-situ A/B, job SK: the AVX2 small-kernel bundle (wip/x264-nw-smallk).
# base = speed-next b3490174, arm = 3e88a2f9: vsad_field (MBAFF field decision), plane_copy_interleave avx2,
# add8x8_idct_dc VEX, quant_4x4x4_scan_last (trellis 4x4x4 prep), var_uv (AQ ac_energy_mb chroma). 8-bit only.
# Gate: .44 G19. New struct fields shift x264_t by 8-byte steps, so a loss with fewer instructions gets AB=lay.
# Copyright (C) 2026 Open Broadcast Systems Ltd
#
#   AB=full | lay  bash smallk/smallk-ab.sh build | live | md5 | time 9 | report   (FRAMES=120)
set -u
JOB=smallk; AB=${AB:-full}; BRANCHES="speed-next wip/x264-nw-smallk"
BASE=b3490174; ARM=3e88a2f9
CELLS="field-frame-mix-i:normal field-frame-mix-i:lowlat tile-chaos-p:normal tile-chaos-p:lowlat ffm422long-i:normal"
NULLCELLS=""
MD5CELLS="fades-i:normal:60 credits-i:lowlat"
LIVE_RE='vsad|var_uv|var_|quant_4x4x4|scan|coeff_last|idct_dc|plane_copy_interleave|load_deinterleave'
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../lib.sh"
xe_cflags() { [ $AB = lay ] && echo "-falign-functions=64"; }
[ -n "${XE_TEST:-}" ] || xe_main "$@"
