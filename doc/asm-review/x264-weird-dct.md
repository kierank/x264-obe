# x264-obe unusual-instruction pass: dct (2026-10-20)

Copyright (C) 2026 Open Broadcast Systems Ltd

Package: common/x86/dct-a.asm, common/x86/dct-64.asm, their dispatch in common/dct.c,
declarations in common/x86/dct.h, and the dct/zigzag tests in tools/checkasm.c. Base:
origin/speed-next 0ac92fa9 (unchanged at the end of the pass). Branch: wip/x264-weird-dct.
All new kernels use x86inc's default AVX-512 registers, are dispatched in braced
`if( cpu&X264_CPU_AVX512ICL ) { ... }` blocks, and the ones that need more than 8 vector
registers are inside `%if ARCH_X86_64` / `#if ARCH_X86_64`.

## Commits

| commit | content |
|--------|---------|
| 901dc755 | 8-bit zmm add8x8_idct/add16x16_idct without vpgatherqq/vpscatterqq (assembled, not dispatched) |
| 82c61344 | checkasm: zigzag_sub_8x8 test (there was none); nz = 0, one-pixel, extreme cases for zigzag_sub_4x4; dc-only and extreme cases for zigzag_sub_4x4ac, and level[0] compared |
| 60c557af | 8-bit AVX512ICL zigzag_sub_4x4/4x4ac/8x8, frame and field (dispatched) |
| 86368b6f | AVX512ICL dct4x4dc/idct4x4dc, both depths (assembled, not dispatched) |
| d1f6a83d | AVX512ICL zigzag_scan_4x4_field, both depths, one permute + one store (dispatched) |
| fbbe094a | 10-bit zmm sub16x16_dct8 and add16x16_idct8 (dispatched) |
| 82715341 | 8-bit zmm add16x16_idct8 (dispatched) and sub16x16_dct8 (assembled, not dispatched) |
| 0e9b762d | 10-bit zmm add8x8_idct/add16x16_idct (assembled, not dispatched); x86_64 guards for both zmm add8x8_idct versions |
| (this doc) | doc/asm-review/x264-weird-dct.md |

Zen 5 branches (a wip commit plus one dispatch commit each):

| branch | commit | dispatches | laptop result |
|--------|--------|------------|---------------|
| zen5/x264-weird-dct-add-idct | ad632c1f | 8-bit zmm add8x8_idct/add16x16_idct (gather-free) | 1.2-1.27x slower than avx2 |
| zen5/x264-weird-dct-dc4x4 | 34744f3c | dct4x4dc/idct4x4dc, both depths | throughput better (8-bit), chained latency worse |
| zen5/x264-weird-dct-sub16x16-dct8 | 3176001d | 8-bit zmm sub16x16_dct8 | 2-10% slower than avx2 |
| zen5/x264-weird-dct-hbd-add-idct | 0d4c5d43 | 10-bit zmm add8x8_idct/add16x16_idct | 1.17-1.22x slower than avx2 |

## Correctness

