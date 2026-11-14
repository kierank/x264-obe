# Xeon E x264-obe in-situ queue (Intel AVX2 timing judge)

Machine: Xeon E-2478 (Raptor Cove: AVX2 + AVX-VNNI, no AVX-512, no SlowGather). x264 runs on cpu 12 or 14 only;
builds run on cpus 12-15. Run order (lead, 11-11, after the 8-bit 4:2:2 profile): X1 (done), O (done, blocked), O-split (1a), AD, M, J (oc, cl8, then il / pcd), 10b-me, 10b-cabac, K k2, Z, T, L, R, AC, U, K k1 last. The section numbers below are the original ranking.
Expected effects are the package reports' laptop (Zen 5) numbers and estimates, not Intel measurements.

## How to run

```
git clone -b wip/x264-core3-jobs https://github.com/kierank/x264-obe ~/xeone-pack   # the scripts (later: git -C ~/xeone-pack pull)
cd ~/xeone-pack/xeone-jobs
# trees: shared-object clones of ~/x264j/src (SRC; cloned from github if missing), one per tree, sha and flavour,
# under ~/xeone/<job>-<AB>-<base8>-<arm8>/ (W). CORE=12 by default (CORE=14 for the other x264 cpu).
```

Phases, one per invocation (`bash <job>.sh <phase>`):

| phase | when | what |
|---|---|---|
| `build` | build window | 8 trees (base, base', arm, arm' x timing / md5 flavour) + counter trees, `taskset -c 12-15 make -j4`, checkasm 3 seeds, the job's checkasm bench lines |
| `live` | build window or before timing, box otherwise idle | `taskset -c $CORE perf record -e cycles:u` symbol samples of `LIVE_RE`, base and arm, every timed cell; then the counter trees' stderr lines |
| `md5` | same | gate: recon md5 (`--dump-yuv`) across all 4 arms, bitstream md5 only within one sha (base/base', arm/arm'); timed cells + md5-only cells |
| `time [R]` | timing block only | R paired rounds (default 9), base/base'/arm/arm' rotated per round, `taskset -c $CORE perf stat -x, -e cycles:u,instructions:u -- x264 ...`; resumes after an interruption |
| `report` | any time | per cell: paired median (arm+arm')/(base+base') - 1, arm/base and arm'/base', A/A base'/base and arm'/arm, arm faster in N/R, median cycles:u and instructions:u of every arm |

Protocol (xeone-jobs/lib.sh, the same for every job):
- configure `--extra-cflags="-fno-pie" --extra-ldflags="-no-pie"` (timing builds), plus `-fno-fast-math -ffp-contract=off`
  for the md5 and counter builds; `--disable-opencl --disable-lavf --disable-ffms --disable-gpac --disable-lsmash`.
- Cells: LOWLAT `--preset veryfast --tune zerolatency --intra-refresh --keyint 30 --bitrate 20000 --vbv-maxrate 20000 --vbv-bufsize 667 --nal-hrd fakevbr --aud --pic-struct --open-gop --profile high --threads 1`
  and NORMAL `--subme 6 --me hex --ref 2 --no-mixed-refs --no-chroma-me --trellis 1 --partitions i8x8,i4x4 --psy-rd 1.0:0 --bframes 3 --rc-lookahead 24 --keyint 30 --bitrate 20000 --vbv-maxrate 20000 --vbv-bufsize 20000 --nal-hrd fakevbr --aud --pic-struct --open-gop --profile high --threads 1`,
  `--frames 30` (60 on fades), `--tff` on -i clips, on tile-chaos-p and field-frame-mix-i. `*422*` clips get
  `--output-csp i422 --profile high422`; 10-bit 4:2:0 gets `--profile high10`.
- Every 8-bit job has the md5-only 8-bit 4:2:2 interlaced cells ffm422-i LOWLAT / NORMAL.
- There are no sgfades clips here. K2 (weighted) uses fades-p / fades-i at 60 frames instead (timed); the other jobs'
  sgfades cells are dropped, and fades-p / fades-i 60-frame cells are md5-only where weightp was the reason.
