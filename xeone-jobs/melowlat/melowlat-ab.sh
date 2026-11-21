#!/bin/bash
# Xeon E (E-2478, Intel AVX2) in-situ A/B, job MLL: wip/x264-nw-melowlat (round 4 A), lowlat ME.
#   0b33bfc9 step 1 ME2: me_search_fpel_qt_avx2, the 8x8 / 16x8 / 8x16 searches on the 16x16's quadrant sads
#   f4efd189 step 2a ME3: the analyse_p asm calls me_search_fpel itself (no C x264_me_search_ref per search)
#   770257f1 step 2b: refine_qpel at hpel 0 calls mbcmp_qpel_search directly (lowlat and normal B)
#   ac46d9f1 step 3 ME1: refine_qpel skips where the search's qpel stage stopped at that mv (normal B / subme 4-5)
# Bit-exact: recon identical across all arms, every mode.
# Copyright (C) 2026 Open Broadcast Systems Ltd
#
#   FRAMES=120 AB=s1 | s2 | s3 | tip | s1lay | s2lay | s3lay | tiplay | 10 | 10lay  bash melowlat/melowlat-ab.sh build | live | md5 | time 9 | report
# AB:
#   s1   base 322af72b (speed-next), arm 0b33bfc9          s1lay  as s1, both sides -falign-functions=64
#   s2   base 0b33bfc9,              arm 770257f1          s2lay  ...
#   s3   base 770257f1,              arm ac46d9f1          s3lay  ...
#   tip  base 322af72b,              arm ac46d9f1          tiplay ...
#   10   BITDEPTH=10 4:2:2, base 322af72b, arm ac46d9f1 (steps 2 and 3; step 1 is 8-bit only)   10lay ...
# Null cells: s1 normal (no qt entry; only x264_me_search_ref's b_me_qtab test); s3 lowlat (no qpel steps in
# the lowlat search: no record; refine +9 insns, search +3).
# Laptop driver (instructions per lowlat P mb, analyse_p16x16 + analyse_p_sub16x16 incl. their searches, real
# frames): step 1 -21..-239, step 2 a further -600..-900 (direct -715..-796 alone); refine_qpel -59 a call.
# Step 3 (subme 5 searches): refine_qpel 858..869 -> 115..459 per call.
set -u
JOB=melowlat; AB=${AB:-tip}; BRANCHES="speed-next wip/x264-nw-melowlat"
case $AB in
s1|s1lay)   BASE=322af72b; ARM=0b33bfc9 ;;
s2|s2lay)   BASE=0b33bfc9; ARM=770257f1 ;;
s3|s3lay)   BASE=770257f1; ARM=ac46d9f1 ;;
tip|tiplay) BASE=322af72b; ARM=ac46d9f1 ;;
10|10lay)   BASE=322af72b; ARM=ac46d9f1; BITDEPTH=10 ;;
*) echo "unknown AB $AB"; exit 1 ;;
esac
if [ "${BITDEPTH:-8}" = 10 ]; then
    CELLS="ffm422p10long-i:lowlat ffm422p10long-i:normal tc422p10-p:lowlat"
    NULLCELLS=""
    MD5CELLS="ffm422p10long-i:thrll ffm422p10long-i:thrnor ffm422p10long-i:llref2 fades-i:fadesll:60 fades-i:normal:60"
else
    CELLS="field-frame-mix-i:lowlat tile-chaos-p:lowlat credits-i:lowlat ffm422long-i:lowlat
           field-frame-mix-i:normal tile-chaos-p:normal"
    case $AB in
    s1|s1lay) NULLCELLS="field-frame-mix-i_normal tile-chaos-p_normal" ;;
    s3|s3lay) NULLCELLS="field-frame-mix-i_lowlat tile-chaos-p_lowlat credits-i_lowlat ffm422long-i_lowlat" ;;
    *)        NULLCELLS="" ;;
    esac
    MD5CELLS="fades-i:lowlat:60 fades-i:normal:60 field-frame-mix-i:thrll field-frame-mix-i:thrnor tile-chaos-p:thrll
              ffm422long-i:thrll ffm422long-i:thrnor field-frame-mix-i:llref2 tile-chaos-p:llref2 field-frame-mix-i:llsub1
              tile-chaos-p:llp4x4 field-frame-mix-i:lldia field-frame-mix-i:llslices4 tile-chaos-p:normal5 field-frame-mix-i:normal4
              tile-chaos-p:normal7 field-frame-mix-i:normalcme tile-chaos-p:normalwp2 field-frame-mix-i:llnoasm
              field-frame-mix-i:llsse42 tile-chaos-p:normalnoasm"
fi
LIVE_RE='me_search_fpel|me_search_ref|refine_qpel|refine_fpel|qpel_search|subpel_search|analyse_p|refine_subpel'
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../lib.sh"
# md5-only modes: threaded at CQP (threaded VBV is nondeterministic run to run), and every fallback or edge path
cqp() { echo "$1" | sed -E 's/--bitrate [0-9]+ //; s/--vbv-maxrate [0-9]+ //; s/--vbv-bufsize [0-9]+ //; s/--nal-hrd fakevbr //; s/$/ --qp 23/'; }
MODE_thrll=$(cqp "${LOWLAT/--threads 1/--threads 4}")
MODE_thrnor=$(cqp "${NORMAL/--threads 1/--threads 4}")
MODE_llref2="$LOWLAT --ref 2"                           # per-ref ME_QTAB tags and records, halfpel_thresh on the direct 16x16 call
MODE_fadesll="$LOWLAT"                                   # 10-bit weighted lowlat (direct call's weighted ref: qfenc NULL, refine_fpel)
MODE_llsub1="$LOWLAT --subme 1"                          # qt entry without REFINE; no direct call (subme != 2)
MODE_llp4x4="$LOWLAT --partitions p8x8,p4x4,b8x8,i8x8,i4x4"  # PSUB8x8: the C sub16x16 path, no ME_QTAB, direct 16x16 only
MODE_lldia="${LOWLAT} --me dia"                          # no me_search_fpel: neither path
MODE_llslices4="$LOWLAT --slices 4"
MODE_normal5=${NORMAL/--subme 6/--subme 5}               # P refine_qpel with records (preset 3)
MODE_normal4=${NORMAL/--subme 6/--subme 4}               # B refine qpel 2, search qpel 1
MODE_normal7=${NORMAL/--subme 6/--subme 7}
MODE_normalcme=${NORMAL/--no-chroma-me/}                 # chroma ME: no record (C refine path)
MODE_normalwp2="$NORMAL --weightp 2"                     # blind dupes: refine_qpel_refdupe clears the record
MODE_llnoasm="$LOWLAT --no-asm"
MODE_llsse42="$LOWLAT --asm SSE4.2"
MODE_normalnoasm="$NORMAL --no-asm"
xe_cflags() { case $AB in *lay) echo "-falign-functions=64" ;; esac; }
xe_bench() { # per call: T = (printed + nop/4) / 10
    [ $BITDEPTH = 8 ] || return 0
    for t in base arm; do (cd $(xe_dir $t t) && taskset -c $CORE ./checkasm8 --bench=satd_qpel_search_16x16 1001 | grep -E "nop:|qpel_search_16x16" | sed "s/^/$t /"); done
}
[ -n "${XE_TEST:-}" ] || xe_main "$@"
