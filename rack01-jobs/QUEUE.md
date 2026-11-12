# rack01 x264-obe in-situ queue (Zen 4, EPYC 8324P, AVX-512)

Ranked by expected production gain on Zen 4, biggest first. Production = P6 normal + lowlat on 8-bit 4:2:0,
8-bit 4:2:2 and 10-bit 4:2:2. Gates rank by the win they unblock. Interleave with the x265 jobs in this order.
Gains are estimates from the package reports and the 11-11 production profile, not measurements.

## How to run

```
git clone https://github.com/kierank/x264-obe ~/x264-r01-jobs && cd ~/x264-r01-jobs && git checkout wip/x264-core3-jobs
export CORE=<one idle cpu, e.g. a node-3 cpu>      # decoders stopped by SNMP, nothing else heavy on the box
bash rack01-jobs/<pkg>/<job>.sh all                 # preflight build check live md5 time report clean
```

- Every script is standalone. It is generated from `<job>.conf` + `lib/engine.sh` by `lib/mkjobs.sh`.
- `CLIPS` defaults to `~/x264-parity/clips/<name>.y4m`: fades-p, tile-chaos-p, pan-fast-p (1080p59.94) and
  fades-i, field-frame-mix-i, credits-i (1080i29.97; `--tff` on -i).
- 4:2:2 content (8-bit `-422`, 10-bit `-422p10`) does not exist on rack01. `build` generates it into `$W/clips`
  with stressgen (x264-obe test/stressgen cf607051, same scenarios, native 4:2:2, `GENFRAMES`=150 frames). No ffmpeg
  is needed, and there is no XCOLORRANGE token.
- Disk (17 GB free): each job keeps its 4 trees, clips and outputs under `$W` (`~/r01-<job>`) and removes them at
  the end (`clean`, also on a failed step unless `KEEP=1`). Results are copied to `~/r01-results/<job>/`. The shared
  clone `~/x264-r01-src` is kept. Peak use is about 3 GB for 8-bit jobs and about 7 GB for 10-bit jobs (four
  10-bit 4:2:2 clips of 1.25 GB plus one recon dump).

## Protocol (lib/engine.sh, the same for every job)

- **Trees:** git-archive exports of exact full shas (`BASE`, `ARM`), so every arm carries the same version string.
  A patched arm uses a perl edit that must change the file, followed by assertion greps (`pl` / `want` / `before`).
  The edits were dry-checked on the pushed shas (`patchcheck`).
- **Build:** `./configure --bit-depth=8|10 --extra-cflags="-fno-fast-math -ffp-contract=off -fno-pie" --extra-ldflags="-no-pie"`,
  with x264 and checkasm built. `/usr/local/bin` comes first in PATH (nasm 3.02).
- **Arms:** base, base' (a second build of base), arm, arm'.
- **Timing:** `taskset -c $CORE perf stat -x, -e cycles:u,instructions:u -- x264 ... --threads 1`, with perf pinned
  together with x264.
  - 12 rounds. The arm order rotates each round, and an interrupted run resumes.
  - At round 6, the job stops early on a clear result:
    - STOP-LOSS: slower in >= 5/6 rounds and median > +0.3 % on every decision cell;
    - STOP-WIN: faster in 6/6 rounds on every decision cell.
  - `report` prints, per cell:
    - the paired median of (arm+arm')/(base+base') - 1;
    - both A/A controls;
    - the instructions:u delta;
    - a WIN / LOSS / MIXED status.
- **md5 gate (before any timing):**
  - recon md5 (`--dump-yuv`) across all 4 arms;
  - bitstream md5 within one sha only (base/base', arm/arm').
  - Cells: the timing cells, every clip x lowlat + normal, the **8-bit 4:2:2 interlaced cells** (`--output-csp i422
    --profile high422` on fades-i / field-frame-mix-i / credits-i), and the job's extra cells.
  - nrbskip adds the no-dump bitstream across arms (`--dump-yuv` turns its phase 1 off).
