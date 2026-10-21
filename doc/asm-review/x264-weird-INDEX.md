<!-- Copyright (C) 2026 Open Broadcast Systems Ltd -->
# x264-obe unusual-instruction pass: index (2026-10-20)

Integration branch `wip/x264-weird`, based on speed-next 4d6a42df (0ac92fa9 plus the
var2_8x16 10-bit fix f9ddbda7). The eight package branches were merged with --no-ff in
this order:

| package | branch tip | merge commit | log |
|---|---|---|---|
| mc | ebc430c7 | 3c274f76 | x264-weird-mc.md |
| dbpred | 9a01d608 | 0ca202f5 | x264-weird-dbpred.md |
| sad | 621a1cb4 | 39314405 | x264-weird-sad.md |
| cabac | a9fa4fe1 | 266370df | x264-weird-cabac.md |
| dct | 87dc2128 | 6b720d43 | x264-weird-dct.md |
| quant | 3c713b61 | c93e97f9 | x264-weird-quant.md |
| pixmisc | 70bff4fd | 8a9e0863 | x264-weird-pixmisc.md |
| satd | e88da8e8 | d29524ce | x264-weird-satd.md |

fix/configure-pie is not merged. In a second round the 13 zen5/ branches were merged
too, dispatched for rack01 (see "zen5/ kernels" below and x264-weird-FOLD-STATUS.md).

Conflicts: only common/pixel.c, in the 8-bit AVX512ICL block (sad's intra_sad_x3_16x16 and
pixmisc's kernels). Both are kept in one braced block. Everything else merged textually,
including pixel-a.asm (pixmisc and satd), checkasm.c and dct.c (dct and quant). The pixmisc
copy of the var2 fix (e291feff) is identical to f9ddbda7 and merged with no change.

## Verification of the merged tree (laptop, WSL, gcc 15.2, nasm 3.01)

- Builds: `--bit-depth=8` and `--bit-depth=10`, each with `--extra-ldflags=-no-pie`.
  The C warnings are the same set as the base's. The only new one is a -Wshadow of
  `src` in the mc checkasm test.
- checkasm8 and checkasm10, seeds 1001, 2002 and 3003: all pass. A 1001 run of both
  depths also passed after every single merge.
- nasm 2.14.02: every .asm assembles at both depths with the build flags. .text, .rodata
  and relocations are byte-identical to nasm 3.01 everywhere except mc-a.asm and
  pixel-a.asm. Their only difference is the pre-existing `movsxd rax, eax` (2.14.02)
  vs `cdqe` (3.01), which base 4d6a42df shows too.
- nm: no duplicate global symbols in libx264.a at either depth, and no undefined
  avx512icl references.
- VNNI encoding (objdump of libx264.a): every vpdpbusd and vpdpwssd is EVEX (0x62),
  8-bit 149 and 10-bit 158. There is no VEX AVX-VNNI, and no `{vex}` encoding of anything.
- Upper state: in every function that touches ymm0-15/zmm0-15, every ret is preceded
  by vzeroupper. The exceptions are the rets of internal subroutines reached by `call`,
  whose callers' RET does it: 3 new ones at 8-bit (satd_16x8_internal,
  sa8d_satd_8x8_internal, and the local helper inside intra_sa8d_x9_8x8) and 4 at 10-bit
  (hadamard_ac_8x8, hadamard_ac_8x8v, sa8d_16x8_internal, and the local helper inside
  add16x16_idct8). The avx2 internals in base follow the same pattern. Kernels on x86inc's default permutation
  (ymm/zmm16-31) need no vzeroupper (the cost of that is accepted, see
  x86inc-dirty-zmm16-31).
- md5 identity at `--threads 1`: base 4d6a42df vs the wip/x264-weird tip, both built
  `--bit-depth=all --extra-cflags="-fno-fast-math -ffp-contract=off"`. Input is
  stressgen 1080 at 40 frames, seed 7, piped to `--demuxer y4m -`, CABAC only.
  There are 19 cells:
  - 8-bit 4:2:0 and 10-bit 4:2:2, each in lowlat and normal, progressive and native
    1080i tff (MBAFF).
    - lowlat: veryfast zerolatency --intra-refresh, one-frame VBV.
    - normal: medium, 1 s VBV, --weightp 2, --bframes 3.
  - At both depths: --me tesa, superfast lowlat (subme 1), --nr 400, and slow
    --trellis 2 --psy-rd 1.0:0.2.
  - Lossless (--qp 0) on ticker: 8-bit progressive, 8-bit 1080i, and 10-bit 4:2:2.

  --asm avx512icl gives 19/19 identical, and --asm avx2 gives 19/19 identical.
