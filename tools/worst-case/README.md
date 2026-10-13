# Worst-case synthetic content for x264-obe

- Code: x264-obe `speed-next` at bd886aae, read-only. Unified 8/10-bit build.
- Method: code reading only. Nothing was compiled, run or measured.
- **Every cost figure here is an estimate from code reading and is NOT measured.** The one anchor is the known measurement: a 10-bit 1080p50 fade costs about +10 ms per weighted frame at t4 lowlat.
- The generator is `worst-case-gen.sh`, beside this file. It was not run, because no ffmpeg was available here to test it. Run `SMOKE=1` first.

---

## 0. Summary

### Lowlat: top cases by expected per-frame latency

| # | Case | Phase hit | Why | Est. effect | Realistic? |
|---|---|---|---|---|---|
| 1 | **flicker**: global luma+chroma gain changing every frame | **SERIAL** (main thread before the slices) + slice barrier | `x264_weights_analyse` runs in full, with chroma at full resolution, and the weighted plane is built, on **every** P frame | +~10 ms on every frame (anchored to the fade measurement). This is sustained, not a one-frame dip | Yes: LED walls, mains-beat flicker, auto-iris, strobing stage light |
| 2 | **blind**: 2x2 zero-sum checker noise that x264's lowres filter cannot see, toggled | parallel (slices), with **repeated row re-encodes** | RC, VBV planning and scenecut plan the frame from a lowres image that does not contain the noise. Row VBV then re-encodes rows at up to +4 QP per pass | 1.5-3x on the frames after each switch; 1.5-2x while the noise is on | Pathological as built. Fine film grain is a weak real analogue |
| 3 | **band**: one quarter-height band of hard content over a static slate | parallel, but all on one slice | Slices are fixed equal row splits. Frame time is the slowest slice, and the band is coded at the low QP that the easy frame gets | 1.5-2.5x frame latency at only 0.5-0.8x the CPU | Yes: tickers, crowd strips, sports graphics |
| 4 | **cuts / flashes / strobe** | pre-slice lowres (banded) + slices | I frames, plus P frames that are really cuts (no flash handling without B-frames, and little scenecut bias right after a keyframe): ME fails and intra is searched in full | 1.5-2.2x per affected frame. Strobe sustains it | Flashes and fast cuts: yes. Strobe: pathological |
| 5 | **grain**: visible temporal noise on motion | slices, plus a little in the pre-slice lowres | No skips, the fast-intra gates stop firing, 16x8 and 8x16 get searched, residual is dense | 1.3-1.8x, sustained | Yes: film, low light |

Also in the lowlat ranking (section 4): dip, pfade, xfade, the 1080i field cases, shuffle/spin, chroma.

### Normal: top cases by expected CPU per frame and lookahead-thread load

1. **grain / flickergrain**: B_SKIP and P_SKIP stop firing, every RD candidate falls inside the 5/4 threshold, and trellis runs on dense blocks. Main encode 1.8-2.5x. The lowres skip (`< 64`) stops firing, so the lookahead does 1.5-2x the work.
2. **flicker at 10-bit 4:2:2**: on the **single** lookahead thread, `x264_weights_analyse` with subme 7 tries 3 scales x 3 offsets per plane. That is up to 9 full-resolution chroma passes per plane, against 3 at lowlat. Weighted P frames also gain a fully searched unweighted duplicate reference. Est. +15-30 ms of lookahead-thread time per P frame. This is the normal-mode overrun risk.
3. **field** (true 1080i motion): a field MB searches both parities of each reference, so 4 refs become 8, in P and in B. Est. 1.3-1.7x.
4. **shuffle / spin** (non-translational motion): direct prediction fails, and B 16x8/8x16 and mixed refs get searched. Est. 1.4-1.8x.
5. **cuts / strobe**: intra RD on I frames, plus the scenecut and flash analysis passes in the lookahead.

### The five to generate first (the script's default `P1` set)

1. `flicker`
2. `blind`
3. `band`
4. `cuts`
5. `grain`

Controls are `baseline` (synthetic) and crowd_run (real), both already on the Zen 2 box.

### Defects and cost cliffs found

Details are in section 6.

- **10-bit weightp cost mixes two scales** (slicetype.c:212, 221 against :823 and lookahead8.c:415). In `cost += X264_MIN( cmp, fenc->i_intra_cost[i_mb] )`, `cmp` is a native 10-bit SATD and `i_intra_cost` is at 8-bit scale. At 10-bit the clamp is therefore 4x too tight. This is upstream behaviour. It dilutes the weight score: weak fades and flicker still pay for the serial analysis, but then get rejected.
- **Row VBV re-encode can repeat on the same row**, at up to +4 QP per pass (ratecontrol.c:1746-1767, encoder.c:3276-3284). This is a latency cliff on frames that the lowres image under-predicts.
- **The lowres filter cannot see 2x2 zero-sum patterns** (mc.c:553-557). Scenecut, VBV planning, mbtree, b-adapt and weightp all go blind to them.
- **The weightp early exit is mean/variance based** (slicetype.c:370). It fails on ordinary content changes: |Δmean| ≥ 0.5 code value, or a variance ratio more than about 1.6% from 1. On non-fade frames the serial luma analysis then runs, and at 10-bit the 16-bit lowres build for both frames runs too (slicetype.c:404-405).
- **Chroma weights are only tried after a luma weight is found** (slicetype.c:363). Chroma-only fades are never weighted. That is a quality gap, not a cost one.
- **Slice and lookahead bands are static equal row splits** (encoder.c:3528-3529, slicetype.c:1005-1006). Nothing balances the load.
- **The 10-bit lowres skip threshold is 16 at 8-bit scale**, against 64 in 8-bit builds (slicetype.c:754; kept on purpose in lookahead8.c:343-347). Near-static content with faint noise costs more lookahead ME at 10-bit.
- **Deblock falls off the whole-MB AVX2 luma path** for intra MBs, intra top neighbours, and an MBAFF frame pair below a field pair (deblock.c:433-444). Cut and I-frame content pays per-edge deblock.
- **At lowlat (subme 2) the P_SKIP probe only runs next to a skip neighbour** (analyse.c:3158-3164). Once the skip chain breaks, static areas get a full search until encode-time skip conversion seeds it again.
- **With keyint 24** (as bd-encode.sh sets it), 4.2% of frames are I frames. At lowlat the **p99 is therefore set by I frames** by construction.

