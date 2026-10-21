<!-- Copyright (C) 2026 Open Broadcast Systems Ltd -->
# x264-obe AVX2 read-every-instruction pass (2026-10-20)

Branch `wip/x264-avx2-pass` on speed-next 64bc7552. Every commit is meant to be bit-exact and
stands alone, so rack01 can drop any single one. Targets: AVX2-only CPUs (Zen 3 EPYC 7413, Core 3)
and Zen 4 wherever no avx512icl kernel is dispatched.

## Method

- Five readers (sad/ssd/var, satd/sa8d/hadamard, quant/dct/trellis/cabac, mc/lowres,
  deblock/predict/weightp misc) read every INIT_YMM/INIT_XMM avx2 kernel of their family at
  both depths and the AVX2-level dispatch. The changes were then made and verified one kernel
  at a time.
- Port and latency facts come from uops.info (Zen 3 / Zen 4, measured):
  - ymm/xmm phaddw and phaddd are 3 uops at one per 2 cycles; a punpckl/punpckh + padd step is
    3 single uops.
  - vpermq/vpermd ymm are 2 uops at latency 6/8 on Zen 3 and 1 uop on Zen 4.
  - vperm2i128 is 1 uop at latency 3.
  - vpblendd/vpblendw run on FP0123.
  - psignw and vpblendvb are 1 uop.
- No laptop speed numbers are used anywhere: rack01 decides. Code alignment was ruled out.
  Data constants are aligned to their load width and appended at the end of their section.
- Verification on the laptop (HX 370, WSL, nasm 3.01):
  - checkasm8/10 at seeds 1001, 2002 and 3003.
  - One-instruction mutations through checkasm. Each must FAIL; the equivalent mutants are
    noted below.
  - Old-vs-new drivers (speed-next objects assembled with prefix x264o_) with PROT_NONE guard
    pages at both ends of every buffer, k1-k7 and callee-saved checks via
    x264_checkasm_call, and XINUSE after every call. They are run on a page-aligned stack.
    - drv-pix covers intra x9 4x4/8x8, intra_satd_lowres, satd_mcc, weightp_sum8/_clip
      (also against the C formula for negative scales), weightp_sum8_nv and weightp_stats8.
    - drv-mc covers the 10-bit biweight avg with unequal strides and every weight from -64 to
      128, and 8-bit avg2_w16 at heights 2-18.
  - Every commit assembles at both depths, and nasm 2.14.02 gives the same code as nasm 3.01.
    The only difference is the pre-existing cdqe/movsxd encoding choice, which is also in the
    base.

## Kernels

### Weak spots from the brief

| kernel | finding | action | commit |
|---|---|---|---|
| weightp_sum8/_clip avx2 | the prologue's `or` of a negative 32-bit scale wipes the round word | zero-extend the scale; unreachable (scales 0..127). The commit text says the avx512icl instance too: wrong, WEIGHTP_SUM8 is avx2-only, and the icl kernel broadcasts scale and round separately | 2ab09ec5 |
| 10-bit deblock h_luma, h_chroma (4:2:0), h_chroma_intra avx2 | one-pass ymm, slower than the two-pass avx in dependent calls (edge after edge) | dispatch avx at the AVX2 level; rack01 to confirm from speed-next's avx/avx2 rows. Zen 4: h_chroma and h_chroma_intra now avx, h_luma stays avx512icl | 0e22ffcc |
| intra_satd_x9_4x4 avx2, 8-bit | 6 ymm phaddw; X9B_MERGE takes 2 vperm2i128 a mode pair | HADD_ILV punpck/paddw tree (modular words); vperm2i128 0x21 + vpblendd | c6bfd18e |
| intra_satd_x9_4x4 avx2, 10-bit | as 8-bit (X9H_MERGE) | same | f4681fc6 |
| intra_sa8d_x9_8x8 avx2/avx512icl, 8-bit | 6 ymm phaddw | HADD_ILV tree | b6e6d14d |
| intra_sa8d_x9_8x8 avx2, 10-bit | 3 ymm + 2 xmm phaddd | dword HADD_ILV, pshufd/paddd for hu | 911c4d77 |
| intra_satd_lowres avx2/avx512icl, 8-bit | 10 ymm phaddw (+4 xmm in the dc/p prologue) | HADD_ILV tree; xmm prologue phaddw kept (one-off, the replacements are longer) | 842619ba |
| intra_satd_lowres avx2, 10-bit | 5 phaddw + 5 phaddd | pmaddwd per mode (words <= 32736, exact) + dword HADD_ILV | ade9fa42 |
| satd_mcc avx2 end (both depths) | 3 shifts + ymm phaddd + xmm phaddd | pblendw/psrld split, HADD_ILV, pshufd/paddd | e1f58a27 |