- Pre-existing, unchanged by this branch: at the same commit, --asm avx2 and
  --asm avx512 output differ in three cells (10-bit normal dissolve and tesa at both
  depths). With --no-mbtree they are identical, so the difference is in the mbtree
  float kernels at the avx512 level. Base and branch behave identically.

## Dispatched kernels

Laptop numbers are the package agents' (HX 370, double-pumped zmm, loaded box). The
ratio is new/old time, so < 1 is faster. They are indicative only.

| package | function | depths | level | laptop result |
|---|---|---|---|---|
| mc | frame_init_lowres_core | 8, 10 | avx512icl ymm | 8: ~1.00; 10: 0.81-0.95 |
| mc | frame_init_lowres_core8 (10-bit lowlat, lookahead8) | 10 | avx512icl | 0.87-0.97 |
| mc | plane_copy_interleave (core, C wrapper needs 32-byte rows) | 8, 10 | avx512icl | ~1.0 (NT-store bound) |
| mc | plane_copy_deinterleave | 8, 10 | avx512icl | 8: 0.61-0.68; 10: 0.46-0.55 (cold: --dump-yuv only) |
| mc | store_interleave_chroma | 10 | avx512icl | below timer floor (4 vs 6 ops/row) |
| dbpred | deblock_strength | 8, 10 | avx512icl | loop ~0.97 |
| dbpred | deblock_v_luma_intra | 8, 10 | avx512icl | 8: 0.76; 10: 0.68 |
| dbpred | deblock_h_luma_intra | 8, 10 | avx512icl | 8: 0.63; 10: 0.76-0.86 |
| dbpred | deblock_h_luma | 8, 10 | avx512icl | 8: 0.70; 10: 0.98 of avx2 (1.13 of avx) |
| dbpred | deblock_v_luma | 10 | avx512icl | 0.95 |
| dbpred | deblock_luma_mb | 10 | avx512icl | 0.97-0.98 |
| sad | pixel_sad_16x16, 16x8 (zmm) | 10 | avx512 | interleaved 0.85-0.97, tight loop 1.07-1.21 (mixed) |
| sad | intra_sad_x3_16x16 | 8 | avx512icl | 0.69-0.80 (subme <= 1 only) |
| cabac | nal_escape | 8, 10 | avx512icl | checkasm random 2566 -> 1863, escape-dense 190257 -> 60771 |
| cabac | trellis_cabac_8x8(_psy) zero-run prefix sums (inside the existing icl kernel; TRELLIS_ICL_ZPREFIX=0 restores the loop) | 8, 10 | avx512icl | corpus replay cycles -6..-23% (e.g. 971 -> 778) |
| dct | zigzag_sub_4x4 frame/field | 8 | avx512icl | 4.6 -> 4.2 (lossless only) |
| dct | zigzag_sub_4x4ac frame/field | 8 | avx512icl | 5.0 -> 5.1, neutral (lossless only) |
| dct | zigzag_sub_8x8 frame/field (was C) | 8 | avx512icl | 54 -> 6.8 (lossless only) |
| dct | zigzag_scan_4x4_field | 8, 10 | avx512icl | neutral |
| dct | sub16x16_dct8 (zmm) | 10 | avx512icl | 77.2 -> 62.6 |
| dct | add16x16_idct8 (zmm) | 8, 10 | avx512icl | 8: 89.6 -> 57.2; 10: 99.1 -> 89.6 (no encoder caller) |
| quant | quant_4x4x4_scan frame/field (+ _ac) | 8, 10 | avx512icl | throughput -10..-17%, latency -15..-37% |
| quant | coeff_level_run4/8/15/16 | 8, 10 | avx512icl | 8: faster; 10: 1.9x faster throughput, 1.6x slower latency (CAVLC only) |
| quant | quant_8x8 | 8, 10 | avx512icl | neutral |
| quant | quant_4x4, quant_4x4_dc | 10 | avx512icl | neutral to better |
| quant | denoise_dct | 8 | avx512icl | neutral (--nr only) |
| pixmisc | pixel_ads1/2/4 | 8, 10 | avx512icl ymm, replaced by zmm in round 2 | 8: 19-22 -> 7-10; 10: 21-25 -> 9-16 (esa/tesa only) |
| pixmisc | pixel_var 8x16, 8x8 (16x16: ymm, replaced by zmm in round 2) | 8, 10 | avx512icl ymm | 8: 11.2 -> 6.6 (16x16); 10: 13.8 -> 10.3 |
| pixmisc | pixel_var2 8x8, 8x16 | 8, 10 | avx512icl ymm | ~0.91-0.95 |
| pixmisc | pixel_ssd 8x16 (16x16, 16x8: ymm, replaced by zmm in round 2) | 8, 10 | avx512icl ymm | 16x16 small win, others neutral |
| pixmisc | pixel_ssd 8x8 | 10 | avx512icl ymm | neutral |
| pixmisc | weightp_dc8x8 | 8, 10 | avx512icl ymm | 8: 5.6 -> 4.4; 10: 4.7 -> 4.4 |
| pixmisc | weightp_stats8 | 8 | avx2 rewrite + avx512icl | old avx2 218 -> new avx2 88.8 -> icl 81.6 |
| pixmisc | weightp_sum8, weightp_sum8_clip | 8 | avx512icl ymm | 294.7 -> 186.6; 133.8 -> 74.4 |
| pixmisc | weightp_sum8_nv | 8 | avx512icl ymm | 188 -> 121 (lookahead threads only) |
| pixmisc | ssim_4x4x2_core | 8, 10 | avx512icl ymm | 8: 5.9 -> 4.7; 10: 5.3 -> 4.4 (--ssim only) |
| satd | pixel_satd 8x8, 8x16, 16x8, 16x16 | 8 | avx512icl (ICL_LOW: ymm0-15, VEX + EVEX) | 0.91-0.98 |
| satd | pixel_satd_avg2 x4 | 8 | avx512icl (ICL_LOW) | 0.92-1.02 (not reached; satd_avg2_pre covers it) |
| satd | pixel_satd_pre, satd_avg2_pre x4 | 8 | avx512icl (ICL_LOW) | 0.95-1.00 (also run by 10-bit lowlat via lookahead8) |
| satd | pixel_satd_bi, satd_bi4 x4 | 8 | avx512icl (ICL_LOW) | 0.89-0.99 |
| satd | pixel_sa8d_8x8 | 8 | avx512icl (ICL_LOW) | 0.95 |
| satd | pixel_sa8d_satd_16x16 | 8 | avx512icl (ICL_LOW) | 0.92 |
| satd | intra_satd_x3_16x16, 8x8c | 8 | avx512icl (ICL_LOW) | 0.92 / 0.95 |
| satd | intra_sa8d_x9_8x8 | 8 | avx512icl (ICL_LOW) | 0.95 |
| satd | intra_satd_lowres | 8 | avx512icl (ICL_LOW) | 0.96 (also 10-bit lowlat via lookahead8) |
| satd | pixel_hadamard_ac 16x16, 16x8, 8x16 | 10 | avx512icl (ICL_LOW, {evex} VNNI) | 0.94-1.00 |
| satd | pixel_sa8d 8x8, 16x16 | 10 | avx512icl (ICL_LOW, {evex} VNNI) | ~1.00 (16x16 not reached) |