---

## 1. Settings assumed

These were confirmed from `common/base.c` (presets and tunes) and `encoder/encoder.c`, and the CLI lines come from `exp/bd-exp:tools/bd/bd-encode.sh` (the obed-style bench).

| | lowlat | normal |
|---|---|---|
| CLI | `--preset veryfast --tune zerolatency`, VBV maxrate=R, bufsize=R/2 | default preset (medium) `--ref 4 --bframes 3 --rc-lookahead 24`, VBV maxrate=R, bufsize=R |
| common | `--keyint 24 --open-gop --aud --pic-struct --nal-hrd fakevbr`; 1080i adds `--tff` (MBAFF; this tree has no PAFF: `sh->b_field_pic = 0`, encoder.c:416) | same |
| threads | sliced t4 (production) / t8; `i_lookahead_threads = i_threads` (encoder.c:1441); `i_sync_lookahead = 0`, so slicetype runs **on the main thread** (encoder.c:1307, lookahead.c:237-252) | `--threads 8` frame threads. Lookahead thread with `i_sync_lookahead = bframes+1`. **`i_lookahead_threads` = 8/6 = 1** (encoder.c:1449-1462: b-adapt 1, subme 7, bframes 3 → divisor 6) |
| ME / subme | hex, me-range 16, **subme 2**, ref 1, no mixed refs, no chroma ME (needs subme ≥ 5, macroblock.c:516) | hex, subme 7, ref 4, mixed refs, chroma ME on P (on B it needs subme ≥ 9) |
| RD | `i_mbrd = 0`, trellis 0 | `i_mbrd = 1` (RD mode decision), trellis 1 (final encode only), psy-rd 1.0 |
| weightp | 1 = SIMPLE: no duplicate refs (encoder.c:2465-2467) | 2 = SMART: duplicate refs (encoder.c:2652-2683) |
| lookahead | `rc_lookahead = 0`, so `i_slicetype_length = 0` and `i_max_search = 1`; `lookahead_8bit = 1` at 10-bit (base.c:616) | b-adapt 1 (fast), mbtree, scenecut 40; `lookahead_8bit` off unless obed sets it |
| partitions | default inter: i4x4, i8x8, p8x8, b8x8 (veryfast leaves `analyse.inter` alone) | same; no p4x4 |
| keyint_min | auto = min(24/10, fps) = 2 (encoder.c:1276) | same |

Assumptions worth checking against obed:

- Whether obed lowlat uses intra refresh. I assumed keyframes, as bd-encode.sh does.
- Whether obed normal enables speedcontrol (`sc.f_speed > 0`, speed.c). If it does, worst-case content lowers the preset instead of overrunning.
- The production bitrates. The run plan uses 20 Mb/s for 1080p50 and 15 Mb/s for 1080i25.

---

## 2. Where the time goes, per frame

### Lowlat (sliced) frame timeline

Main thread, inside `x264_encoder_encode` (encoder.c:3765):

1. **Prologue**: picture copy, AQ, lowres. These run in MB-row bands on the lookahead pool (encoder.c:3623-3720) and are content-independent.
2. **`x264_lookahead_get_frames` → `x264_slicetype_decide`** (encoder.c:3900, lookahead.c:242). This is serial control, with banded lowres work:
   - `x264_slicetype_analyse` → `scenecut()` → `x264_slicetype_frame_cost(0,1,1)` (slicetype.c:1486, 1617-1618). Lowres intra and ME run in lookahead-pool bands (slicetype.c:992-1017).
   - If ME is needed, `x264_weights_analyse(..., b_lookahead=1)` runs first, on luma only and serially (slicetype.c:947-951).
   - **`x264_weights_analyse(..., b_lookahead=0)`** (slicetype.c:2052-2057): **serial**. Luma at lowres, chroma at full resolution.
3. **`x264_slicepool_wait_all`** (encoder.c:3911): waits for the previous frame's deblock and hpel.
4. `x264_ratecontrol_start`, `x264_weighted_pred_init`: cheap.
5. **`x264_threaded_slices_write`** (encoder.c:3521-3560):
   - Every slice thread first builds 64-row bands of the weighted reference, then **waits for all bands** (encoder.c:165-190). This is a barrier.
   - The slices then encode. Frame time = max over slices.
6. Post-slice: merge RC, escape and concatenate NALs. Cost grows with the bytes.
7. Deblock and hpel run per slice on the slice workers after the slice "done" signal (encoder.c:3404-3414). This overlaps the next frame's steps 1-2.

**Content-dependent SERIAL work at lowlat:**

- weights_analyse (both calls, when the early exit fails);
- the 16-bit lowres build for weightp at 10-bit (banded);
- the lowres weighted plane (`x264_lowres8_weight_plane`, serial);
- the lowres ME and intra pass (banded on the lookahead pool, but on the critical path before the slices);
- NAL concat, which grows with the frame's bytes (I frames).

### Normal (frame threads)

- An overrun means throughput falls short over a window of about 8 frames, or the **single lookahead thread** cannot finish `slicetype_decide`, mbtree and weights within its per-frame budget.
- The lookahead thread does per minigop:
  - b-adapt frame costs (`cost2p1`, `cost1b1`, `cost1p0`, `cost2p0`: slicetype.c:1767-1776);
  - flash and scenecut passes (slicetype.c:1527-1557);
  - mbtree propagate over 24 frames (slicetype.c:1185-1278);
  - and, per P frame, a full `weights_analyse`.

---

## 3. Mechanisms: code path, trigger, mode

Mode: L = lowlat, N = normal. S = serial phase, P = parallel phase.

