# x264-obe unusual-instruction pass: satd package

Branch `wip/x264-weird-satd`, based on speed-next 0ac92fa9. The package is
`common/x86/pixel-a.asm`: satd*, sa8d*, hadamard_ac, intra_satd_x3/x9,
intra_sa8d_x9, intra_sad_x9, satd_pre/avg2(_pre)/bi/bi4/fenc_pre/mcc and
intra_satd_lowres, at 8 and 10-bit.

The laptop (HX 370, mobile Zen 5, double-pumped zmm) gives indications only.
Decisions come from rack01 (Zen 4) in situ.

## Techniques

1. **HMAX (VBMI2 + opmask).** The last horizontal stage of the 8-bit satd/sa8d
   transforms is `HADAMARD 1, max|amax`. It costs 5 uops: `TRANS d unord`
   (pblendw, pslld, psrld, por) then pmaxsw. With avx512icl it is
   `vpblendmw t{k1=0x5555}, a, b` + `vpshldd b, a, b, 16` + `pmaxsw a, t, b`:
   3 uops, depth 2. vpshldd has 1-cycle latency on the laptop, like paddw.
   The two words of each dword come out swapped relative to TRANS, so the
   per-lane word sums differ but the total is identical. Saves 4 uops per
   8x4 unit.
2. **Merge-masked broadcast row pairs.** 8-wide kernels build
   `[row k x2 | row k+4 x2]` from `vpbroadcastq m, [k]` plus
   `vpbroadcastq m{k2=0xc}, [k+4]`, which drops the vpblendd. The 4:2:0
   chroma H rows use `vpbroadcastb m{k3=0xffff0000}` the same way.
3. **VNNI `vpdpwssd`** replaces the pmaddwd+paddd pairs of the 10-bit widening
   reductions (hadamard_ac, sa8d). It always runs in two chains.
4. **ymm0-15 encoding (`ICL_LOW_BEGIN/END`).** Under x86inc's default avx512
   permutation (m0-m15 = ymm16-31), every instruction of an icl kernel is
   EVEX. That makes the code 19% larger (satd_bi4 16x16: 2864 -> 3408 bytes).
   On the laptop the 16-wide icl kernels then came out 1-8% *slower* than
   avx2, despite having fewer uops.

   Between ICL_LOW_BEGIN and ICL_LOW_END the permutation is undone, so
   m0-m15 sit on ymm0-15:
   - Only the opmask, VBMI2 and VNNI instructions are EVEX. The rest keep VEX
     encodings (satd_bi4 16x16 is 2768 bytes, smaller than avx2).
   - x86inc emits vzeroupper and the WIN64 xmm6-15 saves as it does for avx2.
   - The kernels leave zmm16-31 untouched.
   - lowres and sa8d_x9 can keep their VEX-only phaddw, pblendw, vpblendd,
     vperm2i128 and phminposuw.

   icl/avx2 throughput ratios, default permutation -> ymm0-15: satd 16x16
   1.04 -> 0.92, satd_avg2 16x16 1.08 -> 0.93, satd_pre 16x16 1.01 -> 0.94,
   satd_avg2_pre 16x16 1.05 -> 0.96, bi4 16x16 1.05 -> 0.97. Latency behaves
   the same way. The 10-bit VNNI kernels are neutral under either encoding.

   This deliberately departs from "use x86inc's default permutation". Commit
   708da2d3 is the default-permutation arm if an A/B is wanted.

   **Hazard:** on ymm0-15, nasm encodes `vpdpwssd` as VEX AVX-VNNI. Zen 4 and
   Ice Lake lack that, and checkasm on this laptop (which has AVX-VNNI) would
   not catch it. Every VNNI op is therefore written `{evex} vpdpwssd`. All 20
   vpdpwssd in libx264.a have the 0x62 (EVEX) prefix (checked with objdump).

## 8-bit lookahead in 10-bit encodes

`encoder/lookahead8.c` is built once, at 8-bit, and 10-bit lowlat encodes run
it. The 8-bit icl satd_pre, satd_avg2_pre and lowres kernels therefore change
10-bit lowlat output when broken (positive controls below). Breaking the
8-bit HMAX made a 10-bit lowlat encode hit `assert( cost >= 0 )` in
x264_10_rc_analyse_slice. This is not a bug: the assert is a useful tripwire
for broken lowres costs.

## Correctness

- **checkasm** 8 and 10-bit, seeds 1001/2002/3003: all pass at every commit.
- **Mutants**, one instruction each: 33, all killed by checkasm. They cover
  each kernel's k-mask set-up, an HMAX operand, the vpshldd shift, the masked
  broadcast source, the vshufi32x4 immediate, the pshufd in the 8x8c DC sum,
  the permutation undo before `.sa8d`, the bi pass accumulate, and one operand
  per vpdpwssd chain.
  - One pextrd mutant (index 2 -> 3 in the 8x8c top sum) survived. It is
    equivalent: lanes 2 and 3 hold the same value. It was replaced by the
    pshufd mutant, which was killed.
- **checkasm coverage added** (b329a99c): the sa8d_satd test ran all 64
  iterations on the same block. It now steps 16 pixels per iteration, keeping
  the alignment the fdec loads need.
