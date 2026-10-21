# x264-obe unusual-instruction pass: cabac package

Branch `wip/x264-weird-cabac`, base `origin/speed-next` 0ac92fa9. Files: `common/x86/cabac-a.asm`,
`common/x86/bitstream-a.asm`, `common/x86/trellis-64.asm` (+ `common/bitstream.c`,
`common/x86/bitstream.h`, `tools/checkasm.c`).

## Where the time goes (laptop perf, 8-bit grain 1080p, medium, 20 Mb/s VBV, --threads 1, avx512icl)

| function | share |
|---|---|
| trellis_cabac_8x8_avx512icl | 3.96% |
| trellis_cabac_4x4_avx512icl | 3.30% |
| cabac_block_residual_internal_avx512 (bitstream writer) | 3.19% |
| cabac_block_residual_rd_internal_avx512icl (4x4 RD) | 2.52% |
| cabac_encode_decision_bmi2 | 0.99% |
| cabac_block_residual_8x8_rd_internal_avx512icl | 0.97% |
| nal_escape | not in the top 45 (<0.5%) |

Coefficient statistics from an instrumented private build (same encode, never committed):
- 4x4 RD calls: nonzero count 1: 40%, 2: 27%, 3: 15%, 4+: 18%.
- 8x8 RD calls: nonzero count mostly 2-10; the largest number of nonzero coefs below `last`
  sharing one last-flag context is 1-4 in 85% of calls.
- 4x4 trellis: 1-5 nonzero, 5-12 zeros below last_nnz typical.
- 8x8 trellis: 1-20 nonzero, **20-55 zeros below last_nnz typical** (peak ~45).

## Method

- Correctness: checkasm8/10, seeds 1001/2002/3003, all pass on the branch tip. Added checkasm
  coverage where the existing test could not fail (nal_escape). Mutation checks below.
- `--threads 1 --asm avx512icl` md5 identity, base vs branch, both built with
  `-fno-fast-math -ffp-contract=off`, 30 frames of stressgen content, 8/8 cells SAME:
  grain 8-bit 4:2:0 lowlat (veryfast zerolatency PIR, one-frame VBV) and normal (medium, 1 s VBV,
  weightp 2, B-frames); credits 8-bit medium trellis 2 psy-trellis 0.3, and lowlat + trellis 1;
  ticker 10-bit 4:2:2 native 1080i tff lowlat, medium, medium trellis 2 psy-trellis 0.3;
  noise 10-bit 4:2:2 medium.
- Laptop speed (HX 370, indicative only, not a merge criterion): checkasm `--bench`, medians
  (CPU 2, seed 1001). The laptop was shared with 7 other agents and checkasm cycles swung by
  +-40%. For the trellis and RD functions I also used a **corpus replay harness**: calls dumped
  from real encodes (40k per type, from a private build of the base tree), replayed through one
  kernel set, checked against the recorded outputs, counting user-mode **core cycles and
  instructions** via perf_event_open. The instruction counts are exact. Cycles are the minimum
  over 7-9 interleaved A/B rounds on an L2-resident subset. Corpora: grain 8-bit 20 Mb/s, credits 8-bit
  8 Mb/s (sparse), ticker 10-bit 4:2:2 1080i 30 Mb/s, noise 10-bit 4:2:2 50 Mb/s (dense).
  Tools are in the session scratchpad (`cabacw/`), not in the tree.

## Per-function log