### Read pass: changed

| kernel | finding | action | commit |
|---|---|---|---|
| satd_mcc avx2 w8/w4, 8-bit | two-pass word filter, 4 pmullw a row | one pmaddubsw pass on (i, i+2) byte pairs, as the 4x4 path | 1c1d8bb1 |
| trellis_cabac avx2 NZ_MASK, 10-bit | pd_04152637 at rodata 112: the 32-byte load splits a line | const-a's 32-aligned deinterleave_shufd | 7f928dd3 |
| quant_4x4x4_scan_frame(_ac) avx2, 8-bit | 4 vpermq q1032 (pure lane swaps) | vperm2i128 0x01 | 1c5c51b5 |
| zigzag_scan_8x8_frame avx2, 8-bit | 4 vpermq q1032 | vperm2i128 0x01 | 8c8ed251 |
| coeff_last64 (10-bit) | avx2_lzcnt assembled but never dispatched at 10-bit | dispatch | a291a6a1 |
| pixel_sad_16x16/16x8 avx2, 8-bit | serial 3-add end chain, feeds the ME compare | tree | 73089b94 |
| pixel_vsad (8-bit sse2, 10-bit avx2) | 2 dependent paddw per iteration on the accumulator | 1 | ae2a609f |
| get_ref avg2 w12/w16, 8-bit | legacy-SSE pixel_avg2_w16_sse2 at the AVX2 level, no load folding | VEX pixel_avg2_w16_avx2 | d531ace0 |
| hpel_filter HPEL_FILT_HBD (10-bit) | 2 shifts + 2 adds for 5*(4c-b) | pmullw by pw_5 (appended) | a438c752 |
| frame_init_lowres_core8 (10-bit) | paddw + psrlw x4 | pmulhrsw by 8192 | 119bed2b |
| sad_x3/sad_x4 16xN avx2, 10-bit | fold + end: 5 (x4) / 3 (x3) lane crossings | in-lane dword steps, one vextracti128 | 5752b5c7 |
| hadamard_ac internal (10-bit, sse2..avx2) | 8 pmaddwd + 7 paddd for the satd half | word sums in two groups (< 32768), 2 pmaddwd | 6578837f |
| DEBLOCK_LUMA_INTER_SSE2 (10-bit v_luma, luma_mb, sse2..avx2) | tc = max(t,0) as pcmpgtw + pand + copy; pavgw twice; clip via subtract/add | pmaxsw; mask fixed up front; one pavgw; clip to [x1-tc, x1+tc] | cff510d2 |
| add16x16_idct_dc avx2, 10-bit | packssdw/punpcklwd/vpermq/punpckldq per row group | vbroadcasti128 + pshufb (table appended), pd_32 in a register | 90bb61d6 |
| pixel_avg_weight w16/w8 avx2, 10-bit | 10 ops per 16 px (unpack, 2 pmaddwd, pack) | b + pmulhrsw(a-b, w<<9), source swap for w >= 64 | d8c6421d |
| LOAD_DUP_4x16P_AVX2 (8-bit sa8d_satd, hadamard_ac 16xN) | vpermq q0011 per row (32 per sa8d_satd_16x16) | vbroadcasti128 + pshufb (table appended) | 94d907c9 |
| frame_init_lowres_core avx2, 8-bit | 4 vpermq q3120 after the even/odd split | vperm2i128 0x20/0x31 before it | 1e1b4e40 |
| frame_init_lowres_core avx2, 10-bit | 4 vpermq q3120 | same | bbab7790 |
| intra_satd_x3_8x8c avx2, 8-bit | xmm phaddd | pshufd/paddd (as the icl branch) | f21fe8b7 |
| satd_bi weighted 16xN avx2, 8-bit | vpermq q3232 / q1010 | vperm2i128 0x11 + register vinserti128 | 08ae873c |
| satd_avg2_8x8/8x16 avx2, 10-bit | 3 vinserti128 loads a row | xmm pavgw/psubw with memory operands, one insert | f4c8c207 |
| satd_8x8/8x16 avx2, 10-bit | 2 vinserti128 loads a row | xmm psubw, one insert | dc0d929f |
| chroma_intra_body (8-bit avx) | psubb/pand/paddb select x2 | vpblendvb | e33e2e53 |
| CHROMA_DEBLOCK_P0_Q0_INTRA (10-bit avx, avx2) | psubw/pand/paddw select x2 | vpblendvb | 9f820220 |
| sad_x4 16xN (+_min) avx2, 8-bit | 10 loads per row pair; two vbroadcasti128 of fenc | sad_x3 layout: one 32-byte fenc load, one accumulator per reference (9 loads); rack01 bench-gated | 8e0b1e18 |
| weightp_sum8/_clip avx2, 8-bit | dword path, 9 (15 clip) ops per 16 px | word path as the avx512icl kernel (H.264 weight range) | c574d485 |
| weightp_stats8 avx2, 10-bit | min and max reduced separately, 59 ops per 8 blocks | ~max interleaved with min, one pminuw reduction: 28 | 71ae1dcf |
| weightp_sum8_nv avx2 (both) | u/v split before 2 HADD4D | word HADD4W first (< 65536), split after: 15 vs 30 per 4 blocks | 7a110966 |
| mc_chroma avx2, 8-bit | deinterleave_shufd reloaded per 2 rows; row loaded twice in loop4 | register; reuse the xmm | cbf9fb96 |
| sa8d_satd (8-bit avx, avx2) | xmm phaddd tail | the icl punpck tail | 57061565 |
| sub8x8_dct avx2, 8-bit | widen both against zero, psubw | punpcklbw fenc/fdec + pmaddubsw hsub_mul | beb4c62f |
| zigzag_scan_4x4_frame, 8-bit | the avx (xmm, 6 shuffles) kernel at the AVX2 level | avx2: load, vperm2i128, 2 pshufb, por | 0600bca4 |