- **Encoder md5 identity**, `--threads 1 --asm avx512icl`. Base speed-next
  0ac92fa9 and the branch tip are both built with
  `-fno-fast-math -ffp-contract=off`. Input is stressgen 1080 at 40 frames,
  seed 7.

  | cell | content | config | md5 |
  |---|---|---|---|
  | 8l_tile | tile-chaos 8-bit 4:2:0 | veryfast zerolatency intra-refresh, 1-frame VBV | match |
  | 8l_cut | cut-storm | same | match |
  | 8l_i_ffm | field-frame-mix tff | same, --tff | match |
  | 8n_pan | pan-fast | medium, 1 s VBV, weightp 2, bframes 3 | match |
  | 8n_cut | cut-storm | same | match |
  | 8n_fades | fades | same | match |
  | 8n_i_comb | comb tff | same, --tff | match |
  | 10l_comb_i | comb 10-bit 4:2:2 tff | lowlat, --tff | match |
  | 10l_tile | tile-chaos 10-bit 4:2:2 | lowlat | match |
  | 10n_dissolve | dissolve 10-bit 4:2:2 | normal | match |
  | 10n_cut | cut-storm 10-bit 4:2:2 | normal | match |
  | 10n_i_ticker | ticker 10-bit 4:2:2 tff | normal, --tff | match |

- **Positive controls.** Each control breaks one kernel's k-mask or one VNNI
  operand and re-encodes the matrix. A cell that runs the kernel must change.

  | broken kernel | cells that changed (the rest were identical) |
  |---|---|
  | HMAX (vpshldd 16 -> 8, all 8-bit icl) | all 8-bit, 10l (lookahead8; the 10l encodes abort on the RC assert) |
  | satd 16x16/16x8 | all 8-bit |
  | sa8d_8x8 (8-bit) | all 8-bit |
  | satd_pre_8x8 / satd_avg2_pre_8x8 | 8-bit except 8l_cut; 10l both |
  | satd_bi / satd_bi4 | 8n_fades, 8n_i_comb (B-frames) |
  | sa8d_satd_16x16 | 8l_tile, 8l_i_ffm (non-RD 8x8dct decision) |
  | intra_satd_x3_16x16 / 8x8c | all 8-bit |
  | intra_sa8d_x9_8x8 | all 8-bit |
  | intra_satd_lowres | all 8-bit, 10l |
  | hadamard_ac 10-bit | all 10n (psy-rd) |
  | sa8d_8x8 10-bit | all 10-bit |
  | sa8d_16x16 10-bit | **none**: sa8d_satd is used instead |
  | satd_avg2 8-bit (8 wide) | **none**: satd_avg2_pre covers 8x8 and larger |

## Laptop bench

Each row is ubench, TSC ticks per call, run with taskset on CPU 8. Each round
interleaves avx2 and icl in one process, 21 repetitions of 16384 calls. The
table shows the median over 5 rounds. "thr" uses independent calls; "lat"
makes each call's position depend on the previous result. The ratio is the
median of the per-round icl/avx2 ratios. The box was loaded (load average
10-20, other agents), so treat ±3% as noise.

