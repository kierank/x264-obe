# x264-obe unusual-instruction pass: dbpred (deblock-a.asm, predict-a.asm)

Branch `wip/x264-weird-dbpred` on speed-next 0ac92fa9. Parked: `zen5/x264-weird-dbpred-mbaff`,
`zen5/x264-weird-dbpred-chroma422` (both on wip 6eeaafa2 / 1727d508, dispatch on).

## Method

- Laptop = HX 370 (Zen 5 mobile, 256-bit datapath), WSL, nasm 3.01, CPU 16 (17 for one run).
  Indicative only; rack01 decides.
- "loop" = private harness: each call reruns on the same pixels, so it measures the dependent
  (latency) cost, as consecutive edges are in an encode. Medians of 41 interleaved A/B rounds,
  median of 3 runs; ratio = new/old time, < 1 is faster. The harness calls through
  `x264_stack_align` and is built with `-mpreferred-stack-boundary=6`, as x264 is.
- checkasm `--bench` medians of 5 runs are listed for the deblock groups; they are noisy on this
  laptop (spreads of 2x between runs), the loop numbers are the ones to read.
- Correctness: checkasm8/10 seeds 1001/2002/3003 pass; every new kernel mutation-tested (all
  caught, see below); encoder md5 identity base vs branch (both `-fno-fast-math
  -ffp-contract=off`, `--threads 1 --asm avx512icl`, 40 frames 1080, stressgen): 12/12 cells
  identical, bitstream and recon (`--dump-yuv`):
  8-bit 4:2:0 lowlat pir-cut / extremes, normal bars-cut / tile-chaos; 10-bit 4:2:2 lowlat
  pir-cut / extremes, normal tile-chaos / chroma-motion; 1080i tff (MBAFF) field-frame-mix lowlat
  and comb normal (8-bit), field-frame-mix lowlat and ticker normal (10-bit 4:2:2).
  lowlat = veryfast zerolatency --intra-refresh, 20 Mb/s, one-frame VBV; normal = medium 1 s
  VBV, weightp 2, 3 B-frames.
- Reachability: mutating each dispatched kernel in the md5 build changes the md5 of a 20-frame
  cell (strength ref compare needs the normal cell: lowlat uses one reference), and perf
  samples land in every dispatched symbol. (All-intra `--keyint 1` encodes never deblock here.)

## Dispatched at avx512icl on the wip branch

| function | depth | old | loop new/old | checkasm old -> new |
|---|---|---|---|---|
| deblock_strength | 8, 10 | avx2 | 0.90-1.07 (median ~0.97, neutral) | 8: 25 -> 21, 10: 80 -> 4 (noise) |
| deblock_v_luma_intra | 8 | avx | 0.76 | 197 -> 95 |
| deblock_h_luma_intra | 8 | avx | 0.63 | 547 -> 256 |
| deblock_h_luma | 8 | avx | 0.70 | 396 -> 289 |
| deblock_v_luma_intra | 10 | avx | 0.68 | 231 -> 71 |
| deblock_h_luma_intra | 10 | avx | 0.76-0.86 | 423 -> 211 |
| deblock_v_luma | 10 | avx2 | 0.95 | 111 -> 104 |
| deblock_h_luma | 10 | avx2 | 0.98 (but see note 3) | 313 -> 291 |
| deblock_luma_mb | 10 | avx2 | 0.97-0.98 | 683 -> 625 |

## Per-function log

Columns: function | current best level | unusual instructions considered | tried? | bit-exact? |
laptop base -> new | decision | reason

### deblock-a.asm, 8-bit

