#!/bin/bash
# Xeon E (E-2478, Intel AVX2) in-situ A/B, job CL2: wip/x264-nw-cacheload2 (tip 9557360a, base speed-next 6a312bce),
# x264_macroblock_cache_load_interlaced round 2. 1802da37 per-format / per-slice-type MBAFF loaders (CABAC 4:2:0 /
# 4:2:2 P / B, not called yet), 440f31b3 enable (28-insn dispatcher, old body as NOINLINE fallback), e051e2a5
# mbaff_load_{luma,chroma_8,chroma_16} avx2 (mbcache-a.asm, undispatched; new x264_t field mbaffpf at the end),
# 9557360a dispatch on every AVX2 CPU. Bit-exact. Laptop (Zen 5, driver walks): instructions per call 8-bit 4:2:0
# P -20 %, B -15 %; 4:2:2 P -25 %, B -19 %; 10-bit C loader only (P -12..-13 %, B -9..-10 %).
# Copyright (C) 2026 Open Broadcast Systems Ltd
#
#   FRAMES=120 AB=full bash cacheload2/cacheload2-ab.sh build | live | md5 | time 9 | report
# AB (default full):
#   full  base 6a312bce, arm 9557360a (the branch)
#   lay   full with -falign-functions=64 on every tree (the code-placement twin)
#   c     base 6a312bce, arm 440f31b3 (the C loaders alone)
#   k     base e051e2a5 (kernels assembled, undispatched: layout control), arm 9557360a (kernels on)
#   10    BITDEPTH=10, base 6a312bce, arm 9557360a: 10-bit 4:2:2 interlaced (C loader only)
# Null cell: tile-chaos-p LOWLAT (progressive: zero calls of the interlaced loader).
# Expected instructions:u per 120-frame 1080i run (8160 MBs x 120): LOWLAT (all P) about -250..-280 per MB;
# NORMAL about -215..-255 (I frames keep the old body); AB=c P -190..-220, B -155..-200; AB=k about -45 per MB.
set -u
JOB=cacheload2; AB=${AB:-full}; BRANCHES="speed-next wip/x264-nw-cacheload2"
BASE=6a312bce; ARM=9557360a
case $AB in
full|lay) ;;
c)  ARM=440f31b3 ;;
k)  BASE=e051e2a5 ;;
10) BITDEPTH=10 ;;
*) echo "unknown AB $AB"; exit 1 ;;
esac
if [ $AB = 10 ]; then
    CELLS="ffm422p10long-i:lowlat ffm422p10long-i:normal tc422p10-p:lowlat"
    NULLCELLS="tc422p10-p_lowlat"
    MD5CELLS="ffm422p10long-i:thrll ffm422p10long-i:thrnor"
else
    CELLS="field-frame-mix-i:lowlat field-frame-mix-i:normal ffm422long-i:lowlat ffm422long-i:normal credits-i:normal tile-chaos-p:lowlat"
    NULLCELLS="tile-chaos-p_lowlat"
    MD5CELLS="fades-i:normal:60 fades-i:lowlat:60 credits-i:lowlat field-frame-mix-i:thrll field-frame-mix-i:thrnor
              ffm422long-i:thrll ffm422long-i:thrnor field-frame-mix-i:slices4 field-frame-mix-i:slicemax
              field-frame-mix-i:nocabac field-frame-mix-i:tesa field-frame-mix-i:i444 field-frame-mix-i:noasm
              field-frame-mix-i:sse42"
fi
LIVE_RE='cache_load|cache_save|mbaff_load|mb_fref_load|mc_copy_w16|load_deinterleave|prefetch_fenc'
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../lib.sh"
# md5-only modes: threaded at CQP (threaded VBV is nondeterministic run to run), slice edges / reencode, and the
# old-body / no-kernel fallbacks the new dispatcher must keep exact.
cqp() { echo "$1" | sed -E 's/--bitrate [0-9]+ //; s/--vbv-maxrate [0-9]+ //; s/--vbv-bufsize [0-9]+ //; s/--nal-hrd fakevbr //; s/$/ --qp 23/'; }
MODE_thrll=$(cqp "${LOWLAT/--threads 1/--threads 4}")
MODE_thrnor=$(cqp "${NORMAL/--threads 1/--threads 4}")
MODE_slices4="$NORMAL --slices 4"
MODE_slicemax="$NORMAL --slice-max-size 1500"
MODE_nocabac="$NORMAL --no-cabac"
MODE_tesa="${NORMAL/--me hex/--me tesa}"
MODE_i444="${NORMAL/--profile high /} --output-csp i444"
MODE_noasm="$NORMAL --no-asm"
MODE_sse42="$NORMAL --asm SSE4.2"
xe_cflags() { [ $AB = lay ] && echo "-falign-functions=64"; }
xe_bench() { [ $BITDEPTH = 8 ] && (cd $(xe_dir arm t) && taskset -c $CORE ./checkasm8 --bench=mbaff 1001 | grep -E '^mbaff|^nop'); }
[ -n "${XE_TEST:-}" ] || xe_main "$@"