| kernel (harness kind) | avx2 thr | icl thr | ratio | avx2 lat | icl lat | ratio |
|---|---|---|---|---|---|---|
| 8-bit pixel_satd_8x8 (cmp)           |   15.7 |   15.3 | 0.975 |   28.5 |   29.0 | 0.968 |
| 8-bit pixel_satd_8x16 (cmp)          |   22.5 |   21.1 | 0.934 |   48.6 |   48.6 | 1.002 |
| 8-bit pixel_satd_16x8 (cmp)          |   18.1 |   17.7 | 0.978 |   44.3 |   41.9 | 0.950 |
| 8-bit pixel_satd_16x16 (cmp)         |   24.1 |   21.5 | 0.911 |   42.5 |   40.1 | 0.934 |
| 8-bit pixel_satd_avg2_8x8 (avg2)     |   16.8 |   16.3 | 0.969 |   33.8 |   32.4 | 0.959 |
| 8-bit pixel_satd_avg2_8x16 (avg2)    |   28.1 |   22.9 | 0.923 |   41.9 |   39.9 | 0.955 |
| 8-bit pixel_satd_avg2_16x8 (avg2)    |   25.3 |   24.6 | 1.021 |   37.0 |   34.5 | 0.966 |
| 8-bit pixel_satd_avg2_16x16 (avg2)   |   39.2 |   36.8 | 0.939 |   63.8 |   60.2 | 0.942 |
| 8-bit pixel_satd_pre_8x8 (pre)       |   22.3 |   19.8 | 1.000 |   31.7 |   30.7 | 0.968 |
| 8-bit pixel_satd_pre_8x16 (pre)      |   27.6 |   27.4 | 0.970 |   39.6 |   38.0 | 0.950 |
| 8-bit pixel_satd_pre_16x8 (pre)      |   21.0 |   20.1 | 0.990 |   32.6 |   31.9 | 0.959 |
| 8-bit pixel_satd_pre_16x16 (pre)     |   36.3 |   31.5 | 0.951 |   42.1 |   42.7 | 0.947 |
| 8-bit pixel_satd_avg2_pre_8x8 (avg2pre) |   31.1 |   30.8 | 0.990 |   47.3 |   46.0 | 0.977 |
| 8-bit pixel_satd_avg2_pre_8x16 (avg2pre) |   36.8 |   36.2 | 0.989 |   55.7 |   55.0 | 0.984 |
| 8-bit pixel_satd_avg2_pre_16x8 (avg2pre) |   25.9 |   31.6 | 0.996 |   49.5 |   36.9 | 0.968 |
| 8-bit pixel_satd_avg2_pre_16x16 (avg2pre) |   30.8 |   29.2 | 0.955 |   46.8 |   44.1 | 0.942 |
| 8-bit pixel_satd_bi_8x8 (bi)         |   36.3 |   30.6 | 0.911 |   36.3 |   34.4 | 0.936 |
| 8-bit pixel_satd_bi_16x16 (bi)       |   37.1 |   36.1 | 0.994 |   46.2 |   43.3 | 0.939 |
| 8-bit pixel_satd_bi_8x8 (biw)        |   44.8 |   43.9 | 0.980 |   48.5 |   46.7 | 0.963 |
| 8-bit pixel_satd_bi_16x16 (biw)      |   88.2 |   85.2 | 0.945 |   89.1 |   86.0 | 0.969 |
| 8-bit pixel_satd_bi4_8x8 (bi4)       |   49.8 |   48.6 | 0.976 |   52.7 |   52.0 | 0.987 |
| 8-bit pixel_satd_bi4_16x16 (bi4)     |   49.1 |   47.6 | 0.991 |   55.3 |   53.3 | 0.949 |
| 8-bit pixel_satd_bi4_8x8 (bi4w)      |   61.9 |   59.3 | 0.987 |   62.6 |   59.9 | 0.987 |
| 8-bit pixel_satd_bi4_16x16 (bi4w)    |  100.5 |   77.2 | 0.894 |   81.0 |   93.2 | 0.967 |
| 8-bit pixel_sa8d_8x8 (cmp)           |   13.9 |   13.0 | 0.952 |   35.9 |   34.2 | 0.947 |
| 8-bit pixel_sa8d_satd_16x16 (cmp64)  |   50.1 |   44.3 | 0.924 |   72.0 |   66.8 | 0.930 |
| 8-bit intra_satd_x3_16x16 (x3)       |   81.6 |   73.9 | 0.922 |   93.7 |   87.4 | 0.912 |
| 8-bit intra_satd_x3_8x8c (x3)        |   41.0 |   40.0 | 0.949 |   59.6 |   51.4 | 0.987 |
| 8-bit intra_satd_lowres (low)        |  124.7 |  119.7 | 0.960 |  127.4 |  117.0 | 0.923 |
| 8-bit intra_sa8d_x9_8x8 (x98)        |  147.6 |  141.7 | 0.946 |  148.1 |  139.7 | 0.968 |
| 10-bit pixel_hadamard_ac_16x16 (hac) |   57.1 |   53.0 | 0.935 |   61.3 |   62.3 | 0.988 |
| 10-bit pixel_hadamard_ac_16x8 (hac)  |   42.3 |   42.9 | 1.002 |   44.7 |   44.6 | 0.998 |
| 10-bit pixel_hadamard_ac_8x16 (hac)  |   27.1 |   31.4 | 0.993 |   46.1 |   46.3 | 0.998 |
| 10-bit pixel_sa8d_8x8 (cmp)          |   18.9 |   19.0 | 1.005 |   35.6 |   35.8 | 1.009 |
| 10-bit pixel_sa8d_16x16 (cmp)        |   36.6 |   28.2 | 0.989 |   53.3 |   51.6 | 0.988 |

checkasm `--bench` (seed 1001, 5 runs) agrees on direction but is far
noisier. For example, single runs of satd_8x8 ranged from 4 to 99 ticks, and
10-bit hadamard_ac went from icl -10% to +40% between runs; mins are icl
-3..-10%. The ubench numbers above are the ones to read.

Static instructions per call, avx2 -> avx512icl (includes alignment padding and
internals):

| kernel | instructions | | kernel | instructions |
|---|---|---|---|---|
| satd 8x8 | 82 -> 66 | | satd_bi 8x8 | 168 -> 147 |
| satd 8x16 | 151 -> 119 | | satd_bi 16x16 | 452 -> 423 |
| satd 16x16 | 206 -> 192 | | satd_bi4 8x8 | 241 -> 203 |
| satd_avg2 8x8 | 92 -> 77 | | satd_bi4 16x16 | 575 -> 545 |
| satd_avg2 16x16 | 232 -> 217 | | sa8d 8x8 | 99 -> 84 |
| satd_pre 8x8 | 58 -> 52 | | sa8d_satd 16x16 | 363 -> 334 |
| satd_pre 16x16 | 158 -> 147 | | intra_satd_x3 16x16 | 472 -> 425 |
| satd_avg2_pre 8x8 | 74 -> 66 | | intra_satd_x3 8x8c | 184 -> 170 |
| satd_avg2_pre 16x16 | 194 -> 182 | | intra_satd_lowres | 453 -> 414 |
| hadamard_ac 8x8 internal (10-bit) | 139 -> 132 | | intra_sa8d_x9_8x8 | 262 -> 256 static (-8 per .sa8d call, 5 calls) |

## Per-function log

The "level" column is what speed-next dispatches on Zen 4. "dispatched" means
the function is dispatched at X264_CPU_AVX512ICL on this branch. Throughput
ratios are from the bench table (icl/avx2).

