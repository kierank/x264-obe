<!-- Copyright (C) 2026 Open Broadcast Systems Ltd -->
# x264-obe unusual-instruction pass: quant package

Package: `common/x86/quant-a.asm` (quant, dequant, idct_dequant_2x4, optimize_chroma,
denoise_dct, decimate_score, coeff_last, coeff_level_run, quant_4x4x4_scan), dispatch in
`common/quant.c` and `common/dct.c` (quant_4x4x4_scan), tests in `tools/checkasm.c`.
The CABAC trellis functions set up in `quant.c` belong to the cabac package.

Base: origin/speed-next 0ac92fa9. Branch: `wip/x264-weird-quant`. All new kernels are x86-64
only, at `avx512icl`.

## Method

- checkasm8/10, seeds 1001 2002 3003, plus new coverage (below).
- Mutation check of every new kernel and of the decimate_score15 fix on a tree with every new
  kernel dispatched (`zen5/` dispatches included): one instruction changed, checkasm must fail,
  then restored and passing.
- Encoder md5 identity at `--threads 1 --asm avx512icl`, base vs branch, both built with
  `-fno-fast-math -ffp-contract=off`.
- Speed: a replay harness (throwaway, not committed) calls base and new kernels on inputs
  dumped from real encodes of stressgen content (test-clock, grain, lowlight, tile-chaos; 8-bit
  4:2:0 veryfast-zerolatency-PIR and medium; 10-bit 4:2:2 progressive and native 1080i).
  Two modes: throughput (independent calls) and latency (each call's input address depends on
  the previous result). TSC ticks per call, median of 9 interleaved repetitions per run, then
  the median over RUNS runs on CPUs 4 and 5. The laptop (Ryzen AI 9 HX 370, split zmm) moves by
  10-30% between runs; only consistent differences are used for decisions, and these numbers are
  indicative only. `checkasm --bench` per-call numbers for most of these functions are a few
  units after the nop subtraction and are not used; only the scan (enough work per call) is
  quoted from it.

## Correctness

- checkasm8 and checkasm10 (`--bit-depth=all`, nasm 3.01), seeds 1001 2002 3003: all pass on
  the branch and on a tree with the `zen5/` dispatches added. The replay harness also compared
  every new kernel with the base kernel (and C for the scan) on 4096-8192 dumped records per
  kernel: 0 mismatches.
- Mutations (one instruction each, on the tree with every new kernel dispatched): 43 in a
  first pass and 6 in a second, each killed at the depth it touches after the coverage fixes
  (checkasm8/10 seed 1001), and both depths passing again when restored. Covered: every
  scan step (quant sign, |level| OR, ac masks, zigzag, block flags, store mask and shift,
  dequant shifts and rounding, dmf gather, flat test, score mask and sentinels), quant_8x8,
  quant_4x4x4 (both depths), quant_4x4_dc, denoise (clamp, sign, sum), decimate (each sentinel
  and shift, mask merge, the DC fix in all three variants) and level_run (reverse, compress
  mask, last).
  Equivalent mutants found and explained: `levelrun_rev_avx512+22` for 8-bit level_run4 (lane
  0 is then a zero lane, same output; `+26` is killed); `shlx -> shrx` in the 8-bit scan's
  flat-dmf test (sends every block to the exact rounding path; removing the branch instead,
  which forces the shift-only path, is killed); dropping the k mask in level_run15 (the coef
  before the block compresses to just after the levels, which the contract leaves free: the
  mask was removed in 340750cf). Survivors that showed coverage gaps, then killed: quant_8x8
  nonzero flag from the last vector only, decimate_score64 run<24 sentinel at 8-bit.
