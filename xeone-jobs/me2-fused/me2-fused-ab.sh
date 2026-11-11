#!/bin/bash
# Xeon E (E-2478, Intel AVX2) in-situ A/B, job K: wip/x264-me2-fused (tip 4c404747), two arms on the AVX2 entry
# me_search_fpel_avx2 (the avx512 commits 12d4c228 / 455e9d8d are rack01's).
# Copyright (C) 2026 Open Broadcast Systems Ltd
#
#   AB=k1 bash me2-fused-ab.sh build | live | md5 | time 9 | report; then the same with AB=k2
# AB:
#   k1  8x16 square refine in shared windows (MF_SQ8, 026f9c51): base = 71cb23ec (its parent; weighted refs in the
#       asm, inert in situ until the 4c404747 guard lift), arm = 026f9c51. (The package report named 42c3f783 as the
#       base: K1BASE=42c3f783 also takes 71cb23ec's frame growth into the arm.)
#       8x16 is searched only when p8x8 is analysed. LOWLAT and NORMAL use --partitions i8x8,i4x4: zero 8x16 searches,
#       so both production cells are null cells here. The normalp8 cells (NORMAL with x264's default
#       --partitions p8x8,b8x8,i8x8,i4x4) reach it. perf symbols cannot split 8x16 from 16x16 inside
#       me_search_fpel_avx2: the instructions:u delta of the normalp8 cells is the liveness witness.
#   k2  weighted refs at subme >= 3 to the fused entry (dispatch tip 4c404747): base = fca9575c (tip~1), arm = 4c404747.
#       Needs weightp content: there are no sgfades clips on this box, so fades-p / fades-i at 60 frames stand in.
#       NORMAL (weightp 2, subme 6) is live; LOWLAT (subme 2 < 3) is the null cell. Liveness: the arm's
#       x264_8_me_search_ref samples fall on fades, its me_search_fpel_avx2 samples rise.
set -u
JOB=me2-fused; AB=${AB:-k1}; BRANCHES=wip/x264-me2-fused
case $AB in
k1) BASE=${K1BASE:-71cb23ec}; ARM=026f9c51
    CELLS="tile-chaos-p:lowlat tile-chaos-p:normal field-frame-mix-i:lowlat field-frame-mix-i:normal
           tile-chaos-p:normalp8 field-frame-mix-i:normalp8"
    NULLCELLS="tile-chaos-p_lowlat tile-chaos-p_normal field-frame-mix-i_lowlat field-frame-mix-i_normal"
    MD5CELLS="ffm422-i:lowlat ffm422-i:normal ffm422-i:normalp8 fades-p:normalp8:60 fades-i:normalp8:60" ;;
k2) BASE=fca9575c; ARM=4c404747
    CELLS="tile-chaos-p:lowlat tile-chaos-p:normal field-frame-mix-i:lowlat field-frame-mix-i:normal
           fades-p:normal:60 fades-i:normal:60 fades-p:lowlat:60 fades-i:lowlat:60"
    NULLCELLS="tile-chaos-p_lowlat field-frame-mix-i_lowlat fades-p_lowlat_60 fades-i_lowlat_60"
    MD5CELLS="ffm422-i:lowlat ffm422-i:normal fades-p:normalp8:60 fades-i:normalp8:60" ;;
*) echo "unknown AB $AB"; exit 1 ;;
esac
LIVE_RE='me_search_ref|me_search_fpel|refine_subpel|satd_subpel_search|qpel_search|get_ref|mc_weight|sad_x[34]'
. "$(dirname "$0")/../lib.sh"
MODE_normalp8=${NORMAL/--partitions i8x8,i4x4/--partitions p8x8,b8x8,i8x8,i4x4}
xe_bench() { (cd $(xe_dir arm t) && taskset -c $CORE ./checkasm8 --bench=me_search_fpel 1001 | grep -E 'me_search_fpel|nop'); }
[ -n "${XE_TEST:-}" ] || xe_main "$@"