| function | depth | current best level | unusual instructions considered | tried? | bit-exact? | laptop thr avx2 -> new | decision | reason |
|---|---|---|---|---|---|---|---|---|
| pixel_satd 8x8, 8x16, 16x8, 16x16 | 8 | avx2 | VBMI2 vpshldd + vpblendmw (HMAX), merge-masked vpbroadcastq, VNNI tail, zmm | yes | yes | 0.91-0.98 | dispatched | -4 uops per 8x4 unit, -2 per 8-wide row pair; VNNI has no add to fold in the tail; zmm satd already exists upstream, disabled for 8-bit by policy (zen5/avx512-8bit-pixel-retest) |
| pixel_satd 4x4, 4x8, 4x16, 8x4 | 8 | avx (avx512 versions exist, undispatched) | same | no | - | - | rejected | cold: no sub-8x8 inter partitions in obed presets; intra 4x4 goes through x9 and chroma 4x4 through satd_mcc |
| pixel_satd 8x8 to 16x16 | 10 | avx2 (zmm dropped in e770eb7e) | VNNI tail, HMAX, zmm | no | - | - | rejected | the vertical-mode transform has no TRANS d (amax already pairs across registers); only 16x16 has a widening (HADDUWD), and two pmaddwd beat it by 1 op even in AVX2; zmm lost in situ before |
| pixel_satd 4xN, 8x4 | 10 | avx | - | no | - | - | rejected | cold |
| pixel_satd_avg2 8x8 to 16x16 | 8 | avx2 | HMAX, masked broadcast | yes | yes | 0.92-1.02 | dispatched (unreached) | positive control: no cell reaches it; satd_avg2_pre covers 8x8 and larger whenever satd_fenc_pre exists (avx2+). Harmless; can be dropped |
| pixel_satd_avg2 | 10 | avx2 | VNNI tail | no | - | - | rejected | vertical mode, as 10-bit satd |
| pixel_satd_pre x4 | 8 | avx2 | HMAX, masked broadcast | yes | yes | 0.95-1.00 | dispatched | same transform as zen5/asm-satd-pre-icl f9e49106 (neutral in situ on Zen 4 under the default permutation), now in VEX encodings; also runs in 10-bit lowlat (lookahead8) |
| pixel_satd_avg2_pre x4 | 8 | avx2 | HMAX, masked broadcast | yes | yes | 0.955-0.996 | dispatched | as satd_pre |
| pixel_satd_fenc_pre 16x16, 8x8 | 8 | avx2 | vpermb row duplication | no | - | - | rejected | one load, one pmaddubsw and one store per row; nothing to fold |
| pixel_satd_bi, satd_bi4 x4 | 8 | avx2 | HMAX, masked broadcast | yes | yes | 0.89-0.99 | dispatched | same transform as zen5/asm-satd-bi-icl ed6e93a6; only B-frame cells reach it |
| pixel_satd_bi, satd_bi4 | 10 | avx2 | VNNI | no | - | - | rejected | vertical mode |
| pixel_satd_mcc, satd_mcc_fenc_pre | 8, 10 | avx2 | VNNI vpdpbusd 4-tap bilinear, vpdpwssd tail, k-masks | considered | - | - | rejected | vpdpbusd needs a 3-shuffle quad interleave and widens to dwords, so it is not below the pmullw/pmaddubsw path; the tail sums unsigned words (vpdpwssd is signed); the transform is vertical (no TRANS d) |
| pixel_sa8d_8x8 | 8 | avx2 | HMAX, masked broadcast, vshufi32x4 | yes | yes | 0.95 | dispatched | vperm2i128 is VEX-only, so the lane butterfly uses vshufi32x4 |
| pixel_sa8d_16x16 | 8 | avx | - | no | - | - | rejected | cold: x264_mb_analyse_transform uses sa8d_satd |
| pixel_sa8d_8x8 | 10 | avx2 | VNNI | yes | yes | 1.00 (lat 1.01) | dispatched (neutral) | 7 -> 5 ops in the widening |
| pixel_sa8d_16x16 | 10 | avx2 | VNNI | yes | yes | 0.99 | dispatched (unreached) | internal returns dwords, which drops both HADDUWD; no cell reaches it |
| pixel_sa8d_satd_16x16 | 8 | avx2 | HMAX for the satd max and sa8d amax; phaddd replaced | yes | yes | 0.92 (lat 0.93) | dispatched | 16 HMAX per 16x16; lowlat transform decision |
| pixel_sa8d_satd_16x16 | 10 | avx2 | VNNI in SA8D_SATD_ACCUM | no | - | - | rejected | about 2 ops of about 330 per call |
| pixel_hadamard_ac 16x16, 16x8, 8x16 | 10 | avx2 | VNNI (two chains, pw_2 for the doubled sa8d terms) | yes | yes | 0.94-1.00 | dispatched | 8x8 internal 139 -> 132; reached by psy-rd at 10n |
| pixel_hadamard_ac 8x8 | 8, 10 | avx2 | VNNI | considered | - | - | rejected | saves 3 ops, but the phaddd tail has no EVEX form (default permutation) and costs them back; under ICL_LOW it is about 3 of 97, below the noise |
| pixel_hadamard_ac 16x16, 16x8, 8x16 | 8 | avx2 | VBMI2 for TRANS d ord, vpermt2w, VNNI | considered | - | - | rejected | sumsub needs the ordered pairs, and VBMI2 has no 2-uop ordered form; vpermt2w transposes lose (x265 lesson); 8-bit sums are words (nothing to widen) |
| intra_satd_x3_16x16, 8x8c | 8 | avx2 | HMAX; merge-masked vpbroadcastq/b rows; phaddd -> pshufd+paddd | yes | yes | 0.92 / 0.95 | dispatched | 12 (16x16) and 3 (8x8c) 8x4 units |
| intra_satd_x3_8x16c | 8 | avx | - | no | - | - | rejected | 8-bit 4:2:2 is not a production format |
| intra_satd_x3_4x4, intra_sa8d_x3_8x8 | 8 | mmx2/ssse3, avx | - | no | - | - | rejected | x9 versions supersede them |
| intra_satd_x3_* | 10 | avx2 / avx512 (16x16) | VNNI in INTRA_HBD_FOLD | no | - | - | rejected | 3 pmaddwd with no add to fold; vertical mode |
| intra_satd_x9_4x4 | 8, 10 | avx2 | k-mask argmin (vpminuw + vpcmpeqw k + kmov + tzcnt), masked vpsubw for psignw, vpermb predictions | considered | - | - | rejected | phminposuw is one op for an 8-way argmin; masked sub costs the same ops as psignw+paddw; no TRANS d stage |
| intra_sa8d_x9_8x8 | 8 | avx2 | HMAX in .sa8d (four amax) | yes | yes | 0.95 | dispatched | 8 uops per .sa8d, 5 calls; VEX-only phaddw etc. kept via ICL_LOW |
| intra_sa8d_x9_8x8 | 10 | avx2 | - | no | - | - | rejected | vertical-mode transform |
| intra_sad_x9_4x4, 8x8 | 8 | sse4/avx, avx2 (8x8) | vdbpsadbw | considered | - | - | rejected | only with mbcmp = SAD (subme <= 1), which obed does not use; psadbw is already one op |
| intra_satd_lowres | 8 | avx2 | HMAX | yes | yes | 0.96 (lat 0.92) | dispatched | 10 satds per call; also in 10-bit lowlat (lookahead8) |
| intra_satd_lowres | 10 | avx2 | - | no | - | - | rejected | vertical-mode transform |
| internals (satd_8x8/16x8/16x4_internal, sa8d_8x8/16x8_internal, sa8d_satd_8x8_internal, hadamard_ac_8x8(v), hadamard_load, hadamard_ac_4x4/2x2max, .sa8d) | 8, 10 | - | as their callers | with callers | - | - | - | covered by the parent rows |
| mmx2/sse2/ssse3/sse4/avx/xop/atom versions of all of the above | 8, 10 | - | - | no | - | - | rejected | not dispatched on Zen 4 where avx2/icl versions exist |

