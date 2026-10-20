# x264-obe unusual-instruction pass: pixmisc (pixel-a.asm, non-satd)

Branch `wip/x264-weird-pixmisc`, base origin/speed-next 0ac92fa9 (2026-10-20).
zmm variants: `zen5/x264-weird-pixmisc-zmm`.

Everything here is at `X264_CPU_AVX512ICL` (cpu.c:185), x86_64 only, braced
`if( cpu&X264_CPU_AVX512ICL ) { ... }` blocks in common/pixel.c (one per depth).
All dispatched kernels are ymm (EVEX, ymm16-31 per x86inc); zmm ones are assembled,
not dispatched.

## Method

- Correctness: checkasm 8 and 10 bit, seeds 1001 2002 3003, all pass. Coverage added
  where the test could not fail (see below). Every new kernel was broken on purpose
  (one instruction or one table byte) and checkasm failed each time; restored, it passes.
- Encoder identity: `--threads 1 --asm avx512icl`, CABAC, both builds
  `-fno-fast-math -ffp-contract=off`, stressgen 1080p (720p for ESA/TESA), 18 cells:
  8-bit 4:2:0 and 10-bit 4:2:2, progressive and tff, lowlat (veryfast zerolatency
  --intra-refresh, one-frame VBV) and normal (medium, 1 s VBV, weightp 2, 3 B), RD
  (subme 10 trellis 2), --me tesa/esa, --ssim --psnr. All 18 md5 identical base vs
  branch, SSIM/PSNR lines identical. A 19th cell (10-bit 4:2:2 chroma-motion) differs,
  and only because of the var2 fix below: base+fix alone gives the branch's md5.