- Build: `--bit-depth=all`, nasm 3.01, gcc 15.2, WSL (`--extra-ldflags=-no-pie`). No new
  warnings in dct files or checkasm (the remaining ones, nasm "implicit DEFAULT ABS" and
  "pp-macro-params-legacy" and gcc's aggressive-loop-optimizations in the intra pred test,
  are the same set as the base's).
- checkasm8 and checkasm10, seeds 1001, 2002, 3003: all pass on wip, on each zen5 branch,
  and on a local "all-on" tree with all four zen5 dispatches applied together.
- Coverage added (82c61344): zigzag_sub_8x8 was never tested (no asm existed). zigzag_sub_4x4
  only ran random blocks, where nz is always 1: it now runs dst == src (nz 0), dst == src
  but the last pixel, dst == src but a random pixel, src max/dst 0 and src 0/dst max.
  zigzag_sub_4x4ac adds "only the dc differs" (nz must stay 0) and src max/dst 0, and compares
  all 16 levels (every version writes level[0] = 0; the old test skipped it).
- Mutation checks (one instruction or table byte broken in a copy, checkasm must fail, then
  the original passes again). All failed as intended:
  - add8x8_idct 8-bit zmm: psraw 6 -> 5; one movhps row load -> wrong row.
  - zigzag_sub: 8x8 kortestd k0,k1 -> k0,k0 (caught by the new last-pixel case); 4x4ac mask
    0xfffe -> 0xffff (caught by the level[0] compare); 4x4 row copy %rep 4 -> 3; 8x8 store row
    7 -> 6; one byte each of zsub8_frame8, zsub8_field8, zsub4_field.
  - dct4x4dc/idct4x4dc: one byte of dc4x4_perm (all four fail); a butterfly mask (all four);
    8-bit idct k4 -> k3; the >>1 rounding shift at 8 and at 10 bit.
  - scan_4x4_field: one byte of scan4field_perm (both depths).
  - 10-bit sub16x16_dct8/add16x16_idct8: store offset 768 -> 512; fdec row r+8 -> r+9; lane
    exchange imm 0x80 -> 0; rounding added to row 1 instead of 0; one byte of the pack index.
  - 8-bit sub16x16_dct8/add16x16_idct8: one byte of dct8_zmm_pairs; store 384 -> 256; block 3
    load into lane 2; store lane 3 -> 2.
  - 10-bit add8x8_idct zmm: one byte of the row index; one lane-transpose immediate; one
    pixel row load.
  - Survivor, equivalent: 8-bit add16x16_idct8 paddsw -> paddw. The residual after >>6 is
    within +-512, so pixel + residual never leaves int16; every add_idct version uses paddsw
    for the same no-op reason.
- md5 identity, --threads 1 --asm avx512icl, base and branch both built with
  `-fno-fast-math -ffp-contract=off`, stressgen 1920x1080, CABAC. 13 cells, all MATCH on wip,
  on each zen5 branch and on the all-on tree:
  8-bit 4:2:0 lowlat (veryfast zerolatency intra-refresh, 1-frame VBV), normal (medium, 1 s
  VBV, weightp 2, 3 B-frames), i16x16-heavy normal (dark-gradient), MBAFF lowlat and normal
  (--tff, native interlaced input), lossless (--qp 0) progressive and MBAFF; 10-bit 4:2:2
  lowlat, normal, i16x16-heavy normal, MBAFF lowlat and normal, lossless MBAFF.
- The md5 cells were checked to reach the new code (break the kernel in the md5 build, the
  cell must change): zigzag_sub 8x8 frame/field and 4x4/4x4ac (lossless cells), scan_4x4_field
  8 and 10-bit (MBAFF cells), 10-bit sub16x16_dct8 (10-bit normal), and on the zen5 trees
  8-bit add8x8_idct (normal and i16x16 cells), dct4x4dc/idct4x4dc (i16x16 cells, both
  depths), 8-bit sub16x16_dct8 (normal) and 10-bit add8x8_idct (normal). All DIFF.
  add16x16_idct8 does NOT change any cell at either depth: it has no caller in encoder/
  (the encoder adds per non-zero 8x8 with add8x8_idct8). Its new versions are tested by
  checkasm only and speed nothing up in an encode.

## Speed (laptop: HX 370, zmm double-pumped like Zen 4; indicative only)

checkasm --bench cannot resolve these on this laptop: the TSC ticks at base clock and the
4-call batches of the small functions come out at or below the rdtsc overhead (0, -1, ...).
A separate harness (not committed; scratchpad dct-hb/bench.c) calls each function 2000
times per run through x264_dct_init/x264_zigzag_init with cpu masks avx2 / avx512 /
avx512icl, interleaves the three arms run by run, executes one zmm instruction first so
every arm sees the same dirty-zmm16-31 state, pins to CPU 6, and reports TSC ticks per call
(TSC ~2 GHz; core clock ~2.5x that), median of 41 runs, then the median of 9 processes. Two
modes: "independent" rotates over 16 buffer sets; "in place" reuses one, so calls that
read their own output (add_idct, dct4x4dc, dct2x4dc) form a store-to-load chain.

Comparisons are within one binary (avx512 arm = base dispatch, icl arm = new). Between
binaries the same unchanged function moved by up to +-30% (code placement), so cross-build
numbers are not used.

| function | depth | old best | indep old -> new | in place old -> new | placement |
|----------|-------|----------|------------------|---------------------|-----------|
| zigzag_sub_8x8 frame | 8 | C | 54.0 -> 6.8 | 53.6 -> 7.5 | dispatched |
| zigzag_sub_8x8 field | 8 | C | 54.0 -> 6.9 | 52.7 -> 7.5 | dispatched |
| zigzag_sub_4x4 frame/field | 8 | ssse3 | 4.6 -> 4.2 | 4.5 -> 4.2-4.3 | dispatched |
| zigzag_sub_4x4ac frame/field | 8 | ssse3 | 5.0 -> 5.1 | 4.9 -> 4.6 | dispatched (neutral) |
| zigzag_scan_4x4_field | 8 | avx512 | 2.77 -> 2.77 | 2.71 -> 2.71 | dispatched (neutral, one store) |
| zigzag_scan_4x4_field | 10 | avx512 | 3.62 -> 3.54 | 2.75 -> 2.75 | dispatched (neutral, one store) |
| sub16x16_dct8 | 10 | avx2 | 77.2 -> 62.6 | 82.9 -> 66.7 | dispatched |
| add16x16_idct8 | 10 | avx2 | 99.1 -> 89.6 | 93.0 -> 86.0 | dispatched (no encoder caller) |
| add16x16_idct8 | 8 | avx | 89.6 -> 57.2 | 85.5 -> 56.3 | dispatched (no encoder caller) |
| sub16x16_dct8 | 8 | avx2 | 62.8 -> 68.7 | 47.1 -> 51.7 | zen5 |
| add8x8_idct (gather-free zmm) | 8 | avx2 | 13.4 -> 16.9 | 12.9 -> 16.0 | zen5 |
| add16x16_idct (gather-free zmm) | 8 | avx2 | 39.1 -> 46.6 | 39.3 -> 47.3 | zen5 |
| add8x8_idct (zmm) | 10 | avx2 | 16.2 -> 19.0 | 15.4 -> 18.8 | zen5 |
| add16x16_idct (zmm) | 10 | avx2 | 61.7 -> 72.1 | 59.6 -> 70.6 | zen5 |
| dct4x4dc | 8 | mmx2 | 9.2 -> 6.9 | 17.4 -> 25.4 | zen5 |
| idct4x4dc | 8 | mmx | 7.2 -> 4.3 | 14.8 -> 18.2 | zen5 |
| dct4x4dc | 10 | avx | 5.9 -> 6.6 | 12.6 -> 21.1 | zen5 |
| idct4x4dc | 10 | avx | 3.8 -> 4.5 | 11.7 -> 19.2 | zen5 |

Second binary check of the dispatched wins (zen5 hbd-add-idct build, same arms): 8-bit
add16x16_idct8 76.3 -> 50.2, 10-bit sub16x16_dct8 70.1 -> 56.8, 10-bit add16x16_idct8 83.7
-> 77.4, zigzag_sub_8x8 47.8 -> 6.2, zigzag_sub_4x4 4.06 -> 3.7, 4x4ac 4.45 -> 4.5 (indep) /
4.2 (in place). The dc4x4 throughput numbers moved between builds (10-bit 10.2 -> 7.0 in an
earlier build, 5.9 -> 6.6 in the zen5 build); the in-place loss was stable.

checkasm --bench (5 runs, median, units as printed) for the larger kernels: 10-bit
sub16x16_dct8 avx2 635 -> icl 500; 10-bit add16x16_idct8 avx2 776 -> icl 718; 8-bit
add16x16_idct8 avx 1027 (sse2 801) -> icl 462.

## Per-function log

Columns: function | current best level (wip dispatch) | unusual instructions considered |
tried? | bit-exact? | laptop ticks base -> new (indep, within one binary) | decision | reason

| function | best level | considered | tried | bit-exact | base -> new | decision | reason |
|----------|-----------|------------|-------|-----------|-------------|----------|--------|
| dct4x4dc 8-bit | mmx2 | masked-subtract butterflies, vprold word swap, vpermd single-permute transpose, embedded broadcast | yes | yes | 9.2 -> 6.9 (in place 17.4 -> 25.4) | zen5 | one-register shuffle chain is longer than the 4-register mmx version; the encoder runs it in the i16x16 dc chain (dct -> quant -> dequant -> idct), so latency decides; rack01 in-situ A/B wanted |
| dct4x4dc 10-bit | avx | same, dwords | yes | yes | 5.9 -> 6.6 (12.6 -> 21.1) | zen5 | slower both ways on this laptop |
| idct4x4dc 8-bit | mmx | same in words, vpermw transpose | yes | yes | 7.2 -> 4.3 (14.8 -> 18.2) | zen5 | as dct4x4dc |
| idct4x4dc 10-bit | avx | same, dwords | yes | yes | 3.8 -> 4.5 (11.7 -> 19.2) | zen5 | slower |
| dct2x4dc 8-bit | mmx2 | vpermt2w gather of the 8 DCs from 4 zmm, vpcompressw, masked zero stores (vmovdqu16 {k}) | no | - | 4.6-6.1 (two builds) | rejected | 8 DCs are 32 bytes apart: 8 scalar pinsrw loads beat 4 zmm loads + 2 vpermt2w + merge on latency, and the 8 zeroing stores would become masked stores (measured 2.3x worse in add8x8_idct); the 2x4 butterfly is ~10 ops already |
| dct2x4dc 10-bit | avx (pinsrd) | vpgatherdd, masked broadcasts | no | - | 5.4 | rejected | DCs are 64 bytes apart (8 cache lines); gather is slow on Zen 4; pinsrd x8 is minimal |
| sub4x4_dct 8-bit | avx512 (xmm, masked broadcasts) | - | no | - | 6.4 (avx2-level ssse3 10.5) | keep | already AVX-512 with merge-masked broadcast loads |
| sub4x4_dct 10-bit | avx2 | - | no | - | 5.8 | keep | one 4x4 in a ymm; nothing to widen |
| sub8x8_dct 8-bit | avx512 (dispatched) | vpermb/vpermt2b zero-masked gather + zero-extend instead of vpermt2d + punpck | no | - | avx2 12.5, avx512 12.9 | keep | one vpermt2b{z} replaces one vpermt2d + one punpck but needs a table copy each; the same trick lost to punpck in add8x8_idct (1.35x vs 1.13x of avx2). Note: on this laptop the dispatched avx512 version is ~2.5% slower than avx2 (rack01 kept it as >= avx2 on Zen 4) |
| sub8x8_dct 10-bit | avx2 | zmm with two 8x8 per pass | no | - | 13.1 | idea | the AVX2 version already transforms all four blocks per ymm pass in words; only sub16x16 could pair two 8x8s; the zmm add idct analogue lost |
| sub16x16_dct 8-bit | avx512 | as sub8x8_dct | no | - | 42.4 | keep | as sub8x8_dct |
| sub16x16_dct 10-bit | avx2 | zmm, two 8x8 per pass | no | - | 49.4 | idea | as sub8x8_dct 10-bit |
| dct4x4x4_internal (avx512 helper) | avx512 | - | no | - | - | keep | helper of sub8x8/16x16_dct avx512 |
| sub8x8_dct_dc 8-bit | avx512 | VNNI vpdpbusd with +-1 weights | no | - | 7.0 | rejected | psadbw already sums 8 pixels per op; vpdpbusd fenc/fdec into one accumulator is a latency chain (x265 lesson) |
| sub8x8_dct_dc 10-bit | sse2 | VNNI vpdpwssd | no | - | 7.0 | rejected | paddw + one pmaddwd with the sign pattern is already minimal |
| sub8x16_dct_dc 8-bit | avx512 | as above | no | - | 11.6 | rejected | as above |
| sub8x16_dct_dc 10-bit | avx | VNNI; zmm with lanes = row groups | no | - | 14.0 | rejected | rows are 16 bytes at a 32-byte stride: zmm rows need 1 load + 3 inserts each, more load uops than the avx version's 32 loads (mova or paddw with a memory operand) |
| sub8x8_dct8 8-bit | avx2 | - | no | - | 27.6 | keep | single block; avx2 already pairs rows for 32-byte stores |
| sub8x8_dct8 10-bit | avx2 | - | no | - | 19.2 | keep | single block; a ymm is a whole dword row |
| sub16x16_dct8 8-bit | avx2 (wip) | zmm with the four blocks in the four lanes; vpermi2q/vpermt2q row-pair joins | yes | yes | 62.8 -> 68.7 | zen5 | 2-10% slower: the 8-bit loads widen in zmm (2 vpmovzxbw zmm + psubw per row) |
| sub16x16_dct8 10-bit | avx512icl (zmm) | same layout; word pass once for all four blocks | yes | yes | 77.2 -> 62.6 | dispatched | -19% (in place -20%) |
| add4x4_idct 8/10-bit | avx / avx | - | no | - | 7.5 / 17.0 | keep | single 4x4, latency-bound |
| add8x8_idct 8-bit | avx2 | gather-free zmm; vpermb zero-masked unpack; merge-masked row-pair loads/stores | yes | yes | 13.4 -> 16.9 | zen5 | punpck/movq-movhps version 1.13-1.27x of avx2; vpermb unpack 1.35x; masked row-pair stores 2.3x (masked stores dominate) |
| add16x16_idct 8-bit | avx2 | same, constants hoisted | yes | yes | 39.1 -> 46.6 | zen5 | as add8x8_idct |
| add8x8_idct 10-bit | avx2 | zmm, four blocks per pass, 4x4 lane transpose with vshufi32x4 | yes | yes | 16.2 -> 19.0 | zen5 | 8 lane shuffles + 4-lane inserts/extracts cost more than the second AVX2 pass on double-pumped zmm |
| add16x16_idct 10-bit | avx2 | same | yes | yes | 61.7 -> 72.1 | zen5 | as above |
| add8x8_idct8 8-bit | avx | ymm/zmm | no | - | 25.6 | idea | single block in 8 xmm rows; a wider register needs a second block (only add16x16_idct8, which has no caller). A plain AVX2 version is not obvious either |
| add8x8_idct8 10-bit | avx2 | - | no | - | 23.0 | keep | a ymm is a whole dword row |
| add16x16_idct8 8-bit | avx512icl (zmm) | four blocks in four lanes, vpermq row order | yes | yes | 89.6 -> 57.2 | dispatched | -36%, but no encoder caller |
| add16x16_idct8 10-bit | avx512icl (zmm) | two blocks per pass, masked vshufi32x4 lane exchange | yes | yes | 99.1 -> 89.6 | dispatched | -10%, but no encoder caller |
| add8x8_idct_dc 8/10-bit | ssse3 / avx | masked zmm loads/stores of row pairs | no | - | 6.6 / 30.7 | rejected | rows are 8 bytes (8-bit) at a 32-byte stride; masked stores measured 2.3x worse in add8x8_idct |
| add16x16_idct_dc 8/10-bit | avx2 / avx2 | same | no | - | 8.3 / 19.0 | rejected | as above; 16-byte rows at a 32/64-byte stride fill only half a zmm |
| zigzag_scan_4x4_frame 8/10-bit | avx512 (vpermw / vpermd) | - | no | - | 3.2 / 4.2 | keep | already one permute |
| zigzag_scan_4x4_field 8/10-bit | avx512icl | vpermw/vpermd from a 16-byte vpmovzx table | yes | yes | 2.77 -> 2.77 / 3.62 -> 3.54 | dispatched | neutral at the call-overhead floor; replaces a full store + overlapping patch store (pshuflw/pshufd), which a later full-width load cannot forward from |
| zigzag_scan_8x8_frame 8-bit | avx512 (vpermi2w + vpermt2w) | vpermb n/a (word elements) | no | - | 3.2 | keep | two permutes for 64 coefs is minimal |
| zigzag_scan_8x8_field 8-bit | avx512 (same) | same | no | - | 3.2 | keep | same |
| zigzag_scan_8x8_frame 10-bit | avx512 (vpermt2d network) | - | no | - | 6.0 | keep | each 16-coef output needs coefs from three of the four input registers; 7 permutes + 4 merges is near the minimum for 2-source permutes |
| zigzag_scan_8x8_field 10-bit | avx512 | - | no | - | 4.3 | keep | 4 vpermt2d |
| zigzag_sub_4x4 frame/field 8-bit | avx512icl | vpermb{z} gather + zero-extend, vptestmw + kortestw nz | yes | yes | 4.6 -> 4.2 | dispatched | lossless only. First version (zmm masked dst loads, vpermt2b) was 1.4-3x slower than ssse3; movd + pinsrd dst rows fixed it |
| zigzag_sub_4x4ac frame/field 8-bit | avx512icl | same, masked move to zero the dc | yes | yes | 5.0 -> 5.1 | dispatched | lossless only, neutral |
| zigzag_sub_8x8 frame/field 8-bit | avx512icl (new; was C) | vpermt2b src packing, vpermb{z} scan, vptestmw x2 + kortestd | yes | yes | 54 -> 6.8 | dispatched | lossless only; 8x |
| zigzag_sub_* 10-bit | C | vpermw{z} / vpermt2w to dwords | no | - | 16 / 35-46 | not done | lossless 10-bit is not used in production |
| zigzag_interleave_8x8_cavlc | avx512 | - | no | - | 3.2 / 4.6 | log only | CAVLC is not used in production |

## Unusual instructions: where they found a use

- VBMI vpermb with a zero mask: gather in scan order and zero-extend bytes to words in one
  instruction (zigzag_sub). As an unpack for add8x8_idct it lost to punpcklbw/punpckhbw.
- VBMI vpermt2b: packs the 8 src rows of zigzag_sub_8x8 (128 bytes -> 64) in one op.
- AVX512BW masks: merge-masked subtract for butterflies (dct4x4dc/idct4x4dc), zero-masked
  vpermb, vptestmw + kortest for nz, masked move to clear the dc (4x4ac), dword-masked
  vshufi32x4 for a 128-bit lane exchange per 256-bit half (10-bit add16x16_idct8).
- vpermw/vpermd as a single-permute transpose: dct4x4dc/idct4x4dc (throughput up, latency
  down - consistent with the "vpermw transposes lose to punpck" lesson when latency-bound) and
  zigzag_scan_4x4_field.
- vprold 16 as a word swap; embedded broadcast {1to16} for the rounding constant.
- vpermi2q/vpermt2q, vpermq with an index: row-pair joins and row order (dct8 zmm kernels).
- Masked loads/stores: tried twice, lost both times (add8x8_idct row pairs 2.3x, zigzag_sub_4x4
  dst rows 1.4-3x). Not used in any kept kernel.

## Unusual instructions with no use here, and why

- GFNI (vgf2p8affineqb etc.): the transforms are 16/32-bit add/sub/shift butterflies; there
  are no per-byte shifts, bit reversals or bit-matrix steps.
- VBMI2 (vpcompress/vpexpand, vpshld/vpshrd): nothing is compacted (the scans are fixed
  permutations); considered vpcompressw for the dct2x4dc DC gather (no better than vpermt2w,
  and both lose to scalar loads). The 17-bit (a+b+1)>>1 of 8-bit dct4x4dc went to a dword pass,
  so no funnel shift was needed.
- vpmultishiftqb: no bit fields.
- BITALG / VPOPCNTDQ: no bit counting; nz flags are k-mask tests.
- VNNI (vpdpbusd/vpdpwssd): the DC sums already take one op per 8 pixels (psadbw, or paddw +
  pmaddwd); a dot-product accumulation would be a latency chain.
- IFMA: no 52-bit multiplies.
- CD (vpconflict, vplzcnt): no conflicts or leading-zero counts.
- BMI2 pdep/pext: no index building; nz masks stay in k registers.
- vpternlog: the nz OR is two vptestm + kortest; the butterflies need add/sub, not logic.

## VP2INTERSECT

No use found. Nothing in the package intersects two sets of indices or values: the
transforms are fixed butterflies, the scans fixed permutations (one table permute each),
and the nz/dc paths are k-mask tests. Not prototyped.

## Bugs found in existing asm

None. Coverage gaps (fixed in 82c61344, not asm bugs): zigzag_sub_8x8 untested; zigzag_sub_4x4
never tested nz = 0; zigzag_sub_4x4ac never compared level[0]. Observations, not bugs:
- add16x16_idct8 (both depths) has no caller in encoder/.
- 8-bit avx512 sub8x8_dct (dispatched) is ~2.5% slower than avx2 on this laptop.
- The avx512 zigzag_scan_4x4_field (both depths) wrote a full store plus an overlapping patch
  store; replaced by one store at avx512icl.

## Assembler

Every changed file (dct-a.asm, dct-64.asm) assembles with ~/tools/nasm-2.14.02 at both
depths with the build's flags (-f elf64 -DSTACK_ALIGNMENT=64 -DARCH_X86_64=1, BIT_DEPTH and
private_prefix per depth), on wip and on the zen5 trees. No instruction used here needs a
newer nasm (vpermb/vpermt2b/vpermi2q/vpermt2q/vshufi32x4/vinserti32x4/64x4/vextracti32x4/
64x4/vpmovzx*/vpmovdw/vprold/kortest*/kadd*/vptestmw/embedded broadcast all assemble).