## Unusual instructions summary

- **Used:**
  - VBMI2 vpshldd, in HMAX: the main win.
  - Opmask: vpblendmw, merge-masked vpbroadcastq/vpbroadcastb,
    kmovd/kshiftrd.
  - VNNI vpdpwssd, with `{evex}`, in 10-bit hadamard_ac and sa8d.
  - vshufi32x4, because vperm2i128 has no EVEX form.
- **Considered, no fit:**
  - VNNI vpdpbusd: satd_mcc bilinear and the 8-bit first stage. Both widen to
    dwords and need extra shuffles.
  - VBMI vpermb/vpermt2w: x9 prediction building and TRANS d ord. pshufb is
    1 cycle, and permute transposes lose.
  - vdbpsadbw: intra_sad_x9, which is not a production path.
  - k-mask argmin: phminposuw is better.
- **No use:**
  - GFNI: no byte shifts in the package.
  - BITALG/VPOPCNTDQ: no bit counting.
  - CD (vplzcnt/vpconflict): nothing to apply them to.
  - IFMA: no 52-bit products.
  - vpternlog: abs is pabsw, and blends are vpblendmw.
- **VP2INTERSECT:** no use found. The package computes dense transforms and
  reduces them with sums, max and min. No kernel intersects two index or value
  sets: the x9/lowres argmin is a min over 9-10 costs, and nothing compares
  two sets.

## Bugs and findings in existing code

- **checkasm** (fixed, b329a99c): the sa8d_satd test reused one pbuf2 block in
  all 64 iterations.
- **No functional bug** was found in the existing asm of the package.
- **x86inc hazard** (handled): VNNI on ymm0-15 assembles silently to VEX
  AVX-VNNI. It would raise SIGILL on Zen 4 and Ice Lake but passes checkasm on
  the laptop. It is documented at ICL_LOW_BEGIN.
- **AVX2 lead, not done (not an unusual instruction):** phaddw ymm is slow on
  the laptop. Four phaddw take about 3.8-4.2 ticks; the exact replacement
  (2 pmaddwd + packssdw each, sums <= 32640) takes 2.1-2.6. Users:
  - intra_satd_lowres: 14 (8-bit) and 12 (10-bit)
  - intra_satd_x9_4x4: 6
  - intra_sa8d_x9_8x8: 6 (8-bit) and 5 (10-bit)
  - satd_mcc: 4 phaddd
  - hadamard_ac_8x8: 1 phaddd

  This is worth a Zen 4 check: Zen 4's vphaddw is believed to be 3 uops.
- **nasm:** satd_mcc's `movsxd r6, r6d` assembles to cltq with 3.01 and to
  movslq with 2.14.02. The semantics are the same, and the difference is
  pre-existing.
- **Bench harnesses:** x264 asm assumes 64-byte stack alignment
  (STACK_ALIGNMENT=64), and sa8d_satd stores ymm to the stack with mova.
  checkasm aligns the stack. A standalone harness must build with
  `-mpreferred-stack-boundary=6`.

## nasm