- **Liveness:** `perf record -e cycles:u` samples, base and arm (no gdb). Assertions per job:
  - `A+` / `A0` / `B+` / `B0`: the arm / base has samples / no samples of a symbol;
  - `A<B` / `A>B`: the arm has fewer / more samples than the base.
  - Null cells must show zero samples of the changed code.
  - A failed liveness check (`NOT LIVE`) stops the job before md5 and timing.
- **Null control:** a zero-call cell where one exists. It is timed in the same rounds, excluded from the decision,
  and expected to read ~0 % within the A/A.
- **Cells:**
  - production P6 normal: `--subme 6 --me hex --ref 2 --no-mixed-refs --no-chroma-me --trellis 1 --partitions i8x8,i4x4 --psy-rd 1.0:0 --bframes 3 --rc-lookahead 24`;
  - lowlat: `--preset veryfast --tune zerolatency --intra-refresh`;
  - both at 20 Mb/s (4:2:2: 50 Mb/s), VBV, fakevbr HRD, keyint 30, open GOP.
- **MBM jobs** (`*-mbm`) NEED KIERAN ROOT. `bash <job>.sh setup-cmds` prints the resctrl mount, group and chown
  commands (never run by the script). Without them, `mbm` stops and prints them.
- **Arm pairs and depths (`AB`, `BITDEPTH`):** dcrd-zen4, dbk422-zen4, dbkgap-zen4 and mvpredc-zen4 offer several arm
  pairs and both depths in one .conf. Each run is its own job (`$JOB` = `<job>-<AB>-<depth>b`, with its own `$W` and
  results directory), so the runs of one package do not share state. An unknown or unsupported pair stops at once.
- **Package steps:** a .conf may define `pkgstep_<name>`, run as `bash <job>.sh <name>` or from its `ALLSTEPS`.
  mvpredc-zen4 runs `twin` after `check`: test/x264-mvpred-c-twin a2abd958 (the old x264_mb_predict_mv_ref16x16
  beside the new one, abort on any difference) on every md5 cell plus frame threads, sliced threads and medium
  `--direct temporal --weightp 2`. Each must exit 0 and print "mismatches 0" (mbaff > 0 on the -i cells), or the job
  stops before live / md5 / timing.
- **Replaced scripts:** none of the older scripts is to be used on rack01.
  - The core3-jobs scripts for these packages and the scratchpad rack01-rd8x8.sh / rack01-pts512.sh used
    `/usr/bin/time`, gdb liveness, or `perf stat -- taskset` (perf unpinned).
  - core3-jobs intrax9 `AB=icl` patched the HIGH_BIT_DEPTH block, so it was a no-op on 8-bit.
  - The idct8 `AB=zen4` sed also changed the AVX block's line.
  - The 10b-cabac script resolved its arms relative to a moving tip.

## Standing rule: AVX-512 kernels are parked on zen5, never dropped

Kieran 11-11: "any failed avx512 needs parking on zen5". When a verdict goes against an AVX-512 kernel (LOSS, or
MIXED/NEUTRAL), the kernel is NOT dropped. It is pushed as `zen5/x264-<topic>`, pointing at a commit where it is
DISPATCHED (Zen 5 is the production target, with a full 512-bit datapath). rack01 does not push: the lead creates
each zen5 branch from the verdicts.

- An arm that is a commit: the zen5 branch points at that sha.
- An arm made by sed/perl: the zen5 branch is the job's tip with its `patch_arm` applied, committed as
  "zen5: dispatch <kernel>".
- A prune job (the arm replaces an AVX-512 pointer with AVX2): if the prune wins on Zen 4, the zen5 branch points at
  the base, where the AVX-512 kernel is still dispatched.

Each AVX-512 job's header and its `report` output name the exact branch (`ZEN5=` in the .conf). The table below
names it in "The verdict decides".

## Ranked queue