- md5 identity at `--threads 1 --asm avx512icl`, base 0ac92fa9 vs branch 340750cf, both
  `-fno-fast-math -ffp-contract=off`, 15 cells, all MATCH, and the same 15 cells MATCH for the
  tree with the `zen5/` dispatches: stressgen test-clock and grain, 1080p 8-bit 4:2:0 lowlat
  (veryfast zerolatency, intra refresh, 20 Mb/s one-frame VBV) and normal (medium, weightp 2,
  3 B-frames, 1 s VBV), 10-bit 4:2:2 progressive and native 1080i tff in both modes, plus
  8-bit `--nr 500` lowlat (grain) and normal (lowlight), and 8-bit 1080i field-frame-mix
  normal. CABAC only, so coeff_level_run is covered by checkasm and the replay alone.

### Laptop replay bench (RUNS = 6; TSC ticks per call; thr = throughput, lat = dependent chain)

| kernel | depth | base | thr base -> new | lat base -> new |
|---|---|---|---|---|
| quant_4x4x4_scan_frame | 8 | avx2 | 21.28 -> 17.67 (-17%) | 28.69 -> 19.21 (-33%) |
| quant_4x4x4_scan_frame_ac | 8 | avx2 | 22.49 -> 19.82 (-12%) | 37.94 -> 25.63 (-32%) |
| quant_4x4x4_scan_frame | 10 | avx2 | 29.76 -> 25.36 (-15%) | 33.59 -> 21.07 (-37%) |
| quant_4x4x4_scan_field | 10 | avx2 | 32.69 -> 29.53 (-10%) | 39.64 -> 33.67 (-15%) |
| quant_4x4x4_scan_frame_ac | 10 | avx2 | 23.78 -> 20.46 (-14%) | 33.32 -> 21.39 (-36%) |
| quant_4x4x4_scan_field_ac | 10 | avx2 | 27.77 -> 23.09 (-17%) | 35.02 -> 26.47 (-24%) |
| coeff_level_run16 | 8 | avx2_lzcnt | 6.58 -> 4.62 | 12.41 -> 9.44 |
| coeff_level_run15 | 8 | avx2_lzcnt | 7.62 -> 4.61 | 13.27 -> 9.86 |
| coeff_level_run8 | 8 | ssse3 | 5.84 -> 4.51 | 11.62 -> 8.81 |
| coeff_level_run4 | 8 | ssse3 | 5.75 -> 4.58 | 12.64 -> 8.84 |
| coeff_level_run16 | 10 | sse2_lzcnt | 5.19 -> 2.71 | 5.99 -> 9.42 |
| coeff_level_run15 | 10 | sse2_lzcnt | 5.29 -> 2.76 | 7.61 -> 9.92 |
| coeff_level_run8 | 10 | sse2_lzcnt | 5.20 -> 2.75 | 5.00 -> 8.90 |
| coeff_level_run4 | 10 | mmx2_lzcnt | 5.20 -> 3.63 | 4.76 -> 8.48 |
| decimate_score15 | 8 | avx512 | 4.62 -> 5.19 | 13.18 -> 15.44 |
| decimate_score16 | 8 | avx512 | 5.44 -> 4.95 | 12.20 -> 14.78 |
| decimate_score64 | 8 | avx512 | 5.45 -> 6.97 | 11.69 -> 16.64 |
| decimate_score15 | 10 | avx512 | 4.51 -> 5.28 | 16.02 -> 19.99 |
| decimate_score16 | 10 | avx512 | 4.57 -> 5.02 | 14.03 -> 16.28 |
| decimate_score64 | 10 | avx512 | 10.59 -> 10.13 | 14.87 -> 19.65 |
| quant_8x8 | 8 | avx2 | 5.83 -> 5.66 | 16.66 -> 16.93 |
| quant_8x8 | 10 | avx2 | 9.19 -> 9.24 | 20.78 -> 21.10 |
| quant_4x4x4 | 8 | avx2 | 6.46 -> 6.66 | 17.95 -> 18.39 |
| quant_4x4x4 | 10 | avx2 | 9.25 -> 11.18 | 21.24 -> 23.68 |
| quant_4x4 | 10 | avx2 | 3.66 -> 3.66 | 15.43 -> 14.73 |
| quant_4x4_dc | 10 | avx2 | 4.87 -> 4.27 | 14.81 -> 14.84 |
| denoise_dct 16 | 8 | avx2 | 5.21 -> 5.49 | 12.27 -> 12.05 |
| denoise_dct 64 | 8 | avx2 | 9.36 -> 9.44 | 15.72 -> 17.02 |
| denoise_dct 16 | 10 | avx2 | 5.01 -> 5.39 | 13.16 -> 14.57 |
| denoise_dct 64 | 10 | avx2 | 9.69 -> 9.41 | 17.49 -> 18.40 |