Every new instruction assembles with nasm 2.14.02 and gives the same
disassembly as 3.01: vpshldd, vpblendmw, kmovd/kshiftrd, masked
vpbroadcastq/b, vshufi32x4, EVEX vpdpwssd and the `{evex}` prefix. The only
differences are the pre-existing satd_mcc cltq/movslq and padding nops, which
are identical for base and branch. Nothing in this package needs a newer nasm.
win64 assembly checked too: xmm6-13 are saved in the ICL_LOW kernels.

## Needs rack01 (Zen 4)

1. In-situ A/B, speed-next vs this tip, with a layout twin (dispatch flipped to
   an unset cpu flag). Cells:
   - 8l, 8n, 10l, 10n
   - progressive and true 1080i
   The 10l cells run the 8-bit lookahead kernels.
2. Encoding A/B: 708da2d3 (default permutation, EVEX) vs the tip (ymm0-15,
   VEX). This settles the x86inc question for x264-obe AVX-512 work in
   general.
3. checkasm on Zen 4, to confirm no VEX AVX-VNNI (SIGILL check). The objdump
   check here found none.
4. Optional: the phaddw lead above.

## Round 2 (2026-10-20, wip/x264-weird2-satd on 67b4aff6)

Kieran: "don't reject, move to zen5 if rack01 is too slow". Every round-1 row
that was not dispatched and not on a zen5/ branch is written and dispatched at
avx512icl here; rack01 (Zen 4) decides placement. Nothing was found to recover:
the round-1 branch history (reflog of wip/x264-weird-satd) is linear, there are
no satd stashes, and the round-1 WSL copies hold only the two encoding arms of
708da2d3. Laptop timings: none taken.

### Checks (every kernel)

- **Driver** (laptop, WSL gcc + nasm, no x264 build): each kernel against the C
  reference copied from common/pixel.c (satd, sa8d, hadamard_ac, mc_chroma +
  satd, predict 4x4/8x8/8x16c + satd/sa8d), or, where a C reference needs the
  predict/mc tables (x9, lowres, fenc_pre layouts), against the existing asm
  that checkasm verifies against C (avx2, and a second level where it exists).
  Inputs: random, PIXEL_MAX vs 0 both ways, random 0/PIXEL_MAX, every
  difference +-PIXEL_MAX, small differences, ramps, all 1456 sa8d cosets
  ((k & m) == t of the 6 coordinate bits, both signs), odd strides and offsets,
  and the last element read placed against a PROT_NONE page. Weighted bi: every
  weight -63..127, clipped extremes. x9/x3: ties (flat blocks, zero bitcosts)
  and saturating bitcosts.
- **ABI** (asm trampoline around every call): rbx/rbp/r12-r15 set to patterns
  and compared after the call, rsp+8 64-byte aligned, k1-k7 random before every
  call, XINUSE (xgetbv 1) bits 2 and 6 (ymm/zmm0-15 upper state) must be clear
  at return. Positive controls: vzeroupper disabled -> flagged; a mov to ebx ->
  flagged; each kernel's k-mask set-up replaced by nop -> killed. No kernel
  relied on a stale k-mask.
- **Mutants**: 2-5 per kernel (k-mask constants, shuffle immediates, table
  entries, VNNI operands, clamps, store offsets), all killed except two
  equivalent ones (a sign flip of a whole intermediate in 10-bit satd_4x4 and
  in 10-bit intra_satd_x9_4x4: |x| sums are unchanged), replaced by killed ones.
