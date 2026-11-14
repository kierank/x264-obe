#!/bin/bash
# Xeon E (E-2478, Intel AVX2) in-situ A/B, job NRB: wip/x264-nw-nrbskip (tip cb5b86c2, on 4e292d6a).
#   phase 1 (fdb7f7b9): non-reference B frames store no fdec planes, mv / ref in the MB row ring
#   phase 2 (cb5b86c2): the thread's per-MB arrays in the MB row ring, every frame
# Correctness is proven on Core 3 (Job Y, script f43c8c51): 39/39 cells bitstream-identical, phase 1 on 100 % of
# non-ref-B MBs, plane bytes -47 %, mv/ref bytes -58..-65 %. This job is the Intel cycles verdict.
# Copyright (C) 2026 Open Broadcast Systems Ltd
#
#   AB=full bash nrbskip/nrbskip-ab.sh build | live | md5 | time 9 | report
# AB (default full):
#   full     base 4e292d6a, arm cb5b86c2 (both phases)
#   p1       base 4e292d6a, arm fdb7f7b9 (phase 1 only)
#   p2       base fdb7f7b9, arm cb5b86c2 (phase 2 over phase 1)
#   fulllay  as full, both trees -falign-functions=64 (code-placement control, diagnostic only)
#   p1lay    as p1, both trees -falign-functions=64
# NORMAL decides phase 1 (B frames). LOWLAT (zerolatency: no B frames) is phase 1's null, but phase 2 runs there,
# so for AB=full / p2 lowlat is a decision cell, and only for AB=p1 is it a null.
set -u
JOB=nrbskip; AB=${AB:-full}; BRANCHES=wip/x264-nw-nrbskip
case $AB in
full|fulllay) BASE=4e292d6a; ARM=cb5b86c2 ;;
p1|p1lay)     BASE=4e292d6a; ARM=fdb7f7b9 ;;
p2)           BASE=fdb7f7b9; ARM=cb5b86c2 ;;
*) echo "unknown AB $AB"; exit 1 ;;
esac
CELLS="tile-chaos-p:normal field-frame-mix-i:normal ffm422-i:normal tile-chaos-p:lowlat field-frame-mix-i:lowlat"
NULLCELLS=""; case $AB in p1|p1lay) NULLCELLS="tile-chaos-p_lowlat field-frame-mix-i_lowlat" ;; esac
MD5CELLS="ffm422-i:lowlat fades-p:normal:60 fades-i:normal:60"
LIVE_RE='macroblock_store|macroblock_cache_save|mbring|store_col|deblock'
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../lib.sh"
xe_cflags() { case $AB in fulllay|p1lay) echo "-falign-functions=64";; esac; }
[ -n "${XE_TEST:-}" ] || xe_main "$@"