### Read pass: no change, or rejected

Each line gives the kernel and then the reason.

- **SAD family**
  - sad_x3/sad_x4 end phaddd (both depths): a single latency-bound op. The replacements are
    longer.
  - 10-bit sad_x3/x4_min ends: the proposed in-lane end saves 2 ops but adds 1 cycle of
    latency to a branch-feeding result. Rejected.
  - pixel_sad_8x8/8x16 (8-bit), sad_avg2, sad_x3 16xN (8-bit), sad_x3/x4 8xN (both depths)
    and 10-bit sad 16xN/8xN: load-minimal already.
  - The 10-bit 8xN XEND pmaddwd variant is neutral (+1 latency).
  - intra_sad_x3/x9 (both depths): subme <= 1 only, so cold. The 10-bit intra_sad_x3_8x8 ymm
    phaddw is left: no gain from the 13-uop form.
- **SSD / VAR**
  - ssd 16xN/8xN (10-bit), ssd 16xN (8-bit), ssd_nv12: FP-bound or per-frame.
  - 8-bit ssd 8x8/8x16 avx2 (undispatched): a vpbroadcastq+vpblendd rewrite and a
    re-dispatch are possible. Not done; it needs a 3-CPU bench to re-dispatch.
  - var 16x16/8x16 (10-bit) chains, VAR_END/VAR2_END merges, 10-bit var_8x8 avx2: small, per
    MB. Not done.
- **SATD / SA8D / HADAMARD**
  - 8-bit satd/satd_avg2/satd_pre/satd_fenc_pre/satd_bi 8-wide: no crossings, nothing to cut.
  - 10-bit sa8d_16x16: no finding. The "word sums" comment there is stale (it produces
    dwords).
  - 10-bit sa8d_8x8 (S) loads: the macro is shared with an ICL_LOW avx512icl instance, so it
    was left (the brief forbids touching ICL_LOW kernels).
  - intra_satd_x3 ymm fold tails (both depths): shared with the ICL_LOW instance. Left.
  - 10-bit sa8d_satd tails, SA8D_SATD_8x4 movas, hadamard_ac FIXME-SWAP movas: renames or a
    couple of ops. Not done.
  - hadamard_ac_8x8 avx2 phaddd + scalar tail packing: about 4 uops. Not done.
  - 10-bit satd_bi/bi4 (S)/(B) loads, intra_satd_x3_8x8c/16c (B) loads: (B) adds a uop on
    Zen 4. Not done.
  - satd 8x4/4x4 chroma at AVX2 are still xmm. A U+V paired kernel needs an API change. Not
    done.