- **nasm 2.14.02**: every avx512icl function disassembles identically with
  2.14.02 and 3.01 (after normalising satd_mcc's pre-existing cltq/movslq), at
  both depths; win64 assembles with both. Nothing needs a newer nasm (no
  vpshldv*/vpshrdv*). Every vpdpwssd/vpdpbusd is EVEX (objdump: 0 without 0x62).
- **Unchanged code**: per-function disassembly against the previous tip for
  the commits that turn functions into macros (satd_mcc, 10-bit
  intra_sa8d_x9_8x8 / intra_satd_lowres, 10-bit intra_satd_x3): the avx2/avx512
  versions are identical.
- **checkasm** (laptop on AC, configure --bit-depth=all): checkasm8 and
  checkasm10, seeds 1001, 2002, 3003, all pass at c5fbd079 (and at f5e859dc).

### Rows

| function | depth | round-1 decision | round-2 action | commit | driver | nasm 2.14.02 |
|---|---|---|---|---|---|---|
| pixel_satd 4x4 | 8 | rejected (cold) | written: avx512 packed layout, last stage SATD_ICL_HMAX (vpblendmw + vpshldd + pmaxsw) into one register, pmaddwd sum; xmm | 057e59b6 | pass, 1909 cases, 3 mutants | ok |
| pixel_satd 4x8, 4x16 | 8 | rejected (cold) | written: as 4x4, ymm0-15 | 736fc50d, 79dd97c6 | pass, 1909 each, 4 mutants | ok |
| pixel_satd 8x4 | 8 | rejected (cold) | written: as 4x4, ymm0-15 | 247bc99e | pass, 1909, 2 mutants | ok |
| pixel_satd 16x16 | 10 | rejected (vertical mode) | written: VNNI tail; two passes fit signed words (2*2*8*1023 = 32736): pmaddwd after pass 2, {evex} vpdpwssd after pass 4, no HADDUWD | abc48e9a | pass, 1909, 2 mutants | ok |
| pixel_satd 8x8, 8x16, 16x8 | 10 | rejected | not written: no widening to replace (one pmaddwd after <= 2 passes); the zmm 16x16/16x8 dropped in e770eb7e are on origin/zen5/hbd-avx512-sad8-satd (38959f89, dispatched there), not re-dispatched | - | - | - |
| pixel_satd 4x4 | 10 | rejected (cold) | written: xmm, qword per row; vertical sumsub, qdq exchange, sumsub; horizontal vprold + paddw + vpsubw {odd}; last stage vpblendmd {even dwords} + vpshldq 32 + pmaxsw; replaces mmx2 | e5247bcd | pass, 1909, 6 mutants | ok |
| pixel_satd 4x8, 4x16 | 10 | rejected (cold) | written: ymm, rows from vpbroadcastq + merge-masked vpbroadcastq | 0103199c, d68cf414 | pass, 1909 each, 4 mutants | ok |
| pixel_satd 8x4 | 10 | rejected (cold) | written: ymm, lane exchange vperm2i128 + vinserti128 | 20cc26c0 | pass, 1909, 2 mutants | ok |
| pixel_satd_avg2 16x16 | 10 | rejected | written: the satd 16x16 VNNI tail (8x8..16x8 have no widening) | 042f176a | pass, 1906, 2 mutants | ok |
| pixel_satd_bi / bi4 16x16 | 10 | rejected | written: VNNI tail in SATD_BI's high bit depth body (8x8..16x8 have no widening) | 7430acaa, 360cd3eb | pass, 22416 each (all weights), 2+2 mutants | ok |
| pixel_satd_fenc_pre_16x16 | 8 | rejected | written: zmm, one 64 byte load of four fenc rows, vshufi32x4 doubles rows into lanes (vpermb not needed: the duplication is 128-bit-lane granular) | 6055a3f0 | pass vs avx2, 2501, 1 mutant | ok |
| pixel_satd_fenc_pre_8x8 | 8 | rejected | written: zmm, vpbroadcastq + three merge-masked vpbroadcastq | c7df4e45 | pass vs avx2, 2501 + guard, 3 mutants | ok |
| pixel_satd_mcc | 8 | rejected | written: width 8 as mc_chroma's 4-tap in one zmm pass: masked 18-byte row loads, vinserti32x8 (register), vpermb quads, vpdpbusd with negated weights onto 64*fenc + 31 (negated difference, same satd), vpmovdw; satd_mcc became a macro | 4ee7e103 | pass vs C, 8880 (all dx/dy, extremes, guard), 4 mutants | ok |
| pixel_satd_mcc | 10 | rejected | written: width 8 as vpermw word pairs + vpmaddwd and vpdpwssd (zmm), +32, psrad, vpmovdw | f5e859dc | pass vs C, 8880, 4 mutants | ok |
| pixel_satd_mcc_fenc_pre | 8 | rejected | written: zmm, vpermb {even bytes}{z} straight to interleaved uv words, vpermi2q for the width 4 and 4x4 layouts | 7e3f4378 | pass vs avx2, 2502 + guard, 5 mutants | ok |
| pixel_sa8d_16x16 | 8 | rejected (cold) | written: four sa8d_8x8_avx512icl transforms, two-chain pmaddwd/vpdpwssd dword fold (8x8 words <= 2*32*255) | 42c8f98d | pass, 1909 incl. cosets, 4 mutants | ok |
| pixel_sa8d_satd_16x16 | 10 | rejected (~2 ops) | written: sa8d sum as two vpdpwssd chains, satd dwords kept in m7 (no spill) | bd0cd62b | pass, 1906, 3 mutants | ok |
| pixel_hadamard_ac_8x8 | 8, 10 | rejected (phaddd, noise) | written: ymm0-15 keeps VEX phaddd; sa8d tail as two vpdpwssd chains (pw_2 = pw_1 + pw_1), 7 ops instead of 10 | c21c5e24 (8), d3c46460 (10) | pass, 1906 each, 3 mutants | ok |
| pixel_hadamard_ac 16x16, 16x8 | 8 | rejected (vpermt2w loses) | written: the four TRANS d ord of the internal as vpermi2w + vpermt2w (hadac_icl_idx); x265 found such transposes slower, rack01 decides | 8db9f3f6 | pass, 1906 each, 3 mutants | ok |
| pixel_hadamard_ac 8x16 | 8 | rejected | written: as 16x16 plus stacked rows from merge-masked vpbroadcastq | e4ba54d5 | pass, 1906, 1 mutant | ok |
| intra_satd_x3_8x16c | 8 | rejected (4:2:2 8-bit) | written: two HMAX 8x8c halves | 53b83a19 | pass vs C, 16000, 3 mutants | ok |
| intra_satd_x3_8x8c, 8x16c | 10 | rejected | written: H rows k and k+4 by merge-masked vpbroadcastw | 233dd10b, 44718455 | pass vs avx2, 16000 each, 1+1 mutants | ok |
| intra_satd_x3_16x16 | 10 | rejected | written: ymm, two passes per signed word fold, vpmaddwd + {evex} vpdpwssd into ymm16-18, three chains; overrides the zmm avx512 one in the slot | 615a7c10 | pass vs avx2 and avx512, 16000 each, 3 mutants | ok |
| intra_satd_x9_4x4 | 8 | rejected (phminposuw better) | written: psignw stages as vprold/pshufd + paddw + vpsubw {k}; k-mask argmin over nine costs (vpermw, vmovdqu16 {k}{z} bitcosts, pminuw + phminposuw, vpcmpeqw + kmovd + tzcnt) | 2047e495 | pass vs avx2 and avx, 20000 each incl. ties, 4 mutants (incl. tzcnt -> bsr) | ok |
| intra_satd_x9_4x4 | 10 | (not in round 1) | written: as 8-bit on the X9H layout (three masked sign stages) | ab0080e7 | pass vs avx2, 20000, 4 mutants | ok |
| intra_sad_x9_4x4 | 8 | rejected (subme <= 1) | written: x9b predictions, psadbw (2*sad, rows twice), or'd word slots, k-mask argmin. vdbpsadbw: its two dword windows per qword are at byte offsets 0-1 / 2-3, so only the edge-window modes (ddl, ddr, vl) map onto it, and all nine predictions are materialised for the fdec store anyway | 142f8174 | pass vs avx and ssse3, 20000 each, 4 mutants | ok |
| intra_sad_x9_8x8 | 8 | rejected | written: avx2 version with the k-mask argmin and one vmovdqu16 {k3} satds store | e32265ab | pass vs avx2 and ssse3, 20000 each, 4 mutants | ok |
| intra_satd_x3_4x4, intra_sa8d_x3_8x8 | 8 | rejected (x9 supersedes) | written (coordinator: reached at frame edges where predict_mode[8] < 0, lossless, --cpu-independent): x9b v/h/dc with masked sign stages; HMAX v+h pair and dc sa8ds | b43ecc53, f718823b | pass vs C and ssse3/sse2, 16000 each, 2+3 mutants | ok |
| intra_sa8d_x9_8x8 | 10 | rejected (vertical) | written: .sa8d widening as two vpdpwssd chains (5 ops instead of 7, five calls) | 39f38b22 | pass vs avx2, 20000, 2 mutants | ok |
| intra_satd_lowres | 10 | rejected (vertical) | written: P prediction in exact dwords by one zmm vpdpwssd + c per row, clipped to [0, PIXEL_MAX] (equal to the saturating words) | 5884983b | pass vs avx2, 2400 incl. clip-reaching gradients, 5 mutants | ok |
| mmx2 .. avx/xop/atom versions | 8, 10 | rejected | skipped: superseded at dispatch by the avx2/avx512icl versions on every AVX-512 CPU (brief row 18) | - | - | - |
| AVX2 phaddw -> pmaddwd + packssdw lead | 8, 10 | lead | not done (optional row 19, not an unusual instruction) | - | - | - |

### Tails (kernels whose result feeds a branch)

Ops after the last transform stage to eax, and their dependency depth:
satd 4x4 (both depths) pmaddwd + HADDD(xmm) + movd: 6, depth 6 (avx2/avx: HADDW
or HADDUW, 6-7). Small ymm satds: 8, depth 8 (the extract adds one). 10-bit
16x16 satd/avg2/bi/bi4: vpdpwssd + HADDD + movd = 8, depth 8 (avx2: HADDUWD 4 +
HADDD 6 + movd = 11, depth 9; the pass 1-2 pmaddwd is off the critical path).
hadamard_ac_8x8 sa8d: 7 (avx2 10), depth 4 (two chains). x9 4x4 argmin: about
13 ops, depth about 10 (avx2 phminposuw + cmov: 9, depth 7): the k-mask form
is longer; it removes the separate v compare. sa8d_16x16 8-bit: paddd + HADDD +
rounding: 9, depth 9.

### Notes for rack01

- The 10-bit satd_mcc width-8 path loads rows with vmovdqu16 zmm {18 words}
  masks at arbitrary reference offsets (a 36-byte span, like the avx2 version's
  two 32-byte loads); the 8-bit path uses ymm masked loads and a register
  vinserti32x8. No per-row memory inserts into zmm.
- intra_satd_x3_16x16 (10-bit): the ymm VNNI version overrides the zmm avx512
  version, which won in situ against avx2 earlier; compare all three.
- 8-bit hadamard_ac 16x16/16x8/8x16 is the vpermt2w transpose variant the x265
  lesson expects to lose: measure, then zen5/ if slower.
- zmm kernels (default x86inc permutation): satd_fenc_pre_16x16/8x8,
  satd_mcc_fenc_pre. The rest are ymm0-15 (ICL_LOW) except the xmm satd_4x4s.

### Bugs found

- common/x86/pixel-a.asm SATDS_SSE2 (line 2581 before c5fbd079): at high bit
  depth the ssse3/sse4/avx/xop instantiations built x264_10_pixel_satd_4x4_* from
  the 8-bit code (movd loads of two pixels, pmaddubsw): wrong results (e.g. 2046
  for a satd of 13184). Never dispatched (10-bit 4x4 used mmx2), so no output
  ever changed; the condition comes from upstream (vertical==0 ||
  HIGH_BIT_DEPTH). Fixed in c5fbd079 (not built at high bit depth).
- Brief correction: 10-bit has intra_satd_x9_4x4 (avx2, 6d956833), so the
  10-bit i4x4 decision runs x9, not satd_4x4; it got its own avx512icl version
  (ab0080e7).
- No overflow found in existing kernels at PIXEL_MAX under the coset, row,
  column and checkerboard patterns (8-bit hadamard_ac 16x16/16x8/8x16 avx2,
  sse2, ssse3 with their paddusw sums included).
