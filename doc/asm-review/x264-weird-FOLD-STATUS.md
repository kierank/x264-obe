<!-- Copyright (C) 2026 Open Broadcast Systems Ltd -->
# x264-weird: zen5/ kernels folded back, status (2026-10-20)

Kieran: the laptop is not indicative of server speed, so the 13 zen5/x264-weird-*
kernel sets that were parked on laptop timings are dispatched on wip/x264-weird again,
to be measured on rack01 (Zen 4). Their laptop timings are notes only.

Base: wip/x264-weird 99d29cc3. One --no-ff merge per zen5 branch, so each one can be
reverted alone (`git revert -m 1 <merge>`):

| zen5 branch | zen5 tip | merge |
|---|---|---|
| dbpred-chroma422 | d0b0b0d9 | 72c57bd1 |
| dbpred-mbaff | 48337be3 | e30c6024 |
| dct-add-idct | ad632c1f | 79b9c3e2 |
| dct-dc4x4 | 34744f3c | 2e7c54ab |
| dct-hbd-add-idct | 0d4c5d43 | fdad85f0 |
| dct-sub16x16-dct8 | 3176001d | da791567 |
| pixmisc-zmm | 7bcea30c | 58a07d20 |
| quant-decimate | 896cb220 | 3998ca35 |
| quant-denoise10 | 2103475d | c35fc777 |
| quant-quant4x4x4 | a10f7b11 | 868b7cb5 |
| sad-hbd-avg2-zmm | e2cd4898 | ca349f4d |
| sad-hbd-sadx-zmm | 63f2ee79 | ca913238 |
| sad-intra8c | f80bdadf | 00bafa32 |

Only common/x86/deblock-a.asm (the two dbpred kernels) changes asm. The other kernels
were already assembled on 99d29cc3 and only their dispatch is new.

## Slot overlaps

Same slot at the same level: only pixmisc-zmm. It replaces the 99d29cc3 avx512icl ymm
dispatch of ads1/2/4, var_16x16, ssd_16x16 and ssd_16x8 (both depths) with the zmm
versions. The zmm kernels run and the ymm ones are now undispatched. No two zen5
branches share a slot. At detect (laptop = rack01 flags) every one of the 53 new
symbols (8-bit 21, 10-bit 32) is in its slot, so no dispatch is overridden.

## Verified (laptop, WSL, gcc 15.2, nasm 3.01, -no-pie)

- checkasm8 and checkasm10, seeds 1001, 2002, 3003: all pass.
- nm: no duplicate global symbols and no undefined x264_ references (8, 10 and all).
- objdump: every vpdpbusd/vpdpwssd is EVEX (8-bit 149, 10-bit 158, all 307), no VEX.
- deblock-a.asm assembles byte-identically with nasm 2.14.02 at both depths.
- md5 at --threads 1 --asm avx512icl, -fno-fast-math -ffp-contract=off, this tip vs
  4d6a42df, 19 cells (the INDEX matrix): 19/19 identical.
- Function-pointer dump (checkasm cpu cascade + detect, both depths): 99d29cc3 -> this
  tip changes 166 slot entries, at AVX512, AVX512ICL and detect only, and all are the
  13 branches' dispatches. --asm avx2 (detect minus AVX-512) is unchanged.

## Not verified yet

- Reachability. uprobe hit counts over the 19 cells show these reached: 10-bit
  sad_x3/x4(_min) and sad_avg2 zmm, ads zmm (tesa), var_16x16 and ssd zmm, dct4x4dc and
  idct4x4dc (both depths), 10-bit add8x8/add16x16_idct, 10-bit deblock_h_chroma_422(_intra),
  8-bit deblock_h_luma(_intra)_mbaff (1080i cells). No hits for decimate_score15/16/64
  (both depths), quant_4x4x4 (both), 10-bit denoise_dct, 8-bit add8x8/add16x16_idct,
  8-bit sub16x16_dct8 and 8-bit intra_sad_x3_8x8c. Some of these are expected to run
  (decimate in P frames), so a failed uprobe on an EVEX first instruction is suspected.
  Check them another way before trusting that they run.
- Layout twin test/x264-weird-twin2: not built yet.
- Speed: nothing on Zen 4 yet. All kernels are pending rack01 numbers.