Earlier runs of the same harness agree on the scan and coeff_level_run wins (8-bit both modes,
10-bit throughput) and on quant_4x4x4 being slower; decimate_score64 flipped between runs
(8-bit throughput 11.5 -> 5.7 in one, 5.45 -> 6.97 here), so it is treated as mixed.
quant_4x4x4_scan_field at 8-bit was not dumped (the 8-bit dumps were progressive); checkasm
--bench gives frame/field alike (8-bit ~70 -> ~56 per call for all eight scan variants).

Real-data context (dumped blocks): decimate_score64 inputs average 3.8 nonzero coefs at 8-bit
and 6.7 at 10-bit (64% / 45% have <= 3), decimate_score16 2.0 / 3.1, decimate_score15 2.8 / 2.5,
so the existing table loop runs one to a few iterations and its branches predict well.

## Per-function log

Levels: "8:" and "10:" are the dispatched levels at 8-bit and 10-bit before this branch.

| function | current best level | unusual instructions considered | tried? | bit-exact? | laptop ticks base -> new (thr / lat) | decision | reason |
|---|---|---|---|---|---|---|---|
| quant_4x4x4_scan_frame/field(_ac) | 8: avx2, 10: avx2 | vpermw/vpermd zigzag, vptestm, kunpckdq, SWAR + pext block flags, imul store mask, masked vmovdqu16/32 stores, vpmov[wd]2m + masked sub, vpternlogd OR3, popcnt score | yes | yes (checkasm, md5) | 8: 21.3 -> 17.7 / 28.7 -> 19.2; 10: 29.8 -> 25.4 / 33.6 -> 21.1 (frame) | dispatched | 10-37% faster at both depths in both modes; the hot lowlat path (no trellis). |
| coeff_level_run4/8/15/16 | 8: ssse3 (4, 8), avx2_lzcnt (15, 16); 10: mmx2_lzcnt (4), sse2_lzcnt | VBMI2 vpcompressw / F vpcompressd (register form), vpermw/vpermd reverse (pshufd for 10-bit 4), popcnt, lzcnt | yes | yes (checkasm; CAVLC only, not in the CABAC md5 cells) | 8: 6.6 -> 4.6 / 12.4 -> 9.4 (16); 10: 5.2 -> 2.7 / 6.0 -> 9.4 (16) | dispatched | 8-bit faster in both modes; 10-bit 1.9x faster in throughput, 1.6x slower in a dependent chain (zmm compare + kmov). CAVLC only: no effect on CABAC production. |
| decimate_score15/16 | 8: avx512, 10: avx512 | branchless score = 3 popcounts of the nonzero mask ANDed with its ORed shifts; kshiftrw for the DC | yes | yes (checkasm, md5 of the zen5 tree) | 8: 4.6 -> 5.2 / 13.2 -> 15.4 (15); 10: 4.6 -> 5.0 / 14.0 -> 16.3 (16) | zen5 (`zen5/x264-weird-quant-decimate`) | slower: the table version is 2 lookups and short; the popcnt chain is longer. Scalar after the mask, so not width dependent. |
| decimate_score64 | 8: avx512, 10: avx512 | same, thresholds 4/12/24 via doubling shifts | yes | yes | 8: 5.5 -> 7.0 / 11.7 -> 16.6; 10: 10.6 -> 10.1 / 14.9 -> 19.7 | zen5 (`zen5/x264-weird-quant-decimate`) | mixed in throughput between runs, slower in latency; real blocks are sparse so the loop is short. |
| quant_8x8 | 8: avx2, 10: avx2 | zmm (2 / 4 vectors), vpmov[wd]2m + masked sub, vptestmd + kortestw | yes | yes | 8: 5.83 -> 5.66 / 16.7 -> 16.9; 10: 9.19 -> 9.24 / 20.8 -> 21.1 | dispatched | neutral on split zmm; half the vector ops on a full-width core. |
| quant_4x4x4 | 8: avx2, 10: avx2 | zmm, 64-bit mask + SWAR + pext block flags | yes | yes | 8: 6.5 -> 6.7 / 18.0 -> 18.4; 10: 9.3 -> 11.2 / 21.2 -> 23.7 | zen5 (`zen5/x264-weird-quant-quant4x4x4`) | slower on split zmm (flag extraction costs more than avx2's packs + movmskps). |
| quant_4x4 | 8: avx2, 10: avx2 | 10-bit: one zmm, masked sign, vptestmd | yes (10-bit) | yes | 10: 3.66 -> 3.66 / 15.4 -> 14.7 | dispatched (10-bit) | neutral; 8-bit is already one ymm. |
| quant_4x4_dc | 8: avx2, 10: avx2 | 10-bit: one zmm, vpbroadcastd from GPR | yes (10-bit) | yes | 10: 4.87 -> 4.27 / 14.8 -> 14.8 | dispatched (10-bit) | neutral to better; 8-bit is already one ymm. |
| quant_2x2_dc | 8: ssse3 (mmx regs), 10: sse4 | none | no | - | - | rejected | 4 coefficients; nothing to widen or replace. |
| dequant_4x4 / dequant_8x8 | 8: avx512 (cqm), avx2/avx512 flat16; 10: avx512 | VNNI vpdpwssd for pmaddwd + paddd(round) in the rshift path | no | - | - | rejected | each vector needs its own accumulator (a copy of the rounding constant), so mova + vpdpwssd replaces pmaddwd + paddd: no fewer uops, longer latency. |
| dequant_4x4_dc | 8: avx2, 10: avx2 | zmm vpsllvd/vpsravd | no | - | - | rejected | 16 coefficients: one ymm at 8-bit, one zmm vs two ymm at 10-bit is the same work on split zmm; no unusual instruction applies. |
| dequant_4x4/8x8_flat16 | 8: avx2 (4x4), avx512 (8x8) | none | no | - | - | rejected | already psllw + pmullw per vector. |
| idct_dequant_2x4_dc / dconly | avx | vpdpwssd, vpscatterdd | no | - | - | rejected | 8 coefficients in two xmm; the dc variant's cost is the 8 scattered stores, and vpscatterdd is slow on AMD. |
| optimize_chroma_2x2_dc | 8: avx, 10: C | none | no | - | - | rejected | serial greedy search, rarely called (see below). |
| optimize_chroma_2x4_dc | C | none | no | - | - | rejected | as 2x2; 614 calls in 32 frames of 10-bit 4:2:2. |
| denoise_dct | 8: avx2, 10: avx2 | vpmov[wd]2m + masked sub (no EVEX psign), vpmovzxwd sums, pmaxsd clamp | yes | yes (md5 with --nr) | 8: 5.2 -> 5.5 / 12.3 -> 12.1 (16), 9.4 -> 9.4 / 15.7 -> 17.0 (64); 10: 5.0 -> 5.4 / 13.2 -> 14.6 (16) | 8-bit dispatched, 10-bit zen5 (`zen5/x264-weird-quant-denoise10`) | 8-bit neutral; 10-bit one zmm per 16 coefs is no less work on split zmm. Only used with --nr. |
| coeff_last4 | 8: mmx2_lzcnt (one 64-bit load + lzcnt), 10: avx512 | vptestnm + kmov + lzcnt | no | - | - | rejected | already one load + lzcnt (8-bit) or vptestmd + kmov + lzcnt (10-bit). |
| coeff_last8/15/16/64 | avx512 (both depths) | vptestnm + kmov + lzcnt | no | - | - | rejected | already exactly that form (64: two/four compares + kunpck + one lzcnt). |

## Unusual instructions

| extension / instruction | used? | where / why not |
|---|---|---|
| VBMI2 `vpcompressw` (register form + plain store) | yes | coeff_level_run 8-bit: compress the nonzero levels of the reversed block. The memory form is avoided (microcoded on Zen 4). |
| AVX512F `vpcompressd` | yes | coeff_level_run 10-bit, same scheme. |
| BW `vpermw` / F `vpermd` | yes | quant_4x4x4_scan zigzag: one vpermw per two 8-bit blocks, one vpermd per 10-bit block (avx2 needs vpermq + 2 pshufb + por per block pair). Also the reversal in coeff_level_run and the dequant_mf dword->word gather in the 8-bit scan dequant (index wraps mod 32, so one table gives both blocks). |
| `vptestm[wd]`, `vpmov[wd]2m`, masked `vpsub[wd]` | yes | nonzero masks; sign restore (psign[wd] has no EVEX form; masked subtract from zero is 2 ops vs 3 for xor/sub). |
| `kunpck*`, `kshiftr*`, `kortest*`, `kmovq` | yes | 64-bit coefficient masks for scan/quant_4x4x4/decimate64; DC exclusion in decimate_score15. |
| masked stores `vmovdqu16/32 {k}` | yes | quant_4x4x4_scan writes only the nonzero blocks to `level` (replaces bt/sbb address selection). |
| BMI2 `pext`, `shlx` | yes | per-block nonzero flags from the 64-bit mask (SWAR "group nonzero" + pext of bit 15 of each block); the block store mask is `(flags >> 15) * 0xffff`. |
| `popcnt`, `lzcnt` | yes | scan and decimate scores as popcounts of masks, level_run count and last. |
| `vpternlogd` | yes | 3-input OR of the 10-bit abs(level) vectors in quant_4x4x4_scan. Considered for the sign restore: it cannot do the subtract. |
| VNNI `vpdpwssd` | no | Only fit is the dequant rshift `pmaddwd + paddd(round)` (4x4 at qp < 24, 8x8 at qp < 36, 10-bit qp counted +12). Each vector needs its own accumulator holding the rounding constant, so it becomes mova + vpdpwssd: no fewer uops, longer latency. The lshift path (pmaddwd + pslld) cannot fuse. |
| IFMA `vpmadd52luq` | no | 10-bit quant `(abs(x)+bias)*mf` is a 32-bit wrap in C (udctcoef); a 52-bit product would differ on overflow and halves the lanes. |
| GFNI | no | No per-byte shifts or bit-matrix work in this package (the avx2 score's byte packing is replaced by masks). |
| VBMI `vpermb`, `vpermt2b`, `vpmultishiftqb` | no | decimate table lookups were replaced by popcounts of masks instead; per-lane run lengths for a vpermb lookup would need per-lane lzcnt over 64 lanes, far more work than three scalar popcnts. |
| BITALG `vpshufbitqmb` | no | Considered for zigzagging the raster nonzero mask in one instruction; the scan needs the zigzagged values for the level store anyway, and vptestm on them gives the scan-order mask directly. |
| `vpopcntw/d/q` | no | decimate/scan need 3 popcounts of one 64-bit mask: scalar popcnt is cheaper than building a vector and reducing it. |
| CD `vpconflictd`, `vplzcntd` | no | No duplicate-index problem; per-lane lzcnt only for a vector run-length decimate, rejected above. |
| `vpshld/vpshrd(v)` | no | Nothing needs a funnel shift. |

## VP2INTERSECT

No use found. Every kernel in this package is either elementwise (quant, dequant, denoise) or
works on one positional mask of one block (coeff_last, coeff_level_run, decimate_score, scan
score). None compares two index or value sets, so there is nothing for an intersection to
replace.

## Bugs found

1. decimate_score15 (all asm levels): `common/x86/quant-a.asm:1521` (DECIMATE4x4,
   mmx2/sse2/ssse3) and `:1754` (DECIMATE4x4_AVX512), line numbers at 0ac92fa9. The C function scores `dct[1..15]`; the asm took the DC out of the
   run mask but not out of the `|level| > 1` early return, so a DC with |level| > 1 returned 9
   where C scores the AC only. Reached by: a nonzero DC in the first coefficient. Not reachable
   from the encoder (i16x16 and chroma move the DC out and zero it before every
   decimate_score15 call), so no encode changes. Fixed in 714a5640 (one instruction per
   variant); checkasm now sets the DC.
2. checkasm coverage gaps (fixed in 1c4402de, 66bbb869, 0035b42d): coeff_last/coeff_level_run
   never set the last coefficient (`max = rand() & (size-1)`) and only used positive levels;
   coeff_last15/coeff_level_run15 never had a nonzero coefficient before the block;
   quant_4x4x4_scan used the 8-bit coefficient range at 10-bit; decimate_score had no dense,
   single-coefficient or exact-run blocks; quant_8x8/quant_4x4 had no sparse blocks (a nonzero
   flag computed from the last vector alone passed); denoise_dct offsets zeroed almost every
   coefficient, so its sign restore was barely reached. All existing kernels pass the new tests
   except decimate_score15 (bug 1).
3. Observations, not changed: at 8-bit with SSSE3+LZCNT, `quant.c` assigns the non-lzcnt
   `coeff_level_run4/8_ssse3` although `_ssse3_lzcnt` variants are assembled (upstream does
   the same). The 10-bit asm dequant (and both scans) use pmaddwd on 32-bit levels, exact
   only for |level| < 32768; that holds for encoder output, and the new kernels keep the same
   arithmetic so they stay identical to avx2.

## Ordinary improvements noticed (not done)

- optimize_chroma_2x4_dc has no asm at either depth and optimize_chroma_2x2_dc none at
  10-bit. Only 614 calls in 32 frames of 1080p 10-bit 4:2:2 (test-clock, grain, 50 Mb/s
  lowlat): it runs only for DC-only chroma at dmf <= 2048. Not worth a port.
- dequant_4x4_dc (avx2) and idct_dequant_2x4_dc/dconly (avx): 16 and 8 coefficients; a zmm
  version would be one vector either way on a split-zmm core.

## nasm

`common/x86/quant-a.asm` assembles with nasm 2.14.02 (rack01's version) at both depths with the
build flags (`-f elf64 -DSTACK_ALIGNMENT=64 -DARCH_X86_64=1 -DBIT_DEPTH=8|10`), and the
objdump disassembly is identical to nasm 3.01's. No instruction in this package needs a newer
nasm (vpcompressw/d, vpermw, vpmov[wd]2m, kunpck*, pext all assemble; a probe also showed
vpshldvw assembling in 2.14.02 in its plain register form).

## What needs rack01

- In-situ A/B (Zen 4, production presets, 8-bit 4:2:0 and 10-bit 4:2:2) of the dispatched
  kernels: quant_4x4x4_scan (the only one on a hot lowlat path), quant_8x8, 10-bit quant_4x4
  and quant_4x4_dc, 8-bit denoise_dct (only with --nr). coeff_level_run is CAVLC-only and does
  not run in CABAC production.
- The parked branches: `zen5/x264-weird-quant-decimate` (scalar after the mask, not width
  dependent; decide in situ on Zen 4), `zen5/x264-weird-quant-quant4x4x4` and
  `zen5/x264-weird-quant-denoise10` (lose on split zmm; wait for a full-width Zen 5 box).