### M1. weightp analysis (L: S; N: lookahead thread)

**Early exit** (slicetype.c:370):

```c
if( fabsf( ref_mean[plane] - fenc_mean[plane] ) < 0.5f && fabsf( 1.f - guess_scale[plane] ) < epsilon )
```

- `guess_scale = sqrtf(fenc_var/ref_var)` and `epsilon = 1/128`. The early exit therefore fails if the mean moves by ≥ 0.5 (8-bit units) **or** the variance ratio leaves about [0.984, 1.016].
- That happens on fades, but also on flicker, pans revealing new content, and moving objects.
- Past the exit, at 10-bit with lookahead-8bit, x264 first builds 16-bit lowres for **both** frames (slicetype.c:404-405, `x264_weight_lowres_init`, banded).

**Search size** (slicetype.c:438-439, table at :430-436):

```c
int scale_dist =  b_lookahead ? 0 : weight_check_distance[h->param.analyse.i_subpel_refine][0];
int offset_dist = b_lookahead ? 0 : weight_check_distance[h->param.analyse.i_subpel_refine][1];
```

- subme 2 (L): {0,1}, so 1 scale x 3 offsets.
- subme 7 (N): {1,1}, so 3 x 3.
- The offset loop only breaks when the first offset wins (`if( minoff == start_offset && i_off != start_offset ) break;`, :474). The longest search is when the best offset sits at +1 from the guess.

**Chroma** (slicetype.c:363) is only analysed if luma got a weight:

```c
for( int plane = 0; plane <= 2 && !( plane && ( !weights[0].weightfn || b_lookahead ) ); plane++ )
```

When it is analysed, the work is:

- `x264_weight_cost_init_chroma` (slicetype.c:113-143): expand the reference's chroma border, then MC the whole full-resolution chroma with the lowres MVs;
- then one `asd8` pass over the full chroma plane per candidate, per plane.

At 4:2:2 each chroma plane is 960x1080.

- **Max serial cost**: a fade where luma gets a weight, both chroma planes also change in variance (fade to black of saturated content), and the best offset is at +1.
- **Acceptance** needs a 0.2% gain (slicetype.c:492: `(float)minscore / origscore > 0.998f` rejects). Mostly-intra frames, crossfades and noisy frames tend to be rejected *after* the luma passes are paid for.

**In the slices** (P):

- A weighted P frame builds the full-resolution weighted luma plane in bands, behind a barrier (encoder.c:165-190).
- ME loses the hpel fast path: `if( !((omx|omy)&1) && !m->weight[0].weightfn )` (me.c:1066). Every hpel candidate then goes through `get_ref` with weighting.
- In N, chroma ME also loses `mbcmp_mcc` when a chroma weight is active (me.c:1021-1022).
- N 10-bit: the weighted P also gets an unweighted duplicate of ref0 at index 1 (encoder.c:2672). It is **fully searched**, because it is not the blind dupe.
- N 8-bit gets two duplicates, one of them blind (encoder.c:2662-2680, 2470-2480).

### M2. Lowres-planned rate control and row VBV re-encode (L, N: P, inside slices)

- The frame QP comes from the lowres SATD (`x264_rc_analyse_slice`, slicetype.c:2093-2153). Row prediction mixes lowres row SATD with the co-located row's bits (ratecontrol.c:1562-1589).
- At each row end, `x264_ratecontrol_mb` may ask for the row to be redone (ratecontrol.c:1755-1767):

```c
if( rc->qpm > qp_max && prev_row_qp < qp_max && can_reencode_row )
{
    rc->qpm = x264_clip3f( (prev_row_qp + rc->qpm)*0.5f, prev_row_qp + 1.0f, qp_max );
    ...
    return -1;
```

- `qpm` only gets above `qp_max` through the VBV/MinCR loop (`while( rc->qpm < qp_absolute_max && (b1 > max_frame_size) )`, :1746). So this is a VBV emergency.
- On re-encode, slice_write restores the bitstream to the start of the row and encodes the whole row again (encoder.c:3276-3284). Each pass raises the row's QP by at most `qp_step` = 4.
- **A row can be re-encoded several times.** The last row has its own last-ditch re-encode (ratecontrol.c:1770-1781).
- `trust_coeff < 0.05` (ratecontrol.c:1713) blocks QP increases at the top of a slice. Bits overshot there are caught later and harder.
- **Trigger**: complexity the planner underestimates. The strongest is detail invisible to lowres (M3) after easy content. The predictors adapt within a few rows and frames (`update_predictor`, clipped to x1.5 per update, ratecontrol.c:2177-2198), so the effect is a transient. Toggling keeps it coming back.
- With slices, `slice_size_planned` comes from the slice's own row SATDs (ratecontrol.c:2753-2757), so a heavy band also gets a larger, but still lowres-planned, budget.

### M3. The lowres image is blind to 2x2 zero-sum detail (L: S consequences; N: lookahead)

`frame_init_lowres_core` (mc.c:553-557):

```c
#define FILTER(a,b,c,d) ((((a+b+1)>>1)+((c+d+1)>>1)+1)>>1)
dst0[x] = FILTER(src0[2*x  ], src1[2*x  ], src0[2*x+1], src1[2*x+1]);
```

- Add `+d,-d / -d,+d` to every aligned 2x2 block, with d even.
- Then dst0, dsth, dstv and dstc are all unchanged.
- So these are all computed on an image without the detail: scenecut, the I/P costs, row SATDs (VBV), b-adapt, mbtree, the weightp luma cost, and the lowres skip.
- AQ is computed at full resolution (ratecontrol.c:232-316), so AQ does see the detail and raises QP in it.
- At full resolution the pattern is maximum high-frequency energy:
  - no skip;
  - intra and inter both poor;
  - the fast-intra thresholds stop protecting (analyse.c:730, 893, 901);
  - dense coefficients.

### M4. Slice and band imbalance (L: P, effectively serial)

Fixed equal splits:

```c
t->i_threadslice_start = ((height *  i    + h->param.i_slice_count/2) / h->param.i_threads) << PARAM_INTERLACED;
```

(encoder.c:3528-3529). The lowres bands are split the same way (slicetype.c:1005-1006).

- At 1080p, t4 gives slice starts at rows 0, 17, 34 and 51 (68 MB rows).
- At 1080i, t4 (34 MB pairs) gives rows 0, 16, 34 and 50.
- Frame time = the slowest slice (encoder.c:3559-3560).
- Concentrated detail makes latency about that of a fully hard frame, at a fraction of the CPU.
- Worse, frame-level RC prices the frame by its *average* (mostly easy) complexity. The band is coded at a lower QP than the same content would get full-frame (AQ partly compensates). So the band slice can be **slower than any slice of a uniformly hard frame** at the same bitrate.

### M5. Skip and early-termination gates (L, N: P)

**Lowlat, subme 2.** The P_SKIP probe only runs when a neighbour is skip (analyse.c:3158-3164):

```c
else if( h->param.analyse.i_subpel_refine >= 3 )
    analysis.b_try_skip = 1;
else if( h->mb.i_mb_type_left[0] == P_SKIP || h->mb.i_mb_type_top == P_SKIP || ... )
    b_skip = x264_macroblock_probe_pskip( h );
```

Otherwise the MB gets a full 16x16 search, 8x8, and 16x8/8x16 when `i_cost8x8 < me16x16.cost + mv costs` (analyse.c:3218-3256).

**Lowlat fast intra** is always on at subme < 3 (analyse.c:478-489):

- i16x16 stops when `i_satd_i16x16 > i16x16_thresh`, which equals `i_satd_inter` here (analyse.c:730, 774).
- i8x8 stops at `(i_satd_inter*4)>>2` (:893).
- i4x4 stops at `min(inter, 16x16, 8x8)` (:901).

So whenever inter prediction is as bad as intra (noise, new content, cuts), the whole intra search runs. That includes a `x264_mb_encode_i8x8` or `x264_mb_encode_i4x4` per block.

**Normal, i_mbrd = 1.**

- P: RD on 16x16 if `cost <= satd*3/2`. RD on 16x8, 8x16 and 8x8 if within `satd*5/4` (analyse.c:2676-2740). `x264_intra_rd( h, &analysis, i_satd_inter * 5/4 + 1 )` (:3376).
- `x264_mb_analyse_transform_rd` adds one more RD encode.
- B: B_SKIP is decided by `ssd_mb` of the direct prediction `<= 6*lambda2` (analyse.c:3511). Noise defeats it, and then every B mode is searched.
- Each `x264_rd_cost_mb` is a full `macroblock_encode` plus a CABAC size estimate (rdo.c:160-196). It costs more with more coefficients.
- On noise every candidate lands within 5/4, so all of them get an RD pass.

**Lowres skip** (slicetype.c:754): `if( m[l].cost < 64 )`. At 10-bit that is 16 in 8-bit terms, kept on purpose in lowres8 (lookahead8.c:343-347).

**Interlaced partgate** (analyse.c:3199-3203, OBE addition):

- It skips sub-16x16 partitions only when the 16x16 residual is below `256*lambda` **and** no left or top neighbour used sub-16x16 or I4x4/I8x8.
- Any detail spreads from MB to MB and switches the gate off.

### M6. ME (L, N: P)

**Hex** (me.c:413-470):

- 6 points, then up to `(i_me_range>>1)-1` = 7 half-hexagon steps of 3 points, then an 8-point square.
- That is about 35 fullpel SADs at most, against about 14 when converged.
- Spatially uniform motion, even when large and erratic, is cheap after the first MB of a row, because the neighbour predictors carry it (`x264_mb_predict_mv_ref16x16`). The worst case is motion that changes **per block** and **per frame**, with a smooth SAD landscape. The hex walks then run to the step limit and still fail, and intra follows (M5).

**Refs.**

- The halfpel early exit across refs (me.c:1104) only saves the qpel stage.
- MBAFF field MBs search 2 refs per frame ref: `h->mb.pic.i_fref[0] = h->i_ref[0] << MB_INTERLACED` (macroblock.c:1014).
- In N, mixed refs are pruned for field MBs by parity (analyse.c:1389-1404), but 16x16 still searches all 2x4 refs.

### M7. Scene cuts and flashes (L: S + P; N: lookahead + P)

Scenecut (slicetype.c:1511): `res = pcost >= (1.0 - f_bias) * icost;`.

- The bias grows with the distance from the last keyframe (slicetype.c:1497-1508). With keyint_min = 2 it is `f_thresh_min*gop/keyint_min` = 0.05 one frame after a keyframe and 0.1 two frames after. It then rises linearly to 0.4 at keyint. With intra refresh it stays at `f_thresh_min/4` = 0.025.
- A cut must therefore make the lowres P cost reach 95% of the I cost, or more, to become an I frame. A second cut soon after an I frame usually stays a **P frame with almost no usable inter**. That gives full ME, then full intra, then dense residual.
- Lowlat has no flash detection: `scenecut()` only looks ahead `if( real_scenecut && h->param.i_bframe )` (slicetype.c:1527).
- A flash frame becomes an I frame. The next frame is a P frame predicted from the flash, which is mostly intra.
- **One-field flashes** at 1080i (a photo flash during one field) are natural, and land the same way.
- In N, flash analysis adds `scenecut_internal` frame costs per decision (slicetype.c:1527-1557). Cuts also produce I frames that go through intra RD.

### M8. MBAFF (L, N: P)

- The field/frame decision is `x264_field_vsad` only (pixel.c:747-773, encoder.c:3148). **Both modes are not analysed**, so the decision itself costs O(1).
- The cost comes from:
  - field MBs doubling the refs (M6);
  - `macroblock_cache_load_interlaced`;
  - mixed-pair deblock: the left edge in two 8-line halves through `deblock_*_mbaff`, and a field pair above a frame pair filtered twice (deblock.c:495-536, 581-600);
  - mixed pairs falling off the whole-MB luma deblock path (deblock.c:433-444).
