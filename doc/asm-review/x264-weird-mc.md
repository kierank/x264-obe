# x264-obe unusual-instruction pass: mc (2026-10-20)

Package: common/x86/mc-a.asm, common/x86/mc-a2.asm, common/x86/mc-c.c dispatch, and
their checkasm tests. Base: origin/speed-next 0ac92fa9. Branch: wip/x264-weird-mc.
All new kernels are `INIT_YMM avx512icl` (EVEX ymm, x86inc's default registers),
x86_64 only, and are dispatched in braced `if( cpu&X264_CPU_AVX512ICL ) { ... }` blocks.

## Commits

| commit | content |
|--------|---------|
| ed1bda81 | checkasm: plane_copy_interleave/deinterleave on 1080p chroma rows (960 wide, 64-byte aligned, padded stride). The old cases are tiny, and their largest ones run the C fallback, so they neither test nor bench the full-row asm. Also benches them as `plane_copy_(de)interleave_960x4`. |
| 8bb70ebf | avx512icl frame_init_lowres_core (8 and 10-bit) and frame_init_lowres_core8 (10-bit, --lookahead-8bit, which zerolatency turns on) |
| dc1a037b | avx512icl plane_copy_interleave_core, plane_copy_deinterleave, 10-bit store_interleave_chroma |

## Correctness

- Build: `--bit-depth=all` (x264, checkasm8, checkasm10) with nasm 3.01, gcc 15.2, WSL.
  On this machine speed-next only links with `--extra-ldflags=-no-pie`; see "Existing issues".
- checkasm8 and checkasm10, seeds 1001, 2002 and 3003: all pass at every commit. The
  lowres-only intermediate state (8bb70ebf) was built and checked separately.
- Mutation checks: one instruction broken per kernel, then rebuilt. checkasm failed in
  every case, and passed again once the instruction was restored:

  | kernel | mutation | checkasm result |
  |--------|----------|-----------------|
  | lowres 8-bit | odd-byte vpermt2b index -> even | `frame_init_lowres differs at plane 1` |
  | lowres 10-bit | odd-word vpermt2w index -> even | `frame_init_lowres differs at plane 1` |
  | lowres8 | rows 1,2 vpermb source -> rows 0,1 | `lowres init8 FAILED` (plane 2) |
  | lowres8 | one index table byte 16 -> 17 | `lowres init8 FAILED` (plane 0, x 4) |
  | interleave 8-bit | v source -> u | `plane_copy_interleave FAILED w=16` |
  | interleave 10-bit | second half v -> u | `plane_copy_interleave FAILED w=16` |
  | deinterleave 8-bit | v half -> u half | `plane_copy_deinterleave FAILED w=1` |
  | deinterleave 10-bit | odd-word index -> even | `plane_copy_deinterleave FAILED w=1` |
  | store_interleave 10-bit | row 1 v -> u | `store_interleave_chroma FAILED h=8` |

- Encoder md5 identity: base 0ac92fa9 vs branch, both built with `-fno-fast-math
  -ffp-contract=off`, `--threads 1 --asm avx512icl`, 1920x1080 stressgen y4m piped to
  `--demuxer y4m`, CABAC only. There were 24 cells at 30 frames and 24 again at 60
  frames (the fades only start at frame 25), and all 48 md5s matched. The cells were
  {fades, pan-fast, extremes, chroma-motion} x {8-bit 4:2:0 lowlat, 8-bit normal, 10-bit
  4:2:2 lowlat, 10-bit 4:2:2 normal, 10-bit 4:2:2 1080i tff lowlat, the same normal}.
  - lowlat: `veryfast zerolatency --intra-refresh`, one-frame VBV.
  - normal: `medium`, 1 s VBV, `--weightp 2 --bframes 3`.
- Encoder positive controls: each kernel was mutated in an x264 build, and the stream md5
  then differed from the unmutated build. That proves the md5 cells reach each kernel:
  lowres 8-bit (8n), lowres 10-bit (10n), lowres8 (10l), interleave 8-bit (8l),
  interleave 10-bit (10l) and store_interleave (10l).
- plane_copy_deinterleave is **not** reached by any of the encode cells. A `ud2` placed in
  it never fired, in lowlat or normal, 8 or 10-bit, with `--weightp 2`, over 60 frames
  of fades. Its encoder callers are weightp's chroma cost when the lowres MVs are missing
  (slicetype.c:254, never seen) and `--dump-yuv` (encoder.c:371). It was therefore
  checked through `--dump-yuv`, 10 frames of chroma-motion at 8-bit and 10-bit 4:2:2.
  The dump md5s were identical between base and new, and the mutant's differed.
- nasm 2.14.02 (`~/tools/nasm-2.14.02/nasm`, the same flags as the build): mc-a.asm and
  mc-a2.asm assemble at both depths. All 8 new functions are byte-identical to the nasm
  3.01 objects (objdump comparison).

## Laptop bench (indicative only)

`checkasm --bench`, taskset CPUs 14/15 (one core's two SMT threads) on the HX 370, and
medians of 5-21 runs per series. The box was loaded (load average 12-18, with other agents'
compiles unpinned on all CPUs), and individual runs varied by up to 2x. The series
below are the repeat measurements of the same pair. Base = the level speed-next
dispatches on an avx512icl CPU.

| function | base level | base -> new (median per series) | ratio |
|----------|-----------|----------------------------------|-------|
| lowres_init 8-bit (w 96-120, h 8) | avx2 | 1548->1552, 1276->1372, 1736->1612, 1774->1642 | ~1.00 (neutral) |
| lowres_init 10-bit | avx2 | 3022->2768, 2577->2086, 2929->2777, 3125->2843 | 0.81-0.95 |
| lowres_init8 10-bit | avx2 | 2482->2160, 2959->2755, 3125->3016 | 0.87-0.97 |
| plane_copy_interleave_960x4 8-bit | sse2 | 5530->5694, 4885->3873, 4048->3769, 5083->5042 | ~0.9-1.0 (NT-store bound) |
| plane_copy_interleave_960x4 10-bit | avx | 7414->8036, 7105->8431, 8502->8471, 8041->7880 | ~1.0 (NT-store bound, noisy) |
| plane_copy_deinterleave_960x4 8-bit | ssse3 | 3787->2294, 3234->2074, 3243->2190 | 0.61-0.68 |
| plane_copy_deinterleave_960x4 10-bit | avx | 5792->3190, 4750->2163, 5811->2995 | 0.46-0.55 |
| store_interleave_chroma 10-bit (h 8/16) | avx | 125->37, 45->16, 30->26 | below the timer floor; fewer instructions (4 vs 6 per row) |

The interleave is non-temporal-store bound: its compute halves, and its time does not
change. It is dispatched as neutral, under the brief's rule.

## Per-function log

Levels below are what an avx512icl CPU runs today (8-bit / 10-bit).

| function | current best level | unusual instructions considered | tried? | bit-exact? | laptop base -> new | decision | reason |
|----------|-------------------|---------------------------------|--------|-----------|--------------------|----------|--------|
| frame_init_lowres_core | avx2 / avx2 | vpermt2b/vpermi2b (VBMI), vpermt2w/vpermi2w, GFNI byte shift, zmm | yes | yes (checkasm, md5, mutation) | 8: neutral; 10: 0.81-0.95 | **dispatched** (avx512icl ymm) | One two-source permute per output plane replaces pshufb+punpck+vpermq (8-bit, 12 -> 4 permutes + 2 movs per 64 columns) and psrld+pand+packusdw+vpermq (10-bit, 8 -> 2 permutes + 1 mov per pair). GFNI has no use: the split is a byte gather, not a shift. zmm was not written: the kernel rounds the width up to mmsize, so 64 would overwrite up to 63 px into the next row's left pad, which with sliced-thread lowres bands belongs to another thread. It would need masked tail stores, and it is double-pumped on Zen 4 anyway. |
| frame_init_lowres_core8 (10-bit lowlat) | avx2 | vpermb, vpmultishiftqb, vpmovuswb | yes (vpermb) | yes | 0.87-0.97 | **dispatched** | vpermb replaces pshufb+vpermd after packuswb. vpmultishiftqb could extract bits 2-9 of each word, but (x+2)>>2 must saturate 256->255 first, so it needs pminuw: no saving. |
| plane_copy_interleave_core (I420/I422 input -> NV12/NV16, serial per frame) | sse2 / avx | vpermt2b, vpermt2w, zmm | yes | yes (incl. pad bytes) | ~neutral (NT-store bound) | **dispatched** | 2 loads + 1 vpermt2b + 1 store per 32 output bytes, vs 6 (8-bit) and 6 per 32 bytes (10-bit). It needs 32-byte aligned rows for ymm movntdq, so the C wrapper falls back to sse2/avx otherwise (x264 frames are 64-byte aligned). The pad loop writes the same 16 bytes as before. |
| plane_copy_deinterleave | ssse3 / avx | vpermb, vpermt2w/vpermi2w | yes | yes (checkasm, --dump-yuv md5) | 0.61-0.68 / 0.46-0.55 | **dispatched** | 8-bit: 1 load + 1 vpermb + 2 stores per 16 px (was 8 ops). 10-bit: 2 loads + mov + 2 permutes + 2 stores per 16 px (was 20). Same 16 px over-write as before. Cold in the encoder: only --dump-yuv and weightp chroma without lowres MVs reach it. |
| store_interleave_chroma (per MB) | sse2 / avx | vpermt2b, vpermt2w | 10-bit yes | yes | 10-bit below the timer floor (4 vs 6 ops/row) | **dispatched** (10-bit) | 10-bit 4:2:2: 16 rows/MB x 2 ops saved. 8-bit not done: sse2 is already movq + punpcklbw [mem] + store per row (3 ops). A zmm two-row vpermt2b is 5 ops per 2 rows and is double-pumped on Zen 4. |
| load_deinterleave_chroma_fenc/fdec | avx512 (pshufb) / avx2 | vpermb, vpermw | no | - | - | rejected (already done) | 8-bit avx512 already exists. 10-bit vpermw was tried as GG (zen5/asm-avx512-dblk-deint): bench -24%, chained -4%, in situ flat on rack01. |
| hpel_filter 8-bit (fused v/c/h, hpel_filter_copy, 3-pass) | avx2 | vpdpbusd (u8 x s8 taps), vpdpwssd for c, vpshrdq funnel shifts for the H windows, vpermt2b windows | analysed (op counts) | - | - | rejected | vpdpbusd sums 4 taps into one dword, so output density is half that of pmaddubsw's words. 32 H outputs cost about 36 uops (2 loads + 2 pshufb + 2 vpdpbusd + mov per 8 outputs, then 4 psrad + 3 packs + permute) vs 21 in DO_FILT_H. The two accumulators that latency needs don't change the count. The 16 V outputs would need 3 unpacks per 4-row dword group: worse. c via vpdpwssd is about 18 vs 18 uops per 16 outputs: even/odd outputs need dword- and word-shifted inputs and a re-interleave. The H windows via valignq + vpshrdq are 7 ops, the same as 2 vperm2i128 + 5 palignr. The 10-bit equivalent (VNNI hpel_c, zen5/asm-vnni e7e36cca) was neutral on Zen 4. |
| hpel_filter 10-bit (1-pass, copy 3-pass) | avx2 | vpdpwssd | no (exists) | - | - | rejected (exists on zen5/asm-vnni) | VNNI 10-bit hpel_c is parked on zen5/asm-vnni (neutral on Zen 4). The AVX-512 one-pass VNNI hpel (aa3c1e8e) is parked in zen5/asm-avx512vl-regs. |
| mc_chroma 8-bit | avx2 | vpdpbusd (bilinear = exactly 4 u8 x s8 taps, weights <= 64), vpermb | analysed | - | - | rejected | vpdpbusd is an exact fit for the 2x2 bilinear filter. But its dword outputs need vpermb to build [s(x), s(x+2), t(x), t(x+2)], plus psrld and two packs: 10 ops per 2 rows of 4x(u,v) vs 7 (pshufb x2, pmaddubsw x2, paddw, pmulhrsw, packuswb). The 4-wide stores (4 movd/pextrd per 2 rows) dominate either way. |
| mc_chroma 10-bit | avx2 | vpermw zmm | no | - | - | rejected (exists) | The zmm variant is still in the source (MC_CHROMA_HBD `mmsize == 64`) but was dropped from the build by d0395c5b (slower on Zen 4). |
| mc_weight / offsetadd / offsetsub / weight_plane 8-bit | avx2 (w4 ssse3), offsets sse2/mmx2 | vpdpbusd, vpmovuswb, GFNI | analysed | - | - | rejected | A single tap: pmulhrsw is already one op per word. vpmovuswb can't replace packuswb (it saturates signed words as unsigned: negatives -> 255). |
| mc_weight family 10-bit | avx512 ymm (w12/16/20, plane zmm) / avx2 | vpdpwssd | analysed | - | - | rejected | Single tap. Already AVX-512 where it won. |
| mc_weight_avg / offset*_avg (fused weighted qpel avg) | avx2 | vpdpbusd | analysed | - | - | rejected | 2-tap average + 1 tap: no 4-tap group, so dword density loses. |
| pixel_avg_WxH / pixel_avg_weight (biweight) 8-bit | avx512 (16x8, 8x16, 8x8, 8x4), avx2 16x16, ssse3 4xN | vpdpbusd | analysed | - | - | rejected | 2 taps: pmaddubsw gives word sums directly, while vpdpbusd needs 2x the registers and repacking. |
| pixel_avg 10-bit | avx2 / sse2 4xN | - | no | - | - | rejected | pavgw / pmulhrsw word ops: no unusual instruction applies. |
| pixel_avg2_w4..w20 (hpel average, ME) | avx2 w16/w20, sse2/mmx2 (8-bit); avx/avx2 (10-bit) | AVX-512 masked loads for the w10/w18/w20 tails | no | - | - | rejected | pavgb/pavgw with load-port-bound loops. 4704a0ab/asm-mcpy closed avg2. Note: 8-bit mc_luma still uses the sse2 avg2 table (MC_LUMA avx2 is HBD only), but the avx2 table differs only at w20. |
| mc_copy_w4/w8/w16 | mmx/sse/avx | - | no | - | - | rejected | Plain copies. |
| plane_copy / plane_copy_core | avx512 (masked tail) / avx2 | - | no | - | - | rejected | Already AVX-512 with k-mask tails. plane_copy_swap is defined but not instantiated (unused). |
| plane_copy_deinterleave_rgb | ssse3 | vpermb | no | - | - | rejected | OBE never feeds RGB to x264. |
| plane_copy_deinterleave_v210 | avx512 | vpmultishiftqb (10-bit field extraction) | no | - | - | rejected (logged only) | OBE never feeds v210 to x264 (brief). vpmultishiftqb would be the natural fit. |
| memcpy_aligned / memzero_aligned | avx512 | - | no | - | - | rejected | Already zmm. |
| prefetch_fenc_420/422, prefetch_ref | mmx2 | - | no | - | - | rejected | Prefetch only. |
| integral_init4h/8h (8-bit) | avx2 (mpsadbw) | vdbpsadbw, log-step prefix sums | analysed | - | - | rejected | Only ESA/TESA call these (not production; ESA is disabled under interlace). They are sliding 4/8-sums plus the row above, not a serial prefix, so x265's log-step prefix-sum trick has nothing to remove. vdbpsadbw against zero gives 4-sums at offsets 0-3 per qword: two per 8 outputs plus an unpack, which is no better than mpsadbw. |
| integral_init4v/8v | avx2 | - | no | - | - | rejected | Two word adds/subs per vector, and not production. |
| mbtree_propagate_cost | avx512 (vdivps) | IFMA | analysed | - | - | rejected | Float math with output rounding; IFMA is 52-bit integer multiply and doesn't apply. |
| mbtree_propagate_list (internal + C clip-add loop) | avx512 internal | vpcompressw (active-entry list), vpconflictd + gather/scatter, VP2INTERSECT | analysed | - | - | rejected | The scatter is a saturating 16-bit add into overlapping dword pairs (idx0/idx0+1). vpconflictd only sees equal dword addresses, not overlaps, and scatter is slow on Zen 4. vpcompressw of the entries whose list bit is set could cut branch mispredicts in the C loop, but mbtree only runs in normal mode, and the loop needs its edge/zero-MV branches anyway. Not worth it without a profile showing it. |
| mbtree_fix8_pack/unpack | - | vpshufb/vpermb byte swap | - | - | - | n/a | Not in this fork (no mbtree fix8 file I/O). |

## Unusual instructions summary

- **VBMI (vpermb, vpermt2b, vpermi2b)**: found a use in lowres init (even/odd byte split),
  lowres8, plane interleave and deinterleave. All of these are byte gathers from two
  vectors that AVX2 does as pshufb + unpack + lane fixups.
- **vpermt2w/vpermi2w** (AVX-512BW, word versions): 10-bit lowres, plane
  (de)interleave, store_interleave. No loss measured here. The x265 pass found they lose
  against punpck in transposes (3-cycle latency, an input destroyed), but these are
  one-shot gathers with no dependency chain.
- **VNNI (vpdpbusd, vpdpwssd)**: no use. Every mc filter outputs words or bytes. vpdpbusd's
  4-into-1 dword sum halves the output density, and repacking costs more than the
  multiplies save. That holds for hpel (6 taps), mc_chroma (4 taps, an exact fit
  otherwise), weighting (1 tap) and biweight (2 taps).
- **GFNI**: no use. No per-byte shifts or bit-matrix work remain: lowres, avg and the
  (de)interleaves are gathers, and the byte filters work in words.
- **VBMI2 (compress/expand, vpshld/vpshrd)**: no use. The funnel shift is an alternative
  for the hpel H windows, at the same op count. Compress was considered for the mbtree
  list and not done (above).
- **vpmultishiftqb**: lowres8's rounding needs saturation first. It is the natural tool
  for v210, which OBE doesn't feed x264.
- **BITALG / VPOPCNTDQ / CD (vpconflict, vplzcnt) / IFMA**: no use. No bit counting,
  conflict-free scatter or 52-bit integer multiply exists in mc.
- **vpternlog / k-masks**: plane_copy already uses k-mask tails. The new kernels needed
  neither.

### VP2INTERSECT

No use found. Nothing in mc intersects two index or value sets. The only scatter-like
code, the mbtree_propagate_list clip-add, accumulates into neighbouring cells that
overlap. A set intersection can't detect those overlaps, and the work is a saturating
add, not a membership test.

## nasm

No new instruction needs a nasm newer than 2.14.02. vpermb, vpermt2b, vpermi2b,
vpermt2w, vpermi2w and vextracti32x4 all assemble with 2.14.02 to the same bytes as
3.01.

## Existing issues found (not fixed here)

1. **Link failure with a default-PIE gcc** (cabac package, not mc): speed-next 0ac92fa9
   fails to link on WSL gcc 15.2 with `relocation R_X86_64_32S against symbol
   'x264_cabac_range_lps' can not be used when making a PIE object`. The non-PIC branch
   of cabac-a.asm:1247 (`movzx r4d, byte [cabac_range_lps-4+r4+r5*2]`) uses an absolute
   address, and configure builds non-PIC asm without `--enable-pic`. The workaround here
   was `--extra-ldflags=-no-pie`. Any distro gcc that defaults to PIE (Ubuntu >= 17.04)
   needs this or `--enable-pic`.
2. **plane_copy_interleave_core pad bound at 10-bit** (mc-a2.asm, PLANE_INTERLEAVE):
   `shr t1, SIZEOF_PIXEL` shifts the byte stride right by 2 at high bit depth where 1 is
   meant, so the pad loop fills less of the row padding than at 8-bit. It is harmless, because the pad holds junk
   that the C version never writes and x264 doesn't read. The avx512icl core keeps the
   same bound, so its memory writes match the old core.
3. **Dead code**: the zmm branch of MC_CHROMA_HBD and PLANE_COPY_AVX512's swap variant are
   assembled nowhere. Both are deliberate (d0395c5b; plane_copy_swap is unused).

## Needs rack01 (Zen 4)

- In-situ cycles for 8bb70ebf (lowres; at 10-bit lowlat lowres8 runs per band on the sliced
  threads) and dc1a037b (interleave per input frame, store_interleave per MB).
  Expect both to be at or below resolution: the lowres kernels are memory-heavy, the
  interleave is NT-store bound, and store_interleave saves about 30 ops per MB at 10-bit
  4:2:2.
- checkasm 3 seeds and the 12-cell md5 matrix at nasm 2.14.02 and its successor.
- No zen5/ branch: no kernel here was slower on the laptop, and none was written as zmm
  (the reasons are in the table).

## Round 2 (2026-10-20)

Rule: every candidate is written and dispatched at avx512icl; rack01 decides, and
Kieran moves the losers to zen5/. Branch wip/x264-weird2-mc on
origin/wip/x264-weird-sa8d8 (67b4aff6). One commit per kernel.

Gates per kernel:
- A standalone C driver (WSL gcc, objects from nasm 3.01) checks the kernel against the C
  reference copied from common/*.c. Every call goes through x264_checkasm_call (callee-saved
  GPRs) with random k1-k7 loaded before it, and XINUSE is checked after it (no dirty ymm/zmm0-15).
- The drivers cover random data, 0/PIXEL_MAX/alternating/sign patterns, every width, height
  and pointer alignment the callers use, odd strides, and limit parameters.
- Input and output row ends are placed against PROT_NONE pages, and a canary checks that
  nothing is written outside what C writes.
- Mutations: at least three single-instruction or table edits per kernel, each FAILS or
  faults. Deleting each kernel's k-mask setup also fails, so no kernel relies on a stale mask.
- nasm 2.14.02: every changed function disassembles the same as with nasm 3.01. The only
  difference anywhere is cltq vs movslq %eax,%rax, an encoding of the same instruction in
  the existing MC_CHROMA_START macro.
- mc-c.c is compiled at both depths, and every *_avx512icl symbol it references exists in
  the assembled objects. The 406 pre-existing functions of mc-a/mc-a2 disassemble
  unchanged, except the fixed avx2 integral_init4h/8h.
- On AC power: x264 --bit-depth=all was built at 2d221b50, 2d0ed692, dba5fcf9, c697ddd9,
  23c97c12 and 3bda5c57. checkasm8 and checkasm10 pass seeds 1001/2002/3003 at each
  (2d221b50 with the eab2461e checkasm fix).
- No encodes on the laptop: the md5 identity check against 67b4aff6 is rack01's.

| function | round-1 decision | round-2 action | commit | driver result | nasm 2.14.02 ok? |
|---|---|---|---|---|---|
| hpel_filter 8-bit (fused v/c/h + copy) | rejected (analysed) | written: H by 8 vpdpbusd (4 phase accumulators) on valignq + immediate vpshrdq windows; c by 6 {evex} vpdpwssd (even/odd accumulators, odd taps <<6), exact (S+512)>>10; v as avx2 (vshufi64x2 lane fix) | 86e98e9b | pass, 6000 cases (widths 32-320, every src misalignment, h 1-8, 9 patterns incl. v/c/h extremes, copy variant); written bytes identical to avx2; mutations: H window shift, c tap, c shift, valignq, vshufi64x2 imm all fail | yes |
| mc_chroma 8-bit | rejected (analysed) | written: zmm two rows, vpermi2b gathers {s[2x],s[2x+2],t[2x],t[2x+2]}, {evex} vpdpbusd vs (cA,cB,cC,cD), (sum+32)>>6 exact, vpermt2b pack; masked loads (2w+2 bytes) and stores (w bytes) | e6faa772 | pass, 100k cases (w 2/4/8, h 2-16, mv +-32, dst strides 8/16/32, interleaved u/v) + PROT_NONE source end; mutations: shift, window index, store mask, load mask, weight pack all fail | yes |
| mc_weight/offsetadd/offsetsub 8-bit w4-w20 | rejected | written: masked rows, both rows in one register via masked vpbroadcastd/q or vinserti32x4 (w12 masked 12-byte loads, 3f38166e), w20 one row per register under a 20-byte mask; pmulhrsw (ssse3 cache) + pmaxsw 0 + vpmovuswb; offsets paddusb/psubusb. vpdpbusd (src,1)x(scale,offset) is not exact: (1<<(denom-1))+(offset<<denom) does not fit a signed byte tap | 6b1955e1, 3f38166e | pass, 400k cases (scale -128..127 incl. limits, offset -128..127, denom 0-7, in place, guards); mutations: clip, second-row address, w12 mask, shift, load offset all fail | yes |
| weight_plane 8-bit (none dispatched before) | (in the weight row) | written: zmm rows (weights 32 px as words, offsets 64 px), masked tail; weight_plane_icl8 | 3bda5c57 | pass, 30k planes (w 8-480, even h, both strides, guards); mutations: tail mask width, column step, signed pack, mask setup all fail | yes |
| mc_weight family 10-bit | rejected | written: new x264_weight_cache_icl keeps every scale (avx2 sends negative/large to SSE2); even/odd pixels by two {evex} vpdpwssd vs (scale,0)/(0,scale) from the dword bias, psrad denom, packusdw+pminuw, pshufb; offsets on the mmx2 cache; w4/w8/w16 two rows per register by masked broadcasts, w12/w20 word masks; zmm weight_plane with masked tail | 2d221b50 (+ checkasm eab2461e) | pass, 300k + 20k planes, scale -128..127, offset -128..127, denom 0-7, guards; mutations: tap shift, psrad, clip, interleave table, row mask, plane tail mask, second-row op, second-row address all fail | yes |
| mc_weight_avg/offset*_avg (fused qpel avg) | rejected | written both depths: pavg of src2's rows (same masked row packing) then the avx512icl op; 8-bit w12 = w16 kernel as at avx2 (checkasm expects it); weightavgfn from x264_weight_cache_icl8 / _icl | 2d0ed692 | pass, 300k cases per depth incl. odd heights 1-17, guards; mutations: pavg operand, src2 row address, src2 advance (both depths) fail | yes |
| pixel_avg 8-bit 16x16, 4x16/4x8/4x4/4x2 | rejected (analysed) | written: biweight by two {evex} vpdpbusd (even (w1,w2,0,0), odd (0,0,w1,w2)), psrad/pslld 10 + vpblendmw, packuswb; w16 two rows per ymm (masked vbroadcasti32x4), w4 two rows per xmm (masked vpbroadcastd); weight-32 4xN gets an EVEX pavgb kernel (mmx2 read 8 bytes of src2 rows) | 3a150295 | pass, 300k cases, weights -63..127 and 32, guards, odd strides; mutations: odd shift, blend mask, odd taps, pavgb, src2 row address fail | yes |
| pixel_avg 10-bit (all sizes) | rejected | written: biweight (s1,s2) pairs x (w1,w2) by two {evex} vpdpwssd from the rounding, psrad 6, packusdw+pminuw (exact for -64..128); pavgw for weight 32; two rows per xmm/ymm/zmm by masked broadcasts | dba5fcf9 | pass, 300k cases, guards; mutations: shift, weight pack, clip, row mask, src2 stride, mask setup fail | yes |
| pixel_avg2_w4..w20 (both depths) + mc_luma/get_ref | rejected | written: 4/8/16/32-byte rows two per register by masked broadcasts, 12/20/24/40-byte rows under byte masks; exact width reads/writes; new avx512icl mc_luma/get_ref and avg wtab both depths (dispatched last: the AVX2 get_ref after the depth blocks overrode it) | cb7b11af | pass, 300k cases per depth, guards; mutations: row masks, src2 address, broadcast address fail | yes |
| mc_copy_w4/w8/w16 (both depths) | rejected | written: two rows per register by masked broadcasts (10-bit w16 per zmm); copy[], copy_16x16_unaligned and the mc_luma copy table | 5aa84e6d | pass, 200k cases per depth, guards; mutations: address, masks, pextrd lane fail | yes |
| store_interleave_chroma 8-bit | rejected | written: two rows per ymm, movq + masked vpbroadcastq of u and v, one vpermt2b (pb_ilv_icl) | 917f048b | pass, 100k cases (h 2-16, u/v layouts), guards; mutations: src row, table, mask fail | yes |
| frame_init_lowres_core (8/10-bit), lowres_core8 | dispatched ymm (round 1) | written zmm with masked tails, OVERRIDES the round-1 ymm slots (kept assembled): writes exactly the ymm kernels' extent (width rounded to 32 bytes, core8 to 16 px), tail loads only the first half | 64c68f3e | pass, 6000 runs x (core, core8) incl. byte-identical whole buffers vs the round-1 ymm kernel and guards on source and every plane; mutations: rounding, tail mask, odd table, lowres8 table, core8 mask, row address fail | yes |
| integral_init4h/8h (8-bit) | rejected | written: log-step sums (a=p+p1, 4-sum=a+a2, 8-sum=s4+s4[x+4]) on vpmovzxbw zmm with valignq + immediate vpshrdq windows; reads what avx2 reads | 4bd3a682 | pass, vs C and vs the fixed avx2 on the whole written region, guards; mutations: window, 8-sum shift fail | yes |
| integral_init4v/8v (both depths) | rejected | written: zmm; 4v's x+4 window a valignq with a qword load (avx2 reads 8 bytes past too) | 4bd3a682 | pass, vs C and vs avx2/sse2 whole region, guards; mutations: valignq, operand, address fail | yes |
| mbtree_propagate_list | rejected (analysed) | written: mbtree_propagate_list_active (vptestmw, register vpcompressw, masked store of popcnt words); the C clip-add loop runs only over those entries, in order. vpconflictd not used (overlapping idx0/idx0+1 saturating adds) | c697ddd9 | pass: active lists 20k (len 1-260, both lists, densities, guards); 4000 rows ref_costs byte-identical to the avx512 wrapper, within the existing +-1 of C; mutations fail/fault | yes |
| plane_copy_deinterleave_rgb | rejected (no RGB in OBE) | written: masked load of 16*pw bytes, one vpermb, masked tail (exact w px) | 23c97c12 | pass, 20k cases pw 3/4, guards on source and all planes; mutations: table, masks, step, extract fail | yes |
| mc_chroma 10-bit zmm | rejected (dropped by d0395c5b) | zen5: local branch zen5/x264-weird2-mc-chroma-hbd-zmm fc7b6ca5 (on 67b4aff6), MC_CHROMA_HBD INIT_ZMM avx512 instantiated and dispatched, not pushed | fc7b6ca5 (zen5, local) | pass, 100k cases + guards (width 2 compared on its 2 px: mc_chroma_avx); mutations: valignq, row insert fail; checkasm8/10 x3 pass on that branch | yes |
| load_deinterleave_chroma 8-bit / 10-bit | rejected | skipped: 8-bit avx512 already dispatched; 10-bit vpermw exists on origin/zen5/asm-avx512-dblk-deint | - | - | - |
| hpel_filter 10-bit | rejected | skipped: VNNI exists on origin/zen5/asm-vnni and origin/zen5/asm-avx512vl-regs | - | - | - |
| plane_copy, memcpy_aligned, memzero_aligned, mbtree_propagate_cost | rejected | skipped: already AVX-512 dispatched | - | - | - |
| plane_copy_deinterleave_v210 | rejected | skipped: OBE x264 gets no v210 input (Kieran) | - | - | - |
| prefetch_fenc_420/422, prefetch_ref | rejected | skipped: prefetch instructions only, no data path | - | - | - |
| mbtree_fix8_pack/unpack | n/a | skipped: not in this fork | - | - | - |
| plane_copy_interleave, plane_copy_deinterleave, 10-bit store_interleave_chroma | dispatched (round 1) | unchanged | - | - | - |

### nasm

Nothing new needs nasm > 2.14.02. vpdpbusd/vpdpwssd ({evex}), vpshrdq (immediate),
valignq, vpermb, vpermi2b, vpermt2b, vpermi2w, vpermt2w, vpcompressw, vptestmw,
vpmovuswb, vpmovzxbw and every masked load and store assemble with 2.14.02 to the
same functions as 3.01. None of the variable vpshldv*/vpshrdv* are used.

### Existing asm bugs found

1. **Fixed (594505d0): 8-bit avx2 integral_init4h/8h column order** (mc-a2.asm
   INTEGRAL_INIT4H/8H, mmsize==32). The row was loaded as one ymm plus one at x+8, and the
   ymm mpsadbw sums each lane on its own. So each 32-column block was stored as
   x+0..7, x+16..23, x+8..15, x+24..31.
   - Reached by --me esa/tesa integral images on AVX2 CPUs.
   - checkasm called the functions with sum+stride but compared only row 0, so the test
     could not fail; it now also compares row 1.
2. **Fixed in checkasm (eab2461e): the weight_plane test** hard-coded which scales the
   avx2 cache sends to SSE2. The avx512icl cache handles them, so the test now compares
   those rows with C instead.
3. **Not fixed: 10-bit mc_chroma_avx2 (and the dropped zmm) loop4/loop8** load one source
   row past the last row they use (row h+1). This was found by putting the source end
   against a PROT_NONE page: it faults in x264_10_mc_chroma_avx2.loop4. Harmless on padded
   frames.
4. **Not fixed: pixel_avg_w4_mmx2** (AVG_FUNC 4) reads 8 bytes per 4-wide src2 row
   (pavgb mm, [mem]). The new avx512icl 4xN path reads 4.
5. **Not fixed: commit message mismatch in d0395c5b.** The message names
   mbtree_propagate_list as 1.60x slower, but the commit does not drop it: the avx512
   version is still dispatched, so no zen5 branch was made for it.

### zen5 branches (local, not pushed)

- zen5/x264-weird2-mc-chroma-hbd-zmm fc7b6ca5: 10-bit mc_chroma avx512 (zmm) re-enabled.