Assembled but not dispatched on this branch: the avx512icl ymm ads1/2/4, var_16x16,
ssd_16x16 and ssd_16x8 (both depths; the zmm versions replaced them in round 2) and the
8-bit ssd_8x8 icl.

## zen5/ kernels: dispatched in round 2, pending Zen 4 numbers

Kieran ruled that the laptop is not indicative of server speed. The kernel sets parked
on zen5/ branches because of laptop timings are therefore merged here with their
dispatch, to be measured on rack01 (Zen 4). The laptop column is a note only and decides
nothing. Each branch has its own --no-ff merge, so `git revert -m 1 <merge>` removes one
set alone. Verification and reachability are in x264-weird-FOLD-STATUS.md.

Same slot at the same level: only pixmisc-zmm, which replaces the round 1 ymm avx512icl
ads1/2/4, var_16x16, ssd_16x16 and ssd_16x8 (zmm runs). No two zen5 branches share a
slot, and at detect every new symbol is in its slot (nothing later overrides it).

| branch | hash | merge | dispatches | laptop (note only) |
|---|---|---|---|---|
| zen5/x264-weird-dbpred-chroma422 | d0b0b0d9 | 72c57bd1 | 10-bit zmm h_chroma_422(_intra), avx512icl | 1.27-1.36 |
| zen5/x264-weird-dbpred-mbaff | 48337be3 | e30c6024 | 8-bit h_luma(_intra)_mbaff vpermb transposes, avx512icl | 1.02-1.07 |
| zen5/x264-weird-dct-add-idct | ad632c1f | 79b9c3e2 | 8-bit zmm add8x8/add16x16_idct, avx512icl | 1.2-1.27 |
| zen5/x264-weird-dct-dc4x4 | 34744f3c | 2e7c54ab | dct4x4dc/idct4x4dc, both depths, avx512icl | 8-bit throughput better, chained latency worse |
| zen5/x264-weird-dct-hbd-add-idct | 0d4c5d43 | fdad85f0 | 10-bit zmm add8x8/add16x16_idct, avx512icl | 1.17-1.22 |
| zen5/x264-weird-dct-sub16x16-dct8 | 3176001d | da791567 | 8-bit zmm sub16x16_dct8, avx512icl | 1.02-1.10 |
| zen5/x264-weird-pixmisc-zmm | 7bcea30c | 58a07d20 | zmm ads, var_16x16, ssd_16x16/16x8, both depths, avx512icl | ssd zmm slower; 10-bit var/ads1 zmm faster |
| zen5/x264-weird-quant-decimate | 896cb220 | 3998ca35 | decimate_score15/16/64 popcnt, both depths, avx512icl | mixed/slower (scalar; decide in situ) |
| zen5/x264-weird-quant-denoise10 | 2103475d | c35fc777 | 10-bit denoise_dct, avx512icl | 0.97-1.11 |
| zen5/x264-weird-quant-quant4x4x4 | a10f7b11 | 868b7cb5 | quant_4x4x4, both depths, avx512icl | 8: ~1.03; 10: ~1.2 |
| zen5/x264-weird-sad-hbd-avg2-zmm | e2cd4898 | ca349f4d | 10-bit zmm sad_avg2 16x16/16x8, avx512 | 0.99-1.25 |
| zen5/x264-weird-sad-hbd-sadx-zmm | 63f2ee79 | ca913238 | 10-bit zmm sad_x3/x4(_min), 4 sizes, avx512 | 0.97-1.59 |
| zen5/x264-weird-sad-intra8c | f80bdadf | 00bafa32 | 8-bit intra_sad_x3_8x8c, avx512icl (also 10-bit lowlat lookahead) | 1.03-1.10 |