- Reached: a counting build (wrappers on every new pointer) shows the encodes call
  ads4/2/1, var 16x16/8x16/8x8, var2 8x8/8x16, ssd 16x16/16x8/8x16 (and 10-bit 8x8),
  weightp_dc8x8, weightp_stats8, weightp_sum8, ssim core (millions of calls each for
  the hot ones). Not reached at --threads 1: weightp_sum8_nv (only when the AQ pass's
  chroma sums can't be used, `ops->k != h`, i.e. lookahead threads) and
  weightp_sum8_clip (only for chroma blocks that may clip); checkasm covers both
  (n 1-40, heights 8/16, denom 0-7, scale 0/127/random, offsets -128/127/0/random).
- Speed: laptop only (HX 370, WSL, zmm double pumped), a private harness: rdtsc
  (TSC ticks, not core cycles) per call, min over 3000 blocks of 64 calls, min of 3
  runs, CPU 10. The box was loaded (load ~20 of 24), so only same-run comparisons
  count; numbers move 10-30% between runs. Indicative only; rack01 decides.
- nasm: every changed file assembles with ~/tools/nasm-2.14.02 at both depths, with and
  without -DPIC; the disassembly of every new function is identical to nasm 3.01's
  (the only 2.14/3.01 difference in pixel-a.asm is satd_mcc's movsxd vs cltq). No new
  instruction needs a nasm newer than 2.14.02 (vpdpbusd, vpdpwssd, vpcompressw,
  vpermt2b/d, vpcmpuw/d, kord, kmovd, vmovdqu16 {k}, vinserti32x4/64x4, bzhi, popcnt).

## Per function

Ticks: laptop rdtsc per call, base (best dispatched before) -> new.

| function | current best level (base) | unusual instructions considered | tried? | bit-exact? | laptop ticks base -> new | decision | reason |
|---|---|---|---|---|---|---|---|
| pixel_ads4 | avx2 (+ssse3 ads_mvs) | VBMI2 vpcompressw (reg) + masked vmovdqu16, kmask compares, kord, BMI2 bzhi, popcnt; pdep/pext; VP2INTERSECT | yes | yes | 8b 22.5 -> 9.7, 10b 25.0 -> 15.9 (width 36) | dispatched (ymm); zmm on zen5 | one pass, no mask buffer, no 4 KB shuffle table; only --me esa/tesa reach it |
| pixel_ads2 | avx2 | as ads4 | yes | yes | 8b 20.3 -> 7.2, 10b 21.9 -> 10.6 | dispatched (ymm); zmm on zen5 | as ads4 |
| pixel_ads1 | avx2 / ssse3 | as ads4 | yes | yes | 8b 19.1 -> 6.6, 10b 20.9 -> 9.1 (zmm 7.8) | dispatched (ymm); zmm on zen5 | as ads4; 10-bit zmm is faster on the laptop too, kept ymm for Zen 4 |
| pixel_ads_mvs (mmx, ssse3) | ssse3 | vpcompressw, pext | via ads | n/a | n/a | superseded at avx512icl | the avx512icl ads compact in-loop; ads_mvs stays for the older levels |
| pixel_var_16x16 | avx2 | VNNI vpdpbusd (x*1, x*(x^0x80) = x*x-128x), vpdpwssd | yes | yes | 8b 11.2 -> 6.6, 10b 13.8 -> 10.3 | dispatched | AQ, every MB. zmm: 8b 10.3 (worse than ymm), 10b 9.4 (better) -> zen5 |
| pixel_var_8x16 | avx2 | as 16x16 | yes | yes | 8b 6.9 -> 5.6, 10b 6.9 -> 6.2 | dispatched | 4:2:2 chroma AQ |
| pixel_var_8x8 | 8b avx2, 10b avx (xmm) | as 16x16 | yes | yes | 8b 4.1 -> 3.8, 10b 5.0 -> 4.1 | dispatched | 4:2:0 chroma AQ |
| pixel_var_* avx512 (zmm, existing) | not dispatched since d0395c5b/bc4042cd | - | - | - | 8b 14.4, 10b 11.9 (16x16) | unchanged | left as is |
| pixel_var2_8x8 | avx2 | vpdpwssd | yes | yes | 8b 6.6 -> 6.2, 10b 5.9 -> 5.6 | dispatched | chroma early termination, inter MBs |
| pixel_var2_8x16 | avx2 | vpdpwssd | yes | yes | 8b 10.6 -> 9.7, 10b 9.7 -> 8.8 | dispatched | as 8x8; bug fixed in the shared end (below) |
| pixel_ssd_16x16 | avx2 | 8b: \|d\| bytes + vpdpbusd (\|d\|*(\|d\|^0x80) + 128*sum\|d\|); 10b: vpdpwssd | yes | yes | 8b 11.9 -> 10.9 (other runs 16.2 -> 14.1), 10b 7.8 -> 7.5 | dispatched | RD. 8b small win, 10b neutral. zmm slower on laptop (8b 16.9, 10b 10.9) -> zen5 |
| pixel_ssd_16x8 | avx2 | as 16x16 | yes | yes | 8b 6.6 -> 6.6, 10b 4.4 -> 4.1 | dispatched | neutral; zmm slower on laptop -> zen5 |
| pixel_ssd_8x16 | 8b avx (xmm; avx2 undispatched by ce584404), 10b avx2 | as 16x16 | yes | yes | 8b 9.1 -> 9.1 (other run 12.5 -> 10.6-12.2), 10b 7.5 -> 7.5 | dispatched | 4:2:2 chroma RD; neutral to slightly better |
| pixel_ssd_8x8 | 8b avx, 10b avx2 | as 16x16 | yes | yes | 8b 5.3 -> 5.6, 10b 4.1 -> 4.1 | 10b dispatched; 8b assembled only | 8-bit no faster than avx (6.9 vs 6.9-7.8 in another run) |
| pixel_ssd_4x4/4x8/4x16 | ssse3/mmx | vpdpwssd | no | - | - | rejected | 16-64 pixels; one VNNI op saves a pmaddwd+paddd at most, prologue dominates |
| pixel_ssd_nv12_core | avx2 | vpdpwssd (replaces pmaddwd+paddd), IFMA for the 64-bit sums | no | - | - | rejected | only the PSNR statistic (--psnr) calls it; IFMA does 4 products a ymm vs pmaddwd's 16 |
| pixel_ssim_4x4x2_core | avx (xmm) | vpdpbusd (8b, x^0x80 and a*(b^0x80) tricks), vpdpwssd (10b) | yes | yes | 8b 5.9 -> 4.7, 10b 5.3 -> 4.4 | dispatched | only --ssim reaches it |
| pixel_ssim_end4 | avx | IFMA, vpdpwssd | no | - | - | rejected | float maths on 4 lanes; 10-bit C is float, so an integer IFMA version can't match it; 8-bit saves one paddd |
| pixel_asd8 | ssse3/xop | vpdpbusd by +-1 (as weightp_dc8x8) | no | - | - | rejected | no caller left in the encoder (the chroma weightp rewrite replaced it) |
| weightp_dc8x8 | sse2 | 8b vpdpbusd pix1 by 1 and pix2 by -1 (4-pixel row sums, no unpack); 10b vpdpwssd | yes | yes | 8b 5.6 -> 4.4 (8.4 -> 5.6 other run), 10b 4.7 -> 4.4 | dispatched | luma weight search |
| weightp_stats8 (8-bit) | avx2 (words) | VBMI vpermt2b + k zeroing (min\|max<<16 pack), vpermt2d | yes | yes | old avx2 218 -> new avx2 88.8 -> avx512icl 81.6 (n 60) | AVX2 rewrite + avx512icl dispatched | bytes: psadbw sums, pminub/pmaxub, per-qword reduction; vpermt2b/d replace 7 ops of packing |
| weightp_stats8 (10-bit) | avx2 | vpermt2w pack | no | - | 179 (unchanged) | rejected | words already; the final pack is a small part |
| weightp_sum8 (8-bit) | avx2 | words (x*scale+round fits) + vpdpwssd accumulate | yes | yes | 294.7 -> 186.6 (h8), 584 -> 361 (h16) | dispatched | chroma weight cost |
| weightp_sum8_clip (8-bit) | avx2 | as weightp_sum8 + pmaxsw/pminsw | yes | yes | 133.8 -> 74.4 (n 16) | dispatched | as above |
| weightp_sum8 / _clip (10-bit) | avx2 | vpdpwssd | no | - | 249.7 / 120 | rejected | x*scale exceeds a word; the per-pixel >> denom (and clip) sits between the multiply and the sum, so VNNI can't fuse it |
| weightp_sum8_nv (8-bit) | avx2 | vpdpbusd by 1,0,1,0 / 0,1,0,1 (u, v sums straight from bytes) | yes | yes | 188 -> 121 (n 60) | dispatched | fenc chroma sums for weightp |
| weightp_sum8_nv (10-bit) | avx2 | vpdpwssd by 1,0 / 0,1 | no | - | - | rejected | one paddw per 16 words beats two vpdpwssd |
| pixel_vsad | avx2 (sad-a.asm / sad16-a.asm) | VNNI, GFNI | no | - | - | not edited | lives in the sad package's files; 8-bit is psadbw already, 10-bit psubw/pabsw/paddw: no unusual fit |
| intra_sa8d_x3_8x8, hadamard_load | sse2/avx, mmx | vpermw transposes | no | - | - | not edited | Hadamard (satd family); lesson: vpermw transposes lose to punpck |
| intra_satd_x3_* (mmx), pixel_satd_mcc(_fenc_pre) | - | - | - | - | - | satd package | intra_satd_x3 / pixel_satd* are the satd agent's |
| pixel-32.asm | - | - | - | - | - | not reachable | x86_64-only build (Makefile assembles no pixel-32.asm) |

Dispatched per depth (avx512icl block):
- 8-bit: ads, var x3, var2 x2, ssd 16x16/16x8/8x16, weightp_dc8x8, weightp_sum8_nv,
  weightp_stats8, weightp_sum8, weightp_sum8_clip, ssim core.
- 10-bit: ads, var x3, var2 x2, ssd x4, weightp_dc8x8, ssim core.
- AVX2 (both CPUs): 8-bit weightp_stats8 on bytes (ef75150f).

8-bit note: speed-next deliberately had no 8-bit AVX-512 pixel functions after a rack01
ablation (~1.5% slower 8-bit encodes, from the avx512-level zmm kernels). These are ymm
VNNI/VBMI2 kernels; 8-bit encodes already run avx512icl trellis and cabac residual
kernels (both in the 8-bit profile of the md5 cells), so ymm16-31 are dirty either way,
but only an in-situ A/B on rack01 can clear them. The pixel.c comment says so.

## Unusual instructions

- VNNI (vpdpbusd, vpdpwssd): used in var, var2, ssd, ssim core, weightp_dc8x8,
  weightp_sum8_nv, weightp_sum8/_clip. The u8 x s8 operand rule is met with x ^ 0x80
  (= x - 128 as a signed byte): x*x = x*(x^0x80) + 128x, a*b = a*(b^0x80) + 128a, exact.
  At least two accumulators everywhere (the x265 lesson); the single-chain ones are 2-4
  deep per call.
- VBMI2: vpcompressw, register form + masked vmovdqu16 store (never the memory form):
  ads. VBMI: vpermt2b with k zeroing builds weightp_stats8's min | max << 16 in block
  order in one instruction.
- Mask registers: ads (vpcmpuw/vpcmpd to k, kord for the 17-bit carry case, kmovd,
  bzhi tail), stats8 (zeroing mask), masked stores.
- BMI2: bzhi (ads tail and store mask), scalar popcnt on the kmask. pdep/pext: not
  needed, vpcompressw does the compaction in-register (x265's pdep win was over a bit
  loop that x264's ICL ads no longer has).
- vpternlogd: only as an all-ones constant, and see the hazard below.
- No use: GFNI (no per-byte shifts or bit-matrix work in these kernels: the 8-bit paths
  are min/max/sub, psadbw and byte multiplies), BITALG / VPOPCNTDQ (one scalar popcnt
  per kmask suffices), CD (no conflict or leading-zero work), IFMA (ssim_end4 is float
  in 10-bit C; 64-bit sums in ssd_nv12 would get 4 products a ymm instead of 16),
  VAES/VPCLMULQDQ (nothing cryptographic or carry-less).

## VP2INTERSECT

No use found. Nothing in this package intersects two index or value sets: ads is a
threshold compare plus compaction (vpcompressw), ads_mvs is the compaction alone, and
the rest are sums, squares, min/max. Not prototyped.

## Bugs and findings in existing code

1. **High bit depth var2_8x16 overflow (fixed, e291feff).** VAR2_END squared the 8x16
   difference sum in 32 bits (pixel-a.asm VAR2_END, `imul r1d, r1d`). At 10-bit |sum|
   reaches 128*1023, so for a mean difference >= 512 sum*sum passes 2^32: all +1023
   differences gave var 100663296 instead of 0. C squares in uint64_t. Reached by
   macroblock_encode's chroma early termination (`var2[PIXEL_8x16]`, 4:2:2): in a
   10-bit 4:2:2 stressgen chroma-motion encode 48898 of 1031646 var2_8x16 calls had
   |sum| >= 65536 (extremes 6, cut-storm 153). The encode's md5 changes with the fix
   (base bcdebcec..., base+fix = branch 8c0ddeb8...): asm now decides as C. All levels
   (sse2, avx2, avx512icl) share the macro. Production (10-bit 4:2:2) is affected;
   the fix commit cherry-picks on its own (also pushed as
   `fix/x264-var2-8x16-hbd-overflow`).
2. **vpternlogd x, x, x, 0xff is not dependency breaking** (found on the laptop, Zen 5
   mobile): resetting an all-ones min register with it each pass chained every pass on
   the previous pass's result and made weightp_stats8 30% slower than AVX2; a constant
   register set once fixed it. The ALL_ONES macro (WEIGHTP_STATS8's mmsize == 64 path)
   does exactly this per pass; the zmm weightp_stats8 was dropped in 9ddb5d1f as 8%
   slower on Zen 4, so a retest of zen5/weightp-avx512 with the fix may change the
   verdict. trellis-64.asm:1715 (cabac package) does it once per call: small.
3. **checkasm gaps (fixed):** var was only tested on random pixels; var2 never on
   large same-sign differences (which is why bug 1 survived); ads at one width (28)
   and random thresholds only (an lt -> le mutation passed); ssim compared only the
   float result. At the ssim test, pbuf3 holds values above PIXEL_MAX in 10-bit (left
   by earlier tests), so extreme cases must fill their own buffers.
4. The ssse3 ads_mvs writes 16 bytes at mvs+nmv (past the last candidate) and the
   pre-ICL ads use the mvs buffer past width as their mask scratch: by design (me.c
   sizes xs for it), noted only because the ICL version writes exactly nmv entries.

## Commits (wip/x264-weird-pixmisc)

- 787ebd80 checkasm: ads over several widths and at the threshold boundaries
- b597a2ed x86: avx512icl ads1/ads2/ads4 with vpcompressw, no mask pass
- e291feff x86: high bit depth var2_8x16: square the sum in 64 bits (bug fix + checkasm)
- 69389dc8 x86: avx512icl var 16x16, 8x16, 8x8 with VNNI
- b92c2ac7 x86: avx512icl var2 8x8 and 8x16 with vpdpwssd
- 5c552856 x86: avx512icl ssd 16x16, 16x8, 8x16, 8x8 with VNNI
- 1d872d32 x86: avx512icl weightp_dc8x8 with VNNI
- f40cd577 x86: avx512icl 8-bit weightp_sum8_nv with vpdpbusd
- ef75150f x86: 8-bit AVX2 weightp_stats8 on bytes
- f68f056a x86: avx512icl 8-bit weightp_stats8, VBMI vpermt2b packing
- a1896cec x86: avx512icl ssim_4x4x2_core with VNNI
- 3c036b79 x86: avx512icl 8-bit weightp_sum8/weightp_sum8_clip on words + vpdpwssd
- 807b2c8a x86: zmm avx512icl var_16x16 and ssd_16x16/16x8, assembled only

## Needs rack01 (Zen 4)

- checkasm --bench of every function above, 8 and 10 bit (laptop is not a server).
- In-situ A/B (8-bit lowlat and normal, 10-bit 4:2:2 incl. 1080i) of the avx512icl
  dispatch against speed-next: 8-bit had no AVX-512 pixel functions on purpose. Neutral
  ones (ssd 16x8/8x16, 10-bit ssd) stay parked unless they win on Zen 4.
- The var2 fix (bug 1) changes 10-bit 4:2:2 output; it is a correctness fix and should
  go to speed-next on its own whatever the speed results.
- zen5/x264-weird-pixmisc-zmm: zmm ads, var_16x16, ssd_16x16/16x8 dispatched, for a
  full-width zmm box.

## Round 2 (2026-10-20): every rejected candidate written and dispatched

Branch `wip/x264-weird2-pixmisc`, base origin/wip/x264-weird-sa8d8 67b4aff6. Kieran's
rules: nothing is rejected by the agent, every candidate is dispatched, and rack01 moves
slow ones to zen5/. One commit per kernel; where a new kernel takes a slot held by a
round-1 kernel, the commit overrides the slot and says so, so dropping that commit
restores the round-1 kernel.

Method (laptop on battery: no configure, no make, no encoder):
- Single-file nasm of pixel-a.asm at both depths, linked into a standalone C driver
  (scratchpad w2pm-drv.c) that compares each kernel with the C reference copied from
  common/pixel.c. Inputs come in six modes: random, PIXEL_MAX vs 0 random (+-max
  residual), near max, alternating extremes, all 0, and all PIXEL_MAX vs 0 (same-sign
  maxed). Strides and offsets are random. Before every kernel call the driver clobbers
  k1-k7, so no kernel can rely on masks left by the previous one. One mutation only
  failed once this was added.
- PROT_NONE guard page after the last input byte: ssd 4xN, ssd_nv12, asd8, ssim_end4,
  vsad. Sanity check: the AVX2 ssd_nv12 (over-reads by design) faults there.
- gdb 17.1 ABI check (scratchpad w2pm-abi.py) at each kernel's entry and return:
  rbx rbp r12-r15 and rsp are preserved, and ymm0-15 are either unchanged or have zero
  upper halves (vzeroupper). For float returns, the upper half of ymm0 must be zero.
  Sanity check: an injected rbx change is caught. Every new kernel passes with "ymm0-15
  unchanged": none of them touches ymm/zmm0-15.
- Mutations: at least one instruction or table byte broken per kernel, rebuilt and
  run; every one was killed (listed below).
- nasm 2.14.02: both whole objects disassemble identically to nasm 3.01's, apart from
  the known satd_mcc movsxd/cltq and its padding. The full driver passes on the 2.14.02
  objects. No instruction needs a newer nasm (vpdpwssd, vpdpbusd, valignq, vpermi2d,
  vpermt2w/b, vbroadcasti32x4/64x4 {k}, vmovdqu8 {k}{z}, kmovb/w/q, kaddb, kshiftlw,
  kshiftrq, kortestq, bzhi, pdep, pext, shlx). No vpshldv/vpshrdv.
- checkasm additions (tools/checkasm.c, C99): ssd_nv12 widths 8-72 pairs (every row
  length mod 64 bytes), random and PIXEL_MAX vs 0; ssim_end4 at widths 1-4 against C;
  asd8 at heights 4-16, PIXEL_MAX vs 0 either way.
- Later on AC power: configure --bit-depth=8 and =10 (--enable-pic, -no-pie link), checkasm8
  and checkasm10 at seeds 1001, 2002, 3003 on tip 95893a5c: all pass, AVX512 and
  AVX512ICL levels included. 13 mutations rebuilt into the real checkasm all failed it,
  and each restored build passed again. They cover: the nv12 tail mask, the ssim_end4 width
  mask, asd8, the 10-bit sum8_clip offset fold, the 10-bit stats8 vpermt2w table, ads
  pext imul, vsad valignq and the 10-bit vpdpwssd, the zmmb k2 shift and the 10-bit k1
  broadcast, ssd 4xN kaddb, the 8-bit zmm stats8 table, 10-bit sum8_nv, and the zmm
  avx512 stats8 constant. A swapped 10-bit vsad psubw survived; it is equivalent under
  pabsw, so it is not a real mutation. No encoder md5 runs (not part of round 2).

| function | round-1 decision | round-2 action | commit | driver (cases; mutations) | nasm 2.14.02 |
|---|---|---|---|---|---|
| pixel_ssd_8x8 (8-bit) | assembled only | dispatched (VNNI vpdpbusd) | 0a0df1ed | pass, 6 modes x 2000; psubb->paddb killed | ok |
| pixel_ssd_8x4 | (missing row) | written: SSD_ICL 8x4 both depths | 9f117f4e | pass; 8-bit psubb->paddb, 10-bit vpdpwssd operand killed | ok |
| pixel_ssd_4x4/4x8/4x16 | rejected (prologue dominates) | written: 4 rows a register by merge-masked vpbroadcastd/q {k1-k3}, 8-bit pmovzxbw, vpdpwssd into 2 accumulators | 3413ca74 | pass + guard; pmovzxbw->pmovsxbw, k2->k1, kaddb k3 killed | ok |
| pixel_ssd_nv12_core | rejected (PSNR only) | written: 64 B a step, zero-masked tail loads (bzhi/kmovq/kshiftrq), 8-bit \|d\| split u/v + vpdpwssd, 10-bit d*(d&0xffff) and d*d, qword sums | cf114410 | pass (widths 0-200, heights 1-20, 1920x20) + guard; psrlw, pand->por, psubd->paddd, k2 shift killed | ok |
| pixel_ssim_end4 | rejected (float, 4 lanes) | written: 2 ymm loads + 6 adds, vpermi2d transpose, vdivps {k}{z} width mask (no table, no branch), 8-bit vpdpwssd for s1^2+s2^2+c1; bit-identical to the avx version | 07c8ce34 | pass (bit-exact vs avx, 1e-5 vs C, widths 1-4) + guard; perm operands, pf_128, paddd->psubd, mask 15->7 killed | ok |
| pixel_asd8 | rejected (no caller) | written: 8-bit vpdpbusd by 1 per image, 10-bit vpdpwssd of the difference, 2 accumulators | 33ac64ea | pass (heights 4-32) + guard; psubw, row offset, psubd, pabsd killed | ok |
| weightp_stats8 zmm (10-bit) | dropped 9ddb5d1f (rack01 +8%) | re-instantiated INIT_ZMM avx512 with the all-ones min reset hoisted (m15 set once; ALL_ONES copies it) | 129b8386 | pass; m15 copy->pxor, perm table killed | ok |
| weightp_stats8 zmm (8-bit) | (round-1 bytes kernel was ymm) | bytes kernel at zmm, 16 blocks a pass, vpermt2b/vpermt2d 64 B tables; overrides the round-1 ymm slot | bef54fb3 | pass; 4 table/mask mutations killed | ok |
| weightp_stats8 (10-bit) | rejected (pack is small) | ymm avx512icl: row 0 seeds sum/min/max (no all-ones), punpck-ladder min/max of 4 registers (11 ops each instead of 4x12), one vpermt2w pack; overrides 129b8386 on ICL | a64b84b3 | pass; table byte, row count, punpckhqdq, punpckhwd killed | ok |
| weightp_sum8_clip (10-bit) | rejected (VNNI can't fuse the shift) | vpdpwssd straight from memory by {scale,0}/{0,scale} onto round + (offset << denom) (exact: the shift floors); 10 ops per 16 px instead of 15 | 33ee3a7e | pass, including negative scales (strict); offset fold, lane shift, clip, scale zero-extension killed | ok |
| weightp_sum8 (10-bit) | rejected (as above) | same macro without the clip: 6 ops + 2 moves per 16 px, no punpck pair | 9275bfc4 | pass, negative scales; rounding and lane mutations killed | ok |
| weightp_sum8_nv (10-bit) | rejected (paddw beats 2 vpdpwssd) | vpdpwssd from memory by {1,0} and {0,1}, 4 blocks a pass, 8 accumulators, no split | 440db5e8 | pass; offset, shift, step killed | ok |
| pixel_ads4/2/1 pdep/pext | (lesson: x265 P4) | written: per 8 candidates pdep(mask,0x01..)*255 then pext of 0x0706..00, movq/pmovzxbw/+base, one 16 B store; groups past width skipped (writes stay within the 8-rounded width, as pre-ICL); overrides the zmm vpcompressw slot | 6a3b0ad5 | pass (widths 1-160, boundary thresholds, write bound) ; constant, imul, skip, popcnt killed | ok |
| pixel_ssd_16x16/16x8 zmm | round-1 zmm (per-row inserts) | _zmmb: rows by vbroadcasti32x4/64x4 {k} (lesson); _zmm code unchanged; overrides _zmm | c47edd50 | pass; mask shift, mask value, row offset killed | ok |
| pixel_var_16x16 zmm | round-1 zmm (per-row inserts) | _zmmb as above via a VAR_ICL_ZMM macro; _zmm unchanged; overrides _zmm | 81dcff66 | pass (16-px aligned, as callers); row offsets, masks removed killed | ok |
| pixel_vsad | not edited (sad files) | written in pixel-a.asm (sad files untouched): 8-bit valignq + psadbw (two row pairs a psadbw, each row loaded once), 10-bit vpdpwssd; renamed vsad_valign in 95893a5c (clash with agent C's 8-bit vsad_avx512icl) | e7b69706, 95893a5c | pass + guard; valignq imm, tail psadbw, vpdpwssd operand, mask killed | ok |
| pixel_var_* avx512 (old zmm) | unchanged | skipped: rack01 already measured and dropped them in situ (d0395c5b, bc4042cd); the slots are held by the avx512icl ymm/zmm kernels at a higher level. Kieran's call whether they go to a zen5/ branch | - | - | - |
| weightp_sum8 / sum8_nv zmm avx512 (both depths), 8-bit word stats8 zmm | dropped 9ddb5d1f | skipped: rack01-measured; kept on zen5/weightp-avx512. The 8-bit word zmm is superseded by the byte kernels (bef54fb3) | - | - | - |
| pixel_ads_mvs | superseded | skipped: no caller at avx512icl (the ICL ads compact in-loop) | - | - | - |
| intra_sa8d_x3_8x8, hadamard_load | satd family | skipped: agent C's package | - | - | - |
| pixel-32.asm | not reachable | skipped: x86_64-only build | - | - | - |

Ops in the result tail of kernels that feed a decision: ads pext 11 ops per 8 candidates
(kmov, bzhi, then movzx, popcnt, pdep, imul, pext, movq, pmovzxbw, paddw, store, add)
against round-1 vpcompressw's 7 per 16 or 32; vsad 8-bit tail 7 ops (vextracti128,
psadbw, paddd, vextracti128, paddd, punpckhqdq, paddd), 10-bit 1 paddd + HADDD.

Round-1 kernels re-checked on the maxed and sign-patterned modes (var2 8x8/8x16 icl
and avx2, weightp_dc8x8, ssim_4x4x2_core, ssd ymm, var ymm/zmm, ads ymm/zmm, stats8,
sum8): all match C.

### Findings in existing asm (round 2)

1. **AVX2 weightp_sum8 and weightp_sum8_clip, both depths, are wrong for negative
   scale** (pixel-a.asm WEIGHTP_SUM8: `shl r7d, 16; or r7d, r5d` ors a sign-extended
   scale into the rounding word: the x265 weight_pp/sp pattern). Unreachable: x264
   clips the weightp scale to 0-127 (slicetype.c x264_clip3( ..., 0, 127 ), and the
   chroma guess breaks out above 127). Not fixed. The new avx512icl kernels zero-extend
   the scale (movzx) and pass negative scales; the round-1 8-bit avx512icl ones also
   pass.
2. The driver's ads inputs first exceeded the 8-bit sums range (64*255). Out of range,
   the round-1 8-bit ads disagree with C, because the cost is 16-bit and saturated. Real
   sums are block DCs (<= 16320 at 8-bit), so this is not a bug.

### Needs rack01

checkasm --bench of every function above at both depths, then the in-situ A/B for the
slot overrides: bef54fb3 (8-bit zmm stats8 vs ymm), a64b84b3 vs 129b8386 (10-bit stats8
ymm icl vs zmm avx512), 6a3b0ad5 (ads pext vs zmm vpcompressw), c47edd50 and 81dcff66
(_zmmb vs _zmm), and vsad_valign vs agent C's vsad.