| # | Job | Command | Expected production gain (Zen 4) | The verdict decides |
|---|---|---|---|---|
| 1 | 10b-me-inline512 | `bash rack01-jobs/10b-me/10b-me-inline512.sh all` | -1 to -3 % of 10-bit 4:2:2 (lowlat + normal). The fused ME today runs the old 10-bit avx512 entry, which is slower than C | dispatch me_search_fpel_inline_avx512 at 10-bit (one line); ZEN5 on a verdict against AVX-512: zen5/x264-10b-me-inline512 = 41f6b02e + this job's patch_arm, committed as "zen5: dispatch me_search_fpel_inline_avx512 (10-bit)" |
| 2 | hpelfly-ab | `bash rack01-jobs/hpelfly/hpelfly-ab.sh all` | -0.5 to -1 % cycles, sign unproven: hpel_filter + copy (~1.2 %) and 3 plane stores per ref go, band compute comes in. Plus large L3/DRAM traffic savings | merge hpelfly at 8-bit (cycles half) |
| 3 | hpelfly-mbm | `bash rack01-jobs/hpelfly/hpelfly-mbm.sh all` (**needs Kieran root**) | traffic only: MB/f of stored H/V/C per ref frame | the traffic half of the hpelfly case (E-2400 one-DIMM goal) |
| 4 | 10b-cabac-rd2 | `bash rack01-jobs/10b-cabac/10b-cabac-rd2.sh all` | -0.5 to -1 % of 10-bit 4:2:2 normal. ~4-4.5 % is in these coders; Zen 4 already runs icl and rd2 is 1.5-2.5x on the laptop. Lowlat 0 | keep 75947ac3 (the Zen 4/5 rd2 dispatch, droppable); ZEN5 on a verdict against AVX-512: zen5/x264-10b-cabac-rd2 = 75947ac3 (the arm commit; then drop 75947ac3 from the merge) |
| 5 | rd8x8-rd2 | `bash rack01-jobs/rd8x8/rd8x8-rd2.sh all` | -0.3 to -0.6 % normal: the 8x8 rd slot is ~1.2 %, and rd2 is 0.33-0.68x of icl in most classes | merge wip/x264-gap-rd8x8-icl f7162d21; ZEN5 on a verdict against AVX-512: zen5/x264-rd8x8-rd2 = f7162d21 (the arm commit) |
| 6 | mbtree-avx512 | `bash rack01-jobs/mbtree/mbtree-avx512.sh all` | -0.3 to -0.4 % normal: the propagate slot is ~0.7 % and the strip is 1.5-2.5x per call | merge the mbtree branch with 0b09bab8 (AVX-512 arm) or only to f017bec6; ZEN5 on a verdict against AVX-512: zen5/x264-mbtree-avx512 = 0b09bab8 (the arm commit; merge stops at f017bec6) |
| 7 | nrbskip-ab | `bash rack01-jobs/nrbskip/nrbskip-ab.sh all` | -0.2 to -0.5 % normal (fewer stores), lowlat small | merge nrbskip (both phases) or phase 1 only |
| 8 | nrbskip-mbm | `bash rack01-jobs/nrbskip/nrbskip-mbm.sh all` (**needs Kieran root**) | traffic only: ~4.8 MB/f analytic | the traffic half of the nrbskip case |
| 9 | mbaffplanes-ab | `bash rack01-jobs/mbaffplanes/mbaffplanes-ab.sh all` | -0.2 to -0.5 % on interlaced, or a loss if the lost THP on F/H costs dTLB. Progressive cells are the null control | merge mbaffplanes |
| 10 | mbaffplanes-mbm | `bash rack01-jobs/mbaffplanes/mbaffplanes-mbm.sh all` (**needs Kieran root**) | traffic only: ~2.1 MB/f normal, ~4.2 MB/f lowlat | the traffic half of the mbaffplanes case |
| 11 | 10b-cabac-rd8 | `bash rack01-jobs/10b-cabac/10b-cabac-rd8.sh all` | ±0.3 % of 10-bit 4:2:2 normal (8x8 rd2 vs icl was mixed on the laptop) | dispatch the 10-bit 8x8 rd2 at AVX512ICL; ZEN5 on a verdict against AVX-512: zen5/x264-10b-cabac-rd8 = 75947ac3 + this job's patch_arm, committed as "zen5: dispatch cabac_block_residual_8x8_rd2_internal_avx512icl (10-bit)" |
| 12 | trellis-z1 | `bash rack01-jobs/trellis/trellis-z1.sh all` | ±0.3 % normal: the trellis 4x4/dc slot is ~2 %, and the icl version was pruned on a bench, never in situ | undo the bench prune of icl trellis 4x4 / dc; ZEN5 on a verdict against AVX-512: zen5/x264-trellis-icl4x4 = 939df094 + this job's patch_arm, committed as "zen5: dispatch trellis_cabac_4x4 / 4x4_psy / dc / chroma_422_dc avx512icl" |
| 13 | trellis-z0 (gate, no timing) | `bash rack01-jobs/trellis/trellis-z0.sh all` | 0 on Zen 4; it unblocks the trellis merge for its Intel win (Core 3 Job X) | the Intel-only nodes dispatch is a Zen 4 no-op (md5 SAME, zero nodes samples) |
| 14 | intrax9-icl | `bash rack01-jobs/intrax9/intrax9-icl.sh all` | ±0.3 %: the x9 slots are ~5 %, and icl was slower on laptop Zen 5 | dispatch the icl x9 kernels on Zen 4/5 or keep AVX2; ZEN5 on a verdict against AVX-512: zen5/x264-intrax9-icl = 76142791 + this job's patch_arm, committed as "zen5: dispatch intra_satd_x9_4x4 / intra_sa8d_x9_8x8(_fdec) / x9_4x4_recon(_notr) avx512icl" |
| 15 | la2-icl | `bash rack01-jobs/la2/la2-icl.sh all` | -0.1 to -0.3 % normal (lowres B path, icl -13 % vs avx2 -5 % on the intra loop) | keep 0877c420 (icl) or stop at b81cae5e (avx2); ZEN5 on a verdict against AVX-512: zen5/x264-la2-icl = 0877c420 (the arm commit; merge stops at b81cae5e) |
| 16 | me2-weighted | `bash rack01-jobs/me2-fused/me2-weighted.sh all` | -0.1 to -0.3 % on weightp content (fades), 0 elsewhere | merge me2-fused up to 4c404747; ZEN5 on a verdict against AVX-512: zen5/x264-me2-weighted = 4c404747 (the arm commit; the Zen 4 me_search_fpel_avx512 weighted path) |
| 17 | trprep-icl | `bash rack01-jobs/trprep/trprep-icl.sh all` | -0.1 to -0.2 % normal (icl prep 8x8 1.8-2.2x vs avx2 1.2-1.6x) | dispatch the icl trellis prep/post; ZEN5 on a verdict against AVX-512: zen5/x264-trprep-icl = 2534f770 + this job's patch_arm, committed as "zen5: dispatch quant_4x4x4_scan_trellis / quant_8x8_scan_trellis / dequant_4x4x4_scan(_ac) avx512icl" |
| 18 | avg2w16-zen4 | `bash rack01-jobs/avg2w16/avg2w16-zen4.sh all` | -0.1 to -0.2 %: the asm get_ref saves call overhead; get_ref + avg2 ~1.4 % | Zen 4 takes the Intel get_ref/mc_luma block |
| 19 | idct8-batch | `bash rack01-jobs/idct8/idct8-batch.sh all` | -0.1 to -0.2 % (all-four-coded inter 8x8 MBs as one add16x16_idct8). It also gates #24 | merge d0fa61cd (batching) |
| 20 | hpelfly-swap | `bash rack01-jobs/hpelfly/hpelfly-swap.sh all` | ±0.2 % (fused search on band planes vs the C search on fly refs) | keep 33d409a1 in the hpelfly merge |
| 21 | pts512-bench (gate) | `bash rack01-jobs/pts512/pts512-bench.sh all` | 0; it unblocks #22 / #27 | whether pts512-hex / -dia are worth their in-situ time |
| 22 | pts512-hex | `bash rack01-jobs/pts512/pts512-hex.sh all` | ~-0.1 % (hex_search 8x8 slot ~1 %) | dispatch icl hex_search 8x8 on Zen 4/5; ZEN5 on a verdict against AVX-512: zen5/x264-pts512-hex = 3956bfc2 (the arm commit) |
| 23 | idct8-zen4 | `bash rack01-jobs/idct8/idct8-zen4.sh all` | 0 to -0.1 % (add8x8_idct8 ~0.6 %, kernels tie) | Zen 4/5 add8x8_idct8 pointer (avx / avx2) |
| 24 | idct8-zen4p16 | `bash rack01-jobs/idct8/idct8-zen4p16.sh all` (after #19) | ~-0.05 % (avx2/icl 0.83-0.91), only with batching | prune add16x16_idct8 avx512icl on Zen 4; ZEN5 on a verdict against AVX-512: PRUNE job (the arm drops avx512icl): if the prune WINS, zen5/x264-idct8-add16x16-icl = 76dda80b (the base, icl dispatched); if it loses or ties, icl stays dispatched and nothing is parked |
| 25 | idct8-zen4icl | `bash rack01-jobs/idct8/idct8-zen4icl.sh all` | 0 to -0.1 % | Zen 4/5 add8x8_idct8 pointer (avx / avx512icl); ZEN5 on a verdict against AVX-512: zen5/x264-idct8-add8x8-icl = d625b235 + this job's patch_arm, committed as "zen5: dispatch add8x8_idct8_avx512icl" |
| 26 | me2-dedupe | `bash rack01-jobs/me2-fused/me2-dedupe.sh all` | 0 to -0.05 % (laptop: inside the noise) | keep 455e9d8d; ZEN5 on a verdict against AVX-512: zen5/x264-me2-dedupe = 455e9d8d (the arm commit) |
| 27 | pts512-dia | `bash rack01-jobs/pts512/pts512-dia.sh all` | 0 at P6; this is headroom under overload (speedcontrol presets 0-1) | dispatch icl point sets + dia_search 8x8; ZEN5 on a verdict against AVX-512: zen5/x264-pts512-dia = 1fa7952b (the arm commit) |
| 28 | cacheload-avx512 | `bash rack01-jobs/cacheload/cacheload-avx512.sh all` | ~0 (laptop: avx512 7.9 vs avx2 7.6 ticks, slower at n <= 2) | dispatch mb_fref_load avx512; ZEN5 on a verdict against AVX-512: zen5/x264-cacheload-avx512 = ab419b5c + this job's patch_arm, committed as "zen5: dispatch mb_fref_load_avx512" |
| 29 | me2-8x16 | `bash rack01-jobs/me2-fused/me2-8x16.sh all` | 0 in production (no 8x16 partitions at P6/lowlat; the P6 cells are the null control). The decision cell is medium | keep 12d4c228 (a medium-only win is a keeper); ZEN5 on a verdict against AVX-512: zen5/x264-me2-8x16-avx512 = 12d4c228 (the arm commit) |
| 30 | a512only-bench (gate) | `bash rack01-jobs/a512only/a512only-bench.sh all` | 0; it unblocks #31 / #32 | whether the 4:2:2 prunes get in-situ time |
| 31 | a512only-oc | `bash rack01-jobs/a512only/a512only-oc.sh all` | ~-0.05 % of 8-bit 4:2:2 (optimize_chroma_2x4_dc avx2 vs icl); 4:2:0 is the null control | prune optimize_chroma_2x4_dc icl on Zen 4; ZEN5 on a verdict against AVX-512: PRUNE job (the arm drops avx512icl): if the prune WINS, zen5/x264-a512only-oc-icl = 86666108 (the base, optimize_chroma_2x4_dc_avx512icl dispatched); otherwise nothing is parked |
| 32 | a512only-cl8 | `bash rack01-jobs/a512only/a512only-cl8.sh all` | ~-0.05 % of 8-bit 4:2:2 (coeff_last8 avx2_lzcnt vs avx512); 4:2:0 is the null control | prune coeff_last8 avx512 on Zen 4; ZEN5 on a verdict against AVX-512: PRUNE job (the arm drops avx512): if the prune WINS, zen5/x264-a512only-cl8-avx512 = 86666108 (the base, coeff_last8_avx512 dispatched); otherwise nothing is parked |
| 33 | a512only-zmm | `bash rack01-jobs/a512only/a512only-zmm.sh all` | 0: expected zero-call, since the no-mvs weightp pcd path is production-dead (wpdeint). The job should stop at `live` with NOT LIVE | confirm there is nothing to dispatch (leave zmm undispatched); ZEN5 on a verdict against AVX-512: zen5/x264-a512only-pcd-zmm = 86666108 + this job's patch_arm, committed as "zen5: dispatch plane_copy_deinterleave_zmm_avx512icl" (also on NOT LIVE) |
| 34 | a512only-pcd | `bash rack01-jobs/a512only/a512only-pcd.sh all` | 0: expected zero-call, as for #33 | confirm there is nothing to prune; ZEN5 on a verdict against AVX-512: PRUNE job (the arm drops avx512icl): if the prune WINS, zen5/x264-a512only-pcd-icl = 86666108 (the base); NOT LIVE / loss / tie: nothing is parked |
| 35 | dcrd-zen4 | `AB=avx2 bash rack01-jobs/dcrd/dcrd-zen4.sh all`, then `AB=icl2` and `AB=icl1`, each at `BITDEPTH=8` and `BITDEPTH=10` (6 runs). `AB=icl2-avx2` (head-to-head) only if avx2 and icl2 both win within 0.3 % | -0.1 to -0.4 % of 4:2:2 normal at both depths: Zen 4 still runs the C 4:2:2 dc rd; laptop per call C / avx2 / icl2 ~1.0x on sparse, 1.7x on dense, 2.1x on full blocks. Lowlat 0 (the null control) | which Zen 4/5 dispatch the 4:2:2 dc rd takes at 8 and 10-bit (arms vs base fe2db406 = C): the C (the tip as is), avx2_bmi2 (a02322ce), rd2_avx512icl (b14be256) or icl1 (14b473a4); ZEN5: the AVX-512 arms already are their zen5 branches (zen5/x264-422-dcrd-icl2 = b14be256, zen5/x264-422-dcrd-icl1 = 14b473a4, pushed): nothing new to create |
| 36 | dbk422-zen4 (gate) | `AB=tip bash rack01-jobs/dbk422/dbk422-zen4.sh all`, then `AB=icl` (8-bit). Optional `AB=tip BITDEPTH=10` (every cell null, 6 rounds) | ~-0.05 % of 8-bit 4:2:2 (instructions:u -79 / -72 per h_chroma_422(_intra) call). It gates the wip/x264-422-deblock merge (the Intel AVX2 win, Xeon E) for AVX-512 machines | AB=tip: merge with Zen 4/5 on the avx2 pair, or keep them on avx (an AVX512ICL override before the merge); AB=icl: dispatch the 8-bit icl pair on Zen 4/5; ZEN5 on a verdict against AVX-512 (AB=icl): zen5/x264-422-deblock-icl = beec0fb5 + this job's patch_arm, committed as "zen5: dispatch deblock_h_chroma_422(_intra)_avx512icl (8-bit)"; AB=tip has no AVX-512 kernel: nothing is parked |
| 37 | dbkgap-zen4 (gate) | `AB=tip bash rack01-jobs/dbkgap/dbkgap-zen4.sh all` at `BITDEPTH=8` and `BITDEPTH=10`, then `AB=icl BITDEPTH=10` | ~-0.05 % of interlaced (MBAFF mixed edges only: instructions:u -11 to -81 per call). It gates the wip/x264-deblock-gaps merge (the Intel win) for AVX-512 machines | AB=tip: merge with Zen 4/5 on the new pointers (8-bit 4:2:0 MBAFF chroma avx, 10-bit luma MBAFF avx2), or AVX512ICL overrides back per depth; AB=icl: dispatch the 10-bit icl luma MBAFF pair on Zen 4/5; ZEN5 on a verdict against AVX-512 (AB=icl): zen5/x264-deblock-gaps-icl = 42c8bdbd + this job's patch_arm, committed as "zen5: dispatch deblock_h_luma(_intra)_mbaff_avx512icl (10-bit)"; AB=tip has no AVX-512 kernel: nothing is parked |
| 38 | mvpredc-zen4 | `AB=all bash rack01-jobs/mvpredc/mvpredc-zen4.sh all`; `AB=c1` / `AB=c2` split it | -0.1 to -0.3 % of interlaced: the 4-6 ref16x16 calls per MBAFF mb stop re-deriving the neighbour shifts, the collocated mvs and the temporal scales. Progressive ~0. The twin gate (step `twin`, a2abd958 "mismatches 0") runs before live / md5 / timing | merge wip/x264-mvpred-c (both commits, or c1 alone if c2 loses on the interlaced cells); C only: no zen5 branch |

## Shas (full shas are in each .conf)

| Job | Base | Arm |
|---|---|---|
| 10b-me-inline512 | 41f6b02e | 41f6b02e + 10-bit AVX512 me_search_fpel -> inline_avx512 |
| hpelfly-ab / -mbm | 14953cf5 | 401d882f |
| hpelfly-swap | 401d882f -DHPELFLY_SWAP=0 | 401d882f |
| 10b-cabac-rd2 | c1fa65f4 | 75947ac3 |
| 10b-cabac-rd8 | 75947ac3 | 75947ac3 + 8x8 rd -> rd2_avx512icl |
| rd8x8-rd2 | e3a52acd | f7162d21 |
| mbtree-avx512 | f017bec6 | 0b09bab8 |
| nrbskip-ab / -mbm | 4e292d6a | cb5b86c2 |
| mbaffplanes-ab / -mbm | c664d151 | 2d0dbfac |
| trellis-z1 | 939df094 | 939df094 + icl 4x4 / 4x4_psy / dc / 422_dc |
| trellis-z0 | 42c3f783 | 939df094 |
| intrax9-icl | 76142791 | 76142791 + icl x9 (8-bit blocks) |
| la2-icl | b81cae5e | 0877c420 |
| me2-weighted | fca9575c | 4c404747 |
| me2-dedupe | 12d4c228 | 455e9d8d |
| me2-8x16 | 026f9c51 | 12d4c228 |
| trprep-icl | 2534f770 | 2534f770 + icl prep/post |
| avg2w16-zen4 | 6454133a | 6454133a + Intel block on AVX-512 |
| idct8-batch | c134a6bb | d0fa61cd |
| idct8-zen4 / -zen4icl | d625b235 | d625b235 + ICL add8x8_idct8 -> avx2 / avx512icl |
| idct8-zen4p16 | 76dda80b | 76dda80b - ICL add16x16_idct8 |
| pts512-hex | e4dd771a | 3956bfc2 |
| pts512-dia | 9e12b65a | 1fa7952b |
| pts512-bench | 3956bfc2 (bench only) | |
| cacheload-avx512 | ab419b5c | ab419b5c + mb_fref_load avx512 |
| a512only-* | 86666108 | 86666108 + oc / cl8 / zmm / pcd edit (bench: no arm) |
| dcrd-zen4 AB=avx2 / icl2 / icl1 | fe2db406 | a02322ce / b14be256 / 14b473a4 |
| dcrd-zen4 AB=icl2-avx2 | a02322ce | b14be256 |
| dbk422-zen4 AB=tip / icl | baf5b648 / beec0fb5 | beec0fb5 / beec0fb5 + 8-bit icl h_chroma_422 pair at AVX512ICL |
| dbkgap-zen4 AB=tip / icl | 9ef632af / 42c8bdbd | 42c8bdbd / 42c8bdbd + 10-bit icl luma MBAFF pair at AVX512ICL |
| mvpredc-zen4 AB=all / c1 / c2 | 44754802 / 44754802 / 970be01c | c234b4b1 / 970be01c / c234b4b1 (twin: a2abd958; AB=c1 also 9f158ea7) |