| function | current best level | unusual instructions considered | tried? | bit-exact? | laptop base -> new | decision | reason |
|---|---|---|---|---|---|---|---|
| nal_escape | avx2 -> **avx512icl** | vptestnmb/vpcmpub k-masks, BMI2 pdep, VBMI vpermb, VBMI2 vpcompressb (register form + masked store), vpexpandb, GFNI | yes | yes (checkasm + guard-page test) | checkasm 16 KiB random: 2566 -> 1863; escape-dense: 190257 -> 60771 | **dispatched** | Escapes come from mask arithmetic: C = (x<=3) & Z<<1 & Z<<2; escapes = every other bit of each run of C, via the add-carry trick. pdep spreads them into a keep mask for an interleaved 0x03/byte vector, and vpcompressb packs it. No scalar escape loop and no read or write outside src..end / the output. vpexpandb works in output space and needs 2 extra pext plus a variable byte shift of the source for the second 64 output bytes, so I chose compress (not built). GFNI: no bit-matrix work. |
| trellis_cabac_8x8, 8x8_psy | avx512icl | VBMI vpermb (state per position), vpermt2b (entropy), vpermi2b (bytes to qwords), valignq scan, VPOPCNTQ, VP2INTERSECT | yes | yes (checkasm, 4 real corpora, md5) | instructions/call 1888 -> 1694 (grain8), 1482 -> 1262 (credits8), 1947 -> 1837 (ticker10i), 1258 -> 979 (noise10); min core cycles 971 -> 778, 506 -> 477, 1075 -> 924, 575 -> 443. checkasm's single synthetic dense block: 8-bit 7353 -> 7680 (+4%), 10-bit 7738 -> 7685 | **dispatched** (inside the existing avx512icl kernel; `TRELLIS_ICL_ZPREFIX=0` restores the loop) | ctx_lo zero runs were summed one coef at a time with 3 dependent loads plus imul. Now prefix sums of cost_sig0 for all 64 positions are built at the first zero run (lazy, so blocks without one pay nothing), and each run is one subtraction. checkasm's bench block has few zeros, unlike real 8x8 blocks (20-55). |
| trellis_cabac_4x4, 4x4_psy | avx512icl | same prefix-sum lever | yes | yes | instructions 818.2 -> 807.7 (8-bit), 1134.5 -> 1139.3 (10-bit) | rejected (kept the loop) | Runs are short (5-12 zeros), so the prefix build cancels the saving. |
| trellis_cabac_dc, chroma_422_dc | avx512icl | same | yes | yes | instructions 314.0 -> 334.2 (+6%), 542.8 -> 551.6 | rejected | Runs of 0-7 zeros. |
| trellis node chain (TR_PASS*/TR_MERGE/TR_END_COEF) | avx512icl | GFNI, vpconflict, vpcompressd for the level_tree append, lambda-scaled entropy tables, VPOPCNT density gate | analysis | - | - | rejected | Per-coef critical chain estimated at ~22 cycles from Zen 4 latencies: state idx -> vpermt2b -> ternlog -> vpmadd52huq -> vpshldq -> vpermi2q -> vpminuq x2 -> vpermt2q -> vpermi2b. IFMA, VNNI and VBMI are already used. Exact (a+b)*lambda2>>4 rules out pre-scaled tables (128-entry qword lookups would need gathers). Compressing the append adds latency. The density gate was rejected on rack01 2026-10-17. |
| trellis sse2/ssse3/avx2 + trellis_coef* helpers | avx2 | none at these levels | no | - | - | n/a | No unusual instructions below avx512icl. avx512icl supersedes them on ICL-class CPUs. |
| cabac_block_residual_8x8_rd_internal | avx512icl | VPOPCNTDQ per-context last-flag counts (9 segments in one vpopcntd) + T0^k power tables, vpermi2b rounds for the last flags | analysis + data | - | corpus: avx512 676 instr/241 cyc -> avx512icl 338/179 (8-bit), as-is | rejected | Last flags are all bin 0 below `last` and contexts are contiguous ranges, so counts are enough. But the break-even is ~12 nonzeros per block, and real blocks have 2-10 (max per context 1-4). Rounds need ~11 instructions each. Power tables would be 6.5 KiB. Note for an ordinary change: in frame mode rounds 0-1 of the sig pass are always empty (rd8_sig_slots rows 0-1 all 255). Skipping them saves ~10 instructions and 2 vpermi2b latencies per call. Not done (0.97% share). |
| cabac_block_residual_rd_internal (4x4) | avx512icl | vpopcnt node_ctx prefix, VNNI byte sums, vpermt2w entropy | analysis | - | corpus: ssse3_lzcnt 255 instr -> avx512icl 176 (8-bit), 331 -> 243 (10-bit) | rejected | The level loop is a serial per-context state chain (contexts 0/4/9 repeat). The rounds approach would need 15x128 unary tables (gathers). The vpsadbw reduction already uses the minimum number of ops. Ordinary idea, not done: a branchless level-1/gt1 first bin (the jg mispredicts on mixed levels). |
| cabac_block_residual_internal (writer) | avx512 (BMI2 register-resident coder) | vpcompressd/w coefficient list, mask-driven sigmap | analysis | - | - | rejected | The arithmetic coder is serial on range/low (~12-cycle chain per bin). Compressing the coeffs[] list saves 2 stores per nonzero coef and costs ~8 per block. No SIMD helps the bin chain. |
| cabac_encode_decision / bypass / terminal, cabac_putbyte | asm / bmi2 | none applicable | no | - | - | n/a | Scalar arithmetic coder. |