- The neighbour bias (pixel.c:764-770) pulls pairs toward their neighbours' choice. Field/frame alternation needs strong, column-alternating combing (`fieldmix`).

### M9. Coefficient-heavy content (L, N: P)

- Under VBV the bits per frame are capped, so CABAC bins, residual coding and trellis work are **bounded by the bitrate**. Exceptions are I frames (the VBV buffer allows bursts) and M2 transients.
- What noise or grain really costs is the **analysis** that the failing gates release (M5) plus RD tries (N).
- Trellis (N, trellis 1, final encode only): `trellis_cabac_quantised` returns early when `last_nnz == 0 && !dc` (rdo.c:663). Otherwise its cost grows with `last_nnz`.
- Deblock: `first_edge_only` for 16x16 MBs with no cbp and no intra, or `qp <= qp_thresh` (deblock.c:430). Coded and intra MBs filter every edge.

### M10. Chroma at 4:2:2 (L, N: P; L: S via M1)

- A 4:2:2 MB has 8x16 chroma per plane: twice the 4:2:0 chroma blocks, a 2x4 DC, and more chroma deblock edges.
- Chroma intra prediction always evaluates its 4 modes (analyse.c:648-660).
- Chroma ME runs in N P frames only.
- At lowlat, saturated chroma detail matters through the bits (bounded) and through M1 chroma passes during fades.

### M11. Lookahead work (N: lookahead thread)

- `x264_slicetype_frame_cost` work grows with lowres ME, which the `< 64` skip gates, plus intra (once per frame).
- b-adapt 1 does up to 4 frame-cost calls per undecided frame (slicetype.c:1767-1776). Each new (p0, p1, b) is a full lowres pass, and it is **single-threaded** here.
- mbtree propagate does fixed work per frame across the 24-frame lookahead.
- Flicker or erratic content can make b-adapt choose P more often. That means more `weights_analyse` calls (M1) per frame.

### M12. I frames (L, N: P)

- keyint 24 means 4.2% I frames. At lowlat these set p99.
- Detailed texture defeats the i8x8 and i4x4 early exits (`i_cost > i_satd_thresh`, analyse.c:812, 858 (i8x8) and 930, 983 (i4x4)). Each of the 4 or 16 blocks is predicted, searched and encoded.
- A flat I frame is cheap, and any detailed one is near the maximum. **The cliff is from flat to detailed, not from typical to worse.**

---

## 4. Recipes

All recipes are in `worst-case-gen.sh` and are listed by `LIST=1`.

- Built at 1080p50 yuv444p 8-bit, then converted to `p420_8`, `p422_10` and `i422_10`.
- `i422_10` is **true interlace**: `tinterlace=mode=interleave_top` (top field from 50p frame 2n, bottom from 2n+1), then `setfield=tff`. It is not progressive content flagged as interlaced. Check it with `idet`.
- The texture is one deep-zoom mandelbrot frame, looped. It is detailed and colourful, with a smooth SAD landscape.

| Case | Recipe | Worst-case because | Mechanisms | Realistic? |
|---|---|---|---|---|
| **flicker** (P1) | pan, `eq=saturation=1.4`, geq gain `1+0.03*sin(N*2.1)+0.02*sin(N*0.77)` on luma and chroma | Every frame fails the M1 early exit with a real luma *and* chroma change, so full weight analysis plus the weighted plane run every frame | M1 | **Yes** |
| **blind** (P1) | pan squeezed to 64..191, plus `128+2*floor((n-128)/2)*(-1)^(x+y)` with n constant per 2x2 block, toggled every 0.7 s; applied after tinterlace for 1080i | Invisible to all lowres planes (M3), so RC under-plans, rows re-encode (M2), there are no skips and intra is searched in full (M5) | M2, M3, M5 | Pathological. Fine film grain is a weak analogue |
| **band** (P1) | static slate `color` + fixed noise; a 1920x272 band at y=272 (MB rows 17-33, i.e. slice 1 of t4) of 30 px/frame scrolling texture with temporal noise | All the work lands on one slice, coded at the frame's low QP | M4, M5 | **Yes** (ticker, crowd strip). The noise makes it harsher |
| **cuts** (P1) | three scenes (pan, testsrc2, life) cut in 2-7 frame runs (`mod(n,29)`), plus a single white frame every 37 frames (one field at 1080i) | Cuts soon after keyframes stay P; flash then P-after-flash; I frames | M7, M12, M5 | **Yes** (montages, photo flashes) |
| **grain** (P1) | pan + `noise=c0s=30:c1s=12:c2s=12`, temporal | No skip or B_SKIP; intra and RD gates fail; denser lowres ME | M5, M9, M11 | **Yes** (strong grain) |
| dip (P2) | saturated pan, gain 1 for 2 s, down to 0 over 0.5 s, back up over 0.5 s | The known fade, at broadcast timing | M1 | **Yes** |
| pfade (P2) | lower 40% dips, top static | Serial cost is the same as a fade. A found weight (SIMPLE has no unweighted dupe) hurts the static 60%, which loses skips | M1, M5 | **Yes** (lower-third fades). Test whether the weight is chosen |
| xfade (P2) | continuous blend of pan and testsrc2 (triangle, 4 s period) | Two motions mixed: ME poor, intra, M1 luma passes paid then rejected | M5, M6, M1 | Yes (sustained here; real dissolves last 0.5-1 s) |
| field (P2) | pan peaking at 15 px/50p frame | Combing everywhere at 1080i, so field MBs and doubled refs; the 50p outputs are the control | M8, M6 | **Yes** (sports) |
| fieldmix (P2) | alternating 16-px columns of moving and static texture | Field and frame MB pairs alternate: mixed-edge deblock, slow cache load, no whole-MB deblock | M8 | Pathological |
| chroma (P2) | pan luma; cb/cr = 110-amplitude moving fine sinusoids plus chroma noise | Chroma bits and blocks at 4:2:2, chroma ME (N), chroma intra | M10 | Partly (LED walls, saturated kits) |
| spin (P2) | texture rotating 90°/s | Non-translational motion: partitions, ME, direct fails (N) | M6, M5 | Yes-ish (spinning graphics) |
| shuffle (P2) | `displace` with a random ±30 px vector per 16x16 block per frame | ME walks to the step limit and fails, then intra | M6, M5 | Pathological |
| baseline (P3) | pan + `noise=c0s=4` | Typical control | | |
| shake (P3) | large erratic but spatially uniform motion | **Expected cheap** (predictors carry it). It checks the reasoning | M6 | |
| chromafade (P3) | chroma-only saturation pulse | **Expected cheap**: the luma exit fires and chroma is never analysed | M1 | |
| strobe (P3) | pan and testsrc2 alternate every frame | Every frame is I or P-mostly-intra | M7 | Pathological |
| qpfloor (P3) | static bars ±1 LSB temporal noise | ABR drives QP down, so every MB is coded; ME is trivial | M9 | Yes (graphics, slates) |
| flickergrain, bandflicker (P3) | combinations | Serial M1 stacked on M5, or on M4 | | |