- Null cells (zero calls of the changed code) are timed in the same rounds, marked `[null cell]`, excluded from the
  verdict, and must read ~0 % inside the A/A.
- Threaded cells (nwinfra thr, lapipe) run 4 threads on `CORES=12,14` only; they add `duration_time`. Core 3's and
  rack01's 4-cpu threaded numbers are not reproducible here.
- `report` prints the numbers; the lead applies the standing timing rules to call WIN / LOSS / MIXED. `time 9` again
  appends 9 more rounds. Liveness must show the arm's symbols (or counters) in every non-null cell before its timing counts.

## Queue

### 1. O: la2 (wip/x264-me2-la2)
- base 5db22450 (tip~2, kernels assembled, nothing dispatched), arm b81cae5e (tip~1, AVX2 dispatch of lowres_i_mbs,
  lowres_b_mbs, intra_satd_lowres_tf). The tip 0877c420 only adds avx512icl: same pointers as b81cae5e here.
- ```
  for p in build live md5; do bash la2/la2-ab.sh $p; done      # build window
  bash la2/la2-ab.sh time 9; bash la2/la2-ab.sh report
  ```
- Cells: LOWLAT / NORMAL on tile-chaos-p, field-frame-mix-i; fades-p NORMAL 60 (weightp: lowres_i_mbs pre-pass).
  md5 adds ffm422-i, fades-i NORMAL 60 and 10-bit `@10` cells (LA8 lookahead: lowres8's B path through satd_bi):
  tile-chaos-p, field-frame-mix-i, tc422p10-p, ffm422p10-i. Builds are `--bit-depth=all`. No zero-call cell
  (LOWLAT reaches intra_satd_lowres_tf through lowres_p_mbs).
- Expected: lowlat -0.1 to -0.3 %, normal about -1 to -2 % (B path moved out of C slicetype_mb_cost; not measured).
- Decides: merge of the AVX2 dispatch b81cae5e for Intel (0877c420 stays rack01's).
- Result (11-11): fades-p normal -1.44 % 9/9, tile-chaos-p lowlat -0.34 %, normal -0.22 %, ffm-i normal 0.00 %,
  **ffm-i lowlat +0.40 % 0/9 (insn -0.06 %)**: blocked; split below.

### 1a. O-split: la2split (wip/x264-me2-la2-split, all arms on base 5db22450)
- AB=a 5a47d2ef (lowres_i_mbs alone), AB=b d956198b (lowres_b_mbs alone), AB=c 4c000a1c (intra_satd_lowres_tf
  alone), AB=fix 0c47ef53 (tip: b81cae5e's dispatch on the fixed kernels: V/DC constants in registers, tf without a
  stack frame), AB=cfix (0c47ef53 with only the tf pointer dispatched, xe_patch), AB=fix1 9c531856 (v1, on request),
  AB=lay (5db22450 -> b81cae5e, both -falign-functions=64: code-placement control, diagnostic only).
- ```
  for ab in c fix a b; do for p in build live md5 prof layout; do AB=$ab bash la2split/la2split-ab.sh $p; done; done   # build window
  for ab in c fix a b; do AB=$ab bash la2split/la2split-ab.sh time 9; AB=$ab bash la2split/la2split-ab.sh report; done
  # only if c or fix still lose ffm-i lowlat: the same for AB=cfix and AB=lay
  ```
- Cells: ffm-i LOWLAT (decides), tile-chaos-p LOWLAT, ffm-i NORMAL, fades-p NORMAL 60; md5 adds ffm422-i, fades-i 60,
  ffm-i NORMAL@10, ffm422p10-i LOWLAT@10. `live` prints LA2_CNT (exact calls / MBs of each pointer, counter trees);
  `prof` sums 3 perf records per arm of ffm-i lowlat (top symbols, shares, largest moves); `layout` prints
  x264_8_pixel_init's size, the code shift of every function and the hot symbols' address mod 64.
- Liveness per call (instructions:u, base -> arm, both kernels branch-free, per LA2_CNT intra call): c -9, cfix -12,
  fix -12 plus the lowres_i_mbs / lowres_b_mbs part (sign only). ffm-i lowlat is expected to make ~236640 intra calls
  (29 P frames x 8160 lowres MBs inside lowres_p_mbs) and almost no lowres_i_mbs / lowres_b_mbs work.

### 2. AD: intrax9 (wip/x264-nw-intrax9, tip 76142791)
- AB=tip: base 5cdbdd1c (tip~1), arm 76142791 (8x8 fdec edge filter in the kernel + i4x4 MB driver dispatched).
  Splits if tip is mixed: AB=i4 (MB driver alone: fdec pointer removed), AB=i2 (fdec alone: MB driver pointer removed); earlier items AB=i1 (42c3f783 -> ad2e4638),
  AB=i3 (f6e9a53f -> 219b043c).
- ```
  for p in build live md5; do CORE=12 AB=tip bash intrax9/intrax9-ab.sh $p; done      # build window
  CORE=12 AB=tip bash intrax9/intrax9-ab.sh time 9      # timing block
  CORE=12 AB=tip bash intrax9/intrax9-ab.sh report
  ```
  (the same three lines with AB=i2 / i4 / i1 / i3 when needed)
- Counters: X9_CNT mb / fdec8x8 / recon4x4 (basecnt / armcnt). No zero-call cell expected (both modes analyse i4x4/i8x8).
- Expected: laptop -250 to -400 ticks per i4x4 MB with the driver, about -110 per sa8d_x9; item 4 may be neutral.
- Decides: keep items 2 + 4 on Intel AVX2 (all of 76142791), or drop the losing pointer (i2 / i4).

### 3. 10b-me (wip/x264-10b-me, tip 41f6b02e)
- base dfd3f236 (tip~1), arm 41f6b02e (10-bit AVX2 + BMI2 dispatch of the fused me_search_fpel_avx2). No --asm cap:
  this cpu is natively AVX2-only. (`CAP=1` mirrors .44 but is not a no-op: it drops Cache64 and AVXVNNI, see 10b-cabac.)
- ```
  for p in build live md5; do bash 10b-me/10b-me-ab.sh $p; done      # build window
  bash 10b-me/10b-me-ab.sh time 9      # timing block
  bash 10b-me/10b-me-ab.sh report
  ```
- Cells (10-bit builds): ffm422p10-i (--tff), tc422p10-p LOWLAT / NORMAL; tile-chaos-p, field-frame-mix-i at 10-bit
  LOWLAT / NORMAL; null ffm422p10-i lowdia (LOWLAT --me dia, zero fused calls). Bitrates are the cells' 20 Mbps
  (dot44.sh used 50 Mbps for 10-bit 4:2:2).
- Expected: laptop harness -2.6 % per search incl. subpel (23/24 cells); the encode share is not measured.
- Decides: keep 41f6b02e (10-bit AVX2 on Intel and Zen 1-3).

### 4. 10b-cabac (wip/x264-10b-cabac, tip 75947ac3)
- AB=avx2: base 1c4583b1 (tip~3, undispatched: ssse3_lzcnt rd, C 4:2:2 dc writer), arm 093a2715 (tip~2, avx2_bmi2 rd
  4x4, 8x8 rd, 4:2:2 dc writer at 10-bit). AB=port: base 093a2715, arm 093a2715 + RD4_AVX2_LEVELS_MIN 17 (no level pass
  in the 4x4 rd). tip~1 / tip change AVX-512 pointers only.
- ```
  for p in build live md5; do AB=avx2 bash 10b-cabac/10b-cabac-ab.sh $p; done      # build window
  AB=avx2 bash 10b-cabac/10b-cabac-ab.sh time 9      # timing block
  AB=avx2 bash 10b-cabac/10b-cabac-ab.sh report
  for p in build live md5; do AB=port bash 10b-cabac/10b-cabac-ab.sh $p; done      # build window
  AB=port bash 10b-cabac/10b-cabac-ab.sh time 9      # timing block
  AB=port bash 10b-cabac/10b-cabac-ab.sh report
  ```
- Cells as 10b-me (no dia); null cell tile-chaos-p LOWLAT (trellis 0, no RD, 4:2:0). Counters: CABLIVE pointer names
  and calls rd4 / rd8 / 422dc_writer.
- The .44 script's --asm cap is NOT a no-op on this cpu: x264_cpu_detect adds Cache64 and AVXVNNI, which the list
  lacks. AVXVNNI has no 10-bit reader, but Cache64 selects predict_8x8_ddl/ddr_ssse3_cache64 in the HIGH_BIT_DEPTH
  block of common/x86/predict-c.c, so the cap swaps two intra kernels. The scripts run uncapped (CAP=1 to mirror .44).
- Expected: laptop per call rd 4x4 1.0-1.7x, 8x8 rd 1.2-3.1x, 4:2:2 dc writer 2.0-2.3x vs the previous pointers.
- Decides: keep 093a2715 on Intel; AB=port decides whether the level pass stays in the avx2 4x4 rd (arm faster = drop it).

### 5. K: me2-fused (wip/x264-me2-fused, tip 4c404747)
- AB=k1: base 71cb23ec (026f9c51's parent; `K1BASE=42c3f783` for the report's base), arm 026f9c51 (8x16 square
  refine in shared windows, MF_SQ8, avx2). AB=k2: base fca9575c (tip~1), arm 4c404747 (weighted refs at subme >= 3 to
  the fused entry).
- ```
  for p in build live md5; do AB=k1 bash me2-fused/me2-fused-ab.sh $p; done      # build window
  AB=k1 bash me2-fused/me2-fused-ab.sh time 9      # timing block
  AB=k1 bash me2-fused/me2-fused-ab.sh report
  for p in build live md5; do AB=k2 bash me2-fused/me2-fused-ab.sh $p; done      # build window
  AB=k2 bash me2-fused/me2-fused-ab.sh time 9      # timing block
  AB=k2 bash me2-fused/me2-fused-ab.sh report
  ```
- k1: LOWLAT and NORMAL have no p8x8, so zero 8x16 searches: all four production cells are null cells. The decision
  cells are normalp8 (NORMAL with `--partitions p8x8,b8x8,i8x8,i4x4`) on tile-chaos-p / field-frame-mix-i;
  perf cannot split 8x16 inside me_search_fpel_avx2, so their instructions:u delta is the liveness witness.
- k2: fades-p / fades-i at 60 frames stand in for sgfades (timed). NORMAL on fades decides; every LOWLAT cell is null
  (subme 2 < 3). Liveness: the arm's x264_8_me_search_ref samples fall, me_search_fpel_avx2 rises.
- Expected: k1 about -4 % per 8x16 search, ~-0.05 % of a p8x8 encode, 0 in production; k2 -0.1 to -0.3 % on weightp content.
- Decides: k1 = keep MF_SQ8 on the avx2 entry (no production effect either way); k2 = merge the guard lift 4c404747.

### 6. Z: mbtree (wip/x264-nw-mbtree, tip 0b09bab8)
- AB=avx2: base 8f852830 (strip kernels assembled, undispatched), arm f017bec6 (strip_asm_avx2 dispatched; = 0b09bab8
  on AVX2-only). Optional AB=cstrip: arm = 8f852830 with the C strip dispatched.
- ```
  for p in build live md5; do AB=avx2 bash mbtree/mbtree-ab.sh $p; done      # build window
  AB=avx2 bash mbtree/mbtree-ab.sh time 9      # timing block
  AB=avx2 bash mbtree/mbtree-ab.sh report
  ```
- NORMAL decides; LOWLAT (zerolatency, no mbtree) is the null cell. Counters NWCNT (nwmbcnt.sh). md5 adds fades 60.
- Expected: strip_asm 1.5-2.5x per call vs today's avx2 wrapper (laptop); normal only.
- Decides: merge f017bec6 for Intel AVX2.

### 7. T: trprep (wip/x264-nw-trprep, tip 2534f770)
- AB=tip: base 40527133 (tip~1, all NULL), arm 2534f770 (AVX2 trellis prep + 4x4x4 post). AB=post8: base 2534f770,
  arm 2534f770 + post8-dispatch.patch (dequant_8x8_scan avx2).
- ```
  for p in build live md5; do AB=tip bash trprep/trprep-ab.sh $p; done      # build window
  AB=tip bash trprep/trprep-ab.sh time 9      # timing block
  AB=tip bash trprep/trprep-ab.sh report
  for p in build live md5; do AB=post8 bash trprep/trprep-ab.sh $p; done      # build window
  AB=post8 bash trprep/trprep-ab.sh time 9      # timing block
  AB=post8 bash trprep/trprep-ab.sh report
  ```
- Cells NORMAL, NORMAL7 (subme 7), LOWLAT (trellis 0: null cell). Counters TRCNT (trcnt.sh).
- Expected: one prep call replaces copy + quant + zigzag per block; one post call replaces scan + dequant + decimate per
  nonzero block; 8x8 post was a laptop loss/neutral.
- Decides: merge 2534f770 for Intel; post8 = whether dequant_8x8_scan is dispatched on Intel.

### 8. M: cacheload (wip/x264-nw-cacheload, tip ab419b5c)
- AB=c1: base 42c3f783, arm 312ea673 (per-slice table of ref pointer bases, C). AB=k: base 1720dcb3 (tip~1), arm
  ab419b5c (mb_fref_load avx2 dispatched).
- ```
  for p in build live md5; do AB=c1 bash cacheload/cacheload-ab.sh $p; done      # build window
  AB=c1 bash cacheload/cacheload-ab.sh time 9      # timing block
  AB=c1 bash cacheload/cacheload-ab.sh report
  AB=c1 bash cacheload/cacheload-ab.sh branches      # timing block
  for p in build live md5; do AB=k  bash cacheload/cacheload-ab.sh $p; done      # build window
  AB=k  bash cacheload/cacheload-ab.sh time 9      # timing block
  AB=k  bash cacheload/cacheload-ab.sh report
  ```
  (`branches` = perf stat cycles/instructions/branch-misses -r 3, base vs arm: a timing-block job)
- No zero-call cell (every MB). md5 adds fades-p / fades-i 60 frames (weighted p_fref_w).
- Expected: small; the kernel saves about 8 ticks per field B MB over the inline C; commit 1 inside a ~2.25 % symbol.
- Decides: merge 312ea673 (C table) and / or ab419b5c (avx2 kernel) for Intel.

### 9. R: nwinfra (wip/x264-nw-infra, tip 2464038e)
- AB=asm: base 8df5d016, arm 2464038e (hpel dual / copy_vc, lowres pad, expand_border_sides, hpel side pads dispatched).
  Per pointer if mixed: AB=hpel (8df5d016 -> a27a3925; -p cells null), lowres (a27a3925 -> 60e2dd6c), sides
  (60e2dd6c -> fbcb12be), hpelpad (fbcb12be -> 2464038e). AB=thr: base 42c3f783, arm 790c3e79 (threading items).
- ```
  for p in build live md5; do AB=asm bash nwinfra/nwinfra-ab.sh $p; done      # build window
  AB=asm bash nwinfra/nwinfra-ab.sh time 9      # timing block
  AB=asm bash nwinfra/nwinfra-ab.sh report
  for p in build md5; do AB=thr bash nwinfra/nwinfra-ab.sh $p; done      # build window
  AB=thr bash nwinfra/nwinfra-ab.sh nondet 20
  AB=thr bash nwinfra/nwinfra-ab.sh time 9      # timing block
  AB=thr bash nwinfra/nwinfra-ab.sh report
  ```
- Counters NWCNT (nwcnt.sh, on the whole series 2464038e). thr adds t4 / t4la4 cells on CORES=12,14 with duration_time.
- Expected: hpel side pads drop the RFO+WB of each filtered row's pad line (~0.84 MB per progressive ref frame, 1.7 MB
  MBAFF); single-encoder cycles effect small.
- Decides: merge the AVX2 dispatch commits for Intel (or the winning subset); thr = the threading items on a 2-cpu box.

### 10. L: avg2w16 (wip/x264-gap-avg2w16, tip 6454133a)
- AB=tip: base d7fe25e4 (tip~1), arm 6454133a (Intel table: VEX avg2 w8/w12/w16, get_ref in asm, mc_luma on it).
  AB=nomcl: same arm without the mc_luma switch.
- ```
  for p in build live md5; do AB=tip bash avg2w16/avg2w16-ab.sh $p; done      # build window
  AB=tip bash avg2w16/avg2w16-ab.sh time 9      # timing block
  AB=tip bash avg2w16/avg2w16-ab.sh report
  for p in build live md5; do AB=nomcl bash avg2w16/avg2w16-ab.sh $p; done      # build window
  AB=nomcl bash avg2w16/avg2w16-ab.sh time 9      # timing block
  AB=nomcl bash avg2w16/avg2w16-ab.sh report
  ```
- Counters AVG2_CNT. No zero-call cell.
- Expected: the cost is get_ref's wrapper (laptop C get_ref 16.2 ticks vs w16 kernel 9.3); mc_luma on the Intel table
  was slower on Zen 5 (hence nomcl).
- Decides: merge 6454133a for Intel, with or without the mc_luma switch.

### 11. AC: hpelfly (wip/x264-nw-hpelfly, tip e40733b2; rewritten 11-12, the B BI-cost stride fix e8bb50a5 before default-on)
- AB=series: base e8bb50a5 (HPEL_FLY default off), arm e40733b2 (on at 8-bit). AB=swap: base e40733b2 built with
  -DHPELFLY_SWAP=0, arm e40733b2 (the band-pointer swap of 33d409a1).
- ```
  for p in build live md5; do AB=series bash hpelfly/hpelfly-ab.sh $p; done      # build window
  AB=series bash hpelfly/hpelfly-ab.sh time 9      # timing block
  AB=series bash hpelfly/hpelfly-ab.sh report
  for p in build live md5; do AB=swap bash hpelfly/hpelfly-ab.sh $p; done      # build window
  AB=swap bash hpelfly/hpelfly-ab.sh time 9      # timing block
  AB=swap bash hpelfly/hpelfly-ab.sh report
  ```
- md5 adds t4, subme 1, slower, chroma-me 7 and esa subme 11 (10 frames) cells; counters = the HPELFLY_STATS line.
- Expected: -4.16 MB of hpel planes per reference frame (~2.1 MB/f normal, 4.2 MB/f lowlat); single-stream cycles may
  rise (interpolation on the fly).
- Decides: whether HPEL_FLY stays on by default at 8-bit on Intel (one-stream cost vs the bandwidth saving), and the swap.

### 12. U: lapipe (wip/x264-nw-lapipe, tip b1d57371)
- AB=grp: base 4e292d6a, arm b1d57371 (refactor + b-adapt + mbtree row-interleaved groups). Per commit: AB=refac
  (4e292d6a -> 10443289), badapt (10443289 -> 435424dd), mbtree (435424dd -> dc9122e0). AB=fpel: base b1d57371, arm
  271581f8 (test/x264-nw-lapipe-fpel-on; output-changing at LOWLAT).
- ```
  for p in build live md5 traffic; do AB=grp bash lapipe/lapipe-ab.sh $p; done      # build window
  AB=grp bash lapipe/lapipe-ab.sh nondet 20
  AB=grp bash lapipe/lapipe-ab.sh time 9      # timing block
  AB=grp bash lapipe/lapipe-ab.sh report
  for p in build md5 quality; do AB=fpel bash lapipe/lapipe-ab.sh $p; done      # build window
  AB=fpel bash lapipe/lapipe-ab.sh time 9      # timing block
  AB=fpel bash lapipe/lapipe-ab.sh report
  ```
- LOWLAT is the null cell for grp; t4 / t4la4 cells on CORES=12,14 with duration_time. Counter trees (grp):
  2cdb8175 / 0ea63421 with -DX264_LOWRES_TRAFFIC=1.
- Expected: b-adapt group ~0.9 MB/f, mbtree group ~0.8 MB/f of lowres reads saved; fpel ~5.6 MB/f at lowlat 1080.
- Decides: merge the group schedule (b1d57371) for Intel; fpel = whether lookahead_fpel may default on (quality + time).

### 13. J: a512only (wip/x264-gap-a512only, tip 86666108)
- KIND=oc: base c31b9ffc, arm ed88c7ab (optimize_chroma_2x4_dc avx2; Intel ran C). KIND=il: base 42d3c9c2, arm 752febdb
  (residual writer with inline last). KIND=cl8: base 2347fb9a, arm c31b9ffc (coeff_last8 avx2_lzcnt). KIND=pcd: base
  e3df3ae3, arm 42d3c9c2 (plane_copy_deinterleave avx2).
- ```
  for p in build live md5; do KIND=oc bash a512only/a512only-ab.sh $p; done      # build window; then the same three lines with KIND=il, cl8, pcd
  KIND=oc bash a512only/a512only-ab.sh time 9      # timing block
  KIND=oc bash a512only/a512only-ab.sh report
  ```
- oc / cl8 time the 8-bit 4:2:2 clips ffm422-i / tc422-p; their 4:2:0 cells are null. il / pcd time the 4:2:0 cells
  (pcd adds fades 60, where weightp chroma analysis runs). D5 intra_sad_x3_8x16c (subme <= 1 only): the checkasm bench
  that `build` prints decides it.
- Expected: oc 2.4-3x C per call; il's caller is 2.13 % self; cl8 ~1.5x on latency; pcd is rarely reached.
- Decides: keep each Intel AVX2 dispatch commit (D1-D4) or drop it.

### 14. NRB: nrbskip (wip/x264-nw-nrbskip, tip cb5b86c2; added 11-14)
- Core 3 Job Y proved it bitstream-identical in 39/39 cells (4:2:2 both depths, 10-bit, threads, slices, psnr/ssim),
  phase 1 on 100 % of non-ref-B MBs, plane bytes -47 %, mv/ref -58..-65 %. This is the Intel cycles verdict.
```
  for p in build live md5; do AB=full bash nrbskip/nrbskip-ab.sh $p; done   # build window
  AB=full bash nrbskip/nrbskip-ab.sh time 9                                  # timing block
  AB=full bash nrbskip/nrbskip-ab.sh report
```
- Lowlat has no B frames (phase 1 inert) but phase 2 runs there, so it is a decision cell for AB=full.
- If full loses or is mixed: AB=p1 and AB=p2 to split the phases. If a loss comes with FEWER instructions: AB=fulllay.

### 15. MBP: mbaffplanes (wip/x264-nw-mbaffplanes, c664d151 -> 2d0dbfac; added 11-14, after NRB)
- Core 3 Job AA: bit-exact (15/15 single-thread, threaded at CQP), aliasing live; costs 2.8-4.5x page faults
  (5900 major / 30 frames), cycles:k +12-17 % lowlat, F/H lose THP. Intel cycles verdict for the E-2400 1080i goal.
```
  for p in build live md5 faults; do AB=full bash mbaffplanes/mbaffplanes-ab.sh $p; done   # build window (faults: quiet box)
  FRAMES=120 AB=full bash mbaffplanes/mbaffplanes-ab.sh time 9                            # timing block
  FRAMES=120 AB=full bash mbaffplanes/mbaffplanes-ab.sh report
```
- Interlaced cells decide; tile-chaos-p normal / pan-fast-p lowlat (no field planes) are nulls. A loss with fewer
  instructions: AB=lay.