| function | best level | considered | tried | exact | laptop | decision | reason |
|---|---|---|---|---|---|---|---|
| deblock_strength | avx2 (avx512 zmm undispatched) | vpermb, vpternlogd, k-masks, vptestmb, VP2INTERSECT | yes | yes | loop ~0.97 | dispatched | vpermb builds cur/left/top ref and nnz from 2 loads (was pshufb+vpermq+vpermd+broadcast+blend); ternlog folds xor+or; bS 2 via masked paddb. The existing zmm avx512 version is 1.42x slower on the laptop (1.74x at 10-bit) and stays undispatched |
| deblock_v_luma_intra | avx | GFNI vgf2p8affineqb, vpternlogd, vpcmpub k, masked moves | yes | yes | loop 0.76 | dispatched | [pN\|qN] ymm lanes run both sides once. Each `psrlw x,1/2 + pavgb x,0` rounding-parity pair becomes one affine (bit0 = x1^x2 / x2^x3), each `pxor+pand pb_1` one ternlog, the six pxor/pand/pxor selects two masked moves |
| deblock_h_luma_intra | avx | as above + VBMI vpermi2b | yes | yes | loop 0.63 | dispatched | 16 rows of p3..q3 -> [pN\|qN] pairs with 3 zmm vpermi2b, back with 2; no stack round trip (the old path stored 8-byte halves and reloaded 16 bytes, a store-forwarding miss) |
| deblock_v_luma | avx | vpternlogd, k-masks, symmetric lanes | yes | yes | loop 1.13 (symmetric ymm) | rejected | the p0/q0 delta is not antisymmetric (rounding), so it is computed in lane 0 and lane-swapped onto q0: that vinserti sits on the critical path. An EVEX xmm port saves ~3 of ~60 ops (ternlog NOT for pcmpeqb+pxor, OR3+vptestnmb for the mask) and was not written; the predict experiment below shows that size of saving is not measurable |
| deblock_h_luma | avx | VBMI vpermi2b, vpternlogd, k-masks | yes | yes | loop 0.70 | dispatched | h_luma_intra's transposes plus the symmetric inter filter (4th vpermi2b gives [q2\|p2] so no lane swap is needed for the masks) |
| deblock_h_luma_mbaff | avx | vpermb zmm 8x8 transpose, k-masks, ternlog | yes | yes | loop 1.02-1.07 | zen5 | `zen5/x264-weird-dbpred-mbaff`: one vpermb each way plus the xmm filter; for 8 rows the zmm vpermb + insert/extract chain is longer than the punpck transposes |
| deblock_h_luma_intra_mbaff | avx | as above + GFNI | yes | yes | loop 1.02-1.07 | zen5 | same branch, same reason |
| deblock_luma_mb | avx2 | VBMI vpermt2b 16x16 transposes, k-masks | no | - | - | rejected | 16x16 byte transpose = 8 zmm vpermt2b vs 24 punpck + 8 vpermq, ~3% of the function; the columns written back per edge with xmm stores can't be reloaded as zmm without store-forwarding misses (so 12 inserts stay), and the per-edge xmm filter is a latency chain (edge n+1 reads edge n's output) where the symmetric/k-mask filter lost (v_luma above) |
| deblock_v_chroma | avx | vpternlogd, k-masks | no | - | - | rejected | ~2 of ~25 ops saved (NOT via ternlog, OR3+vptestnmb for the mask); same size as the measured-neutral predict change |
| deblock_h_chroma (4:2:0) | avx | VBMI vpermb 8x8 transpose, ternlog | no | - | - | rejected | 8 rows x 8 bytes is one vpermb, but load (4 movhps + 3 inserts) and store (2 inserts + vpermb + 3 extracts) cost as many shuffles as TRANSPOSE4x8W_LOAD/TRANSPOSE8x2W_STORE; the same structure for luma MBAFF measured 1.02-1.07x |
| deblock_h_chroma_422 | avx | as h_chroma, 16 rows in zmm | no | - | - | rejected | not a production format at 8-bit (8-bit is 4:2:0) |
| deblock_h_chroma_mbaff | sse2 | as h_chroma | no | - | - | rejected | 4 rows; nothing to gain from 64-byte shuffles |
| deblock_v/h_chroma_intra, h_chroma_422_intra, chroma_intra_body | avx | vpternlogd, masked blends | no | - | - | rejected | CHROMA_INTRA_P0 pxor+pand -> ternlog needs a fresh copy, so 0 ops saved; the final psubb/pand/paddb select -> one masked move saves 4 ops per call, not measurable at this size |
| deblock_h_chroma_intra_mbaff | mmx2 | - | no | - | - | rejected | 4 rows of mmx; nothing to widen |
| chroma_inter_body | avx | ternlog, k | no | - | - | rejected | see v_chroma |

### deblock-a.asm, 10-bit