Variants: `ILF=vlpf` adds tinterlace's vertical low-pass, as SVT made their 1080i. The default is no filter, which is harder. `BAND_Y` and `BAND_H` move the band. At t8 the default band spans slices 2-3.

---

## 5. Rankings

All figures are **ESTIMATED from code reading, NOT measured**. They are per affected frame and relative to typical natural content (crowd_run-like) at the same bitrate. "S" means it hits the serial main-thread phase.

### Lowlat (t4, 10-bit 4:2:2 1080p50 unless noted)

| Rank | Case | Est. per-frame latency | Serial? | Notes |
|---|---|---|---|---|
| 1 | flicker | +~10 ms on **every** P frame (fade anchor); about 1.6-1.9x | **S** (weights_analyse incl. chroma, lowres16 build, lowres weighted plane) + slice barrier | Sustained. If typical P ≥ ~10 ms, every frame overruns 20 ms |
| 2 | blind (switch frames) | 1.5-3x for 1-3 frames per switch; 1.5-2x while on | P (row re-encodes) | The max-latency candidate. I frames inside the noise are worst |
| 3 | band | 1.5-2.5x latency at 0.5-0.8x CPU | P, but on one slice; the lowres band is imbalanced too (pre-slice) | t8 halves the band's slice and does not fix it |
| 4 | cuts / strobe | 1.5-2.2x on cut and post-flash frames; strobe sustained | pre-slice lowres (banded); NAL concat grows with I bytes (S, small) | Deblock leaves the whole-MB path on intra |
| 5 | dip | as flicker, during the 1 s of each 3 s | **S** | The known case |
| 6 | pfade | ≥ dip (unproven) | **S** + P | Depends on whether a weight is chosen |
| 7 | grain | 1.3-1.8x sustained | P (+ a little pre-slice lowres ME) | |
| 8 | xfade | 1.3-1.6x | P + some S (luma weight passes) | |
| 9 | shuffle / spin | 1.2-1.7x | P | |
| 10 | field @1080i | 1.2-1.5x per frame against its own progressive version | P | The 1080i25 budget is 40 ms, so less critical |
| 11 | chroma | 1.1-1.3x | P (S only with M1) | |
| - | shake, chromafade | ~1.0x (controls) | | Should come out cheap |

### Normal (--threads 8, 10-bit 4:2:2)

| Rank | Case | Est. main CPU/frame | Est. lookahead thread | Notes |
|---|---|---|---|---|
| 1 | grain / flickergrain | 1.8-2.5x | 1.5-2x | No B_SKIP; RD on every candidate; trellis dense |
| 2 | flicker | 1.2-1.4x (+1 searched dupe ref, weighted MC) | **+15-30 ms per P frame** (9-pass chroma) | The single lookahead thread is the overrun risk if b-adapt picks P often |
| 3 | field @1080i | 1.3-1.7x | ~1x | 8 field refs |
| 4 | shuffle / spin | 1.4-1.8x | 1.3-1.6x | B direct fails |
| 5 | cuts / strobe | 1.3-1.6x window average | +flash passes | Intra RD |
| 6 | blind | like grain at a lower planned QP; transient re-encodes | ~1x (blind) | 1 s VBV buffer, so fewer emergencies |
| 7 | chroma | 1.1-1.3x | ~1x | Chroma ME on P |
| - | band | n/a (no slices) | | Only through reference-row waits, which are minor under pacing |

---

## 6. Defects and surprises (file:line)

1. **10-bit weight cost scale mismatch** (upstream).
   - slicetype.c:212 and :221: `cost += X264_MIN( cmp, fenc->i_intra_cost[i_mb] );`. Here `cmp` is `mbcmp[PIXEL_8x8]` on 10-bit `lowres[]` pixels.
   - `i_intra_cost` is stored at 8-bit scale: `i_icost = ((i_icost + intra_penalty) >> (BIT_DEPTH - 8)) + lowres_penalty;` (slicetype.c:823; lowres8 path at lookahead8.c:415).
   - At 10-bit the min clamps whenever the inter SATD is above about ¼ of intra, so most blocks contribute the same value with and without a weight. The ratio check (`> 0.998f`, :492) then rejects more weights.
   - Effect: moderate 10-bit fades and flicker pay the serial luma analysis (and, when a luma weight survives, chroma), but code unweighted.
   - Verify by logging `minscore/origscore` at 8-bit and 10-bit on `dip`.
2. **Repeated row re-encode** (ratecontrol.c:1746-1767, encoder.c:3276-3284).
   - One row can be encoded up to about (qp_absolute_max − qp)/4 + 1 times.
   - There is no cap or counter, and nothing is logged.
