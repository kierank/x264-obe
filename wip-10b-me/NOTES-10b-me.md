# wip/x264-10b-me notes (laptop agent, 2026-11-11)

Package `me`: 10-bit (HIGH_BIT_DEPTH) fused fpel search for Intel AVX2.

## Findings
- 10-bit AVX-512 dispatch (pixel.c HIGH_BIT_DEPTH AVX512 block): x264_me_search_fpel_avx512 = the OLD
  ME_SEARCH_FPEL macro (INIT_YMM avx512): C-ABI calls to fn->sad / sad_avg2 / x3_min / x4_min (sad16-a.asm
  avx2 uint16 kernels; avx512 x3/x4 pruned on Zen 4), predictor_clip_avx512, sq_min/hex_min/hex_search are
  NULL at 10-bit so it uses .x3/.x4 calls with FPEL_BIAS_V biases; subpel via fn->subpel =
  satd_subpel_search_*_avx2 (10-bit, BMI2), qpel satd_qpel_search_*_avx2.
- 10-bit AVX2 had an undispatched old ME_SEARCH_FPEL xmm entry ("slower than C on Zen 4"); replaced.
- No 10-bit sad_sq_min / hex_min / hex_search / predictor_clip at AVX2 (predictor_clip_avx2 is 8-bit only
  in pixel-a.asm though it is depth-independent). The new search needs none (all inline).
- refine_subpel C self time in the AVX2 profile goes with the fused path: it calls fn->subpel itself
  (qfenc = p_fenc at 10-bit). Weighted refs keep C refine_subpel (mbcmp_subpel_search_weight is zeroed in
  encoder.c) and keep C me_search_ref at subme >= 3 (same eligibility as 8-bit, me.c unchanged).

## Design (common/x86/me-64.asm, MH_* block, HIGH_BIT_DEPTH only)
- Self-contained copy of MF_SEARCH (own H_* frame, MH_* macros, mh_sq_* rodata) so that
  wip/x264-me2-fused (4c404747, which edits MF_* / F_* and deletes mf_sq_*) merges without textual or
  semantic conflict in the asm. Conflict point: tools/checkasm.c fns[3] -> fns[4] (me2-fused adds fn_wt[3]
  next to it; resolve by making all three [4]).
- uint16 SAD: psubw + pabsw, word accumulators (<= 16 rows x 1023), pmaddwd pw_1, unpck tree reduce (no
  phadd, so the same code is EVEX-clean).
- 16 wide: row = ymm; fenc rows resident at 16x8 (m8-15), loaded once per row at 16x16 (16 regs needed).
  8 wide: row pairs; fenc pairs resident (8x8 m12-15, 8x16 m8-15).
- 8x8 uses the same inline body (no 10-bit hex_search kernel).
- Square: one .x8 (8 accumulators, 3 row pointers + disp) where m0-m9 are free (avx2 16x16, 8x8; all
  avx512 sizes), else two .x4.
- avx512 entry me_search_fpel_inline_avx512: same code in EVEX, fenc in m16-31 (= ymm0-15) at every size
  incl. 16x16, vzeroupper at exit. Undispatched.

## Status at this commit
- Before the .x8 / avx512 fenc-in-ymm0-15 changes: checkasm8 + checkasm10 seed 1 OK; harness10 (C path vs
  arms b0/avx2/old512/inline512, smooth+random, 4 sizes, subme 2/4/7, with/without halfpel thresh)
  bit-exact OK. The .x8 / avx512 fenc-in-ymm0-15 changes are UNTESTED in this WIP commit.
- Mutation run (mut.sh) was in progress.
- Dispatch commit not yet made (plan: pixel.c 10-bit AVX2 block, if BMI2 && !_WIN32 ->
  x264_me_search_fpel_avx2, own commit at the tip).

## Scripts (wip-10b-me/)
build.sh/b1.sh build checkasm8/10 in WSL from the worktree; ck.sh checkasm seeds; hb.sh/h1.sh build+run
harness10 (base = origin/speed-next me-64.asm's 10-bit avx2 entry linked as fpel_b0_avx2); mut.sh/mut.pl/
mutlist.txt mutations; evex.sh EVEX scan + 8-bit me-64-8.o identity vs base.