| function | best level | considered | tried | exact | laptop | decision | reason |
|---|---|---|---|---|---|---|---|
| deblock_strength | avx2 | as 8-bit | yes | yes | loop ~1.0 | dispatched | same code (bit-depth independent) |
| deblock_v_luma_intra | avx | vpcmpgtw k, kandw, vpblendmw, vmovdqu16 | yes | yes | loop 0.68 | dispatched | whole 16-pixel edge per ymm (was 2x8), k-mask selects instead of pxor/pand/pxor chains |
| deblock_h_luma_intra | avx | as above | yes | yes | loop 0.76-0.86 | dispatched | rows 0-7\|8-15 per ymm, lane-local TRANSPOSE8x8W both ways |
| deblock_v_luma | avx2 | vpcmpgtw k, kandw/kandnw, vpmovw2m, merge-masked paddw, vpblendmw | yes | yes | loop 0.95 | dispatched | EVEX branch of DEBLOCK_LUMA_INTER_SSE2 (tc0+ap+aq as two masked paddw, p1'/q1' by vpblendmw) |
| deblock_h_luma | avx2 | as above | yes | yes | loop 0.98 vs avx2 | dispatched | see note 3: the avx (xmm) version is faster than both on the laptop |
| deblock_luma_mb | avx2 | as above, vptestmd+kmovb | yes | yes | loop 0.97-0.98 | dispatched | AVX2 body re-instantiated; bS 0 edges by vptestmd + kmovb |
| deblock_h_luma_mbaff, h_luma_intra_mbaff | avx | k-masks, vpermt2w | no | - | - | rejected | 8 rows; word transposes by vpermt2w lose to punpck (x265 pass); k-mask savings ~5% at most |
| deblock_v_chroma | avx2 | vpcmpgtw k | no | - | - | rejected | counted: LOAD_MASK (ssse3 path) is 10 ops, the k-mask version is 10 ops; tc&mask is 3 ops either way |
| deblock_h_chroma (4:2:0) | avx (avx2 dispatched) | k-masks, vpermt2d | no | - | - | rejected | as v_chroma; a vpermt2d 4x4 dword transpose needs as many ops as TRANSPOSE4x4D. Note 3 |
| deblock_h_chroma_422 | avx2 | zmm 16 rows, vpcmpgtw k | yes | yes | loop 1.36 | zen5 | `zen5/x264-weird-dbpred-chroma422`: rows 4i..4i+3 in lane i, tc0[i] by vpbroadcastd + in-lane pshufb; halves the ops at 2x width, so it can only pay with a 512-bit datapath |
| deblock_h_chroma_422_intra | avx2 | as above | yes | yes | loop 1.27 | zen5 | same branch |
| deblock_v/h_chroma_intra, chroma mbaff/intra_mbaff, inter/intra_body | avx/avx2 | k-masks | no | - | - | rejected | as v_chroma (no op saving) |

### predict-a.asm (both depths)

| function | best level | considered | tried | exact | laptop | decision | reason |
|---|---|---|---|---|---|---|---|
| predict_8x8_ddl/ddr/vl/vr (8-bit) | avx | vpternlogd lowpass parity | yes | yes | loop 1.02 / 1.00 / 0.99 / 1.00 | rejected | PRED8x8_LOWPASS with ternlog is 4 ops instead of 6; the functions are bound by their 8 row stores |
| predict_8x8_* other directional (hd, hu, both depths; 10-bit ddl..vr) | avx/ssse3 | vpermb row generation, masked stores, ternlog | no | - | - | rejected | vpermb could make all 8 rows from the filtered edge in 1-4 ops, but storing them needs 3 extracts (rows are 8/16 bytes at FDEC_STRIDE) or masked zmm stores, and masked stores don't forward to the dct/satd loads that read fdec next; the ternlog lowpass was neutral (above). 10-bit lowpass is already paddw/psrlw/pavgw |
| predict_8x8_filter | ssse3 (8), avx (10) | vpermb column gather, ternlog | no | - | - | rejected | the left column is 8 rows at FDEC_STRIDE: gathering it into a zmm costs more loads/inserts than the 7-punpck chain; lowpass ternlog as above |
| predict_4x4_* (ddl, ddr, vr, hd, vl, hu, dc*, v, h) | mmx2/ssse3/sse2 (8), sse2/avx (10) | vpermb, ternlog, masked stores | no | - | - | rejected | 4 rows of 4 pixels, 1-10 checkasm units; only the lowpass parity (2 -> 1 op) applies |
| predict_8x8_v/h/dc/dc_top/dc_left/dc_128 | mmx2/sse2 | VNNI vpdpbusd sums | no | - | - | rejected | psadbw already sums 8 bytes per op; nothing to widen in 8 rows of 8 |
| predict_8x8c/8x16c v, h, dc, dc_top, dc_left, dc_128 | mmx/sse2/ssse3/avx2 | vpbroadcastb, vpermb | no | - | - | rejected | store-bound; vpbroadcastb from memory is plain AVX2 (already used at 10-bit) |
| predict_8x8c_p_core, 8x16c_p_core, 16x16_p_core | avx2 | zmm width, IFMA | no | - | - | rejected | plane is i00 + b*x + c*y in words: no unusual instruction applies (pmullw/paddw suffice, IFMA is 52-bit); zmm only widens rows (zen5 material, not written) |
| predict_16x16_v/h/dc_core/dc_top/dc_left_core/dc_128 | sse/ssse3/avx2 | - | no | - | - | rejected | store-bound broadcasts and psadbw sums |

## Unusual instructions: summary

