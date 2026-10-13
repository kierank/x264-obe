# --me-8bit stage 3: SVT style storage of the reference planes (design only)

Stages 1 and 2 (`--me-8bit 1|2`) add an msb8/lsb8 split next to the 16-bit
reference planes; everything outside the integer and subpel search still
reads the 16-bit planes. Stage 3 would drop the 16-bit reference planes and
keep only msb8 + lsb8 (10 bits a pixel stored instead of 16: -37.5% of the
plane bytes). This is a storage change only: msb << 2 | lsb is the 16-bit
value exactly, so with every reader unpacking bit-exactly the output must be
md5-identical to the same encode with 16-bit storage.

Layout (as stages 1/2, `common/frame.h`): per plane one block, msb rows
(stride `i_stride` bytes, the 16-bit plane's geometry and padding) then lsb
rows (stride `i_stride/4`, pixel x in bits `2*(x&3)` of byte `x>>2`).
Unpack of 16 pixels: 16 msb bytes + 4 lsb bytes -> `vpmovzxbw`, `psllw 2`,
lsb bytes broadcast and spread to words (`pshufb` 0,0,0,0,1,1,1,1,...),
per-word shift by 0/2/4/6 (`vpsrlvw` on AVX-512BW; AVX2: `pmullw` by
64/16/4/1 then `psrlw 6`), `pand 3`, `por`: 6-8 ops per 16 pixels. Pack
(stage 1 `plane_split8`): 6.5 ops per 16 pixels (AVX2), 4.5 (avx512icl).

## Planes in scope

| plane | 16-bit size per 1080p ref (derived: stride 1984, 1088+64 rows) | readers on the hot path |
|---|---|---|
| luma fullpel `plane[0]` / `filtered[0][0]` | 4.6 MB | fpel ME, MC, hpel input, deblock, PSNR, recon |
| luma h/v/c `filtered[0][1..3]` | 13.7 MB | subpel ME, MC |
| field luma `plane_fld[0]`, `filtered_fld[0][*]` (MBAFF) | +19.3 MB (1088+128 rows) | as above, field MBs |
| chroma `plane[1]` (NV12/NV16, interleaved uv) | 2.3 / 4.6 MB | mc_chroma, satd_mcc, deblock, PSNR |
| field chroma `plane_fld[1]` (MBAFF) | as chroma | field mc_chroma at field edges (see wip/fld-chroma-edge 613552d9) |
| 4:4:4 chroma planes 1, 2 with their hpel planes | as luma | as luma |

## Every reader and writer at speed-next (6e76c333 + this branch)

Each entry: what it would read/write instead; whether the unpack/pack fuses
into the existing kernel's loads/stores or needs a temp block; kernels
affected; cost against the saving.

### Writers

1. **Recon store, `x264_macroblock_cache_save`** (`common/macroblock.c`,
   `copy[PIXEL_16x16]` luma, `store_interleave_chroma` NV12/NV16). Writes
   the 16x16 recon from the fdec cache (`p_fdec`, stays 16-bit) into the
   frame. Becomes a pack store: `plane_split8` of 16 rows (luma), a uv
   interleave + pack for chroma. Fused: the copy becomes the pack (the MB is
   16 px = 4 lsb bytes a row, MB edges are lsb byte edges, no RMW). Kernels:
   new `store8_16x16`, `store_interleave_chroma8`. Cost ~+6 ops/16 px on a
   kernel that is a pure copy today; small (once per MB). Saving: 192 of
   the luma MB's 512 store bytes (derived).
2. **Deblock, `x264_frame_deblock_row`** (`common/deblock.c`; asm
   `deblock_v_luma`, `deblock_h_luma`, `deblock_h_luma_mbaff`,
   `*_luma_intra*`, `deblock_luma_mb` AVX2, chroma `deblock_v/h_chroma*`,
   `deblock_h_chroma_422*`, `*_mbaff`). In-place read-modify-write of the
   frame. Vertical edges touch x = 16k-3..16k+2: two lsb bytes per row,
   both owned by the same row; horizontal edges touch whole rows. Options:
   (a) unpack the 16-bit window around the edge, filter, repack (temp
   block per MB edge: 16x(16+6) luma); (b) deblock the MB in the 16-bit
   fdec cache before cache_save (needs the neighbours' unfiltered
   pixels, i.e. a 16-bit band of the row above and the left column: what
   x264 upstream avoided by deblocking the frame). (a) is the conservative
   path: every deblock kernel gets an unpack prologue and a pack epilogue,
   or one per-MB-row helper unpacks 16+4 rows to a scratch band, runs the
   existing kernels on it and repacks. The band helper changes no asm and
   costs ~2x the bytes of the band through L1; recommended.
3. **Border expansion**: `x264_frame_expand_border` (frame and field
   pads of all planes), `x264_frame_expand_border_filtered` (h/v/c),
   `x264_frame_expand_border_chroma`, `x264_expand_border_mbpair`
   (fenc only, out of scope), `x264_frame_expand_border_mod16*` (fenc).
   Byte versions exist: `plane_expand_border8` (stage 2) is the 8-bit
   mirror for luma; chroma (`b_chroma`: 2-pixel uv replication) needs an
   lsb pattern of the uv pair, (u lsb | v lsb << 2) * 0x11. C only, no asm.
4. **hpel filter** (`x264_frame_filter`, `frame_filter_fld`; asm
   `hpel_filter_avx2` one pass, `hpel_filter_v/c/h(_copy)_{sse2,avx2}`,
   C `hpel_filter`). Output: stage 2's `hpel_filter8` already stores the
   split; drop the 16-bit stores (a variant with only the 8-bit stores).
   Input: the fullpel rows -2..+3 per output row, read as msb+lsb: fuse the
   unpack into the six row loads of the v filter and the h loads (the
   one-pass kernel loads each source chunk once per row for v plus the
   unaligned h windows; the h windows would come from the unpacked row 0
   via `palignr`/`vperm2i128`, as the c window does). ~+7 ops per 16 px per
   loaded row: the v filter loads 6 rows per output row, so +42 ops per
   chunk against ~45 today unless rows are unpacked once into a rolling
   6-row 16-bit ring (temp block 6 x row, L1-resident at 1984 px = 24 KB:
   too big for L1 with the outputs; per 64 px column strips instead). This
   is the costliest kernel change and the riskiest asm.
5. **plane_fld copies**: `fdec_copy_fld_rows` (`encoder/encoder.c`),
   `hpel_filter_copy` (field pass) copy frame rows into plane_fld. Become
   byte copies of msb and lsb rows (cheaper: 10/16 of the bytes). For
   chroma, 613552d9 already removes most of the copy.
6. **Weighted reference planes**: `x264_analyse_weight_frame`
   (`encoder/analyse.c`) and `x264_weighted_reference_duplicate`
   (`encoder/encoder.c`) write `fenc->weighted[k]` from the ref's
   fullpel via `x264_weight_scale_plane` (`mc_weight_w*`). Keep the
   weighted plane 16-bit (it is per-frame scratch, one plane per weighted
   ref, and the fullpel search falls back to 16-bit for it) and fuse the
   unpack into the weight kernel's source load; or store it split too and
   let the level 1 search use it (removes the weighted-ref fallback).
7. **Integral image** (ESA/TESA, `x264_frame_filter`, `integral_init4h/8h`
   + `4v/8v`): reads the fullpel rows; sums of unpacked 10-bit values,
   unpack fused into the h kernels' row loads.

### Readers

8. **Final MC** (`common/macroblock.c` `x264_mb_mc_0xywh`/`1xywh`/`01xywh`,
   `encoder/macroblock.c` P-skip/probe_skip; `mc_luma`, `get_ref`,
   `pixel_avg2_w4/8/10/12/16/18/20`, `pixel_avg*` weighted bipred,
   `mc_weight_w*`, `mc_chroma`, `load_deinterleave_chroma_fdec` for the
   zero-mv chroma copy). Fullpel copies become an unpack (`mc_copy` ->
   `unpack8`), hpel averages read two split planes: fuse the unpack into
   `pixel_avg2`'s two loads (+14 ops per 16 px row on a 4-op kernel) or
   unpack each source block once (temp 16x17). mc_chroma's bilinear 2x2
   reads (u,v interleaved): unpack the (w+1)x(h+1) source window into a
   temp, then the existing kernel. Cost: MC is per partition, a few % of
   the encode; the unpacks roughly double the MC kernels' cost.
9. **Subpel ME and RD** (`encoder/me.c` refine_subpel, `x264_me_refine_qpel_rd`,
   `x264_me_refine_bidir_rd/satd`, `COST_MV_RD`, `BIME_CACHE`,
   `x264_rd_cost_part`; kernels `sad/satd_avg2`, `satd_avg2_pre`,
   `satd_bi/bi4`, `satd_mcc`). Level 2 already reads msb8 for the luma
   search; the exact 16-bit cost at the result (ME8_EXACT), qpel RD,
   bidir and chroma ME need unpacked predictions: unpack in get_ref (temp
   block, as get_ref already writes one for qpel) and in the fused
   `*_avg2` kernels' loads.
10. **Fullpel ME** fallbacks: weighted refs (6), ESA/TESA sads on candidates
   (unpack fused into sad loads, or run ESA on msb8 too), the subme >= 3
   subpel predictor costs in me_search_ref (`COST_MV_HPEL`), the level 1
   exact recompute: all through the get_ref/avg2 unpack of 8/9.
11. **hpel input**: see 4.
12. **Intra left column on reload** (`x264_macroblock_load_pic_pointers`,
   `b_mbaff || b_reencode_mb`: `p_fdec[i][-1+j*FDEC_STRIDE] =
   plane_fdec[...]`): 16 scalar unpacks per MB; C.
13. **PSNR / SSIM** (`x264_fdec_filter_row`; `pixel_ssd_wxh`,
   `ssd_nv12_core`, `ssim_4x4x2_core`): unpack fused into the ssd/ssim
   loads of the fdec side (fenc stays 16-bit), or per-row unpack into a
   2-row temp. Only with --psnr/--ssim.
14. **Recon output**: `--dump-yuv` (`x264_frame_dump`) and the API's
   `pic_out->img.plane[]`, which today points at the fdec planes for every
   frame. Needs a 16-bit recon copy (unpack of the whole frame) whenever
   the caller can read it: API change, gate on `b_full_recon` or a new
   flag, and document that pic_out recon is otherwise absent.
15. **Lowres / lookahead**: `x264_frame_init_lowres*` and
   `lowres8_convert` work on the fenc (input) frames, which are not
   reference planes: unchanged. OpenCL lookahead (8-bit only): unchanged.
16. **Slicetype weightp chroma** (`encoder/slicetype.c` weight_cost_init_chroma*
   reads `ref->plane[1]`): the lookahead's refs are fenc frames: unchanged.
17. **Frame-thread row sync** (`x264_frame_cond_broadcast`/`wait`): no
   data change; the pack must happen before the broadcast, as the stage 1
   split already does (`x264_frame_split8` before the broadcast).
18. **Sliced threads pass ordering** (`x264_threadslice_filter`, pass 1/2):
   deblock and hpel of slice-boundary rows run in pass 2; the deblock band
   helper (2) and the split hpel (4) inherit the same row ownership. No
   new races: MB columns are lsb byte columns, rows are separate bytes.

## Recommended order

Each step keeps the 16-bit plane as a shadow under -DX264_ME8_VERIFY (the
stage 1/2 verifier compares msb8+lsb8 against it at every frame retire),
then deletes it once md5 identity holds across the test matrix.

1. **h/v/c luma planes** (75% of the luma reference bytes): one writer
   (hpel, already fused in stage 2), readers are get_ref/mc_luma/the
   `*_avg2` kernels/qpel RD/bidir (8, 9). Drop `filtered[0][1..3]`
   16-bit stores; unpack in get_ref's temp and in `pixel_avg2` and the
   fused avg2-cmp kernels. Field versions with them.
   As built: `filtered[0][1..3]` are not allocated at level 2 (the VERIFY
   build keeps them as a shadow written by the plain hpel filter);
   `hpel_filter8` writes only the split (frame pass), the field pass and
   non-AVX2 go row by row through scratch rows. Every reader goes through
   `x264_ref_mc_luma`/`x264_ref_get_ref`/`x264_ref_hpel_pair`
   (`common/macroblock.h`), which unpack (`plane_unpack8`) the windows the
   unchanged 16-bit kernels read into a 32 pixel stride temp; fullpel mvs
   still read the 16-bit `plane[0]`, but for mbcmp_bi4's shared stride.
   Readers fused (x86_64 AVX2 and AVX-512 ymm, `common/x86/pixel-a.asm`
   "packed readers"): the dispatchers call kernels that read msb8/lsb8 in
   place, the unpack in their loads, the column phase from the msb address
   (`msb & 3`, per-phase pshufb/multiplier rows of `pk8_tab` loaded once a
   call, so every x alignment is native): `copy_pk`/`avg2_pk` (mc_copy and
   pixel_avg2, widths 4-20: mc_luma, get_ref, qpel RD, BIME, weighted refs
   with the weight in place), `sad/satd(_avg2)_pk` (subpel_cmp: ME8_EXACT,
   COST_MV_HPEL) and `satd_bi4_pk` (B BI costs). The temp path remains for
   C/no-asm, x86_32 and pre-AVX2 CPUs; sizes below 8x8 in subpel_cmp go
   through get_ref (copy_pk/avg2_pk) and the 16-bit cmp.

   Test plan for the readers (output must be md5-identical to b1cd784d at
   `--me-8bit 2`, which is identical to bf65074f's level 2):
   - build AVX2 (Zen 2), avx512 (Zen 4 rack01), `--disable-asm`, x86_32 if
     available; `checkasm10` ("mc pk", "pixel pk", "pixel bi4 pk" incl.
     their in-code positive controls) on Zen 2 and Zen 4, several seeds; the
     manual controls in the commit messages (swap pk8_tab mul rows, swap two
     PK_BI_TAB copies) must fail checkasm.
   - `-DX264_ME8_VERIFY` build clean over the matrix; `-DX264_ME8_VERIFY_CONTROL`
     must report and change the md5.
   - md5 of `--me-8bit 2` at HEAD vs b1cd784d and vs bf65074f per build
     (AVX2, avx512, `--disable-asm`; across builds only with
     `--cpu-independent`); `--asm avx2` on Zen 4 too: progressive and MBAFF
     (true 1080i) 10-bit 4:2:0 and 4:2:2; subme 0/1/2/7/9; weightp 0/2;
     refs 1/4; bframes 0/3 (b-adapt as production); `--threads 1` and
     sliced threads; recon (`-o` + `--dump-yuv`) equal to a decode.
   - cycles: perf stat and a per-symbol profile of L2 at HEAD vs L2 at
     b1cd784d vs L2 at bf65074f vs L0, lowlat and subme 7/9, 1080p and
     1080i, realtime-paced per-frame CPU (not file fps).
2. **4:4:4 chroma hpel planes** if 4:4:4 matters (same code as 1).
3. **Fullpel luma**: writers recon store (1), deblock band helper (2),
   expansion (3), field copies (5); readers hpel input (4, the hard one),
   MC (8), PSNR (13), recon output (14), weightp (6), integral (7),
   intra reload (12).
   As built (wip/me8-s3, 04b558e7, fbc86a0c, fcd75109), at both levels
   outside 4:4:4 (`h->b_fpel8`; 4:4:4 keeps its 16-bit planes):
   - Level 1 stores h, v and c split too (`X264_ME8_HPEL8`): the readers
     that average the fullpel plane with h or v take one stride for both,
     so a packed fullpel next to 16-bit h/v/c would need mixed-source
     kernels; with all four split, level 2's readers serve both levels.
     `m->p_fref8[1..3]` (the level 2 subpel search) are set at level 2 only.
   - The references' fullpel luma is read only from msb8/lsb8[0]:
     `p_fref[0]` and the unweighted `p_fref_w` are NULL, and every reader at
     a fullpel mv takes the split path (`X264_REF_SPLIT8`, subpel_cmp, the
     b8 exact cost, the BI costs incl. the zero mv, `x264_weight_scale_ref`
     for weighted planes: `plane_unpack8` 16 rows then the weight in place).
   - The writers are not converted. The frame being encoded keeps a 16-bit
     fullpel plane, but it is its frame thread's (`h->fpel16`, frame and
     MBAFF field, one per frame thread), not its own:
     `x264_frame_bind_fpel16` hands it to each new fdec after
     `x264_reference_update` and takes it from the previous frame (NULL;
     `X264_ME8_VERIFY`: copied into that frame's shadow). So recon store,
     deblock (MBAFF, sliced passes), borders, field copies,
     `x264_frame_split8`, hpel input, intra reload, PSNR/SSIM, dump and
     pic_out run unchanged on 16-bit rows, and the split is stage 1's, after
     every expand_border and before the frame thread broadcast.
   Why not the band design of (1)-(4): the frame being encoded is read at
   16 bits only by its own thread and only within a few MB rows of where it
   is written, so packing it would add a band unpack + repack per deblocked
   row and a strip unpack per hpel row (~2.5 plane passes a reference frame,
   derived) to save the write-back of a plane nobody else reads. The
   references, which the search, MC and refine read, are packed either way.
   The cost of this design is footprint: one 16-bit plane per frame thread
   (4.6 MB at 1080p, derived) instead of none.
   Lifetime: a frame bound to thread T is T's fdec, or its previous one
   between T's `x264_thread_sync_context` and its `x264_reference_update`
   (one caller-thread call; only `x264_reference_update` pops fdec frames),
   so nobody else can pop it; that previous frame's frame_end (dump,
   pic_out) ran in an earlier call (thread_oldest never rebinds in the call
   that outputs it unless there is one frame thread, where the encode
   precedes frame_end), and with sliced threads worker 0's trailing
   `x264_threadslice_filter` is awaited by `x264_slicepool_wait_all` before
   `x264_reference_update`. Worker threads never read a reference's 16-bit
   plane pointers (`x264_macroblock_load_pic_pointers` skips them), so the
   caller thread changing them at bind is not a race.
   API: `pic_out->img` is valid until the next `x264_encoder_encode` /
   `x264_encoder_close` (x264.h), reference frames included.
   Rows [-2*PADV, -PADV) of the MBAFF frame plane are never written (frame
   pads are PADV rows) in either layout; the weighted plane build copies
   them as before (zero pages from the allocator in both).

   Test plan (nothing here was built or measured):
   - builds: AVX2 (Zen 2), avx512 (Zen 4 rack01), `--disable-asm`,
     `--bit-depth=all` and 10 only, x86_32 if available; checkasm10 and
     checkasm8 several seeds ("mc pk", "pixel pk", "pixel bi4 pk",
     plane_split8/unpack8, hpel_filter8 with their in-code and manual
     controls, as in steps 1 and 2).
   - `-DX264_ME8_VERIFY` clean over the matrix below (the verifier now also
     compares frame and field fullpel against the copy made at release);
     `-DX264_ME8_VERIFY_CONTROL` must report plane 0 (and h) and change the
     md5.
   - md5 at HEAD = cefc5c06 per level (0, 1, 2), per build, `--asm avx2` on
     Zen 4 too: progressive and MBAFF (true 1080i) 10-bit 4:2:0 and 4:2:2,
     subme 0/1/2/7/9, weightp 0/2, refs 1/4, bframes 0/3 (b-adapt as
     production), `--threads 1`, sliced threads, frame threads (threaded
     output varies run to run: there compare recon with a decode, and md5
     at `--threads 1` only), `--psnr --ssim` values equal, `--dump-yuv`
     equal to a decode; 4:4:4 at levels 1/2 unchanged too.
   - cycles (perf stat, per-symbol profile, realtime-paced per-frame CPU):
     L1 and L2 at HEAD vs L0 and vs cefc5c06 L1/L2, lowlat and subme 7/9,
     1080p and 1080i: refine_subpel's and ME8_EXACT's share at L1 (the
     reference reads now 10 bits a pixel), the level 1 cost of reading h, v
     and c through the pk kernels, `x264_weight_scale_ref`, and RSS.
4. **NV12/NV16 chroma** last: mc_chroma and satd_mcc have the most
   irregular access (2x2 bilinear on interleaved uv, field-edge plane
   choice of 613552d9), deblock chroma, and the smallest saving.

## Riskiest parts

- hpel input unpack (4): the one-pass AVX2 kernel is register-full; the
  unpack needs 3-4 more registers or a strip-mined 16-bit ring. (Step 3 as
  built avoids it: see the per-thread plane.)
- Deblock (2): in-place RMW on a packed format; the band helper avoids
  touching the 15 deblock kernels but needs exact band bookkeeping for
  MBAFF (field/frame edges, `deblock_h_luma_mbaff`) and the 4 rows above.
  (Avoided likewise.)
- Step 3 as built: a reader of a reference's 16-bit fullpel. Through
  `p_fref` it gets NULL; a direct `fref->plane[0]` read added later gets
  NULL once the frame is released (always at --threads 1) but the live
  plane of the thread still encoding it with frame threads. And the
  per-thread plane's lifetime (bind after `x264_reference_update`, step 3).
- API recon (14): behaviour change for callers that read pic_out.
- mc_chroma (8, step 4): source windows crossing the field-edge rule.
- Every reader must see bit-exact values: any reader left on a stale or
  missing 16-bit plane changes output silently. The shadow-plane phase
  with the verifier and an md5 identity matrix (progressive, MBAFF
  1080i, sliced and frame threads, weightp, subme 0/1/2/7/9/11, ESA/TESA)
  is what makes each step safe.

## Cost against saving, overall

Stored bytes per 1080p 4:2:2 10-bit reference (derived from the geometry, not measured): luma 4 planes 18.3 MB ->
11.4 MB, chroma 4.6 -> 2.9 MB (MBAFF roughly doubles both). With 3 refs this
moves a ~69 MB working set to ~43 MB: still above a Zen 4 CCD's 32 MB L3,
so the saving is DRAM bandwidth, which matters for the search (stages 1/2
already read 8 bits for it) and little for MC/deblock, which are L1/L2
bound per MB and get slower by the unpack. Expect stage 3 to pay only
where the encode is bandwidth bound (many refs, many frame threads, 4K):
measure stage 2 with `perf stat` memory-bound counters first. If the
search's 8-bit reads already remove most of the DRAM traffic, stage 3's
gain is the footprint (more frame threads per box) rather than speed.