## Mutation checks (each must FAIL checkasm, then pass after restore; all restored OK)

nal_escape avx512icl (checkasm8): ignore escape-before-byte (`andn r4,r6,r4` -> `and`) FAIL;
`shld r7,r5,2` -> `1` FAIL; drop the EVEN xor in the run trick FAIL; compare `<= 3` -> `< 3`
FAIL; carry-in dropped in the unrolled first block (`adc r7,r3` -> `add`) FAIL; in the second block
(`adc r8,r4` -> `add`) FAIL; in the single-block loop (`adc r4,r3` -> `add`) FAIL; entry check of
the previous two zero bytes (`cmp r7d,3` -> `4`) FAIL; hi-half length `sub r7d,32` -> `31` FAIL
(out-of-bounds write); hi compress mask k5 -> k4 FAIL; second store of the unrolled loop stores m0
FAIL. Equivalent mutant: dropping `shr r5,1` in the carry update only differs for blocks of 1-2
bytes with a nonzero carry, and those cannot occur: after an escape block the next block is
64-n >= 31 bytes, and the first block has a zero carry. The first test survived the three carry
mutants: it had no isolated 00 00 0x events at block boundaries. I added sparse-event modes (6-8)
to checkasm and those mutants are now killed.

trellis 8x8 prefix (checkasm8 and checkasm10): run end index (`[prefix + r7*8]` -> `r3`) FAIL;
`lea r7d,[r12+1]` -> `+2` FAIL; scan step valignq 6 -> 7 FAIL; carry add removed FAIL; index
advance vpaddb removed FAIL; hi-byte mask 0x03 -> 0x01 FAIL; shift 4 -> 3 FAIL; carry broadcast
index m11 -> m14 FAIL.

## Added checkasm coverage

`check_bitstream`, nal_escape: 4000 extra cases. dst/src at every 0-63 offset. Sizes 0-299
exhaustive, plus random sizes up to 2 KiB. Mostly-zero escapable data; periodic zero pairs;
zeros at block ends; long zero runs; random data; isolated `00 00 0x` / `00 00 00 0x` events
(dense and very sparse) that split pairs across blocks. Guards check for no write before dst and
none past the end (64 bytes of slack for the older versions, 0 for avx512icl). Plus a second bench,
`nal_escape_dense`. Separately, a guard-page driver (200k cases, PROT_NONE pages on both sides of
src and dst) confirms the avx512icl kernel never reads before src or at/after end, and never
writes outside the output.

## Unusual instructions summary

- **Used:** VBMI2 vpcompressb (register form + masked store), BMI2 pdep, vptestnmb/vpcmpub to
  k-masks + kmovq (nal_escape); VBMI vpermb/vpermt2b/vpermi2b (zero-masked byte->qword
  widening), valignq prefix scan, vpermq broadcast (trellis 8x8). Already present before this
  pass: VBMI tables, IFMA vpmadd52huq, VNNI vpdpwssd, vpternlog, vpminuq (trellis and RD).
