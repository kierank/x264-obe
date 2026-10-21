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
symbols (8-bit 18, 10-bit 35) is in its slot, so no dispatch is overridden.

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

- Reachability: uprobe hit counts over the 19 md5 cells (same binary, avx512icl, t1).
  All 53 new symbols are reached. Kernels whose first instruction is EVEX cannot take a
  uprobe at the entry, so those were probed on every ret. Cells reaching each one:
  - 10-bit sad_x3_min/sad_x4_min (4 sizes), sad_avg2 16x16/16x8: all 10-bit non-tesa
    cells (10l, 10n, 1080i, nr, trellis2, lossless). sad_x3 (4 sizes): 10_tesa.
    sad_x4: 10_tr2psy (all 4), 10_sf_cut (16x16), 10_tesa (8x8).
  - ads1/2/4 zmm: the tesa cells (both depths).
  - var_16x16 zmm: nearly every cell. ssd_16x16 zmm: the normal, nr, tesa, trellis2
    and lossless cells. ssd_16x8 zmm: trellis2 only.
  - dct4x4dc, idct4x4dc, add8x8_idct, add16x16_idct (both depths), 8-bit
    sub16x16_dct8: every lossy cell of that depth.
  - decimate_score64: lowlat, normal, superfast. decimate_score15/16: normal, tesa, nr,
    trellis2 (both depths).
  - quant_4x4x4: normal, tesa, nr, trellis2 (both depths).
  - 10-bit denoise_dct: 10_nr_grain.
  - 8-bit intra_sad_x3_8x8c: 8_sf_cut, 10_sf_cut (10-bit lowlat uses the 8-bit
    lookahead) and the 8-bit lossless cells.
  - 8-bit deblock_h_luma(_intra)_mbaff: 8l_i_ffm and 8n_i_comb (1080i).
  - 10-bit deblock_h_chroma_422(_intra): 10l and 10n (progressive and 1080i), 10_nr and
    10_sf_cut.

## Layout twin: test/x264-weird-twin2 a5c65c9a (verified)

On 69df9397, with the same X264_TWIN technique as test/x264-weird-twin 28a8d88f. It
redirects 162 symbols to WB's function for each slot: the old 121, less the 12 ymm
ads/var_16x16/ssd that are no longer dispatched, plus the 53 new ones.
(test/x264-weird-twin2-wip faf5ddab has the same tree. It was pushed before
verification.)
- Function-pointer tables (27 levels: the checkasm cpu cascade, detect, and detect
  minus AVX-512; both depths): twin2 == 4d6a42df at every slot. The only exceptions are as in 28a8d88f:
  plane_copy_interleave_icl at avx512icl (its core is redirected to the base's core),
  and the static zigzag_sub_8x8 C functions, which show under their alias name.
- All 28 asm objects are byte-identical to the 69df9397 build.
- The 12 changed C objects (bitstream, dct, deblock, pixel, quant, mc-c, both depths)
  have identical .text, .rodata and .data, with relocations at the same offsets and of
  the same types.
- Every linked .text symbol address is identical to the 69df9397 build (3644 symbols).
- The nm global defined symbols are equal (2752).
- checkasm8 and checkasm10, seeds 1001, 2002, 3003: pass.
- Changed in place, so not twinned: still only weightp_stats8_avx2, trellis 8x8
  ZPREFIX and the decimate_score15 DC fix. Function by function, the WB vs tip
  differences are the same list as for 99d29cc3. Round 2 changes no function that
  4d6a42df has. The only round 2 changes to round 1 functions are rodata neighbour
  bytes in the 8-bit deblock_v/h_luma_intra_avx512icl, from the new tables; their
  instructions are unchanged.

## Not verified yet
- Speed: nothing on Zen 4 yet. All kernels are pending rack01 numbers.