- **QUANT / DCT / CABAC**
  - The 8-bit add16x16_idct8 avx2 proposal: REJECTED. add16x16_idct8 has no caller in
    encoder/; the encoder calls add8x8_idct8 per block.
  - quant_4x4x4_scan dequant / score vpermq q3120, decimate_score64, coeff_last64 (8-bit),
    trellis NZ_MASK vpermq: same uops on Zen 3, latency only, and +1 uop on Zen 4 where the
    kernel runs there. Not done.
  - 10-bit quant_4x4x4_scan / zigzag 4x4 vpermd: no cheaper exact form.
  - denoise_dct pmaxsd: --nr only. Not done.
  - The cabac 8x8 RD residual prologue avx2 instance (Zen 3, scalar-dominated): not done.
  - coeff_level_run avx2: CAVLC only.
  - Note from the quant reader: `QUANT_TWO_AC_AVX2` and the scan kernels shift
    (|coef|+bias)*mf with psrad where C uses an unsigned >>16. They match while the product
    is < 2^31; worth checking against the MAX_MF bound (not a change here).
- **MC / LOWRES**
  - 8-bit fused hpel_filter: three things are possible, about 15-18% of the kernel:
    - native-lane C windows (drops 4 lane crossings and a vpermq);
    - memory H windows;
    - a dedicated pw_512 register.
    Not done in this pass: a large restructure of a shared SSE/AVX2 macro, and the H windows
    need a bench (split-line loads). It runs on Zen 4 too, so it is a good next item.
  - avg_weight_w8 (8-bit) broadcast+blend, mc_*_avg_wN w8 movhps, avg2_w18 pavgw folding,
    load_deinterleave_chroma_fenc avx2, the AVG_FUNC unroll, mbtree_propagate_list ymm: small
    or bench-gated. Not done.
  - 8-bit mc_luma still uses the sse2 avg2 table at AVX2. Moving it is a dispatch change; not
    done.
- **DEBLOCK / MISC**
  - LUMA_INTRA_P012 vpblendvb (Zen 3 luma intra): the "old" operand can be a memory operand,
    and vpblendvb needs it in a register. Not done.
  - 10-bit deblock_v_luma_intra avx2 one-pass instance: the same dependent-call caveat as
    h_luma. Not done.
  - deblock_strength constant hoist, luma_mb alpha/beta re-broadcast, 8-bit luma_mb hoists:
    negligible.
  - weightp_dc8x8 avx2, pixel_ads, ssim, asd8: cold, or no caller (asd8). predict avx2:
    store-bound, minimal.
- **Rodata**: every 32-byte table loaded by the AVX2 kernels in all families is 32-aligned,
  except trellis pd_04152637 (fixed above).

Equivalent mutants seen, each explained by the layout:
- lowres qdq->dq and x9 hu wd/dq: the totals are only permuted.
- sad16 x3 self-interleave partner: the unused dwords change.
- sum8_nv HADD4W last paddw->paddd: no carry under the < 65536 bound.
- satd_mcc w4 table broadcast of mcc_ch_shuf8: lane 0 is the same.

## rack01 (Zen 4) job list

rack01 has about 2 GB free, so every dump and bulk output goes to /dev/shm.

**1. checkasm --bench**: base = speed-next 64bc7552, new = wip/x264-avx2-pass tip. Build
both with `--bit-depth=all`. Run 11 interleaved runs of checkasm8 and checkasm10 for each,
same binaries, and take the median per row. Rows: every kernel in the tables above, at the
level rack01 dispatches and at avx2 (checkasm benches every level).
- The deblock dispatch decision reads the base binary's avx vs avx2 rows of the 10-bit
  deblock h_luma, h_chroma and h_chroma_intra (and h_chroma_422 for information).
- Also the base binary's 10-bit h_luma avx vs avx512icl rows (Zen 4 runs avx512icl; an
  earlier laptop run had it slower than avx).
- Pass: no changed kernel slower than base beyond noise. A loser is dropped (each commit
  stands alone).
- sad_x4 16xN (8e0b1e18) and the pixel_avg2_w16 swap (d531ace0) are bench-gated.

**2. md5 identity**: `--threads 1` on the 8 A/B cells (8l/8n/10l/10n x prog/il), new tip vs
speed-next 64bc7552. Write the recon to /dev/shm and record md5 of the bitstream and the
recon. Pass: identical md5 in all 8 cells. No RC float code changed, so the -fno-fast-math
build is not required.

**3. Optional, in situ**: CPU per frame, paced at 60 fps, on the 10-bit 4:2:2 and 8-bit cells
(lowlat and normal), new vs base. This needs .93 (Zen 3) for the AVX2-only gains: at most
of the changes above, Zen 4 runs avx512icl instead.