- **No use found:** GFNI (no byte shifts or bit-matrix work in this package); vpexpandb (the
  compress form was cheaper for nal_escape, see above); BITALG/VPOPCNTDQ (the 8x8 RD last counts
  fall below break-even on real data, and the trellis density gate was rejected before);
  vpconflict (no scatter collisions: the context map per pass is fixed); vpshld/vpshrd variable
  forms (none needed; the existing vpshldq imm is in the trellis).
- **VP2INTERSECT: no use.** Nothing in this package intersects two index or value sets.
  nal_escape is a pattern scan. The trellis merges candidates by min, not by matching. The RD/writer
  contexts are fixed per position. Lowest-position coef lists are a mask problem (lzcnt/tzcnt), not
  an intersection.

## Bugs found in existing asm / build

1. **PIE link failure (fixed on its own branch `fix/configure-pie` b2bce598):** configure
   assembled x86-64 asm without -DPIC unless the build was shared or used --enable-pic. Every asm
   object then holds absolute 32-bit relocations: cabac-a 488, trellis-64 ~1540, pixel-a 774,
   sad16-a 209, mc-a 147, ... (counts per object in 0ac92fa9). A compiler that defaults to PIE
   (gcc 15.2) cannot link them. The first error names cabac-a.asm:1247 (`cabac_range_lps`), but
   fixing one file only moves the error to the next. The fix matches upstream x264
   "x86: Always use PIC in x86-64 asm" (configure always passes -DPIC on x86-64), plus checkasm-a
   `call puts wrt ..plt` on ELF (upstream "x86inc: Improve ELF PIC support for external function
   calls"). Verified: PIE and -no-pie links, checkasm both depths x 3 seeds, t1 md5 identical to
   0ac92fa9 on 4 cells. Not on this branch: my builds use `-no-pie`.
2. **nal_escape sse2/avx2 read past the padding (not fixed, latent):** the avx2 loop loads up to
   ~126 bytes past `end` (loads for the next iteration at r1+2..4*mmsize), but `x264_nal_end`
   pads only 64 bytes with 0xff. The extra bytes lie inside `p_bitstream` in practice: the
   result doesn't depend on them, but they can be uninitialised (valgrind). The avx2 version
   also writes up to 63 bytes past the output end (within the +64 that nal_buffer_size allows).
   The avx512icl version reads and writes nothing outside the buffers.
3. In this pass's own code, caught before commit: `%assign x A && B` assembles under nasm 3.01
   but nasm 2.14.02 warns "trailing garbage after expression ignored" and silently evaluates only
   `A`. That would have enabled the 8x8-only prefix code in the 4x4 kernels. Replaced with
   `%if A && B / %assign x 1`.

## nasm versions

Every changed .asm (bitstream-a, trellis-64; cabac-a unchanged) assembles with nasm 3.01 and
~/tools/nasm-2.14.02 for 8/10-bit, elf64 PIC and non-PIC, and win64. .text and .rodata are
byte-identical between the two versions for bitstream-a, cabac-a and trellis-64 (8 and 10 bit,
elf64). **No instruction in this pass needs a nasm newer than 2.14.02** (vpcompressb, vpermb,
vpermi2b, vpermt2b, vptestnmb, vpcmpub, kmovq, valignq, pdep all assemble on 2.14.02).

## Needs rack01 (Zen 4)

- trellis 8x8 zero-run prefix: in-situ normal-mode A/B (medium/speedcontrol, trellis 1/2,
  8-bit 4:2:0 and 10-bit 4:2:2 incl. 1080i), `TRELLIS_ICL_ZPREFIX=1` (default) vs `=0`. The
  checkasm bench block is unrepresentative (few zeros): judge in situ.
- nal_escape avx512icl: in-situ share is negligible. Check checkasm `--bench=nal_escape` on Zen 4.
  Laptop zmm is double-pumped, like Zen 4's.
- fix/configure-pie: PIC (RIP-relative) vs non-PIC asm A/B before merging, if wanted (upstream
  reports no measurable difference).