## Placement and what needs rack01

- Dispatched on wip: zigzag_sub (lossless only), zigzag_scan_4x4_field (interlaced, neutral),
  10-bit sub16x16_dct8 (the one production-path speed change: inter 8x8 transform and
  analyse.c's fenc_dct8), add16x16_idct8 both depths (no caller).
- rack01 (Zen 4): checkasm --bench of every new kernel, and an in-situ A/B of wip vs
  speed-next on 10-bit 4:2:2 normal/lowlat (sub16x16_dct8) and MBAFF (scan_4x4_field); the
  expected effect is small.
- rack01 in-situ: zen5/x264-weird-dct-dc4x4 on i16x16-heavy content (dark-gradient, flat
  graphics), since throughput and chained latency disagree on the laptop.
- Zen 5 server (when one exists): all four zen5 branches.
- Decide whether to keep add16x16_idct8 kernels that nothing calls.
- Ideas not done (ordinary AVX-512): 10-bit sub16x16_dct with two 8x8 per zmm pass; an AVX2
  or zmm 8-bit add8x8_idct8; a fused U+V chroma DC kernel for 4:2:2 (the fenc/fdec chroma
  planes sit side by side, so a zmm row load covers both planes; needs a call-site change in
  macroblock.c, out of scope here; see also zen5/asm-chroma422-dc-chain).
