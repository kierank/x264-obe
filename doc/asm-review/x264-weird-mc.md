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