- **GFNI** (vgf2p8affineqb): used. The 8-bit intra luma filter's three `psrlw+pavgb 0` rounding
  parity steps per side become one affine each (only bit 0 is consumed, and
  bit0(((x>>1)+1)>>1) = x1^x2, bit0(((x>>2)+1)>>1) = x2^x3 are linear). No other byte shifts in the
  package: the 8-bit inter/chroma filters are pavgb-based.
- **VBMI** (vpermb/vpermi2b): used for deblock_strength byte gathers and the 8-bit h_luma(_intra)
  16-row transposes; tried for MBAFF 8-row transposes (zen5) and rejected for 8-row chroma and
  the 16x16 luma_mb transposes (counted).
- **vpternlogd**: used (parity masks, OR3, NOT, xor+or accumulate). Not measurable alone.
- **k-masks** (vpcmpub/vpcmpgtw, kand/kandn, vpmovb2m/w2m, vpmovm2b, vptestm/nm, masked
  moves/adds, vpblendmw, kmovb): used throughout. Independent compares + kand beat chains of masked
  compares (lower latency). In the 10-bit chroma filter they save no ops.
- **AVX-512BW in xmm/ymm only**: every dispatched kernel is ymm (or zmm only for the vpermi2b
  transposes); full-zmm kernels are on the zen5 branches.
- **VBMI2** (compress/expand, vpshld/vpshrd): no use; no sparse data or concatenated shifts
  (palignr covers the predict edge shifts).
- **BITALG / VPOPCNTDQ / popcnt**: no use; bS and masks are per position, never counted.
- **VNNI**: no use; the only sums (predict DC) are psadbw.
- **IFMA**: no use; plane prediction products fit in 16 bits.
- **CD (vpconflict/vplzcnt)**: no use; no indices or leading zeros.
- **BMI2 pdep/pext**: no use; the only k-mask that goes to a GPR is luma_mb's 8-edge bS-0 mask (kmovb).
- **VP2INTERSECT**: no use found. deblock_strength compares each scan8 position with its left
  and top neighbour element-wise (ref and mv per list); x264 does not do the spec's cross-list
  reference-set matching (the bS 1 test is the conservative element-wise one), so there are no
  two sets to intersect. predict has no index sets.

## nasm

Every changed .asm (wip and both zen5 branches) assembles with nasm 2.14.02 and 3.01 at both
depths. Instructions used that 2.14.02 accepts: vgf2p8affineqb, vpermb, vpermi2b, vpternlogd,
vpcmpub, vpcmpgtw, vpmovb2m, vpmovw2m, vpmovm2b, vptestmb, vptestmd, vptestnmd, kandd, kandnd,
kandw, kandnw, kmovb, kmovd, vpblendmw, vmovdqu8/16, vinserti32x4/64x4, vextracti32x4/64x4.
None needs a newer nasm.

## Bugs and coverage

- checkasm: a deblock_strength-only change was tested but `deblock` was not reported under its
  cpu flag (`used_asm` was never set for it). Fixed, 70f2ec99.
- checkasm: no deblock test reached the PIXEL_MAX clip of p0'/q0' at 10-bit (a 10-bit kernel with
  the upper clip deleted passed). Half the full-range cases are now PIXEL_MAX - (0..15),
  253df003; every existing kernel passes with it.
- No bug found in existing deblock/predict asm.
- Trap (not a bug today): the 10-bit DEBLOCK_P0_Q0 macro takes `[pw_4]` and
  `[pw_pixel_max]` as full-width memory operands; those constants are 32 bytes, so an INIT_ZMM
  instantiation reads past them (the zen5 chroma422 kernel broadcasts them instead).

## Notes for rack01

1. Everything above is from a 256-bit-datapath laptop; rack01 (Zen 4) A/B of the wip tip vs
   0ac92fa9 decides. deblock_strength and the 10-bit v/h_luma, luma_mb changes are within a few
   percent and may come out neutral.
2. The zen5 branches lose 2-36% on the laptop and need a full-width zmm Zen 5 box.
3. Ordinary finding, not changed: at 10-bit the AVX2 h_luma, h_chroma (4:2:0) and h_chroma_intra
   are ~1.24x SLOWER than their AVX (xmm, two 8-row passes) versions in the dependent-call loop
   (h_chroma_422 avx2 1.06x, v_chroma avx2 0.93x). The avx512icl 10-bit h_luma, built on the AVX2
   layout, is 0.98x of AVX2 but 1.13x of AVX. Worth a rack01 check of avx vs avx2 dispatch for
   the 10-bit h filters.
4. Deblock was under 1% of all-intra cycles on rack01 (2026-10-13), so none of this moves frame
   time much; the intra kernels matter most for lowlat PIR (an intra column every frame).