3. **Lowres blind spot** (mc.c:553-557). The `blind` case shows it. Fine-grain textures partly share it.
4. **The weightp early exit fires rarely on normal content** (slicetype.c:370).
   - The 16-bit lowres build for both frames (slicetype.c:404-405), the luma cost passes, and possibly the lowres weighted plane run on non-fade frames.
   - It is worth measuring how often `weights_analyse` gets past the exit on crowd_run: probe its duration.
5. **No chroma weight without a luma weight** (slicetype.c:363). Saturation fades are never weighted. Quality only.
6. **Static slice and band splits** (encoder.c:3528-3529, slicetype.c:1005-1006).
7. **The 10-bit lowres skip threshold is 4x stricter** (slicetype.c:754; documented in lookahead8.c:343-347).
8. **Weighted P at 10-bit SMART (normal) adds a fully searched unweighted dupe** (encoder.c:2672; the 10-bit filter at :2472 only blocks the weighted dupes).
9. **The whole-MB AVX2 luma deblock is off** for intra MBs, intra tops, and frame-under-field pairs (deblock.c:433-444). Cut and I-frame content pays more deblock.
10. **The lowlat P_SKIP probe needs a skip neighbour** (analyse.c:3158-3164).
11. **`update_predictor` ignores rows with var < 10** (ratecontrol.c:2180). Rows that are flat in lowres never teach the row predictor, which is part of why `blind` stays under-predicted.
12. **Speedcontrol** (speed.c) is compiled in and inactive unless `sc.f_speed > 0`. If obed enables it, worst-case content shows up as preset drops, not overruns. Log it.

---

## 7. Measurement plan

### Clips

- Length: `DUR=6` s by default, which is 300 frames at 50p and 150 at 25i. That covers 12+ keyint-24 GOPs at 50p, several blind toggles and two dips. Use `DUR=10` for the final numbers.
- Formats: `p420_8` (1080p50 8-bit 4:2:0), `p422_10` (1080p50 10-bit 4:2:2), `i422_10` (1080i25 10-bit 4:2:2 TFF MBAFF).
- Interlace check:

  ```sh
  ffmpeg -i X_i422_10.y4m -vf idet -an -f null - 2>&1 | grep 'Multi frame'
  ```

  Expect TFF to dominate and Progressive to be about 0 for motion cases. Static cases (`band` background, `qpfloor`) read Undetermined or Progressive in still areas. That is expected, not PsF.
- Controls: `baseline`, plus crowd_run. On the Zen 2 box use `crowd_run_1080p50.y4m` for p420_8, converted to p422_10, and `crowd_run_1080i25_422p10.yuv`, which already exists from make-sources.sh.

### What to measure

- **Per-frame wall latency under pacing**: from the scheduled arrival tick to `x264_encoder_encode` return (lowlat), and the lateness of each call's start (both modes).
- **p50, p99, max, and the overrun count.**
  - lowlat: latency > 20 ms at 50p, > 40 ms at 25i. Also report > 80% of the budget, since obed has other stages.
  - normal: any call that starts after its tick, meaning the pipeline is full.
- **CPU per frame**: the process CPU delta per call under pacing, plus total CPU divided by frames.
- **Per-frame context**: from `--verbose`: frame type, QP, size, I/P/SKIP MB counts, scenecut lines. From the end-of-run summary: Weighted P-Frames and field-MB %.
- **Normal only**: lookahead-thread busy fraction (see the probes).

### Pacing harness

The x264 CLI has no pacing. This is a minimal patch to x264.c, to carry on a **scratch branch on the Zen 2 box** and not in the read-only checkout. It wraps the call at x264.c:1990.

```c
/* before the loop (after i_start = x264_mdate();) */
double pace_fps = getenv( "X264_PACE_FPS" ) ? atof( getenv( "X264_PACE_FPS" ) ) : 0;
FILE *flog = getenv( "X264_FRAMELOG" ) ? fopen( getenv( "X264_FRAMELOG" ), "w" ) : NULL;
int64_t period = pace_fps > 0 ? (int64_t)(1e9 / pace_fps + 0.5) : 0;
struct timespec tick; clock_gettime( CLOCK_MONOTONIC, &tick );
/* replacing x264.c:1990 */
if( period ) clock_nanosleep( CLOCK_MONOTONIC, TIMER_ABSTIME, &tick, NULL );
struct timespec a, b; struct rusage ra, rb;
clock_gettime( CLOCK_MONOTONIC, &a ); getrusage( RUSAGE_SELF, &ra );
i_frame_size = encode_frame( h, opt->hout, &pic, &last_dts );
clock_gettime( CLOCK_MONOTONIC, &b ); getrusage( RUSAGE_SELF, &rb );
if( flog ) fprintf( flog, "%d %lld %lld %lld %d\n", i_frame,
    (long long)((a.tv_sec - tick.tv_sec)*1000000LL + (a.tv_nsec - tick.tv_nsec)/1000),   /* late_us */
    (long long)((b.tv_sec - a.tv_sec)*1000000LL + (b.tv_nsec - a.tv_nsec)/1000),         /* wall_us */
    (long long)(((rb.ru_utime.tv_sec + rb.ru_stime.tv_sec) - (ra.ru_utime.tv_sec + ra.ru_stime.tv_sec))*1000000LL
              + ((rb.ru_utime.tv_usec + rb.ru_stime.tv_usec) - (ra.ru_utime.tv_usec + ra.ru_stime.tv_usec))), /* cpu_us */
    i_frame_size );
if( period ) { tick.tv_nsec += period; while( tick.tv_nsec >= 1000000000 ) { tick.tv_nsec -= 1000000000; tick.tv_sec++; } }
```

How it works:

- The input frame is read before the sleep, so file I/O is outside the timing.
- At lowlat (zerolatency, sliced), the call's output is the same frame, so `wall_us` is the per-frame latency.
- In normal mode, use `late_us > 0` for overruns, and the CPU totals.

Fallback with no patch:

