# x264-obe unusual-instruction pass: sad (2026-10-20)

Package: common/x86/sad-a.asm (8-bit), common/x86/sad16-a.asm (10-bit), their dispatch in
common/pixel.c and declarations in common/x86/pixel.h, and the checkasm tests. Base:
origin/speed-next 0ac92fa9. Branch: wip/x264-weird-sad. All new kernels are x86_64 only,
use x86inc's default AVX-512 registers (m0-m15 = zmm16-31), and are dispatched in braced
`if( cpu&... ) { ... }` blocks.

## Commits

| commit | content |
|--------|---------|
| bbcdaca9 | checkasm: sad_x3/sad_x4 maxed-difference test (pbuf3 = ~pbuf4; there was none), intra sad_x3 at 7 aligned block positions per pattern (was 1) |
| d891e9a5 | 10-bit AVX-512 zmm `pixel_sad_16x16/16x8` (dispatched) and zmm `sad_x3/sad_x4(_min)_16x16/16x8` (assembled, not dispatched) |
| 50c0a8de | 8-bit AVX512ICL `intra_sad_x3_16x16` (dispatched) and `intra_sad_x3_8x8c` (assembled, not dispatched) |
| b79651dd | drops the vpermt2b left-column variant of the intra kernels (lost to movd + pinsrb) |
| 0a0443ea | 10-bit zmm `sad_x3/sad_x4(_min)_8x16/8x8` (assembled, not dispatched) |
| e93ebcc8 | 10-bit zmm `sad_avg2_16x16/16x8` (assembled, not dispatched) |

Zen 5 branches (wip plus one dispatch commit each; see "Placement"):

| branch | commit | dispatches |
|--------|--------|------------|
| zen5/x264-weird-sad-hbd-sadx-zmm | 63f2ee79 | 10-bit zmm sad_x3/sad_x4 and _min, 16x16/16x8/8x16/8x8 |
| zen5/x264-weird-sad-intra8c | f80bdadf | 8-bit AVX512ICL intra_sad_x3_8x8c |
| zen5/x264-weird-sad-hbd-avg2-zmm | e2cd4898 | 10-bit zmm sad_avg2 16x16/16x8 |

## Correctness