## Bugs and coverage fixes

| item | where | status |
|---|---|---|
| 10-bit var2_8x16: VAR2_END squared the sum in 32 bits (mean diff >= 512; 4:2:2 chroma early termination; changes 10-bit 4:2:2 output) | pixel-a.asm VAR2_END | fixed in speed-next f9ddbda7 (pixmisc e291feff, same change). Production master has the same bug: fix/master-var2-8x16 cb7ce8d3, not merged |
| decimate_score15 counted the DC in the \|level\| > 1 -> 9 check, unlike C (not reachable: the encoder zeroes the DC first) | quant-a.asm DECIMATE4x4 and DECIMATE4x4_AVX512, all levels | fixed in 714a5640 (quant) |
| nal_escape sse2/avx2 read up to ~126 bytes past `end`, but only 64 bytes are padded. The extra bytes are inside p_bitstream and can be uninitialised (valgrind). avx2 also writes up to 63 bytes past the output end, within nal_buffer_size's +64 | bitstream-a.asm | NOT fixed (latent). The avx512icl version stays inside both buffers |
| speed-next does not link with a PIE-default gcc: non-PIC asm gives absolute R_X86_64_32/32S relocations in every object | configure, checkasm-a.asm | fix/configure-pie b2bce598 (always -DPIC on x86-64, as upstream; `puts wrt ..plt`), NOT merged: needs a rack01 PIC vs non-PIC A/B. Builds here use -no-pie |
| checkasm: deblock_strength-only changes were not reported (used_asm not set) | tools/checkasm.c | fixed 70f2ec99 |
| checkasm: the 10-bit deblock p0/q0 PIXEL_MAX clip was never reached | tools/checkasm.c | fixed 253df003 |
| checkasm: plane_copy_(de)interleave only ran small sizes, whose largest cases hit the C fallback | tools/checkasm.c | fixed ed1bda81 (960x4 rows + bench) |
| checkasm: sad_x had no maxed-difference test; intra sad_x3 ran one position | tools/checkasm.c | fixed bbcdaca9 |
| checkasm: nal_escape could not catch carry and block-boundary mutants | tools/checkasm.c | fixed e6036dd5 (4000 cases, guards) |
| checkasm: zigzag_sub_8x8 had no test; zigzag_sub_4x4 never had nz = 0; 4x4ac never compared level[0] | tools/checkasm.c | fixed 82c61344 |
| checkasm: coeff_last/level_run never set the last coefficient or negative levels; the 10-bit scan used the 8-bit range; decimate had no dense, single or exact-run blocks; quant had no sparse blocks; the denoise sign restore was barely reached | tools/checkasm.c | fixed 1c4402de, 66bbb869, 0035b42d |
| checkasm: var only on random pixels; var2 never on large same-sign differences (why the var2 bug survived); ads at one width; ssim compared only the float result | tools/checkasm.c | fixed in the pixmisc branch (787ebd80, e291feff and the kernel commits) |
| checkasm: sa8d_satd reused one block in all 64 iterations | tools/checkasm.c | fixed b329a99c |