- Pace with `ffmpeg -re -i clip.y4m -f yuv4mpegpipe -strict -1 - | x264 ... --demuxer y4m -`.
- Time `x264_encoder_encode` with uprobes (below).
- `-re` jitter adds noise, so use this only to rank cases.

Summary per log:

```sh
awk -v B=20000 '{w[NR]=$3; c+=$4; if($3>B)o++; if($2>0)l++} END{n=asort(w); printf "p50 %d p99 %d max %d over %d late %d cpu/frame %d us\n", w[int(n*.5)], w[int(n*.99)], w[n], o, l, c/NR}'
```

`asort` needs gawk.

### Per-phase instrumentation

These are uprobes at a few calls per frame, which is under the ~1k calls/s cap. Confirm the names with `nm x264 | grep -E 'x264_10_(weights_analyse|slicetype_decide|threads_(distribute|merge)_ratecontrol|cabac_encode_flush|macroblock_thread_init|ratecontrol_end)'`. Use `x264_8_` for 8-bit.

| Phase | Entry / return probes | Gives |
|---|---|---|
| total | `x264_encoder_encode` (api.c:175) | per-call latency |
| pre-slice serial (L) | encode entry → `x264_10_threads_distribute_ratecontrol` entry | prologue + slicetype + weights |
| weightp (L: S; N: lookahead tid) | `x264_10_weights_analyse` entry/return; the 4th arg (`%cx`) is `b_lookahead` | serial weight time, and how often the early exit fails |
| slicetype | `x264_10_slicetype_decide` entry/return (L: main tid; N: lookahead tid) | lowres + decide; N: lookahead busy % |
| slices | `distribute` → `x264_10_threads_merge_ratecontrol` | the parallel phase |
| per slice | `x264_10_macroblock_thread_init` (slice start, per tid) → `x264_10_cabac_encode_flush` (slice end) | slice imbalance. Skip at t8 if near the probe cap |
| post | merge → encode return | NAL concat, RC end |

Counters that need a scratch patch:

- **Row VBV re-encodes**: `x264_ratecontrol_mb` runs per MB, far too often to probe. Add an int to `h->stat.frame` *before* `i_ssd`. It is summed across slice threads by the loop at encoder.c:3592. Increment it at encoder.c:3276 and print it in the frame debug line.
- A per-frame flag for whether a weight was chosen.

### Zen 2 run plan (target: about an hour)

Box: Ryzen 3000, Zen 2, AVX2 only. Run `lscpu -e` and pin lowlat t4 to **one CCX** with its SMT siblings, to stand in for the 4-core-CCX EPYC 8324P. Stop other load.

```sh
X=./x264                         # speed-next bd886aae + the scratch pacing patch, 8+10-bit
CMN="--aud --pic-struct --open-gop --keyint 24 --colorprim bt709 --transfer bt709 --colormatrix bt709 --overscan crop --nal-hrd fakevbr --verbose"
LL="--preset veryfast --tune zerolatency"
NM="--ref 4 --bframes 3 --rc-lookahead 24"
# per format: depth/csp/rate
F_p420_8="--output-depth 8 --output-csp i420"
F_p422_10="--output-depth 10 --output-csp i422"
F_i422_10="--output-depth 10 --output-csp i422 --tff"
# lowlat: R=20000 for 1080p50, 15000 for 1080i25; bufsize R/2
X264_PACE_FPS=50 X264_FRAMELOG=ll_t4_flicker_p422.log taskset -c $CCX0 \
  $X $CMN $LL --threads 4 $F_p422_10 --bitrate 20000 --vbv-maxrate 20000 --vbv-bufsize 10000 -o /dev/null wc/flicker_p422_10.y4m 2> ll_t4_flicker_p422.err
X264_PACE_FPS=25 ... --threads 4 $F_i422_10 --bitrate 15000 --vbv-maxrate 15000 --vbv-bufsize 7500 ... wc/flicker_i422_10.y4m
# normal: bufsize = R
X264_PACE_FPS=50 X264_FRAMELOG=nm_t8_flicker_p422.log \
  $X $CMN $NM --threads 8 $F_p422_10 --bitrate 20000 --vbv-maxrate 20000 --vbv-bufsize 20000 -o /dev/null wc/flicker_p422_10.y4m 2> nm_t8_flicker_p422.err
```

Do not use `--psnr` or `--ssim` in timing runs, because they add per-row work. Run a quality pass separately if needed.

Order and budget (about 55 min):

1. **Smoke, about 3 min.** `SMOKE=1 CASES="$(LIST=1 sh worst-case-gen.sh | cut -d' ' -f1)" sh worst-case-gen.sh` runs every graph for 0.1 s into null. Fix any filter-syntax errors first; the graphs were written without an ffmpeg to test on.
2. **Generate P1, about 12 min, ~24 GB.** `OUT=/data/wc sh worst-case-gen.sh`. Then run idet on `field`-like motion in `flicker_i422_10` and `cuts_i422_10`.
3. **Lowlat t4, paced, about 12 min.**
   - Cases: P1 + baseline + crowd_run.
   - Formats: p422_10, i422_10, p420_8.
   - 3 repeats, because lowlat has a ±0.04% sliced race (see the bd notes).
   - Order of interest: flicker, blind, band, cuts, grain.
4. **Lowlat t8, paced, about 4 min.** Same set, 1 repeat, on 8 cores, to see whether band, flicker and the serial share scale.
5. **Normal t8, paced, about 8 min.** Same set, 2 repeats.
6. **Per-phase uprobes, about 6 min.** flicker, blind, band and cuts at lowlat t4 p422_10, and flicker and grain at normal p422_10 (lookahead tid).
7. **If time remains: P2.** `OUT=/data/wc CASES="dip pfade field shuffle" FORMATS="p422_10 i422_10" sh worst-case-gen.sh`, then steps 3 and 5 for those. dip validates the known +10 ms anchor; field and shuffle cover 1080i and ME.

Report, per arm:

- the branch, commit, config line, input file and format;
- p50, p99 and max wall time, the overrun and late counts, CPU per frame;
- for lowlat, the per-phase split.