- Build: `--bit-depth=all` with nasm 3.01 and gcc 15.2 in WSL (`--extra-ldflags=-no-pie`,
  as speed-next doesn't link as PIE here). No new C warnings; the build's warnings are
  the same set as the base's.
- checkasm8 and checkasm10, seeds 1001, 2002 and 3003: all pass on wip, and on an
  "all-on" build with all three zen5 dispatch commits applied.
- Coverage added (bbcdaca9):
  - sad_x3/sad_x4 had no maxed-difference test. The new loop uses fenc = pbuf3+j and
    refs at pbuf4. A positive control fired with the random loop disabled: ref 4's
    accumulate in the avx2 10-bit sad_x4_16x16 broken -> `pixel sad_x4 : [FAILED]`.
  - intra sad_x3 ran one block per pattern. It now runs 7 positions, 16 pixels apart
    (aligned: the sse2 intra functions use mova), which gives other neighbours and DC
    roundings. The DC-rounding mutation below was also caught by the old single
    position (pattern 1/2), so the loop is extra margin rather than a fix.
- Mutation checks: one instruction (or one table byte) broken, rebuilt, checkasm run,
  then restored and passed again:

  | kernel | mutation | result |
  |--------|----------|--------|
  | 10-bit zmm sad | `psubw m1, [fenc]` -> `paddw` | `pixel sad : [FAILED]` |
  | 10-bit zmm sad | upper half loaded from row k instead of k+1 | `sad[0]: 86118 != 86272` |
  | 10-bit zmm sad | final half fold `paddw ym0, ym1` -> `ym0, ym0` | `pixel sad : [FAILED]` |
  | 10-bit zmm sad_x 16 wide | merge mask dropped from vbroadcasti64x4 | `sad_x3[0] ... [FAILED]` |
  | 10-bit zmm sad_x 16 wide | `pmaddwd m2, m6` removed in the tail | `sad_x3`, `sad_x3_min` FAILED |
  | 10-bit zmm sad_x 8 wide | lane 2 ref r3 -> r2 | `sad_x3[2] ... [FAILED]` |
  | 10-bit zmm sad_x 8 wide | lane 3 ref r4 -> r3 | `sad_x4[2] ... [FAILED]` |
  | 10-bit zmm sad_x 8 wide | x3 vpcompressd mask 0x0111 -> 0x1111 | passes: equivalent mutant (lane 3 is best + 64*sad, never below best) |
  | 10-bit zmm sad_avg2 | `pavgw` -> `por` | `pixel sad_avg2 : [FAILED]` |
  | 8-bit intra 16x16 | DC `pavgw` (rounding) -> `psrlw 1` | `intra_sad_x3_16x16: ... [FAILED]` |
  | 8-bit intra 16x16 | left row 4g+2 loaded from 4g+3 | `intra sad_x3 : [FAILED]` |
  | 8-bit intra 16x16 | V prediction loaded 1 byte late | `intra sad_x3 : [FAILED]` |
  | 8-bit intra (both) | pack shift `psllq 32` -> `16` | 16x16 and 8x8c FAILED |
  | 8-bit intra 8x8c | `isad8c_shift` dc3 2 -> 1 | `intra_sad_x3_8x8c: ... [FAILED]` |
  | 8-bit intra 8x8c | `isad8c_dcidx` byte 4 -> 0 | `intra_sad_x3_8x8c: ... [FAILED]` |
  | 8-bit intra 8x8c | vdbpsadbw imm 0 -> 0x1b | passes: equivalent mutant (the imm shuffles an all-zero source) |

- Encoder md5 identity, base 0ac92fa9 vs branch, both built with `-fno-fast-math
  -ffp-contract=off`; `--threads 1 --asm avx512icl`; stressgen 1920x1080 y4m (30 frames)
  piped to `--demuxer y4m`; CABAC only. There are 14 cells:
  {8-bit 4:2:0, 10-bit 4:2:2} x {lowlat pan-fast, normal tile-chaos, subme-1 cut-storm,
  subme-1 flash, normal comb 1080i tff, lowlat ticker 1080i tff, subme-1 field-split
  1080i tff}.
  - lowlat: `veryfast zerolatency --intra-refresh`, 20 Mb/s with a one-frame VBV.
  - normal: `medium`, 1 s VBV, `--weightp 2 --bframes 3`.
  - subme-1: `superfast zerolatency --intra-refresh`, one-frame VBV. This is the only
    setting that reaches intra_sad_x3, which speedcontrol presets 0-1 use.

  Results: wip, 14/14 identical; all-on (wip + the 3 zen5 dispatches), 14/14 identical.
- Reachability:
  - perf samples in these encodes hit every dispatched new kernel. In the all-on build
    they also hit the zen5 kernels (10-bit sad_x3/x4_min 16x16/16x8/8x16/8x8 zmm,
    sad_avg2_16x16/16x8 zmm, sad_16x16/16x8 zmm, 8-bit intra 8x8c/16x16).
  - Encoder positive control: a build with the zmm sad's upper row from row k and the
    intra 16x16 DC rounding broken changed the md5 of all 7 10-bit cells and all 3
    8-bit subme-1 cells. As expected, the 8-bit lowlat and normal cells (subme > 1, no
    intra sad) were unchanged.
- nasm 2.14.02 (`~/tools/nasm-2.14.02/nasm`, same flags as the build) assembles both
  changed files. objdump of the 2.14.02 and 3.01 objects is identical, so no new
  instruction needs a nasm newer than 2.14.02 (vdbpsadbw, vpermb, vpermw, vpermt2q,
  vpsrlvd, vpternlogq, vpcompressd, merge-masked vbroadcasti64x4, vshufi64x2,
  vinserti32x4, vpmovzxwd, vpdpwssd in the rejected VNNI variant).

## Laptop speed (HX 370, Zen 5 mobile with double-pumped zmm; indicative only)

Two harnesses linked against libx264.a, both reporting the median of 15-21 rounds of 200k
calls in TSC ticks, pinned to CPU 12 or 13. A is the avx2 path, B is the new kernel.
- "interleaved" (scratchpad sadtools/sadbench.c) calls through the pixf table, with
  scalar work between calls, like the ME's C code.
- "tight" (symbench*.c) is a bare loop of calls, so it measures vector throughput.

| function | interleaved B/A (cpu 12, 13) | tight B/A | decision |
|----------|------------------------------|-----------|----------|
| 10-bit sad_16x16 zmm | 0.89, 0.97 (earlier runs 0.83-0.94) | 1.07-1.15 | dispatched (mixed; rack01 decides) |
| 10-bit sad_16x8 zmm | 0.95, 0.91 (0.85-0.95) | 1.15-1.21 | dispatched (mixed; rack01 decides) |
| 10-bit sad_x3_16x16 / 16x8 zmm | 1.37 / 1.10, 1.41 / 1.53 | - | zen5 |
| 10-bit sad_x4_16x16 / 16x8 zmm | 1.42 / 1.24, 1.28 / 1.21 | - | zen5 |
| 10-bit sad_x3/x4_min 16x16, 16x8 zmm | 1.15-1.50 | - | zen5 |
| 10-bit sad_x3 8x16 / 8x8 zmm | 1.27 / 0.97, 1.56 / 1.20 | - | zen5 |
| 10-bit sad_x4 8x16 / 8x8 zmm | 1.23 / 1.26, 1.59 / 1.17 | - | zen5 |
| 10-bit sad_x3/x4_min 8x16, 8x8 zmm | 1.05-1.50 | - | zen5 |
| 10-bit sad_avg2_16x16 / 16x8 zmm | 0.99 / 1.00, 0.99 / 1.00 | 1.24-1.25 / 1.16-1.23 | zen5 |
| 10-bit sad_16x16 / 16x8 zmm VNNI (vpdpwssd, 2 acc) | - | 1.09-1.27 / 1.18-1.37 (plain zmm, same runs: 1.05-1.20 / 1.15-1.21) | rejected |
| 8-bit intra_sad_x3_16x16 icl | 0.77, 0.72 | 0.69-0.80 | dispatched |
| 8-bit intra_sad_x3_8x8c icl | 1.05, 1.03 | 1.07-1.10 | zen5 |
| 8-bit intra 16x16 / 8x8c, vpermt2b left | - | 0.72-0.82 / 1.12-1.15 (pinsrb: 0.69-0.80 / 1.07-1.10) | rejected (variant) |
| 10-bit intra C combos with avx2 sad (16x16 / 8x8c / 8x16c) | 1.23-1.26 / 0.75-1.10 / 0.92-0.93 | - | rejected |

Why the zmm sad_x family loses on double-pumped zmm: a reference row pair (16 wide) or a
four-reference row (8 wide) has to be merged from separate loads (one or three merge ops
per zmm), and every zmm op takes two 256-bit slots. Per row pair and ref, the 16-wide case
is 1 merge + 3 ops (8 slots) against avx2's 6. On a full-width part it would be 4 ops
against 6, and 8 wide x4 would be 6 ops a row against 8. The single sad needs one merge per
row pair, and its fenc pair is a memory operand, which is why it is close.

## Placement

- wip, dispatched: 10-bit zmm sad_16x16/16x8 (AVX512 block, falls back to avx2 when the
  first stride isn't FENC_STRIDE) and 8-bit AVX512ICL intra_sad_x3_16x16. The 8-bit one is
  an exception to the "no 8-bit AVX-512 pixel functions" note (c24c3625), stated in the
  comment there; 8-bit encodes already run AVX-512 cabac/dct, so it adds no new dirty-zmm
  state.
- zen5/ (assembled on wip, dispatched only on the branch): 10-bit zmm sad_x3/x4(_min) all
  four sizes, 10-bit zmm sad_avg2 16 wide, 8-bit intra_sad_x3_8x8c.
- Dropped (not on any branch): VNNI sad variant and the vpermt2b left-column variant;
  the avx2-sad 10-bit intra C combos.

## Function table

Production dispatch on Zen 4 is listed first. In 8-bit, the AVX512 pixel table is off
(c24c3625). "Undispatched avx512" means the upstream-derived kernels that c24c3625 took out
of dispatch; they were not re-measured here (rack01's ablation exists).

### 8-bit (sad-a.asm)

| function | current best level | unusual instructions considered | tried? | bit-exact? | laptop base -> new | decision | reason |
|----------|--------------------|---------------------------------|--------|-----------|--------------------|----------|--------|
| pixel_sad_16x16 / 16x8 (mmx2, sse2, sse3, sse2_aligned, avx2, avx512 zmm/ymm) | avx2 (sse2 if stride1 != 16) | zmm 4 rows, kmask, VNNI vpdpbusd | no | - | - | unchanged | psadbw is native and the avx2 version is two rows a ymm with the fenc pair as a memory operand. zmm versions exist but are undispatched (c24c3625). vpdpbusd can't form \|a-b\|. |
| pixel_sad_8x16 / 8x8 (mmx2, sse2, avx2, avx512 xmm) | avx2 (mmx2 if stride1 != 16) | masked broadcasts (in the avx512 version) | no | - | - | unchanged | the undispatched avx512 already uses merge-masked vpbroadcastq |
| pixel_sad_8x4 / 4x8 / 4x4 / 4x16 (mmx2, avx512 xmm) | mmx2 | masked loads for odd widths | no | - | - | unchanged | only p4x4/p8x4 partitions reach them, and speedcontrol never enables those. The avx512 version (merge-masked dword broadcasts) exists, undispatched. |
| pixel_sad_avg2_16x16/16x8/8x16/8x8 | avx2 | zmm (4 rows of both sources), vpternlog | no | - | - | unchanged | zmm needs 3 merges per source per 4 rows (6 merges + pavgb + psadbw), no fewer ops even at full width. pavgb is one op. |
| pixel_sad_x3/x4_16x16/16x8 (mmx2, sse2, sse3, ssse3, avx, avx2, avx512 zmm) | avx2 | vdbpsadbw, zmm, vpcompressd tail | considered | - | - | unchanged | refs are arbitrary pointers, so vdbpsadbw's shifted windows only help with an ME API change (refs at x-1/x/x+1). That's out of scope and on the R&D backlog. The zmm version with its vpcompressd tail exists, undispatched. |
| pixel_sad_x3/x4_8x16/8x8/8x4 (mmx2, sse2, ssse3, avx2 W8, avx512 ymm) | avx2 | masked broadcasts | no | - | - | unchanged | avx2 W8 is current, and the avx512 ymm version (merge-masked broadcasts) is undispatched |
| pixel_sad_x3/x4_4x8/4x4 (mmx2, avx512 ymm) | mmx2 | masked broadcasts | no | - | - | unchanged | unused in production (no p4x4) |
| pixel_sad_x3/x4_min_16x16/16x8/8x16/8x8 | avx2 | kmask argmin | no (done 2026-10-12) | - | - | unchanged | a kmask argmin was measured slower than pminsd on the packed (cost<<6)+idx (asm-avx512vl-kmask) |
| intra_sad_x3_16x16 (mmx2, sse2, ssse3, avx2, avx512icl new) | avx512icl (new) | vpshufb/vpermb H prediction, vpermt2b left gather, vpternlogq pack, vpgatherdd | yes | yes | 1.00 -> 0.69-0.80 | dispatched | 4 rows a zmm: 12 zmm psadbw replace 32 ymm/xmm psadbw and 16 vpbroadcastb. The three sums are packed into one qword (vpternlogq) and reduced once. vpgatherdd wasn't tried: Zen 4 gathers are microcoded and pinsrb already beat the vpermt2b gather. |
| intra_sad_x3_8x8c (mmx2, ssse3, avx2, avx512icl new) | avx2 | vdbpsadbw (4-pixel DC sums), vpermw, vpsrlvd, vpermb (DC/H predictions), vpermt2q, vpternlogq | yes | yes | 1.00 -> 1.03-1.10 | zen5 | 3 zmm psadbw replace 8 ymm psadbw, but the zmm permutes double-pump. Plausible on full width. |
| intra_sad_x3_8x8 (mmx2) | mmx2 | - | no | - | - | unchanged | unused when intra_sad_x9_8x8 is dispatched (ssse3+). The x9 kernels are in the satd package. |
| intra_sad_x3_4x4 (mmx2) | mmx2 | - | no | - | - | unchanged | unused when intra_sad_x9_4x4 is dispatched (ssse3+) |
| pixel_vsad (mmx2 x86_32, sse2) | sse2 | ymm row pairs | no | - | - | unchanged | each row is used twice (row y vs y+1), so ymm row pairs need a merge per row and cut no psadbw |
| pixel_sad_*_cache32/64 (mmx2, sse2, ssse3) and sad_x3/x4 cache variants | never on modern CPUs | - | no | - | - | unchanged | CACHELINE_32/64 are never set on SSE4.2+ CPUs, so these are dead code for OBE |

### 10-bit (sad16-a.asm)

| function | current best level | unusual instructions considered | tried? | bit-exact? | laptop base -> new | decision | reason |
|----------|--------------------|---------------------------------|--------|-----------|--------------------|----------|--------|
| pixel_sad_16x16 / 16x8 (mmx2, sse2, ssse3, aligned, avx2, avx512 zmm new) | avx512 zmm (new) | zmm row pairs with merge-masked vbroadcasti64x4, VNNI vpdpwssd, vpternlog abs | yes | yes | 0.85-0.97 interleaved, 1.07-1.21 tight | dispatched (rack01 decides) | the fenc pair is one 64-byte memory operand. VNNI (2 accumulators) is slower (latency, and it saves only the final pmaddwd since words never overflow here: at most 16*1023). A vpternlog abs is 3 ops against pabsw's 1. |
| pixel_sad_8x16 / 8x8 (avx2 xmm, sse2, ssse3, mmx2) | avx2 (xmm) | zmm (4 rows, 3 merges) | no | - | - | unchanged | a single sad has 1 ref, so a 4-row zmm needs 3 merges per 4 rows on top of 3 ops; worse than xmm with memory operands even at full width |
| pixel_sad_8x4 / 4x8 / 4x4 (ssse3, mmx2) | ssse3 (mmx regs) | masked loads | no | - | - | unchanged | only 10-bit i4x4 mbcmp at subme <= 1 (sad_4x4) reaches them. MMX-width is fine for 4x4. |
| pixel_sad_x3/x4_16x16 / 16x8 (avx2, avx512 zmm new) | avx2 | zmm row pairs, vshufi64x2 + vpcompressd tail, VNNI | yes | yes | 1.00 -> 1.10-1.53 | zen5 | merge per ref per row pair (see above) |
| pixel_sad_x3/x4_8x16 / 8x8 (avx2, avx512 zmm new) | avx2 | 4 refs in the 4 lanes (vinserti32x4), vpcompressd with a lane-3 zero mask for x3 | yes | yes | 1.00 -> 0.97-1.59 | zen5 | 3 inserts per row |
| pixel_sad_x3/x4_min (4 sizes, avx2, avx512 zmm new) | avx2 | same as above, plus the min tree | yes | yes | 1.00 -> 1.05-1.50 | zen5 | as above |
| pixel_sad_x3/x4_8x4 / 4x8 / 4x4 (ssse3, sse2, mmx2) | ssse3 | - | no | - | - | unchanged | unused in production |
| pixel_sad_avg2_16x16 / 16x8 (avx2, avx512 zmm new) | avx2 | zmm row pairs of both sources | yes | yes | 0.99-1.00 interleaved, 1.16-1.25 tight | zen5 | two merges per row pair |
| pixel_sad_avg2_8x16 / 8x8 (avx2 xmm) | avx2 | zmm | no | - | - | unchanged | 3 merges per source per 4 rows, worse than xmm memory operands even at full width |
| pixel_vsad (sse2, ssse3, xop, avx2) | avx2 | zmm, VNNI | no | - | - | unchanged | strided rows, each used twice, so zmm needs merges. Words never overflow (62*1023). VNNI only replaces HADDUW. |
| intra_sad_x3_4x4 (sse2, ssse3, avx) | avx | vdbpsadbw | no | - | - | unchanged | 10-bit has no psadbw/vdbpsadbw equivalent for words. 16 pixels a mode fit one xmm already. |
| intra_sad_x3_8x8 (sse2, ssse3, avx2) | avx2 | zmm (all 8 rows of a mode in 2 zmm) | no | - | - | unchanged | at 10 bit the sums need dwords (16*16*1023 > 65535), so the packed-qword trick of the 8-bit kernels doesn't apply. Small gain, subme <= 1 only. |
| intra_sad_x3_8x8c / 8x16c / 16x16 (C: predict + ssse3 sad) | C | asm port | partly | yes | avx2 sad: 16x16 1.23-1.26 | rejected (avx2 sad) | swapping the combos to the avx2 sads loses at 16x16: the 32-byte loads right after the xmm prediction stores fail store forwarding. A real asm port (no prediction stores) is the fix; 8x16c is the 10-bit 4:2:2 chroma case at subme <= 1. Not done (ordinary asm, overload presets only). |

## Unusual instructions summary

| extension / instruction | use found? | where / why not |
|-------------------------|-----------|-----------------|
| AVX512BW vdbpsadbw | yes | 8x8c DC: one instruction gives the four 4-pixel sums of top and left (src2 = zero). For ME offsets it needs an API change (refs at adjacent x offsets); R&D backlog. |
| VBMI vpermb | yes | 8x8c DC and H predictions from 4 dc bytes and 8 left bytes |
| VBMI vpermt2b | tried, rejected | left-column gather from zmm row-pair loads: split 64-byte loads, slower than movd + pinsrb in both intra kernels |
| AVX512BW vpermw, vpsrlvd | yes | 8x8c DC: { s0+s2, s1, s3, s1+s3 } and per-lane shifts (2,1,1,2) before pavgw |
| vpternlogq | yes | 3-way OR packing the three intra sums into one qword. As a 10-bit abs: no (3 ops against pabsw). |
| kmask: merge-masked broadcasts, kmovb/kmovw | yes | zmm row pairs (vbroadcasti64x4 {k1}), x3/x4 tails |
| vpcompressd (register form) | yes | x3/x4 zmm tails pick the lane sums (and zero lane 3 for x3). The register form only; a memory destination is microcoded on Zen 4. |
| VNNI vpdpwssd | tried, rejected | 10-bit sad: words never overflow here, so it saves only the final pmaddwd and adds a 4-5 cycle accumulate chain. 1.09-1.37 of avx2 even with 2 accumulators, slower than the plain zmm sad. |
| VNNI vpdpbusd | no | 8-bit SAD needs \|a-b\| first; psadbw already reduces |
| GFNI | no | no per-byte shifts or bit-matrix work in SAD |
| VBMI2 (vpcompressb/w, vpexpand, vpshld*) | no | no compaction or funnel shifts in SAD |
| BITALG / VPOPCNTDQ | no | no bit counting |
| IFMA | no | no 52-bit multiplies |
| CD (vpconflict, vplzcnt) | no | no index conflicts or leading-zero needs |
| BMI2 pdep/pext | no | no index building (the asm-hex-search line is closed) |
| vpgatherdd | considered | left column: Zen 4 gathers are microcoded, and pinsrb already won over the 2-op vpermt2b gather |
| VP2INTERSECT | no use | SAD has no index or value sets to intersect: every kernel is an elementwise abs-diff plus a reduction, with no set membership, no matching of sorted lists and no compare-all-pairs loop. Not prototyped. |

## Bugs in existing asm

None found. Checked: the word-accumulator bounds of every 10-bit kernel (all at most
16*1023 a lane, or 62*1023 for vsad); 8-bit vsad's paddw (at most 31*2040 a lane); the
fallback tail calls (SAD_W16_AVX512_START, SAD_W8_AVX2_START, the new 10-bit sad); the
x86_32 guards. Observations, not bugs:
- The 8-bit avx2 and avx512 sad_x3 tails store 16 bytes into `scores` (int[3] in the
  API). Every caller passes an array of 4 or more, as upstream.
- The 10-bit intra 8x8c/8x16c/16x16 are C combos that call the ssse3 sad after
  predicting into fdec (see the function table).

## For rack01 (Zen 4) after its rerun

1. Correctness: checkasm (both depths, 3 seeds) and the md5 matrix on the wip tip and on
   each zen5 tip.
2. In-situ A/B with a layout twin (dispatch moved to an unset flag):
   - 10-bit zmm sad_16x16/16x8, 10l and 10n, progressive and 1080i. The laptop is mixed:
     faster with scalar work between calls, slower in a tight loop.
   - 8-bit intra_sad_x3_16x16 avx512icl at subme 1 (speedcontrol presets 0-1, or
     `--subme 1`). Only overload presets run it.
3. zen5/ branches: none expected to win on Zen 4 (double-pumped like this laptop); park
   until a full-width Zen 5 server exists.

## Round 2 (2026-10-20): every rejected or undispatched row written and dispatched

Branch `wip/x264-weird2-sad`, base `wip/x264-weird-sa8d8` 67b4aff6. Kieran's rules:
"don't reject, send all to rack01", and "move to zen5 if rack01 is too slow". Every
kernel below is dispatched on this branch, one commit per kernel. rack01 decides. No
laptop timings were taken.

Laptop checks (the laptop was on battery for most of the round):
- **Drivers.** Each kernel was compared against the C reference in a standalone gcc
  driver: random, PIXEL_MAX vs 0 both ways, inverted-fenc and checkerboard maxima, and
  small spreads for DC rounding. The drivers live in
  `scratchpad/x264-weird2-sad-drv/*.c`.
  - Refs sit at arbitrary offsets and strides, and the last row is placed against a
    PROT_NONE guard page.
  - k1-k7 are clobbered with random values (kclob.asm) before every kernel call.
- **gdb ABI check.** `abichk.py` checks every kernel at its ret, with tail calls
  handled. It confirms that rbx, rbp and r12-r15 are preserved, that rsp is correct,
  and that bits 128-511 of zmm0-15 are zero. All pass. Positive controls fired on a
  `xor ebx,ebx` and on a VEX ymm1 write.
- **Mutation.** 123 mutants, re-run after the k-clobber was added: all killed. They
  include a "kmov -> nop" mask-setup removal in every kernel that uses a k-mask.
  Equivalent mutants (accumulator choice, fallback target, lane 3 of x3) are noted
  per row. A null mutant (no change) survives, as it should.
- **Full build and checkasm.** Once on AC power: `--bit-depth=all` build, then
  checkasm8 and checkasm10 at seeds 1001, 2002 and 3003. All pass. Positive control:
  10-bit intra 8x16c mask, VNNI sad_x pw_64 and 8-bit sad_avg2 pavgb broken together
  made `intra sad_x3`, `sad_x3_min`/`sad_x4_min` and `sad_avg2` FAIL. With them
  restored, everything passes.
- **nasm.** Every intermediate commit's asm assembles with nasm 3.01 and 2.14.02 to
  identical disassembly. Nothing needs a nasm newer than 2.14.02 (vpdpwssd EVEX,
  vpermi2b, vpermb, vpermw, valignq, vpmovqw, vpmovqd, vdbpsadbw, kmovw from memory,
  k-merged broadcasts). Every vpdpwssd has the EVEX prefix.

Coordinator lessons applied:
- No per-row-inserted or shifted zmm loads were added. Rows are packed by k-merged
  broadcasts (vpbroadcastq/d, vbroadcasti32x4/64x4), or the kernel stays at ymm.
- The round-1 vpermt2b left variant (zmm loads from fdec-1, always split) was rewritten
  with 64-byte-aligned loads only.
- Reduction tails, which feed mode decisions and ME branches, are kept short. Their op
  counts are listed below.
- vpdpwssd always uses two or more accumulators.
- New rodata goes at the end of the section with ALIGN, and generator variables are
  %undef'd.

### Round-2 rows

| function | depth | round-1 decision | round-2 action | commit | driver | nasm 2.14.02 |
|---|---|---|---|---|---|---|
| intra_sad_x3_16x16 | 10 | rejected (C combo; avx2-sad combo lost) | written: AVX512 zmm, predictions in registers (pshufb H, pavgw DC), tail SAD_X_HBD16_ZMM_END 17 ops / 10 deep | 9e1ccaaa | pass; 6 mutants killed | ok |
| intra_sad_x3_8x8c | 10 | rejected (C combo) | written: AVX512, fenc rows by k-merged vbroadcasti32x4 (16 B aligned, no splits), DC by shufps quad sums + zero-masked vpshufd + vpsrlvd/pavgw | e4fd6ef4 | pass; 11 mutants | ok |
| intra_sad_x3_8x16c | 10 | rejected (C combo; 4:2:2 chroma) | written: AVX512, eight DCs by two vpermd (one zero-masked) | 7ea69536 | pass; 10 mutants | ok |
| intra_sad_x3_8x8 | 10 | rejected ("small gain, subme <= 1") | written: AVX512, 4 rows a zmm, edge reversed by one pshufb | 89e81a16 | pass; 4 mutants | ok |
| intra_sad_x3_4x4 | 10 | rejected ("fits one xmm") | written: AVX512, k-merged vpbroadcastq fenc, { V \| H } by one vpermw, tail 9 ops / 8 deep | 9ccb1538 | pass; 9 mutants (lane-3 mask mutant equivalent) | ok |
| pixel_vsad | 10 | rejected ("needs merges") | written: AVX512 zmm row pairs (ymm + k-merged vbroadcasti64x4), valignq for the row below; words at most 31*1023 at height 32; tail 11 ops | 2f543a2e | pass, all even heights 2-32, max pattern; 5 mutants (paddw->paddsw equivalent: no overflow) | ok |
| pixel_vsad | 8 | rejected | written: AVX512ICL ymm (VL only), valignq + psadbw, tail 7 ops. Agent D has a separate pixel_vsad_valign_avx512icl; rack01 compares them | 333e42b4 | pass; 4 mutants | ok |
| pixel_sad_x3(_min) 16x16/16x8 | 10 | zmm (zen5; parked after rack01 -1.3..-2.0 %) | written: AVX512ICL ymm VNNI (x265 P5): vpdpwssd pw_1/pw_64, 2 accumulators per ref, refs as memory operands; tail 15 ops / 7 deep. Overrides the zmm slot | 664f44da | pass, every min winner; 13 mutants | ok |
| pixel_sad_x4(_min) 16x16/16x8 | 10 | as above | written, as above | 7569c8ae | pass | ok |
| pixel_sad_x3(_min) 8x16/8x8 | 10 | as above | written: x264 paired-ref layout (SAD_X3_HBD_Y) + vpdpwssd; tail 11 ops / 8 deep (x3 lane 3 >= 0 cannot win a min) | 3349ac2b | pass | ok |
| pixel_sad_x4(_min) 8x16/8x8 | 10 | as above | written: paired refs (SAD_X4_HBD_Y) + vpdpwssd; tail 9 ops / 6 deep | 65a3f574 | pass | ok |
| pixel_sad_x3/x4 8x4 | 10 | rejected ("unused in production") | written: the 8-wide VNNI kernel at height 4 | deabfcdd | pass | ok |
| pixel_sad_x3/x4 4x8, 4x4 | 10 | rejected | written: one ref a qword lane (movq + k-merged vpbroadcastq), vpdpwssd, tail 4 ops (vpmovqd) | e121509c, 10cfbb4f | pass; 5 mutants | ok |
| pixel_sad_16x16/16x8 VNNI | 10 | written, rejected (laptop) | recovered and rewritten: AVX512ICL zmm, row pairs by k-merged vbroadcasti64x4, vpdpwssd 2 accumulators; tail 10 ops. Overrides the round-1 zmm slot | 80538902 | pass; 5 mutants (accumulator and fallback mutants equivalent) | ok |
| pixel_sad_8x16/8x8/8x4 | 10 | rejected ("3 merges, worse") | written: AVX512 zmm, 4 rows from one load + 3 k-merged vbroadcasti32x4 (no load wider than a row); tail 10 ops | 3b202de5, 7052e1fd, a47f6786 | pass; 10 mutants | ok |
| pixel_sad_4x8/4x4 | 10 | rejected ("MMX width is fine") | written: AVX512 ymm, k-merged vpbroadcastq; tail 8 ops | 64e63acf, d6558686 | pass | ok |
| pixel_sad_avg2_8x16/8x8 | 10 | rejected | written: AVX512 zmm, both sources and fenc k-merged, pavgw; tail 10 ops | e9dcc969, 47335394 | pass; 4 mutants | ok |
| pixel_sad_avg2 16x16/16x8/8x16/8x8 | 8 | rejected ("no fewer ops") | written: AVX512ICL zmm, 4 rows a source by k-merged vbroadcasti32x4, psadbw against a 64 B fenc operand, 2 accumulators; 8 wide reads 8 bytes past each row like the avx2 kernel | c3e8f141, 625ce693, 3cf1824c, d899f9fa | pass (guard page 8 bytes after each row, as avx2 needs); 7 mutants | ok |
| intra_sad_x3_8x16c | 8 | not in the round-1 table (sse2 C combo) | written: AVX512ICL, as the 8x8c kernel (vdbpsadbw, vpermw+pmaddwd DC, vpermb) | df965c35 | pass; 8 mutants | ok |
| intra_sad_x3_16x16 / 8x8c, vpermt2b left | 8 | written, rejected (laptop; split loads) | rewritten split-free: only 64 B aligned fdec loads, vpermi2b/vpermb gathers with k-masks (16x16: two chains merged by vmovdqu8). fdec at 64n (luma, U) or 64n+16 (V) takes the fast path, any other alignment tail-calls the pinsrb kernel. 51e93209 macro-izes the round-1 bodies (objdump identical). Override the slots | 51e93209, 184dd1de, 446f2bfb | pass at aligned and unaligned fdec; 12 mutants | ok |
| intra_sad_x3_4x4 | 8 | unchanged ("unused when x9 is dispatched") | written: AVX512ICL. Reached: x9 is used only when predict_mode[8] >= 0 (analyse.c:969), so frame edges, lossless and --cpu-independent run x3. { V \| H \| DC } lanes, one psadbw, tail 2 ops | b286da56 | pass; 7 mutants | ok |
| intra_sad_x3_8x8 | 8 | unchanged ("unused when x9 is dispatched") | written: AVX512ICL, reached as above (analyse.c:851). vpermb H from the reversed edge, packed-qword tail | a7d93e7b | pass; 6 mutants | ok |
| pixel_sad 16x16/16x8/8x16/8x8/small | 8 | unchanged (upstream avx512 undispatched, c24c3625) | skipped: the AVX-512 expression exists (upstream zmm/ymm avx512); rack01 measured it slower in situ (c24c3625), and it is dispatched on zen5/avx512-8bit-pixel-retest. vpdpbusd cannot form \|a-b\|; psadbw already reduces | - | - | - |
| pixel_sad_x3/x4 (all sizes) | 8 | unchanged | skipped: as above (upstream avx512 on zen5/avx512-8bit-pixel-retest). vdbpsadbw needs refs at adjacent x offsets, which needs an ME API change (out of scope) | - | - | - |
| pixel_sad_x3/x4_min | 8 | unchanged (kmask argmin measured 2026-10-12) | skipped: the k-mask argmin is on zen5/asm-avx512vl-kmask (rack01-measured) | - | - | - |
| pixel_sad_*_cache32/64 | 8 | unchanged | skipped: CACHELINE_32/64 are never set on SSE4.2+ CPUs, so no AVX-512 CPU can select them | - | - | - |
| mmx2/sse2/ssse3/xop variants | 8, 10 | unchanged | skipped: superseded at dispatch on every AVX-512 CPU | - | - | - |

### Findings (round 2)

- No functional bug was found in the existing sad asm.
- 8-bit avx2 (and new zmm) sad_avg2 8x16/8x8 read 8 bytes past each reference row, as
  their comment says (planes' PADH). A guard-page driver segfaults without that slack.
  This is pre-existing and documented, not a bug.
- The round-1 8-bit intra_sad_x3_8x8c fenc 64-byte loads read up to 8 bytes past the
  V block's last row. They stay inside fenc_buf (48 rows). The round-2 10-bit chroma
  kernels use row loads and read nothing past the block.
- Review of the satd agent's skip reason: 8-bit intra_satd_x3_4x4 and
  intra_sa8d_x3_8x8 are reachable (frame edges, lossless, --cpu-independent), as their
  sad counterparts are. Passed on to it.