Other findings, not changed:
- `vpternlogd x,x,x,0xff` does not break the dependency on the laptop. The ALL_ONES
  macro's per-pass use made the zmm weightp_stats8 slower, so zen5/weightp-avx512 is
  worth a retest.
- The 10-bit AVX2 deblock h_luma, h_chroma (4:2:0) and h_chroma_intra are ~1.24x slower
  than AVX on the laptop.
- AVX2 phaddw ymm is slow on the laptop. Users: lowres (14), x9 (~6), and satd_mcc
  (4 phaddd).
- The dispatched 8-bit avx512 sub8x8_dct is ~2.5% slower than avx2 on the laptop.
- add16x16_idct8 has no caller in encoder/.
- 10-bit intra_sad_x3 8x8c/8x16c/16x16 are still C combos (subme <= 1 only).
- nasm 2.14.02 is not a safe assembler for vpshldv*/vpshrdv*. It accepts the register
  form with rc 0 but emits a stray imm8 byte after it, which corrupts the following
  code: probed `vpshldvw ymm1, ymm2, ymm3` -> `62 f2 ed 28 70 cb 03`. No
  vpshldv*/vpshrdv* is used on this branch.
- With ICL_LOW (m0-15 on ymm0-15), nasm silently emits VEX AVX-VNNI for vpdpwssd unless
  it is written `{evex}`. The satd kernels do that, and the objdump check above confirms
  it.

## rack01 (Zen 4) A/B list, from the package logs

- mc: in-situ cycles for 8bb70ebf (lowres; at 10-bit lowlat lowres8 runs per band) and
  dc1a037b (interleave per frame, store_interleave per MB). Expected at or below
  resolution.
- dbpred: wip 9a01d608 vs 0ac92fa9. The 10-bit avx vs avx2 vs icl dispatch of the h
  filters (h_luma, h_chroma, h_chroma_intra).
- sad: 10-bit zmm sad_16x16/16x8 (10l/10n, progressive and 1080i, with a layout twin);
  8-bit intra_sad_x3_16x16 at subme 1 (speedcontrol presets 0-1).
- cabac: trellis 8x8 zero-run prefix, TRELLIS_ICL_ZPREFIX=1 vs 0 (normal, trellis 1/2,
  8-bit 4:2:0 and 10-bit 4:2:2 including 1080i); nal_escape `--bench`; PIC vs non-PIC for
  fix/configure-pie.
- dct: checkasm --bench of the new kernels; in situ on 10-bit 4:2:2 normal/lowlat
  (sub16x16_dct8) and MBAFF (scan_4x4_field); zen5/x264-weird-dct-dc4x4 on
  i16x16-heavy content. Decide whether to keep add16x16_idct8 (no caller).
- quant: in situ quant_4x4x4_scan first (the hot lowlat path), then quant_8x8, 10-bit
  quant_4x4/4x4_dc, 8-bit denoise_dct (--nr); zen5/x264-weird-quant-decimate in situ on
  Zen 4 (scalar, not width dependent).
- pixmisc: checkasm --bench at both depths; in-situ A/B of the avx512icl dispatch (8-bit
  lowlat and normal, 10-bit 4:2:2 including 1080i). 8-bit had no AVX-512 pixel functions
  on purpose after the earlier ablation, so the 8-bit avx512icl pixel kernels need their
  own A/B.
- satd: in-situ A/B with a layout twin (8l/8n/10l/10n, progressive and 1080i; 10l runs the
  8-bit lookahead kernels); the encoding A/B 708da2d3 (default permutation, EVEX) vs the
  tip (ICL_LOW, VEX); checkasm on Zen 4 as a SIGILL check; optionally the phaddw lead.
- Round 2 (zen5/ kernels above): checkasm --bench of every one at both depths, then the
  in-situ A/B with the layout twin test/x264-weird-twin2. Keep or revert each merge on
  the Zen 4 numbers.
- Whole branch: 10-bit 4:2:2 check of 4d6a42df vs 0ac92fa9 (the var2 fix changes output),
  then wip/x264-weird vs 4d6a42df.
- nasm: everything here assembles identically with 2.14.02, so no upgrade is required
  for this branch.
