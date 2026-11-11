# wip/x264-10b-cabac notes (laptop agent, 2026-11-11)

Base origin/speed-next d625b235. 10-bit only; the 8-bit build is byte-identical
(cabac-a.o .text/.rodata/.data identical, the object differs only in nasm ..@
macro-local symbol names; ck3.sh compares every 8-bit library object).

## Commits (oldest first)
1. checkasm: x86 bitstream header; 10-bit levels past int16 (test only)
2. avx2 rd 4x4 (10-bit) port, not dispatched
3. avx2 8x8 rd (10-bit) port incl. RD8_LEVELS + sig pairs, not dispatched
4. avx2 4:2:2 dc writer (10-bit), not dispatched
5. avx512icl 8x8 rd2 (10-bit), not dispatched (mixed vs icl: rack01 decides)
6. avx2 rd 4x4 (10-bit): levels per level > 1 (RD_LEVELS; >= 2 level-1 coefs)
7. avx512icl rd2 4x4 (10-bit): levels per level > 1 (>= 1 level-1 coef), not dispatched
8. WIP notes/scripts (this directory; drop before merge)
9. dispatch avx2_bmi2 rd 4x4 / 8x8 rd / 422 dc writer at 10-bit (also changes
   AVX-512-without-ICL: rd 4x4 and 422 dc)
10. AVX-512 without ICL keeps avx2_bmi2 8x8 rd at 10-bit (own commit, droppable)
11. dispatch rd2 4x4 avx512icl at 10-bit (Zen 4/5 change, own commit, droppable)

Final 10-bit pointers (rd 4x4 / 8x8 rd / 422 dc writer):
- Intel AVX2, Zen 1-3: avx2_bmi2 / avx2_bmi2 / avx2_bmi2
- AVX-512 without ICL: avx2_bmi2 / avx2_bmi2 / avx2_bmi2
- Zen 4/5: rd2_avx512icl / avx512icl / avx512icl
- 422 dc rd: C everywhere (the icl one lost on Zen 4, 54f7ee3e; no avx2 one)

## Laptop (Zen 5, ticks/call, fresh blocks; driver drv.c)
rd4x4  ssse3/port/avx2 final/icl/icl rd2: dense 82/98/65/60/26, decay40 114/112/67/80/31,
       sparse 41/45/41/20/15, large 82/68/58/39/40
rd8x8  ssse3/avx2/avx512/icl/icl2: dense 330/106/328/272/90, decay40 173/92/170/142/81,
       sparse 97/78/93/47/59, large 184/154/183/129/144
422dc  C/avx2/icl: mid 127/52/52, large 356/173/173

## Scripts
- drv.c + build.sh: driver (C copied from encoder/cabac.c rd and writer); build.sh also
  checks 8-bit object identity, win64/x86_32 assembly (x86_32 fails on base too, line 1206).
- mut.sh + mutlist.txt: 8 mutations; 7 killed, the icl rd2 4x4 ">= 1" one is masked
  by the level-1 selector (exact either way).
- ck3.sh: checkasm8/10 seeds 1-5 per commit, EVEX scan, checkasm bench, 8-bit identity.
- ab-10b-cabac.sh: .44 (MODE=avx2 / a512) and rack01 (MODE=icl) in-situ A/B.

## Ideas not done
- 8-bit: the same RD_LEVELS 4x4 rework (avx2 and icl rd2) would likely win at 8-bit
  too; not done (8-bit had to stay byte-identical).
- 8-bit AVX-512-without-ICL 8x8: avx2_bmi2 beats avx512 at 10-bit in every class; the
  8-bit pointer is unchanged.
- 422 dc rd (C at both depths, 0.6 % from rd_cost_mb on NORMAL): an avx2 port of the
  icl 422 dc rd + RD_LEVELS-style levels.

## Verification (13:10-13:39Z, ck3.out)
- checkasm10 seeds 1-5 on every commit, checkasm8 seeds 1-5 on the tip, d57d0370 and
  873f5dea (pre-rewrite shas): 65/65 runs "All tests passed".
- 8-bit: all 55 objects' .text/.rodata/.data and libx264.a byte-identical, d625b235 vs tip.
- EVEX scan: 0 EVEX instructions outside avx512/icl functions (8 and 10-bit cabac-a.o).
- checkasm --bench (trained branches; T = (printed + 159/4)/10), rd 4x4 sparse/mid/dense/large:
  ssse3_lzcnt 14.9/20.9/43.2/25.3, avx2_bmi2 16.1/23.0/31.7/24.7, rd2 icl 21.1/11.9/14.6/17.2.
  On trained branches the per-coefficient loop is cheaper on sparse/mid; the fresh-block
  driver is the realistic view (avx2 sparse equal, mid -30 %).
