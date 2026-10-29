;*****************************************************************************
;* trellis-64.asm: x86_64 trellis quantization
;*****************************************************************************
;* Copyright (C) 2012-2014 x264 project
;*
;* Authors: Loren Merritt <lorenm@u.washington.edu>
;*
;* This program is free software; you can redistribute it and/or modify
;* it under the terms of the GNU General Public License as published by
;* the Free Software Foundation; either version 2 of the License, or
;* (at your option) any later version.
;*
;* This program is distributed in the hope that it will be useful,
;* but WITHOUT ANY WARRANTY; without even the implied warranty of
;* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;* GNU General Public License for more details.
;*
;* You should have received a copy of the GNU General Public License
;* along with this program; if not, write to the Free Software
;* Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02111, USA.
;*
;* This program is also available under a commercial proprietary license.
;* For more information, contact us at licensing@x264.com.
;*****************************************************************************

; This is a pretty straight-forward translation of the C code, except:
; * simd ssd and psy: 2x parallel, handling the 2 candidate values of abs_level.
; * simd trellis_coef0, ZERO_LEVEL_IDX, and the coef0 part of the main loop:
;   4x parallel, handling 4 node_ctxs of the same coef (even if some of those
;   nodes are invalid).
; * Interprocedural register allocation. Eliminates argument-passing overhead
;   to trellis_coef* subroutines. Also reduces codesize.

; Optimizations that I tried, and rejected because they were not faster:
; * Separate loops for node_ctx [4..7] or smaller subsets of [0..3].
;   Costs too much icache compared to the negligible speedup.
; * There are only 21 possible sets of live node_ctxs; we could keep track of
;   exactly which set we're in and feed that (along with abs_level) into a jump
;   table instead of the switch to select a trellis_coef subroutine. This would
;   eliminate all branches about which node_ctxs are live, but costs either a
;   bunch of icache or a bunch of call/ret, and the jump table itself is
;   unpredictable.
; * Separate versions of trellis_coef* depending on whether we're doing the 1st
;   or the 2nd of the two abs_level candidates. This would eliminate some
;   branches about if(score is better).
; * Special case more values of coef. I had a coef2 at some intermediate point
;   in the optimization process, but it didn't end up worthwhile in conjunction
;   with all the other optimizations.
; * Unroll or simd writeback. I don't know why this didn't help.

%include "x86inc.asm"
%include "x86util.asm"

SECTION_RODATA 64

pd_8: times 4 dd 8
pd_m16: times 4 dd -16
pd_0123: dd 0, 1, 2, 3
pd_4567: dd 4, 5, 6, 7
sq_1: dq 1, 0
pq_128: times 2 dq 128
pq_ffffffff: times 2 dq 0xffffffff

; avx512icl
ALIGN 64
; node payload bytes for vpermi2b( payload, level_state ): per node
; level1 state x2, levelgt1 state x2, level1 state x2, levelgt1 state, 0
tr_idx:    db 65,65,69,69,65,65,69,127, 66,66,69,69,66,66,69,127
           db 67,67,69,69,67,67,69,127, 25,25,69,69,25,25,69,127
           db 32,32,70,70,32,32,70,127, 40,40,71,71,40,40,71,127
           db 48,48,50,50,48,48,50,127, 56,56,59,59,56,56,59,127
tr_idx422: db 65,65,69,69,65,65,69,127, 66,66,69,69,66,66,69,127
           db 67,67,69,69,67,67,69,127, 25,25,69,69,25,25,69,127
           db 32,32,70,70,32,32,70,127, 40,40,71,71,40,40,71,127
           db 48,48,50,50,48,48,50,127, 56,56,58,58,56,56,58,127
; vpermb( level_state ): ctx 0,4,8,9 into node 2 / nodes 0-3
tr_pk1:    times 16 db 63
           db 0,4,8,9,63,63,63,63
           times 40 db 63
tr_pkn:    times 4 db 0,4,8,9,63,63,63,63
           times 32 db 63
tr_m11:    dq -1, -1, 0xffffffff00000000, -1, -1, -1, -1, -1
tr_m1n:    times 4 dq 0xffffffff00000000
           times 4 dq -1
tr_mt:     dq 0, 0, 0, 0xff00, 0xff, 0xff, 0xff, 0xff
tr_mtu:    dq 0, 0, 0, 0, 0, 0, 0xff0000, 0xff000000
tr_mtu422: dq 0, 0, 0, 0, 0, 0, 0xff0000, 0xff0000
tr_w3lt:   times 8 dw 0, 0, 0, 64
tr_w3ge:   times 8 dw -1, -1, -1, 64
tr_iota:   dq 0, 1, 2, 3, 4, 5, 6, 7
tr_inv:    dq -16, -15, -14, -13, -12, -11, -10, -9
tr_iotahi1: dq 1<<32, 2<<32, 3<<32, 4<<32, 5<<32, 6<<32, 7<<32, 8<<32
; vpermi2q( keys, -1 ): abs_level 1, abs_level > 1
tr_p1a:    dq 8, 0, 1, 2, 4, 5, 6, 7
tr_p1b:    dq 8, 8, 8, 3, 8, 8, 8, 8
tr_pn1:    dq 1, 8, 3, 8, 8, 8, 7, 8
tr_pn2:    dq 8, 8, 8, 8, 0, 4, 5, 6
tr_pn3:    dq 8, 8, 8, 8, 2, 8, 8, 8
; x264_cabac_entropy[s^b] low/high bytes, x264_cabac_transition[s][b]
tr_e0lo:
    db 7,189,7,169,8,150,8,131,9,112,9,92,10,73,10,54
    db 11,35,11,15,12,252,12,233,13,214,14,194,15,175,15,156
    db 16,137,17,117,18,98,19,79,20,60,21,40,22,21,24,2
    db 25,239,26,219,28,200,29,181,31,162,33,142,35,123,37,104
    db 39,85,41,65,43,46,46,27,48,8,51,244,54,225,57,206
    db 60,187,64,167,68,148,72,129,76,110,80,90,85,71,90,52
    db 96,33,102,13,108,250,115,231,122,212,130,192,139,173,148,154
    db 157,135,168,115,180,96,192,77,206,58,221,39,238,19,0,0
tr_e0hi:
    db 0,5,0,5,0,5,0,5,0,5,0,5,0,5,0,5
    db 0,5,0,5,0,4,0,4,0,4,0,4,0,4,0,4
    db 0,4,0,4,0,4,0,4,0,4,0,4,0,4,0,4
    db 0,3,0,3,0,3,0,3,0,3,0,3,0,3,0,3
    db 0,3,0,3,0,3,0,3,0,3,0,2,0,2,0,2
    db 0,2,0,2,0,2,0,2,0,2,0,2,0,2,0,2
    db 0,2,0,2,0,1,0,1,0,1,0,1,0,1,0,1
    db 0,1,0,1,0,1,0,1,0,1,0,1,0,1,1,1
tr_e1lo:
    db 189,7,169,7,150,8,131,8,112,9,92,9,73,10,54,10
    db 35,11,15,11,252,12,233,12,214,13,194,14,175,15,156,15
    db 137,16,117,17,98,18,79,19,60,20,40,21,21,22,2,24
    db 239,25,219,26,200,28,181,29,162,31,142,33,123,35,104,37
    db 85,39,65,41,46,43,27,46,8,48,244,51,225,54,206,57
    db 187,60,167,64,148,68,129,72,110,76,90,80,71,85,52,90
    db 33,96,13,102,250,108,231,115,212,122,192,130,173,139,154,148
    db 135,157,115,168,96,180,77,192,58,206,39,221,19,238,0,0
tr_e1hi:
    db 5,0,5,0,5,0,5,0,5,0,5,0,5,0,5,0
    db 5,0,5,0,4,0,4,0,4,0,4,0,4,0,4,0
    db 4,0,4,0,4,0,4,0,4,0,4,0,4,0,4,0
    db 3,0,3,0,3,0,3,0,3,0,3,0,3,0,3,0
    db 3,0,3,0,3,0,3,0,3,0,2,0,2,0,2,0
    db 2,0,2,0,2,0,2,0,2,0,2,0,2,0,2,0
    db 2,0,2,0,1,0,1,0,1,0,1,0,1,0,1,0
    db 1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,1
tr_t0:
    db 0,1,2,51,2,51,4,53,6,53,8,53,10,55,12,55
    db 14,55,16,57,18,57,20,57,22,59,24,59,26,61,28,61
    db 30,61,32,63,34,63,36,65,38,67,40,67,42,67,44,69
    db 46,69,48,71,50,73,52,73,54,75,56,75,58,77,60,79
    db 62,79,64,81,66,83,68,83,70,85,72,85,74,89,76,89
    db 78,91,80,91,82,95,84,95,86,97,88,97,90,101,92,101
    db 94,103,96,105,98,105,100,109,102,109,104,111,106,113,108,115
    db 110,117,112,119,114,119,116,123,118,123,120,125,122,127,124,126
tr_t1:
    db 0,1,50,3,50,3,52,5,52,7,52,9,54,11,54,13
    db 54,15,56,17,56,19,56,21,58,23,58,25,60,27,60,29
    db 60,31,62,33,62,35,64,37,66,39,66,41,66,43,68,45
    db 68,47,70,49,72,51,72,53,74,55,74,57,76,59,78,61
    db 78,63,80,65,82,67,82,69,84,71,84,73,88,75,88,77
    db 90,79,90,81,94,83,94,85,96,87,96,89,100,91,100,93
    db 102,95,104,97,104,99,108,101,108,103,110,105,112,107,114,109
    db 116,111,118,113,118,115,122,117,122,119,124,121,126,123,127,125
tr_b4:     dq 0x000000ff00000000
tr_kb5:    dq 0x2020202020202020
tr_abs1:   dq 1<<48
tr_lomask: dq 0xffffffff
tr_m16:    dq -16
tr_8hi:    dq 8<<32
tr_top:    dq 1<<63
tr_pw1:    dd 0x00010001
tr_q7:     dq 7
; vpermi2b( entropy lo, entropy hi ) of 8 positions to qwords
tr_qidx:
%assign tr_j 0
%rep 8
    db tr_j, 64+tr_j, 0, 0, 0, 0, 0, 0
    %assign tr_j tr_j+1
%endrep
%undef tr_j

; trellis_wrap: 4x4 zigzag, frame then field. 8-bit: vpshufb of the low / high
; 8 words of the block, in both lanes. 10-bit: vpermd, bit 3 picks the half.
ALIGN 32
tw_scan4:  db 0,1,8,9,2,3,4,5,10,11,-1,-1,-1,-1,-1,-1,12,13,6,7,14,15,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1
           db -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,0,1,8,9,2,3,-1,-1,-1,-1,-1,-1,4,5,10,11,12,13,6,7,14,15
           db 0,1,2,3,8,9,4,5,6,7,10,11,12,13,14,15,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1
           db -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
tw_zz4:    dd 0,4,1,2,5,8,12,9,6,3,7,10,13,14,11,15
           dd 0,1,4,2,3,5,6,7,8,9,10,11,12,13,14,15
tw_zz2x4d: dd 0,2,1,4,6,3,5,7
tw_nodcd:  dd 0,-1,-1,-1,-1,-1,-1,-1
tw_nodcw:  dw 0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1
tw_zz2x4w: db 0,1,4,5,2,3,8,9,12,13,6,7,10,11,14,15
tw_acmask: dq 0xfffefffefffefffe

; trellis_wrap avx512: 4x4 zigzag of 2 blocks for vpermw, frame then field
ALIGN 64
tw512_zz4w: dw 0,4,1,2,5,8,12,9,6,3,7,10,13,14,11,15,16,20,17,18,21,24,28,25,22,19,23,26,29,30,27,31
            dw 0,1,4,2,3,5,6,7,8,9,10,11,12,13,14,15,16,17,20,18,19,21,22,23,24,25,26,27,28,29,30,31
; 8x8 zigzag, frame then field: vpermi2w (8-bit); vpermi2d of coefs 0-31 and
; 32-63, merged by the bit 5 masks of tw512_zz8k (10-bit)
%if HIGH_BIT_DEPTH
    %define TW_DX dd
%else
    %define TW_DX dw
%endif
tw512_zz8:  TW_DX  0, 8, 1, 2, 9,16,24,17,10, 3, 4,11,18,25,32,40,33,26,19,12, 5, 6,13,20,27,34,41,48,56,49,42,35
            TW_DX 28,21,14, 7,15,22,29,36,43,50,57,58,51,44,37,30,23,31,38,45,52,59,60,53,46,39,47,54,61,62,55,63
            TW_DX  0, 1, 2, 8, 9, 3, 4,10,16,11, 5, 6, 7,12,17,24,18,13,14,15,19,25,32,26,20,21,22,23,27,33,40,34
            TW_DX 28,29,30,31,35,41,48,42,36,37,38,39,43,49,50,44,45,46,47,51,56,57,52,53,54,55,58,59,60,61,62,63
; ac positions of a zmm
tw512_nodc: TW_DX 0
    times 64/SIZEOF_DCTCOEF-1 TW_DX -1
%undef TW_DX
tw512_zz8k: dw 0xc000,0xfe01,0x7f80,0xfffc,0x0000,0xe040,0xfff0,0xffff

cextern_common cabac_entropy
cextern_common cabac_transition
cextern cabac_size_unary
cextern cabac_transition_unary
cextern deinterleave_shufd
cextern pw_1
cextern pw_m2
cextern_common dct4_weight_tab
cextern_common dct8_weight_tab
cextern_common dct4_weight2_tab
cextern_common dct8_weight2_tab
cextern_common last_coeff_flag_offset_8x8
cextern_common significant_coeff_flag_offset_8x8
cextern_common coeff_flag_offset_chroma_422_dc

SECTION .text

%define TRELLIS_SCORE_BIAS 1<<60
%define SIZEOF_NODE 16
%define CABAC_SIZE_BITS 8
%define LAMBDA_BITS 4

%macro SQUARE 2 ; dst, tmp
    ; could use pmuldq here, to eliminate the abs. but that would involve
    ; templating a sse4 version of all of trellis, for negligible speedup.
%if cpuflag(ssse3)
    pabsd   m%1, m%1
    pmuludq m%1, m%1
%elif HIGH_BIT_DEPTH
    ABSD    m%2, m%1
    SWAP     %1, %2
    pmuludq m%1, m%1
%else
    pmuludq m%1, m%1
    pand    m%1, [pq_ffffffff]
%endif
%endmacro

%macro LOAD_DUP 2 ; dst, src
%if cpuflag(ssse3)
    movddup    %1, %2
%else
    movd       %1, %2
    punpcklqdq %1, %1
%endif
%endmacro

; xmm8 = nonzero quant_coefs[i], b_ac <= i <= last_nnz, as a bit mask
%macro NZ_MASK 0
    mov       r6, quant_coefsm
%if num_coefs == 64
%if HIGH_BIT_DEPTH
    vmovdqu   ymm1, [r6+  0]
    vpackssdw ymm1, ymm1, [r6+ 32]
    vmovdqu   ymm2, [r6+ 64]
    vpackssdw ymm2, ymm2, [r6+ 96]
    vmovdqu   ymm3, [r6+128]
    vpackssdw ymm3, ymm3, [r6+160]
    vmovdqu   ymm4, [r6+192]
    vpackssdw ymm4, ymm4, [r6+224]
    vpacksswb ymm1, ymm1, ymm2
    vpacksswb ymm3, ymm3, ymm4
    vmovdqu   ymm0, [deinterleave_shufd]
    vpermd    ymm1, ymm0, ymm1
    vpermd    ymm3, ymm0, ymm3
%else
    vmovdqu   ymm1, [r6+ 0]
    vpacksswb ymm1, ymm1, [r6+32]
    vmovdqu   ymm3, [r6+64]
    vpacksswb ymm3, ymm3, [r6+96]
    vpermq    ymm1, ymm1, q3120
    vpermq    ymm3, ymm3, q3120
%endif
    vpxor     xmm0, xmm0, xmm0
    vpcmpeqb  ymm1, ymm1, ymm0
    vpcmpeqb  ymm3, ymm3, ymm0
    vpmovmskb r6d, ymm1
    vpmovmskb r10d, ymm3
    vzeroupper
    shl       r10, 32
    or        r6, r10
%else
    pxor      m0, m0
%if HIGH_BIT_DEPTH
    movu      m1, [r6+ 0]
    packssdw  m1, [r6+16]
%if num_coefs == 16
    movu      m2, [r6+32]
    packssdw  m2, [r6+48]
    packsswb  m1, m2
%else
    packsswb  m1, m0
%endif
%else
    movu      m1, [r6]
%if num_coefs == 16
    packsswb  m1, [r6+16]
%else
    packsswb  m1, m0
%endif
%endif
    pcmpeqb   m1, m0
    pmovmskb  r6d, m1
%endif
    not       r6
    xor      r10d, r10d
    bts       r10, iiq
    lea       r10, [r10*2-1]
    and       r6, r10
%if num_coefs == 16 && dc == 0
    mov      r10d, b_acm
    not       r10
    and       r6, r10
%endif
    movq      m8, r6
%endmacro

;-----------------------------------------------------------------------------
; int trellis_cabac_4x4_psy(
;     const int *unquant_mf, const uint8_t *zigzag, int lambda2,
;     int last_nnz, dctcoef *orig_coefs, dctcoef *quant_coefs, dctcoef *dct,
;     uint8_t *cabac_state_sig, uint8_t *cabac_state_last,
;     uint64_t level_state0, uint16_t level_state1,
;     int b_ac, dctcoef *fenc_dct, int psy_trellis )
;-----------------------------------------------------------------------------
%macro TRELLIS 4
%define num_coefs %2
%define dc %3
%define psy %4
cglobal %1, 4,15,9
    mov r2d, r2d ; int args, used as 64-bit
    mov r3d, r3d
    %assign level_tree_size 64*8*2*4 ; could depend on num_coefs, but nonuniform stack size would prevent accessing args from trellis_coef*
    %assign pad 96 + level_tree_size + 16*SIZEOF_NODE + 16-gprsize-(stack_offset&15)
    SUB  rsp, pad
    DEFINE_ARGS unquant_mf, zigzag, lambda2, ii, orig_coefs, quant_coefs, dct, cabac_state_sig, cabac_state_last
%if WIN64
    %define level_statem rsp+stack_offset+80 ; r9m, except that we need to index into it (and r10m) as an array
%else
    %define level_statem rsp+stack_offset+32
%endif
    %define b_acm r11m ; 4x4 only
    %define b_interlacedm r11m ; 8x8 only
    %define i_coefsm1 r11m ; dc only
    %define fenc_dctm r12m
    %define psy_trellism r13m
%if num_coefs == 64
    shl dword b_interlacedm, 6
    %define dct_weight1_tab dct8_weight_tab
    %define dct_weight2_tab dct8_weight2_tab
%else
    %define dct_weight1_tab dct4_weight_tab
    %define dct_weight2_tab dct4_weight2_tab
%endif

    %define stack rsp
    %define last_nnzm [stack+0]
    %define zigzagm   [stack+8]
    mov     last_nnzm, iid
    mov     zigzagm,   zigzagq
%if WIN64 == 0
    %define orig_coefsm  [stack+16]
    %define quant_coefsm [stack+24]
    mov     orig_coefsm,  orig_coefsq
    mov     quant_coefsm, quant_coefsq
%endif
%if cpuflag(avx2)
    NZ_MASK
%endif
    %define unquant_mfm   [stack+32]
    %define levelgt1_ctxm [stack+40]
    %define ssd            stack+48
    %define cost_siglast   stack+80
    %define level_tree     stack+96

    ; trellis_node_t is layed out differently than C.
    ; struct-of-arrays rather than array-of-structs, for simd.
    %define nodes_curq r7
    %define nodes_prevq r8
    %define node_score(x) x*8
    %define node_level_idx(x) 64+x*4
    %define node_cabac_state(x) 96+x*4
    lea nodes_curq, [level_tree + level_tree_size]
    lea nodes_prevq, [nodes_curq + 8*SIZEOF_NODE]
    mov        r6, TRELLIS_SCORE_BIAS
    mov       [nodes_curq + node_score(0)], r6
    mov dword [nodes_curq + node_level_idx(0)], 0
    movd      mm0, [level_statem + 0]
    punpcklbw mm0, [level_statem + 4]
    punpcklwd mm0, [level_statem + 8]
    %define level_state_packed mm0 ; version for copying into node.cabac_state
    pcmpeqb    m7, m7 ; TRELLIS_SCORE_MAX
    movq [nodes_curq + node_score(1)], m7
    mova [nodes_curq + node_score(2)], m7

    %define levels_usedq r4
    %define levels_usedd r4d
    mov dword [level_tree], 0
    mov       levels_usedd, 1

    %define abs_levelq r9
    %define abs_leveld r9d
    %define abs_coefq r14
    %define zigzagiq r5
    %define zigzagid r5d

%if num_coefs == 8
    mov dword levelgt1_ctxm, 8
%else
    mov dword levelgt1_ctxm, 9
%endif
%if psy
    LOAD_DUP m6, psy_trellism
    %define psy_trellis m6
%elif dc
    LOAD_DUP   m6, [unquant_mfq]
    paddd      m6, m6
    %define unquant_mf m6
%endif
%ifdef PIC
%if dc == 0
    mov unquant_mfm, unquant_mfq
%endif
    ; Keep a single offset register to PICify all global constants.
    ; They're all relative to "beginning of this asm file's .text section",
    ; even tables that aren't in this file.
    ; (Any address in .text would work, this one was just convenient.)
    lea r0, [$$]
    %define GLOBAL +r0-$$
%else
    %define GLOBAL
%endif

    TRELLIS_LOOP 0 ; node_ctx 0..3
    TRELLIS_LOOP 1 ; node_ctx 1..7

.writeback:
    ; int level = bnode->level_idx;
    ; for( int i = b_ac; i <= last_nnz; i++ )
    ;     dct[zigzag[i]] = SIGN(level_tree[level].abs_level, orig_coefs[zigzag[i]]);
    ;     level = level_tree[level].next;
    %define dctq r10
%if cpuflag(avx2)
    ; only nonzero coefs have levels, the others are already 0
    mov    r0d, [nodes_curq + node_level_idx(0) + rax*4]
    movq   r6, m8
.writeback_loop:
    bsf    r3, r6
    movzx  r2d, byte [zigzagq + r3]
%else
    mov    iid, last_nnzm
    add zigzagq, iiq
    neg    iiq
%if num_coefs == 16 && dc == 0
    mov    r2d, b_acm
    add    iiq, r2
%endif
    mov    r0d, [nodes_curq + node_level_idx(0) + rax*4]
.writeback_loop:
    movzx   r2, byte [zigzagq + iiq]
%endif
%if cpuflag(ssse3)
    movd    m0, [level_tree + r0*4]
    movzx   r0, word [level_tree + r0*4]
    psrld   m0, 16
    movd    m1, [dctq + r2*SIZEOF_DCTCOEF]
%if HIGH_BIT_DEPTH
    psignd  m0, m1
    movd [dctq + r2*SIZEOF_DCTCOEF], m0
%else
    psignw  m0, m1
    movd   r4d, m0
    mov  [dctq + r2*SIZEOF_DCTCOEF], r4w
%endif
%else
    mov    r5d, [level_tree + r0*4]
%if HIGH_BIT_DEPTH
    mov    r4d, dword [dctq + r2*SIZEOF_DCTCOEF]
%else
    movsx  r4d, word [dctq + r2*SIZEOF_DCTCOEF]
%endif
    movzx  r0d, r5w
    sar    r4d, 31
    shr    r5d, 16
    xor    r5d, r4d
    sub    r5d, r4d
%if HIGH_BIT_DEPTH
    mov  [dctq + r2*SIZEOF_DCTCOEF], r5d
%else
    mov  [dctq + r2*SIZEOF_DCTCOEF], r5w
%endif
%endif
%if cpuflag(avx2)
    lea    r3, [r6-1]
    and    r6, r3
    jnz .writeback_loop
%else
    inc    iiq
    jle .writeback_loop
%endif

    mov eax, 1
.return:
    ADD rsp, pad
    RET

%if num_coefs == 16 && dc == 0
.return_zero:
    pxor       m0, m0
    mova [r10+ 0], m0
    mova [r10+16], m0
%if HIGH_BIT_DEPTH
    mova [r10+32], m0
    mova [r10+48], m0
%endif
    jmp .return
%endif
%endmacro ; TRELLIS



%macro TRELLIS_LOOP 1 ; ctx_hi
.i_loop%1:
    ; if( !quant_coefs[i] )
    mov   r6, quant_coefsm
%if HIGH_BIT_DEPTH
    mov   abs_leveld, dword [r6 + iiq*SIZEOF_DCTCOEF]
%else
    movsx abs_leveld, word [r6 + iiq*SIZEOF_DCTCOEF]
%endif

    ; int sigindex  = num_coefs == 64 ? significant_coeff_flag_offset_8x8[b_interlaced][i] :
    ;                 num_coefs == 8  ? coeff_flag_offset_chroma_422_dc[i] : i;
    mov    r10, cabac_state_sigm
%if num_coefs == 64
    mov    r6d, b_interlacedm
%ifdef PIC
    add    r6d, iid
    movzx  r6d, byte [significant_coeff_flag_offset_8x8 + r6 GLOBAL]
%else
    movzx  r6d, byte [significant_coeff_flag_offset_8x8 + r6 + iiq]
%endif
    movzx  r10, byte [r10 + r6]
%elif num_coefs == 8
    movzx  r13, byte [coeff_flag_offset_chroma_422_dc + iiq GLOBAL]
    movzx  r10, byte [r10 + r13]
%else
    movzx  r10, byte [r10 + iiq]
%endif

%if notcpuflag(avx2) ; avx2 visits only the nonzero coefs
    test  abs_leveld, abs_leveld
    jnz %%.nonzero_quant_coef

%if %1 == 0
    ; int cost_sig0 = x264_cabac_size_decision_noup2( &cabac_state_sig[sigindex], 0 )
    ;               * (uint64_t)lambda2 >> ( CABAC_SIZE_BITS - LAMBDA_BITS );
    ; nodes_cur[0].score -= cost_sig0;
    movzx  r10, word [cabac_entropy + r10*2 GLOBAL]
    imul   r10, lambda2q
    shr    r10, CABAC_SIZE_BITS - LAMBDA_BITS
    sub   [nodes_curq + node_score(0)], r10
%endif
    ZERO_LEVEL_IDX %1, cur
    jmp .i_continue%1
%endif

%%.nonzero_quant_coef:
    ; int sign_coef = orig_coefs[zigzag[i]];
    ; int abs_coef = abs( sign_coef );
    ; int q = abs( quant_coefs[i] );
    movzx   zigzagid, byte [zigzagq+iiq]
    movd    m0, abs_leveld
    mov     r6, orig_coefsm
%if HIGH_BIT_DEPTH
    LOAD_DUP m1, [r6 + zigzagiq*SIZEOF_DCTCOEF]
%else
    LOAD_DUP m1, [r6 + zigzagiq*SIZEOF_DCTCOEF - 2]
    psrad    m1, 16     ; sign_coef
%endif
    punpcklqdq m0, m0 ; quant_coef
%if cpuflag(ssse3)
    pabsd   m0, m0
    pabsd   m2, m1 ; abs_coef
%else
    pxor    m8, m8
    pcmpgtd m8, m1 ; sign_mask
    pxor    m0, m8
    pxor    m2, m1, m8
    psubd   m0, m8
    psubd   m2, m8
%endif
    psubd   m0, [sq_1] ; abs_level
    movd  abs_leveld, m0

    xchg  nodes_curq, nodes_prevq

    ; if( i < num_coefs-1 )
    ;     int lastindex = num_coefs == 64 ? last_coeff_flag_offset_8x8[i] : i;
    ;                     num_coefs == 8  ? coeff_flag_offset_chroma_422_dc[i] : i
    ;     cost_siglast[0] = x264_cabac_size_decision_noup2( &cabac_state_sig[sigindex], 0 );
    ;     cost_sig1       = x264_cabac_size_decision_noup2( &cabac_state_sig[sigindex], 1 );
    ;     cost_siglast[1] = x264_cabac_size_decision_noup2( &cabac_state_last[lastindex], 0 ) + cost_sig1;
    ;     cost_siglast[2] = x264_cabac_size_decision_noup2( &cabac_state_last[lastindex], 1 ) + cost_sig1;
%if %1 == 0
%if dc && num_coefs != 8
    cmp    iid, i_coefsm1
%else
    cmp    iid, num_coefs-1
%endif
    je %%.zero_siglast
%endif
    movzx  r11, word [cabac_entropy + r10*2 GLOBAL]
    xor    r10, 1
    movzx  r12, word [cabac_entropy + r10*2 GLOBAL]
    mov   [cost_siglast+0], r11d
    mov    r10, cabac_state_lastm
%if num_coefs == 64
    movzx  r6d, byte [last_coeff_flag_offset_8x8 + iiq GLOBAL]
    movzx  r10, byte [r10 + r6]
%elif num_coefs == 8
    movzx  r10, byte [r10 + r13]
%else
    movzx  r10, byte [r10 + iiq]
%endif
    movzx  r11, word [cabac_entropy + r10*2 GLOBAL]
    add    r11, r12
    mov   [cost_siglast+4], r11d
%if %1 == 0
    xor    r10, 1
    movzx  r10, word [cabac_entropy + r10*2 GLOBAL]
    add    r10, r12
    mov   [cost_siglast+8], r10d
%endif
%%.skip_siglast:

    ; int unquant_abs_level = ((unquant_mf[zigzag[i]] * abs_level + 128) >> 8);
    ; int d = abs_coef - unquant_abs_level;
    ; uint64_t ssd = (int64_t)d*d * coef_weight[i];
%if dc
    pmuludq m0, unquant_mf
%else
%ifdef PIC
    mov    r10, unquant_mfm
    LOAD_DUP m3, [r10 + zigzagiq*4]
%else
    LOAD_DUP m3, [unquant_mfq + zigzagiq*4]
%endif
    pmuludq m0, m3
%endif
    paddd   m0, [pq_128]
    psrld   m0, 8 ; unquant_abs_level
%if psy || dc == 0
    mova    m4, m0
%endif
    psubd   m0, m2
    SQUARE   0, 3
%if dc
    psllq   m0, 8
%else
    LOAD_DUP m5, [dct_weight2_tab + zigzagiq*4 GLOBAL]
    pmuludq m0, m5
%endif

%if psy
    test   iid, iid
    jz %%.dc_rounding
    ; int predicted_coef = fenc_dct[zigzag[i]] - sign_coef
    ; int psy_value = abs(unquant_abs_level + SIGN(predicted_coef, sign_coef));
    ; int psy_weight = dct_weight_tab[zigzag[i]] * h->mb.i_psy_trellis;
    ; ssd1[k] -= psy_weight * psy_value;
    mov     r6, fenc_dctm
%if HIGH_BIT_DEPTH
    LOAD_DUP m3, [r6 + zigzagiq*SIZEOF_DCTCOEF]
%else
    LOAD_DUP m3, [r6 + zigzagiq*SIZEOF_DCTCOEF - 2]
    psrad   m3, 16 ; orig_coef
%endif
%if cpuflag(ssse3)
    psignd  m4, m1 ; SIGN(unquant_abs_level, sign_coef)
%else
    PSIGN d, m4, m8
%endif
    psubd   m3, m1 ; predicted_coef
    paddd   m4, m3
%if cpuflag(ssse3)
    pabsd   m4, m4
%else
    ABSD    m3, m4
    SWAP     4, 3
%endif
    LOAD_DUP m1, [dct_weight1_tab + zigzagiq*4 GLOBAL]
    pmuludq m1, psy_trellis
    pmuludq m4, m1
    psubq   m0, m4
%if %1
%%.dc_rounding:
%endif
%endif
%if %1 == 0
    mova [ssd], m0
%endif

%if dc == 0 && %1 == 0
    test   iid, iid
    jnz %%.skip_dc_rounding
%%.dc_rounding:
    ; Optimize rounding for DC coefficients in DC-only luma 4x4/8x8 blocks.
    ; int d = abs_coef - ((unquant_abs_level + (sign_coef>>31) + 8)&~15);
    ; uint64_t ssd = (int64_t)d*d * coef_weight[i];
    psrad   m1, 31 ; sign_coef>>31
    paddd   m4, [pd_8]
    paddd   m4, m1
    pand    m4, [pd_m16] ; (unquant_abs_level + (sign_coef>>31) + 8)&~15
    psubd   m4, m2 ; d
    SQUARE   4, 3
    pmuludq m4, m5
    mova [ssd], m4
%%.skip_dc_rounding:
%endif
    mova [ssd+16], m0

    %assign stack_offset_bak stack_offset
    cmp abs_leveld, 1
    jl %%.switch_coef0
%if %1 == 0
    mov    r10, [ssd] ; trellis_coef* args
%endif
    movq   r12, m0
    ; for( int j = 0; j < 8; j++ )
    ;     nodes_cur[j].score = TRELLIS_SCORE_MAX;
%if cpuflag(ssse3)
    mova [nodes_curq + node_score(0)], m7
    mova [nodes_curq + node_score(2)], m7
%else ; avoid store-forwarding stalls on k8/k10
%if %1 == 0
    movq [nodes_curq + node_score(0)], m7
%endif
    movq [nodes_curq + node_score(1)], m7
    movq [nodes_curq + node_score(2)], m7
    movq [nodes_curq + node_score(3)], m7
%endif
    mova [nodes_curq + node_score(4)], m7
    mova [nodes_curq + node_score(6)], m7
    je %%.switch_coef1
%%.switch_coefn:
    call trellis_coefn.entry%1
    call trellis_coefn.entry%1b
    jmp .i_continue1
%%.switch_coef1:
    call trellis_coef1.entry%1
    call trellis_coefn.entry%1b
    jmp .i_continue1
%%.switch_coef0:
    call trellis_coef0_%1
    call trellis_coef1.entry%1b

.i_continue%1:
%if cpuflag(avx2)
    ; next nonzero coef below i
    movq   r6, m8
    xor   r10d, r10d
    bts    r10, iiq
    dec    r10
    and    r6, r10
%if %1
    bsr    iiq, r6
    jnz .i_loop%1
%else
    ; the zeros in between, down to b_ac if none:
    ; nodes_cur[0].score -= cost_sig0;
%if num_coefs == 16 && dc == 0
    mov   r12d, b_acm
    dec   r12d
%else
    mov   r12d, -1
%endif
    bsr    r6, r6
    cmovnz r12d, r6d
    mov    r9, cabac_state_sigm
%if num_coefs == 64
    mov    r5d, b_interlacedm
    lea    r5, [significant_coeff_flag_offset_8x8 + r5 GLOBAL]
%endif
    xor   r11d, r11d
    dec    iid
    cmp    iid, r12d
    jle %%.zeros_done
%%.zeros:
%if num_coefs == 64
    movzx r10d, byte [r5 + iiq]
    movzx r10d, byte [r9 + r10]
%elif num_coefs == 8
    movzx r10d, byte [coeff_flag_offset_chroma_422_dc + iiq GLOBAL]
    movzx r10d, byte [r9 + r10]
%else
    movzx r10d, byte [r9 + iiq]
%endif
    movzx r10d, word [cabac_entropy + r10*2 GLOBAL]
    imul   r10, lambda2q
    shr    r10, CABAC_SIZE_BITS - LAMBDA_BITS
    add    r11, r10
    dec    iid
    cmp    iid, r12d
    jg %%.zeros
    sub   [nodes_curq + node_score(0)], r11
%%.zeros_done:
%if num_coefs == 16 && dc == 0
    cmp    iid, b_acm
%else
    test   iid, iid
%endif
    jge .i_loop%1
%endif
%else
    dec iid
%if num_coefs == 16 && dc == 0
    cmp iid, b_acm
%endif
    jge .i_loop%1
%endif

    call trellis_bnode_%1
%if %1 == 0
%if num_coefs == 16 && dc == 0
    jz .return_zero
%else
    jz .return
%endif
    jmp .writeback

%%.zero_siglast:
    xor  r6d, r6d
    mov [cost_siglast+0], r6
    mov [cost_siglast+8], r6d
    jmp %%.skip_siglast
%endif
%endmacro ; TRELLIS_LOOP

; just a synonym for %if
%macro IF0 1+
%endmacro
%macro IF1 1+
    %1
%endmacro

%macro ZERO_LEVEL_IDX 2 ; ctx_hi, prev
    ; for( int j = 0; j < 8; j++ )
    ;     nodes_cur[j].level_idx = levels_used;
    ;     level_tree[levels_used].next = (trellis_level_t){ .next = nodes_cur[j].level_idx, .abs_level = 0 };
    ;     levels_used++;
    add  levels_usedd, 3
    and  levels_usedd, ~3 ; allow aligned stores
    movd       m0, levels_usedd
    pshufd     m0, m0, 0
    IF%1 mova  m1, m0
         paddd m0, [pd_0123]
    IF%1 paddd m1, [pd_4567]
         mova  m2, [nodes_%2q + node_level_idx(0)]
    IF%1 mova  m3, [nodes_%2q + node_level_idx(4)]
         mova [nodes_curq + node_level_idx(0)], m0
    IF%1 mova [nodes_curq + node_level_idx(4)], m1
         mova [level_tree + (levels_usedq+0)*4], m2
    IF%1 mova [level_tree + (levels_usedq+4)*4], m3
    add  levels_usedd, (1+%1)*4
%endmacro

INIT_XMM sse2
TRELLIS trellis_cabac_4x4, 16, 0, 0
TRELLIS trellis_cabac_8x8, 64, 0, 0
TRELLIS trellis_cabac_4x4_psy, 16, 0, 1
TRELLIS trellis_cabac_8x8_psy, 64, 0, 1
TRELLIS trellis_cabac_dc, 16, 1, 0
TRELLIS trellis_cabac_chroma_422_dc, 8, 1, 0
INIT_XMM ssse3
TRELLIS trellis_cabac_4x4, 16, 0, 0
TRELLIS trellis_cabac_8x8, 64, 0, 0
TRELLIS trellis_cabac_4x4_psy, 16, 0, 1
TRELLIS trellis_cabac_8x8_psy, 64, 0, 1
TRELLIS trellis_cabac_dc, 16, 1, 0
TRELLIS trellis_cabac_chroma_422_dc, 8, 1, 0
INIT_XMM avx2
TRELLIS trellis_cabac_4x4, 16, 0, 0
TRELLIS trellis_cabac_8x8, 64, 0, 0
TRELLIS trellis_cabac_4x4_psy, 16, 0, 1
TRELLIS trellis_cabac_8x8_psy, 64, 0, 1
TRELLIS trellis_cabac_dc, 16, 1, 0
TRELLIS trellis_cabac_chroma_422_dc, 8, 1, 0



%define stack rsp+gprsize
%define scoreq r14
%define bitsq r13
%define bitsd r13d

INIT_XMM
%macro clocal 1
    ALIGN 16
    global mangle(private_prefix %+ _%1)
    mangle(private_prefix %+ _%1):
    %1:
    %assign stack_offset stack_offset_bak+gprsize
%endmacro

%macro TRELLIS_BNODE 1 ; ctx_hi
clocal trellis_bnode_%1
    ; int j = ctx_hi?1:0;
    ; trellis_node_t *bnode = &nodes_cur[j];
    ; while( ++j < (ctx_hi?8:4) )
    ;     if( nodes_cur[j].score < bnode->score )
    ;         bnode = &nodes_cur[j];
%assign j %1
    mov   rax, [nodes_curq + node_score(j)]
    lea   rax, [rax*8 + j]
%rep 3+3*%1
%assign j j+1
    mov   r11, [nodes_curq + node_score(j)]
    lea   r11, [r11*8 + j]
    cmp   rax, r11
    cmova rax, r11
%endrep
    mov   r10, dctm
    and   eax, 7
    ret
%endmacro ; TRELLIS_BNODE
TRELLIS_BNODE 0
TRELLIS_BNODE 1


%macro TRELLIS_COEF0 1 ; ctx_hi
clocal trellis_coef0_%1
    ; ssd1 += (uint64_t)cost_sig * lambda2 >> ( CABAC_SIZE_BITS - LAMBDA_BITS );
    mov  r11d, [cost_siglast+0]
    imul  r11, lambda2q
    shr   r11, CABAC_SIZE_BITS - LAMBDA_BITS
    add   r11, [ssd+16]
%if %1 == 0
    ; nodes_cur[0].score = nodes_prev[0].score + ssd - ssd1;
    mov  scoreq, [nodes_prevq + node_score(0)]
    add  scoreq, [ssd]
    sub  scoreq, r11
    mov  [nodes_curq + node_score(0)], scoreq
%endif
    ; memcpy
    mov  scoreq, [nodes_prevq + node_score(1)]
    mov  [nodes_curq + node_score(1)], scoreq
    mova m1, [nodes_prevq + node_score(2)]
    mova [nodes_curq + node_score(2)], m1
%if %1
    mova m1, [nodes_prevq + node_score(4)]
    mova [nodes_curq + node_score(4)], m1
    mova m1, [nodes_prevq + node_score(6)]
    mova [nodes_curq + node_score(6)], m1
%endif
    mov  r6d, [nodes_prevq + node_cabac_state(3)]
    mov  [nodes_curq + node_cabac_state(3)], r6d
%if %1
    mova m1, [nodes_prevq + node_cabac_state(4)]
    mova [nodes_curq + node_cabac_state(4)], m1
%endif
    ZERO_LEVEL_IDX %1, prev
    ret
%endmacro ; TRELLIS_COEF0
TRELLIS_COEF0 0
TRELLIS_COEF0 1



%macro START_COEF 1 ; gt1
    ; if( (int64_t)nodes_prev[0].score < 0 ) continue;
    mov  scoreq, [nodes_prevq + node_score(j)]
%if j > 0
    test scoreq, scoreq
    js .ctx %+ nextj_if_invalid
%endif

    ; f8_bits += x264_cabac_size_decision2( &n.cabac_state[coeff_abs_level1_ctx[j]], abs_level > 1 );
%if j >= 3
    movzx r6d, byte [nodes_prevq + node_cabac_state(j) + (coeff_abs_level1_offs>>2)] ; >> because node only stores ctx 0 and 4
    movzx r11, byte [cabac_transition + r6*2 + %1 GLOBAL]
%else
    movzx r6d, byte [level_statem + coeff_abs_level1_offs]
%endif
%if %1
    xor   r6d, 1
%endif
    movzx bitsd, word [cabac_entropy + r6*2 GLOBAL]

    ; n.score += ssd;
    ; unsigned f8_bits = cost_siglast[ j ? 1 : 2 ];
%if j == 0
    add  scoreq, r10
    add  bitsd, [cost_siglast+8]
%else
    add  scoreq, r12
    add  bitsd, [cost_siglast+4]
%endif
%endmacro ; START_COEF

%macro END_COEF 1
    ; n.score += (uint64_t)f8_bits * lambda2 >> ( CABAC_SIZE_BITS - LAMBDA_BITS );
    imul bitsq, lambda2q
    shr  bitsq, CABAC_SIZE_BITS - LAMBDA_BITS
    add  scoreq, bitsq

    ; if( n.score < nodes_cur[node_ctx].score )
    ;     SET_LEVEL( n, abs_level );
    ;     nodes_cur[node_ctx] = n;
    cmp scoreq, [nodes_curq + node_score(node_ctx)]
    jae .ctx %+ nextj_if_valid
    mov [nodes_curq + node_score(node_ctx)], scoreq
%if j == 2 || (j <= 3 && node_ctx == 4)
    ; if this node hasn't previously needed to keep track of abs_level cabac_state, import a pristine copy of the input states
    movd [nodes_curq + node_cabac_state(node_ctx)], level_state_packed
%elif j >= 3
    ; if we have updated before, then copy cabac_state from the parent node
    mov  r6d, [nodes_prevq + node_cabac_state(j)]
    mov [nodes_curq + node_cabac_state(node_ctx)], r6d
%endif
%if j >= 3 ; skip the transition if we're not going to reuse the context
    mov [nodes_curq + node_cabac_state(node_ctx) + (coeff_abs_level1_offs>>2)], r11b ; delayed from x264_cabac_size_decision2
%endif
%if %1 && node_ctx == 7
    mov  r6d, levelgt1_ctxm
    mov [nodes_curq + node_cabac_state(node_ctx) + coeff_abs_levelgt1_offs-6], r10b
%endif
    mov  r6d, [nodes_prevq + node_level_idx(j)]
%if %1
    mov r11d, abs_leveld
    shl r11d, 16
    or   r6d, r11d
%else
    or   r6d, 1<<16
%endif
    mov [level_tree + levels_usedq*4], r6d
    mov [nodes_curq + node_level_idx(node_ctx)], levels_usedd
    inc levels_usedd
%endmacro ; END_COEF



%macro COEF1 2
    %assign j %1
    %assign nextj_if_valid %1+1
    %assign nextj_if_invalid %2
%if j < 4
    %assign coeff_abs_level1_offs j+1
%else
    %assign coeff_abs_level1_offs 0
%endif
%if j < 3
    %assign node_ctx j+1
%else
    %assign node_ctx j
%endif
.ctx %+ j:
    START_COEF 0
    add  bitsd, 1 << CABAC_SIZE_BITS
    END_COEF 0
%endmacro ; COEF1

%macro COEFN 2
    %assign j %1
    %assign nextj_if_valid %2
    %assign nextj_if_invalid %2
%if j < 4
    %assign coeff_abs_level1_offs j+1
    %assign coeff_abs_levelgt1_offs 5
%else
    %assign coeff_abs_level1_offs 0
    %assign coeff_abs_levelgt1_offs j+2 ; this is the one used for all block types except 4:2:2 chroma dc
%endif
%if j < 4
    %assign node_ctx 4
%elif j < 7
    %assign node_ctx j+1
%else
    %assign node_ctx 7
%endif
.ctx %+ j:
    START_COEF 1
    ; if( abs_level >= 15 )
    ;     bits += bs_size_ue_big(...)
    add  bitsd, r5d ; bs_size_ue_big from COEFN_SUFFIX
    ; n.cabac_state[levelgt1_ctx]
%if j == 7 ; && compiling support for 4:2:2
    mov    r6d, levelgt1_ctxm
    %define coeff_abs_levelgt1_offs r6
%endif
%if j == 7
    movzx  r10, byte [nodes_prevq + node_cabac_state(j) + coeff_abs_levelgt1_offs-6] ; -6 because node only stores ctx 8 and 9
%else
    movzx  r10, byte [level_statem + coeff_abs_levelgt1_offs]
%endif
    ; f8_bits += cabac_size_unary[abs_level-1][n.cabac_state[levelgt1_ctx[j]]];
    add   r10d, r1d
    movzx  r6d, word [cabac_size_unary + (r10-128)*2 GLOBAL]
    add  bitsd, r6d
%if node_ctx == 7
    movzx  r10, byte [cabac_transition_unary + r10-128 GLOBAL]
%endif
    END_COEF 1
%endmacro ; COEFN



clocal trellis_coef1
.entry0b: ; ctx_lo, larger of the two abs_level candidates
    mov  r10, [ssd+8]
    sub  r10, r11
    mov  r12, [ssd+24]
    sub  r12, r11
.entry0: ; ctx_lo, smaller of the two abs_level candidates
    COEF1 0, 4
    COEF1 1, 4
    COEF1 2, 4
    COEF1 3, 4
.ctx4:
    rep ret
.entry1b: ; ctx_hi, larger of the two abs_level candidates
    mov  r12, [ssd+24]
    sub  r12, r11
.entry1: ; ctx_hi, smaller of the two abs_level candidates
trellis_coef1_hi:
    COEF1 1, 2
    COEF1 2, 3
    COEF1 3, 4
    COEF1 4, 5
    COEF1 5, 6
    COEF1 6, 7
    COEF1 7, 8
.ctx8:
    rep ret

%macro COEFN_PREFIX 1
    ; int prefix = X264_MIN( abs_level - 1, 14 );
    mov  r1d, abs_leveld
    cmp  abs_leveld, 15
    jge .level_suffix%1
    xor  r5d, r5d
.skip_level_suffix%1:
    shl  r1d, 7
%endmacro

%macro COEFN_SUFFIX 1
.level_suffix%1:
    ; bs_size_ue_big( abs_level - 15 ) << CABAC_SIZE_BITS;
    lea  r5d, [abs_levelq-14]
    bsr  r5d, r5d
    shl  r5d, CABAC_SIZE_BITS+1
    add  r5d, 1<<CABAC_SIZE_BITS
    ; int prefix = X264_MIN( abs_level - 1, 14 );
    mov  r1d, 15
    jmp .skip_level_suffix%1
%endmacro

clocal trellis_coefn
.entry0b:
    mov  r10, [ssd+8]
    mov  r12, [ssd+24]
    inc  abs_leveld
.entry0:
    ; I could fully separate the ctx_lo and ctx_hi versions of coefn, and then
    ; apply return-on-first-failure to ctx_lo. Or I can use multiple entrypoints
    ; to merge the common portion of ctx_lo and ctx_hi, and thus reduce codesize.
    ; I can't do both, as return-on-first-failure doesn't work for ctx_hi.
    ; The C version has to be fully separate since C doesn't support multiple
    ; entrypoints. But return-on-first-failure isn't very important here (as
    ; opposed to coef1), so I might as well reduce codesize.
    COEFN_PREFIX 0
    COEFN 0, 1
    COEFN 1, 2
    COEFN 2, 3
    COEFN 3, 8
.ctx8:
    mov zigzagq, zigzagm ; unspill since r1 was clobbered
    ret
.entry1b:
    mov  r12, [ssd+24]
    inc  abs_leveld
.entry1:
    COEFN_PREFIX 1
    COEFN 4, 5
    COEFN 5, 6
    COEFN 6, 7
    COEFN 7, 1
    jmp .ctx1
    COEFN_SUFFIX 0
    COEFN_SUFFIX 1



;=============================================================================
; avx512icl: all 8 nodes at once, kept in registers for the whole block.
; m0 (cur) / m2 (prev): key = (score - 2^59) << 4 | n. n is the node for a kept
; node and 8+source for a candidate, so unsigned min is the C's strict < with
; ties to the existing node, then the lowest source; n also indexes the payload.
; Invalid: key >= -16. Needs valid scores in 2^60 +- 2^59: per coef |ssd| < 2^52
; (|d| < 2^21 for the transforms' range, coef_weight2 < 2^10) and bits < 2^44,
; over 64 coefs < 2^59. trellis_bnode's score*8+j already needs < 2^61.
; m1 (cur) / m3 (prev): payload = cabac_state[4] | level_idx<<32 for prev,
; | abs_level<<48 for a pending cur node (its level_tree entry, a qword here).
; All 8 entries are stored per nonzero coef: at most 1 + 8*64 = 513.
;=============================================================================

; build-time A/B: vpmuludq instead of IFMA, compare masks instead of unsigned min
%ifndef TRELLIS_ICL_MULQ
    %define TRELLIS_ICL_MULQ 0
%endif
%ifndef TRELLIS_ICL_CMPMERGE
    %define TRELLIS_ICL_CMPMERGE 0
%endif
%ifndef TRELLIS_ICL_ZPREFIX
    %define TRELLIS_ICL_ZPREFIX 0
%endif

INIT_ZMM avx512icl

%macro TR_LOOKUP_E 2 ; dst, bin: x264_cabac_entropy[l1_state^bin] << 32
    vmovdqu64  %1, [tr_e %+ %2 %+ lo]
    vpermt2b   %1, m10, [tr_e %+ %2 %+ lo+64]
    vmovdqu64  m21, [tr_e %+ %2 %+ hi]
    vpermt2b   m21{k3}{z}, m10, [tr_e %+ %2 %+ hi+64]
    vpternlogq %1, m21, [tr_b4]{1to8}, 0xec
%endmacro

%macro TR_LOOKUP_T 2 ; dst, bin: x264_cabac_transition[l1_state][bin], byte 0/1
    vmovdqu64  %1, [tr_t %+ %2]
    vpermt2b   %1, m10, [tr_t %+ %2 + 64]
%endmacro

%macro TR_SUFFIX 4 ; dst, abs_level, abs_level (dword), tmp: abs_level >= 15 ? bs_size_ue_big( abs_level - 15 ) << CABAC_SIZE_BITS : 0
    lea    %4, [%2-14]
    bsr    %4, %4
    shl    %4, CABAC_SIZE_BITS+1
    add    %4, 1<<CABAC_SIZE_BITS
    xor    %1, %1
    cmp    %3, 15
    cmovge %1, %4
%endmacro

; candidate keys m18 from ssd m17 and f8_bits<<32 m16, for every valid source node
%macro TR_KEYS 0
%if TRELLIS_ICL_MULQ
    vpsrlq      m16, m16, 32
    vpmuludq    m16, m16, m5
    vpsrlq      m16, m16, CABAC_SIZE_BITS - LAMBDA_BITS
    vpaddq      m17, m17, m16
%else
    vpmadd52huq m17, m16, m5     ; ssd + (f8_bits*lambda2 >> 4)
%endif
    vpshldq     m17, m17, m7, 4  ; <<4 | 8
    vmovdqa64   m18, m4
    vpaddq      m18{k1}, m2, m17
%endmacro

; best candidate in m19 vs cur: the node in its low 4 bits, 8-15 for a
; candidate, 0-7 for the existing node, which so wins ties
%macro TR_MERGE 0
%if TRELLIS_ICL_CMPMERGE
    vpcmpuq    k2, m19, m0, 1
    vpternlogq m0{k2}, m19, [tr_m16]{1to8}, 0xd8
    vpermq     m1{k2}, m19, m15
%else
    vpminuq    m0, m0, m19
    vpermt2q   m1, m0, m15
    vpternlogq m0, m14, [tr_m16]{1to8}, 0xec
%endif
%endmacro

; abs_level 1: node j -> 1,2,3,3,4,5,6,7. m11 = entropy, m12 = transition
%macro TR_PASS1 0
    vpaddq     m16, m16, m11
    TR_KEYS
    vmovdqa64  m15, m3
    vpternlogq m15, m8, [tr_m11], 0xec   ; node 2: level_state, all: abs_level 1
    vpternlogq m15, m12, [tr_mt], 0xd8
    vmovdqu64  m19, [tr_p1a]
    vpermi2q   m19, m18, m4
    vmovdqu64  m20, [tr_p1b]
    vpermi2q   m20, m18, m4
    vpminuq    m19, m19, m20
    TR_MERGE
%endmacro

; abs_level > 1: node j -> 4,4,4,4,5,6,7,7. %1 = abs_level<<48, %2 = cabac_size_unary[prefix], %3 = cabac_transition_unary[prefix]
%macro TR_PASSN 3
    vmovdqu64  m19, [%2]
    vpermt2w   m19{k6}{z}, m10, [%2+64]
    vmovdqu64  m20, [%2+128]
    vpermt2w   m20{k5}{z}, m10, [%2+192]
    vpternlogq m19, m20, m11, 0xfe
    vpdpwssd   m16, m19, [tr_pw1]{1to16}
    TR_KEYS
    vpbroadcastq m21, %1
    vporq      m21, m21, m9
    vmovdqa64  m15, m3
    vpternlogq m15, m21, [tr_m1n], 0xec  ; nodes 0-3: level_state
    vpternlogq m15, m12, [tr_mt], 0xd8
    vmovdqu64  m21, [%3]
    vpermt2b   m21, m10, [%3+64]
    vpternlogq m15, m21, [TR_MTU], 0xd8
    vmovdqu64  m19, [tr_pn1]
    vpermi2q   m19, m18, m4
    vpminuq    m19, m19, m18
    vmovdqu64  m20, [tr_pn2]
    vpermi2q   m20, m19, m4
    vmovdqu64  m16, [tr_pn3]
    vpermi2q   m16, m19, m4
    vpminuq    m19, m20, m16
    TR_MERGE
%endmacro

; levelgt1 state < 64 / >= 64, for the two halves of a cabac_size_unary row
%macro TR_SUMASK 0
    vpcmpuw   k6, m10, [tr_w3lt], 1
    vpcmpuw   k5, m10, [tr_w3ge], 5
%endmacro

; append all 8 nodes' entries (the invalid ones are never reached), give them
; their new level_idx; the next coef's state indexes
%macro TR_END_COEF 0
    vmovdqu64    m10, [TR_IDX]
    vpermi2b     m10, m1, m6
    vmovdqu64    [ltree + r4*8], m1
    vpternlogq   m1, m13, [tr_lomask]{1to8}, 0xec
    vpaddq       m13, m13, [tr_8hi]{1to8}
    add          r4d, 8
%endmacro

; scalar part of one coef, i = r3: q r8, ssd1[q-1] r7, ssd1[q] r13,
; cost_siglast r11, r14, r9 (ctx_lo); ctx_lo: ssd0 in ssd00m, ssd01m
%macro TR_PREP 1 ; ctx_hi
    mov    r6, quantp
%if HIGH_BIT_DEPTH
    mov    r7d, [r6+r3*4]
%else
    movsx  r7d, word [r6+r3*2]
%endif
    mov    r8d, r7d
    neg    r8d
    cmovl  r8d, r7d
    movzx  r9d, byte [r1+r3]
    mov    r6, origp
%if HIGH_BIT_DEPTH
    mov    r10d, [r6+r9*4]
%else
    movsx  r10d, word [r6+r9*2]
%endif
    mov    r11d, r10d
    neg    r11d
    cmovl  r11d, r10d
%if dc
    mov    r12d, mf2m
%else
    mov    r6, unqp
    mov    r12d, [r6+r9*4]
%endif
    ; unquant_abs_level = (unquant_mf * abs_level + 128) >> 8
    lea    r14d, [r8-1]
    imul   r14d, r12d
    add    r14d, 128
    shr    r14d, 8
    imul   r12d, r8d
    add    r12d, 128
    shr    r12d, 8
    ; ssd = (int64_t)d*d * coef_weight2
    mov    r13d, r11d
    sub    r13d, r12d
    movsxd r13, r13d
    imul   r13, r13
    mov    r7d, r11d
    sub    r7d, r14d
    movsxd r7, r7d
    imul   r7, r7
%if dc
    shl    r13, 8
    shl    r7, 8
%else
    mov    r6d, [dct_weight2_tab + r9*4 GLOBAL]
    imul   r13, r6
    imul   r7, r6
%endif
%if psy
    ; ssd -= dct_weight_tab[zigzag[i]] * psy_trellis * abs( unquant_abs_level + SIGN(predicted_coef, sign_coef) )
    test   r3d, r3d
    jz %%nopsy
    mov    r6, fenc_dctm
%if HIGH_BIT_DEPTH
    mov    r6d, [r6+r9*4]
%else
    movsx  r6d, word [r6+r9*2]
%endif
    sub    r6d, r10d
    mov    r11d, r10d
    sar    r11d, 31
    xor    r6d, r11d
    sub    r6d, r11d
    mov    r11d, [dct_weight1_tab + r9*4 GLOBAL]
    imul   r11d, psy_trellism
    add    r12d, r6d
    mov    r9d, r12d
    neg    r9d
    cmovl  r9d, r12d
    imul   r9, r11
    sub    r13, r9
    add    r14d, r6d
    mov    r9d, r14d
    neg    r9d
    cmovl  r9d, r14d
    imul   r9, r11
    sub    r7, r9
%%nopsy:
%endif
%if %1 == 0
    mov    ssd00m, r7
    mov    ssd01m, r13
%if dc == 0
    test   r3d, r3d
    jz %%dc_rounding
%%dc_rounding_done:
%endif
%if dc && num_coefs != 8
    cmp    r3d, i_coefsm
%else
    cmp    r3d, num_coefs-1
%endif
    je %%last_coef
%endif
    ; cost_siglast = { sig 0, sig 1 + last 0, sig 1 + last 1 }
%if num_coefs == 64
    mov    r6, sigtabp
    movzx  r6d, byte [r6+r3]
%elif num_coefs == 8
    movzx  r6d, byte [coeff_flag_offset_chroma_422_dc + r3 GLOBAL]
%else
    mov    r6d, r3d
%endif
    mov    r9, cabac_state_sigm
    movzx  r9d, byte [r9+r6]
    movzx  r11d, word [cabac_entropy + r9*2 GLOBAL]
    xor    r9d, 1
    movzx  r12d, word [cabac_entropy + r9*2 GLOBAL]
%if num_coefs == 64
    movzx  r6d, byte [last_coeff_flag_offset_8x8 + r3 GLOBAL]
%endif
    mov    r9, cabac_state_lastm
    movzx  r9d, byte [r9+r6]
    movzx  r14d, word [cabac_entropy + r9*2 GLOBAL]
    add    r14d, r12d
%if %1 == 0
    xor    r9d, 1
    movzx  r9d, word [cabac_entropy + r9*2 GLOBAL]
    add    r9d, r12d
%%csl_done:
%endif
    cmp    r8d, 2
    jl .q1_%1
    je .q2_%1
    jmp .qn_%1
%if %1 == 0
%%last_coef:
    xor    r11d, r11d
    xor    r14d, r14d
    xor    r9d, r9d
    jmp %%csl_done
%if dc == 0
%%dc_rounding:
    ; d = sign_coef - ((SIGN(unquant_abs_level, sign_coef) + 8)&~15)
    mov    r11d, r10d
    sar    r11d, 31
    mov    r6d, r12d
    xor    r6d, r11d
    sub    r6d, r11d
    add    r6d, 8
    and    r6d, ~15
    mov    r12d, r10d
    sub    r12d, r6d
    movsxd r12, r12d
    imul   r12, r12
    mov    r6d, r14d
    xor    r6d, r11d
    sub    r6d, r11d
    add    r6d, 8
    and    r6d, ~15
    mov    r14d, r10d
    sub    r14d, r6d
    movsxd r14, r14d
    imul   r14, r14
    mov    r6d, [dct_weight2_tab + r9*4 GLOBAL]
    imul   r12, r6
    imul   r14, r6
    mov    ssd01m, r12
    mov    ssd00m, r14
    jmp %%dc_rounding_done
%endif
%endif
%endmacro

; lane 0 differs only in ctx_lo
%macro TR_BCAST 4 ; ctx_hi, dst, lanes 1-7, lane 0
    vpbroadcastq %2, %3
%if %1 == 0
    vpbroadcastq %2{k7}, %4
%endif
%endmacro

%macro TR_LOOP 1 ; ctx_hi
.coef%1:
    vmovdqa64 m2, m0
    vmovdqa64 m3, m1
    vpcmpuq   k1, m2, [tr_m16]{1to8}, 1
    TR_PREP %1

.q1_%1:
    ; trellis_coef0: the copy, then abs_level 1 against it
    imul   r11, r2
    shr    r11, CABAC_SIZE_BITS - LAMBDA_BITS
    add    r11, r7
%if %1 == 0
    mov    r6, ssd00m
    sub    r6, r11
    shl    r6, 4
    vmovq  xm17, r6
    vpaddq m0, m2, m17
%else
    vmovdqa64 m0, m2
%endif
    vmovdqa64 m1, m3
    sub    r13, r11
    vpbroadcastq m17, r13
%if %1 == 0
    mov    r6, ssd01m
    sub    r6, r11
    vpbroadcastq m17{k7}, r6
%endif
    add    r14d, 1<<CABAC_SIZE_BITS
    shl    r14, 32
%if %1 == 0
    add    r9d, 1<<CABAC_SIZE_BITS
    shl    r9, 32
%endif
    TR_BCAST %1, m16, r14, r9
    TR_LOOKUP_E m11, 0
    TR_LOOKUP_T m12, 0
    TR_PASS1
    TR_END_COEF
    jmp .next%1

.q2_%1:
    vmovdqu64 m0, [tr_inv]
    TR_BCAST %1, m17, r7, qword ssd00m
    lea    r6, [r14+(1<<CABAC_SIZE_BITS)]
    shl    r6, 32
%if %1 == 0
    lea    r10, [r9+(1<<CABAC_SIZE_BITS)]
    shl    r10, 32
%endif
    TR_BCAST %1, m16, r6, r10
    TR_LOOKUP_E m11, 0
    TR_LOOKUP_T m12, 0
    TR_PASS1
    shl    r14, 32
%if %1 == 0
    shl    r9, 32
%endif
    TR_BCAST %1, m16, r14, r9
    TR_BCAST %1, m17, r13, qword ssd01m
    TR_LOOKUP_E m11, 1
    TR_LOOKUP_T m12, 1
    TR_SUMASK
    mov    r10, 2<<48
    lea    r11, [cabac_size_unary + 1*256 GLOBAL]
    lea    r12, [cabac_transition_unary + 1*128 GLOBAL]
    TR_PASSN r10, r11, r12
    TR_END_COEF
    jmp .next1

.qn_%1:
    vmovdqu64 m0, [tr_inv]
    TR_LOOKUP_E m11, 1
    TR_LOOKUP_T m12, 1
    TR_SUMASK
    ; abs_level q-1
    lea    r10d, [r8-1]
    TR_SUFFIX r12d, r10, r10d, r6d
    lea    r6, [r14+r12]
    shl    r6, 32
%if %1 == 0
    lea    r12, [r9+r12]
    shl    r12, 32
%endif
    TR_BCAST %1, m16, r6, r12
    TR_BCAST %1, m17, r7, qword ssd00m
    ; prefix = X264_MIN( abs_level-1, 14 )
    lea    r6d, [r8-2]
    mov    r12d, 14
    cmp    r6d, r12d
    cmova  r6d, r12d
    mov    r12d, r6d
    shl    r12d, 8
    lea    r11, [cabac_size_unary GLOBAL]
    add    r11, r12
    shl    r6d, 7
    lea    r12, [cabac_transition_unary GLOBAL]
    add    r12, r6
    shl    r10, 48
    TR_PASSN r10, r11, r12
    ; abs_level q
    TR_SUFFIX r12d, r8, r8d, r6d
    lea    r6, [r14+r12]
    shl    r6, 32
%if %1 == 0
    lea    r12, [r9+r12]
    shl    r12, 32
%endif
    TR_BCAST %1, m16, r6, r12
    TR_BCAST %1, m17, r13, qword ssd01m
    lea    r6d, [r8-1]
    mov    r12d, 14
    cmp    r6d, r12d
    cmova  r6d, r12d
    mov    r12d, r6d
    shl    r12d, 8
    lea    r11, [cabac_size_unary GLOBAL]
    add    r11, r12
    shl    r6d, 7
    lea    r12, [cabac_transition_unary GLOBAL]
    add    r12, r6
    mov    r10, r8
    shl    r10, 48
    TR_PASSN r10, r11, r12
    TR_END_COEF
    jmp .next1
%endmacro

%macro TRELLIS_ICL 4
%define num_coefs %2
%define dc %3
%define psy %4
%if num_coefs == 8 && dc
    %define TR_IDX tr_idx422
    %define TR_MTU tr_mtu422
%else
    %define TR_IDX tr_idx
    %define TR_MTU tr_mtu
%endif
%if num_coefs == 64
    %define dct_weight1_tab dct8_weight_tab
    %define dct_weight2_tab dct8_weight2_tab
%else
    %define dct_weight1_tab dct4_weight_tab
    %define dct_weight2_tab dct4_weight2_tab
%endif
; zero-run prefix sums: 8x8 only, where runs of 20-55 zero coefs are typical
%assign tr_zpfx 0
%if TRELLIS_ICL_ZPREFIX && num_coefs == 64
    %assign tr_zpfx 1
%endif
cglobal %1, 4,15,22
    mov r2d, r2d
    mov r3d, r3d
    %assign pad 128 + 8*520 + tr_zpfx*8*66 + 16-gprsize-(stack_offset&15)
    SUB  rsp, pad
%if WIN64
    %define level_statem rsp+stack_offset+80
%else
    %define level_statem rsp+stack_offset+32
%endif
    %define cabac_state_sigm  r7m
    %define cabac_state_lastm r8m
    %define i_coefsm   r11m ; dc only
    %define fenc_dctm  r12m
    %define psy_trellism r13m
    %define quantp  [rsp+ 0]
    %define origp   [rsp+ 8]
    %define unqp    [rsp+16]
    %define mf2m    dword [rsp+24]
    %define maskp   [rsp+32]
    %define sigtabp [rsp+40]
    %define ssd00m  [rsp+48]
    %define ssd01m  [rsp+56]
    %define nodesp  rsp+64
    %define ltree   rsp+128
    %define prefix  rsp+128+8*520 ; cost_sig0 of the positions below i, built at the first zero
    %define pfxdone byte [rsp+128+8*520+8*65]
    mov    r6, r4mp
    mov    origp, r6
    mov    r6, r5mp
    mov    quantp, r6
    mov    unqp, r0
%if dc
    mov    r6d, [r0]
    add    r6d, r6d
    mov    mf2m, r6d
%endif
%ifdef PIC
    lea    r0, [$$]
    %define GLOBAL +r0-$$
%else
    %define GLOBAL
%endif

    ; nonzero quant_coefs[i], b_ac <= i <= last_nnz
    mov    r6, quantp
%if num_coefs == 64
%if HIGH_BIT_DEPTH
    vmovdqu32 m10, [r6+  0]
    vmovdqu32 m11, [r6+ 64]
    vmovdqu32 m12, [r6+128]
    vmovdqu32 m13, [r6+192]
    vptestmd  k1, m10, m10
    vptestmd  k2, m11, m11
    vptestmd  k3, m12, m12
    vptestmd  k4, m13, m13
    kunpckwd  k1, k2, k1
    kunpckwd  k3, k4, k3
    kunpckdq  k1, k3, k1
%else
    vmovdqu16 m10, [r6+ 0]
    vmovdqu16 m11, [r6+64]
    vptestmw  k1, m10, m10
    vptestmw  k2, m11, m11
    kunpckdq  k1, k2, k1
%endif
    kmovq     r5, k1
%elif num_coefs == 16
%if HIGH_BIT_DEPTH
    vmovdqu32 m10, [r6]
    vptestmd  k1, m10, m10
%else
    vmovdqu16 ym10, [r6]
    vptestmw  k1, ym10, ym10
%endif
    kmovw     r5d, k1
%else
%if HIGH_BIT_DEPTH
    vmovdqu32 ym10, [r6]
    vptestmd  k1, ym10, ym10
%else
    vmovdqu16 xm10, [r6]
    vptestmw  k1, xm10, xm10
%endif
    kmovb     r5d, k1
%endif
    xor    r6d, r6d
    bts    r6, r3
    lea    r6, [r6*2-1]
    and    r5, r6
%if num_coefs == 16 && dc == 0
    mov    r6d, r11m ; b_ac
    not    r6
    and    r5, r6
%endif
    mov    maskp, r5
%if num_coefs == 64
    mov    r7d, r11m ; b_interlaced
    shl    r7d, 6
    lea    r6, [significant_coeff_flag_offset_8x8 GLOBAL]
    add    r6, r7
    mov    sigtabp, r6
%endif

    vpternlogq m4, m4, m4, 0xff
%if TRELLIS_ICL_MULQ
    vpbroadcastq m5, r2
%else
    mov    r6, r2
    shl    r6, 16
    vpbroadcastq m5, r6
%endif
    vmovq  xm6, [level_statem]
    vpinsrw xm6, xm6, [level_statem+8], 4
    vpbroadcastq m7, [tr_top]
    vmovdqu64 m14, [tr_iota]
    vmovdqu64 m8, [tr_pk1]
    vpermb m8, m8, m6
    vporq  m8, m8, [tr_abs1]{1to8}
    vmovdqu64 m9, [tr_pkn]
    vpermb m9, m9, m6
    kmovq  k3, [tr_kb5]
    mov    r6d, 1
    kmovb  k7, r6d
    vmovdqu64 m0, [tr_inv]
    vpbroadcastq m0{k7}, [tr_top]
    vpxord m1, m1, m1
    vmovdqu64 m10, [TR_IDX]
    vpermi2b m10, m1, m6
    mov    dword [ltree+4], 0
    vmovdqu64 m13, [tr_iotahi1]
    mov    r4d, 1
%if tr_zpfx
    mov    pfxdone, 0
%endif

    TR_LOOP 0
.next0:
    ; the zeros below i, down to the next nonzero or b_ac:
    ; nodes_cur[0].score -= cost_sig0
    btr    r5, r3
%if num_coefs == 16 && dc == 0
    mov    r12d, r11m
    dec    r12d
%else
    mov    r12d, -1
%endif
    bsr    r6, r5
    cmovnz r12d, r6d
    lea    r7d, [r3-1]
    cmp    r7d, r12d
    jle .zeros_done
%if tr_zpfx
    cmp    pfxdone, 0
    je .prefix
.prefix_done:
    lea    r7d, [r12+1]
    mov    r11, [prefix + r3*8]
    sub    r11, [prefix + r7*8]
%else
    mov    r9, cabac_state_sigm
%if num_coefs == 64
    mov    r10, sigtabp
%endif
    xor    r11d, r11d
.zeros:
%if num_coefs == 64
    movzx  r6d, byte [r10+r7]
%elif num_coefs == 8
    movzx  r6d, byte [coeff_flag_offset_chroma_422_dc + r7 GLOBAL]
%else
    mov    r6d, r7d
%endif
    movzx  r6d, byte [r9+r6]
    movzx  r6d, word [cabac_entropy + r6*2 GLOBAL]
    imul   r6, r2
    shr    r6, CABAC_SIZE_BITS - LAMBDA_BITS
    add    r11, r6
    dec    r7d
    cmp    r7d, r12d
    jg .zeros
%endif
    shl    r11, 4
    vmovq  xm19, r11
    vpsubq m0, m0, m19
.zeros_done:
    mov    r3d, r12d
    test   r5, r5
    jnz .coef0
    call .bnode
    jnz .writeback
%if num_coefs == 16 && dc == 0
    mov    r10, r6m ; dct
%if HIGH_BIT_DEPTH
    vmovdqu64 [r10], m21
%else
    vmovdqu64 [r10], ym21
%endif
%endif
    xor    eax, eax
    jmp .return

%if tr_zpfx
.prefix:
    ; prefix[i] = sum of cost_sig0 of positions 0..i-1
    mov    r6, cabac_state_sigm
    vmovdqu8  xm15, [r6]
    mov    r6, sigtabp
    vmovdqu8  m16, [r6]
    vpermb    m16, m16, m15               ; state of each position
    vmovdqu64 m17, [tr_e0lo]
    vpermt2b  m17, m16, [tr_e0lo+64]
    vmovdqu64 m18, [tr_e0hi]
    vpermt2b  m18, m16, [tr_e0hi+64]
    vmovdqu64 m15, [tr_qidx]
    mov    r6, 0x0303030303030303
    kmovq     k2, r6
    mov    r6d, 8
    vpbroadcastb m2, r6d
    vpbroadcastq m3, r2
    vpbroadcastq m11, [tr_q7]
    vpxord    m12, m12, m12
    vpxord    m21, m21, m21
    mov    qword [prefix], 0
%assign %%g 0
%rep 8
    vmovdqa64 m19, m15
    vpermi2b  m19{k2}{z}, m17, m18        ; entropy of positions 8g..8g+7
%if %%g < 7
    vpaddb    m15, m15, m2
%endif
    vpmuludq  m19, m19, m3
    vpsrlq    m19, m19, CABAC_SIZE_BITS - LAMBDA_BITS
    valignq   m20, m19, m21, 7
    vpaddq    m19, m19, m20
    valignq   m20, m19, m21, 6
    vpaddq    m19, m19, m20
    valignq   m20, m19, m21, 4
    vpaddq    m19, m19, m20
    vpaddq    m19, m19, m12
    vmovdqu64 [prefix + 8 + 64*%%g], m19
%if %%g < 7
    vpermq    m12, m11, m19
%endif
%assign %%g %%g+1
%endrep
    mov    pfxdone, 1
    jmp .prefix_done
%endif

    TR_LOOP 1
.next1:
    btr    r5, r3
    bsr    r3, r5
    jnz .coef1
    call .bnode
.writeback:
    ; int level = bnode->level_idx;
    ; for each nonzero i: dct[zigzag[i]] = SIGN(level_tree[level].abs_level, dct[zigzag[i]]); level = level_tree[level].next;
    vmovdqu64 [nodesp], m1
    mov    r0d, [nodesp + r14*8 + 4]
    mov    r12, maskp
    mov    r10, r6m ; dct
.writeback_loop:
    bsf    r3, r12
    movzx  r2d, byte [r1+r3]
    mov    r5d, [ltree + r0*8 + 4]
    movzx  r0d, r5w
    shr    r5d, 16
%if HIGH_BIT_DEPTH
    mov    r4d, [r10 + r2*4]
%else
    movsx  r4d, word [r10 + r2*2]
%endif
    sar    r4d, 31
    xor    r5d, r4d
    sub    r5d, r4d
%if HIGH_BIT_DEPTH
    mov    [r10 + r2*4], r5d
%else
    mov    [r10 + r2*2], r5w
%endif
    lea    r13, [r12-1]
    and    r12, r13
    jnz .writeback_loop
    mov    eax, 1
.return:
    ADD    rsp, pad
    RET

.bnode:
    ; first node with the lowest score: r14, ZF if node 0. m21 = 0
    vshufi64x2 m20, m0, m0, q1032
    vpminuq    m19, m0, m20
    vshufi64x2 m20, m19, m19, q2301
    vpminuq    m19, m19, m20
    vpshufd    m20, m19, q1032
    vpminuq    m19, m19, m20
    vmovq      r14, xm19
    vpxord     m21, m21, m21
    and        r14d, 7
    ret
%endmacro ; TRELLIS_ICL

TRELLIS_ICL trellis_cabac_4x4, 16, 0, 0
TRELLIS_ICL trellis_cabac_8x8, 64, 0, 0
TRELLIS_ICL trellis_cabac_4x4_psy, 16, 0, 1
TRELLIS_ICL trellis_cabac_8x8_psy, 64, 0, 1
TRELLIS_ICL trellis_cabac_dc, 16, 1, 0
TRELLIS_ICL trellis_cabac_chroma_422_dc, 8, 1, 0



;=============================================================================
; trellis_wrap: rdo.c's trellis_cabac_quantised after the quant, unix64 avx2.
; The blocks with an ac level take the trellis_cabac_* of the x264_trellis_wrap_t
; (zigzag scan here, last_nnz from the nonzero mask); dc-only and all-zero
; blocks take trellis_dc_shortcut without branches (all-zero: level 0). 4x4x4
; loops over the mask of such blocks, not over the 4 blocks.
; rbx: p, rbp: dct, R14: orig, R12-R13, R15: per function. Outgoing stack
; arguments at rsp+0, the scanned levels 64-aligned from rsp+64.
;=============================================================================
%if UNIX64

%define TW_UNQUANT  0
%define TW_ZIGZAG   8
%define TW_SIG     16
%define TW_LAST    24
%define TW_STATE   32
%define TW_FENC    40
%define TW_TRELLIS 48
%define TW_SCAN    56
%define TW_LAMBDA2 64
%define TW_ARG     68
%define TW_PSY     72
%define TW_FIELD   76
%define TW_STACK   384
%define TW_BLKSHIFT 5+HIGH_BIT_DEPTH ; log2 of a 4x4 block in bytes

INIT_XMM avx2

; rdi: the scanned levels
%macro TW_LEVELS 0
    lea    rdi, [rsp+64+63]
    and    rdi, ~63
%endmacro

; 4x4 zigzag scan of [rsi] to [rdi]; eax = nonzero levels in scan order
%macro TW_SCAN4 0
    mov    eax, [rbx+TW_FIELD]
    shl    eax, 6
%if HIGH_BIT_DEPTH
    lea    R8, [tw_zz4]
%else
    lea    R8, [tw_scan4]
%endif
    add    R8, rax
%if HIGH_BIT_DEPTH
    vmovdqu   ymm0, [rsi]
    vmovdqu   ymm1, [rsi+32]
    vmovdqu   ymm2, [R8]
    vpermd    ymm3, ymm2, ymm0
    vpermd    ymm4, ymm2, ymm1
    vpslld    ymm2, ymm2, 28
    vblendvps ymm3, ymm3, ymm4, ymm2
    vmovdqu   ymm2, [R8+32]
    vpermd    ymm4, ymm2, ymm0
    vpermd    ymm0, ymm2, ymm1
    vpslld    ymm2, ymm2, 28
    vblendvps ymm4, ymm4, ymm0, ymm2
    vmovdqa   [rdi], ymm3
    vmovdqa   [rdi+32], ymm4
    vpackssdw ymm0, ymm3, ymm4
    vpermq    ymm0, ymm0, q3120
%else
    vmovdqu   ymm0, [rsi]
    vpermq    ymm1, ymm0, q1010
    vpermq    ymm0, ymm0, q3232
    vpshufb   ymm1, ymm1, [R8]
    vpshufb   ymm0, ymm0, [R8+32]
    vpor      ymm0, ymm0, ymm1
    vmovdqa   [rdi], ymm0
%endif
    vextracti128 xmm1, ymm0, 1
    vpacksswb xmm0, xmm0, xmm1
    vpxor     xmm1, xmm1, xmm1
    vpcmpeqb  xmm0, xmm0, xmm1
    vpmovmskb eax, xmm0
    xor       eax, 0xffff
    vzeroupper
%endmacro

; trellis_cabac_*( unquant_mf, zigzag, lambda2, last_nnz = ecx, orig + rax, levels,
;     dct + rax, sig, last, level_state0, level_state1, arg, fenc_dct + rax, psy_trellis )
; levels + rax with an argument
%macro TW_CALL 0-1 0
    lea    rdx, [rbp+rax]
    mov    [rsp+ 0], rdx
    mov    rdx, [rbx+TW_FENC]
    add    rdx, rax
    mov    [rsp+48], rdx
    lea    R8, [R14+rax]
    lea    R9, [rsp+64+63]
    and    R9, ~63
%if %1
    add    R9, rax
%endif
    mov    rdx, [rbx+TW_SIG]
    mov    [rsp+ 8], rdx
    mov    rdx, [rbx+TW_LAST]
    mov    [rsp+16], rdx
    mov    rax, [rbx+TW_STATE]
    mov    rdx, [rax]
    mov    [rsp+24], rdx
    movzx  edx, word [rax+8]
    mov    [rsp+32], rdx
    mov    edx, [rbx+TW_ARG]
    mov    [rsp+40], rdx
    mov    edx, [rbx+TW_PSY]
    mov    [rsp+56], rdx
    mov    rdi, [rbx+TW_UNQUANT]
    mov    rsi, [rbx+TW_ZIGZAG]
    mov    edx, [rbx+TW_LAMBDA2]
    call   [rbx+TW_TRELLIS]
%endmacro

; trellis_dc_shortcut( eax = sign_coef, ecx = quant_coef, ... ) -> eax, 0 if
; quant_coef is 0: both candidates q-1 and q of q = max(|quant_coef|, 1), the
; lower score (q on a strict <). q >= 15 at .tw_big%2.
; clobbers rcx, rdx, rsi, rdi, R8-R11, [rsp+0..19]
%macro TW_DC 2 ; coef_weight2 table, label suffix
    mov    [rsp+16], ecx
    mov    edx, ecx
    neg    ecx
    cmovs  ecx, edx
    mov    edx, 1
    cmp    ecx, edx
    cmovl  ecx, edx
    ; ssd: d = sign_coef - ((SIGN( (unquant_mf[0]*level + 128) >> 8, sign_coef ) + 8) & ~15)
    mov    rdx, [rbx+TW_UNQUANT]
    mov    edx, [rdx]
    mov    R9d, edx
    imul   R9d, ecx
    mov    R10d, R9d
    sub    R10d, edx
    add    R9d, 128
    add    R10d, 128
    sar    R9d, 8
    sar    R10d, 8
    mov    edx, eax
    sar    edx, 31
    xor    R9d, edx
    xor    R10d, edx
    sub    R9d, edx
    sub    R10d, edx
    add    R9d, 8
    add    R10d, 8
    and    R9d, ~15
    and    R10d, ~15
    mov    R11d, eax
    sub    R11d, R9d
    sub    eax, R10d
    movsxd R11, R11d
    cdqe
    imul   R11, R11
    imul   rax, rax
    lea    R9, [%1]
    mov    R9d, [R9]
    imul   R11, R9
    imul   rax, R9
    mov    [rsp+8], R11
    mov    [rsp+0], rax
    ; bits: sig and last of position 0, coeff_abs_level_m1 ctx 1 and 5
    lea    R10, [cabac_entropy]
    mov    rsi, [rbx+TW_SIG]
    movzx  esi, byte [rsi]
    mov    rdi, [rbx+TW_LAST]
    movzx  edi, byte [rdi]
    xor    esi, 1
    xor    edi, 1
    movzx  esi, word [R10+rsi*2]
    movzx  edi, word [R10+rdi*2]
    add    esi, edi
    mov    rdi, [rbx+TW_STATE]
    movzx  eax, byte [rdi+1]
    movzx  edi, byte [rdi+5]
    lea    R11, [cabac_size_unary]
    lea    R11, [R11+rdi*2]
    xor    R8d, R8d
    xor    R9d, R9d
    cmp    ecx, 1
    seta   R8b
    cmp    ecx, 2
    seta   R9b
    xor    R8d, eax
    xor    R9d, eax
    movzx  R8d, word [R10+R8*2]
    movzx  R9d, word [R10+R9*2]
    add    R8d, esi
    add    R9d, esi
    cmp    ecx, 15
    jge .tw_big%2
    lea    eax, [rcx-1]
    shl    eax, 8
    movzx  eax, word [R11+rax]
    add    R8d, eax
    lea    eax, [rcx-2]
    xor    esi, esi
    test   eax, eax
    cmovs  eax, esi
    shl    eax, 8
    movzx  eax, word [R11+rax]
    add    R9d, eax
    cmp    ecx, 1
    cmove  R9d, esi
.tw_bits%2:
    mov    eax, [rbx+TW_LAMBDA2]
    imul   R8, rax
    imul   R9, rax
    shr    R8, CABAC_SIZE_BITS - LAMBDA_BITS
    shr    R9, CABAC_SIZE_BITS - LAMBDA_BITS
    add    R8, [rsp+8]
    add    R9, [rsp+0]
    lea    eax, [rcx-1]
    cmp    R8, R9
    cmovb  eax, ecx
    xor    eax, edx
    sub    eax, edx
    xor    ecx, ecx
    cmp    dword [rsp+16], 0
    cmove  eax, ecx
%endmacro

; levels >= 15: prefixes min( level-1, 14 ), suffixes bs_size_ue_big( level-15 )
%macro TW_DC_BIG 1
.tw_big%1:
    movzx  eax, word [R11+14*256]
    add    R8d, eax
    lea    eax, [rcx-14]
    bsr    eax, eax
    lea    eax, [rax*2+1]
    shl    eax, CABAC_SIZE_BITS
    add    R8d, eax
    lea    eax, [rcx-2]
    mov    esi, 14
    cmp    eax, esi
    cmovg  eax, esi
    shl    eax, 8
    movzx  eax, word [R11+rax]
    add    R9d, eax
    lea    eax, [rcx-15]
    test   eax, eax
    jz .tw_bits%1
    bsr    eax, eax
    lea    eax, [rax*2+1]
    shl    eax, CABAC_SIZE_BITS
    add    R9d, eax
    jmp .tw_bits%1
%endmacro

%if HIGH_BIT_DEPTH
    %define TW_LOAD mov
    %define TW_COEF dword
%else
    %define TW_LOAD movsx
    %define TW_COEF word
%endif

;-----------------------------------------------------------------------------
; int trellis_wrap_4x4x4( dctcoef dct[4][16], dctcoef orig[4][16], x264_trellis_wrap_t *p )
;-----------------------------------------------------------------------------
cglobal trellis_wrap_4x4x4, 3,15,6, TW_STACK
    mov    rbx, rdx
    mov    rbp, rdi
    mov    R14, rsi
    ; nonzero coefs, 16 bits per block in raster order
%if HIGH_BIT_DEPTH
    vmovdqu   ymm0, [rbp+  0]
    vpackssdw ymm0, ymm0, [rbp+ 32]
    vmovdqu   ymm1, [rbp+ 64]
    vpackssdw ymm1, ymm1, [rbp+ 96]
    vmovdqu   ymm2, [rbp+128]
    vpackssdw ymm2, ymm2, [rbp+160]
    vmovdqu   ymm3, [rbp+192]
    vpackssdw ymm3, ymm3, [rbp+224]
    vpacksswb ymm0, ymm0, ymm1
    vpacksswb ymm2, ymm2, ymm3
    vmovdqu   ymm4, [deinterleave_shufd]
    vpermd    ymm0, ymm4, ymm0
    vpermd    ymm1, ymm4, ymm2
%else
    vmovdqu   ymm0, [rbp+ 0]
    vpacksswb ymm0, ymm0, [rbp+32]
    vmovdqu   ymm1, [rbp+64]
    vpacksswb ymm1, ymm1, [rbp+96]
    vpermq    ymm0, ymm0, q3120
    vpermq    ymm1, ymm1, q3120
%endif
    vpxor     xmm2, xmm2, xmm2
    vpcmpeqb  ymm0, ymm0, ymm2
    vpcmpeqb  ymm1, ymm1, ymm2
    vpmovmskb eax, ymm0
    vpmovmskb ecx, ymm1
    shl       rcx, 32
    or        rax, rcx
    not       rax
    mov       rcx, [tw_acmask]
    and       rcx, rax
    ; per block: nonzero (bits 0-3), an ac level (bits 4-7)
    vmovq     xmm0, rax
    vpinsrq   xmm0, xmm0, rcx, 1
    vpcmpeqw  xmm0, xmm0, xmm2
    vpacksswb xmm0, xmm0, xmm0
    vpmovmskb eax, xmm0
    vzeroupper
    not       eax
    mov       R15d, eax
    shr       R15d, 4
    and       R15d, 15
    mov       ecx, R15d
    not       ecx
    and       eax, ecx
    and       eax, 15
    xor       R12d, R12d
    test      eax, eax
    jnz .dc
.dc_done:
    test      R15d, R15d
    jz .end
.block:
    bsf       R13d, R15d
    mov       esi, R13d
    shl       esi, TW_BLKSHIFT
    add       rsi, rbp
    TW_LEVELS
    TW_SCAN4
    bsr       ecx, eax
    mov       eax, R13d
    shl       eax, TW_BLKSHIFT
    TW_CALL
    mov       ecx, R13d
    shl       eax, cl
    or        R12d, eax
    lea       eax, [R15-1]
    and       R15d, eax
    jnz .block
.end:
    mov       eax, R12d
    RET

    ; dc-only blocks: rare
.dc:
    mov       R13d, eax
.dc_loop:
    bsf       ecx, R13d
    shl       ecx, TW_BLKSHIFT
    TW_LOAD   eax, TW_COEF [R14+rcx]
    TW_LOAD   ecx, TW_COEF [rbp+rcx]
    TW_DC     dct4_weight2_tab, 0
    bsf       ecx, R13d
    mov       edx, ecx
    shl       edx, TW_BLKSHIFT
%if HIGH_BIT_DEPTH
    mov       [rbp+rdx], eax
%else
    mov       [rbp+rdx], ax
%endif
    test      eax, eax
    setnz     al
    movzx     eax, al
    shl       eax, cl
    or        R12d, eax
    lea       eax, [R13-1]
    and       R13d, eax
    jnz .dc_loop
    jmp .dc_done
    TW_DC_BIG 0

;-----------------------------------------------------------------------------
; int trellis_wrap_4x4( dctcoef dct[16], dctcoef orig[16], x264_trellis_wrap_t *p )
; int trellis_wrap_8x8( dctcoef dct[64], dctcoef orig[64], x264_trellis_wrap_t *p )
;-----------------------------------------------------------------------------
%macro TW_ONE 1 ; num_coefs
cglobal trellis_wrap_%1x%1, 3,15,6, TW_STACK
    mov    rbx, rdx
    mov    rbp, rdi
    mov    R14, rsi
    ; an ac level?
%if HIGH_BIT_DEPTH
    vmovdqu   ymm0, [rbp]
    vpand     ymm0, ymm0, [tw_nodcd]
    vpor      ymm0, ymm0, [rbp+32]
%if %1 == 8
%assign i 64
%rep 6
    vpor      ymm0, ymm0, [rbp+i]
%assign i i+32
%endrep
%endif
%else
    vmovdqu   ymm0, [rbp]
    vpand     ymm0, ymm0, [tw_nodcw]
%if %1 == 8
    vpor      ymm0, ymm0, [rbp+32]
    vpor      ymm0, ymm0, [rbp+64]
    vpor      ymm0, ymm0, [rbp+96]
%endif
%endif
    vptest    ymm0, ymm0
    vzeroupper
    jz .dconly
    TW_LEVELS
    mov       rsi, rbp
%if %1 == 4
    TW_SCAN4
    bsr       ecx, eax
%else
    call      [rbx+TW_SCAN]
    TW_LEVELS
%if HIGH_BIT_DEPTH
    vmovdqa   ymm0, [rdi+  0]
    vpackssdw ymm0, ymm0, [rdi+ 32]
    vmovdqa   ymm1, [rdi+ 64]
    vpackssdw ymm1, ymm1, [rdi+ 96]
    vmovdqa   ymm2, [rdi+128]
    vpackssdw ymm2, ymm2, [rdi+160]
    vmovdqa   ymm3, [rdi+192]
    vpackssdw ymm3, ymm3, [rdi+224]
    vpacksswb ymm0, ymm0, ymm1
    vpacksswb ymm2, ymm2, ymm3
    vmovdqu   ymm4, [deinterleave_shufd]
    vpermd    ymm0, ymm4, ymm0
    vpermd    ymm1, ymm4, ymm2
%else
    vmovdqa   ymm0, [rdi+ 0]
    vpacksswb ymm0, ymm0, [rdi+32]
    vmovdqa   ymm1, [rdi+64]
    vpacksswb ymm1, ymm1, [rdi+96]
    vpermq    ymm0, ymm0, q3120
    vpermq    ymm1, ymm1, q3120
%endif
    vpxor     xmm2, xmm2, xmm2
    vpcmpeqb  ymm0, ymm0, ymm2
    vpcmpeqb  ymm1, ymm1, ymm2
    vpmovmskb eax, ymm0
    vpmovmskb ecx, ymm1
    vzeroupper
    shl       rcx, 32
    or        rax, rcx
    not       rax
    bsr       rcx, rax
%endif
    xor       eax, eax
    TW_CALL
    RET

.dconly:
    TW_LOAD   eax, TW_COEF [R14]
    TW_LOAD   ecx, TW_COEF [rbp]
%if %1 == 4
    TW_DC     dct4_weight2_tab, 0
%else
    TW_DC     dct8_weight2_tab, 0
%endif
%if HIGH_BIT_DEPTH
    mov       [rbp], eax
%else
    mov       [rbp], ax
%endif
    test      eax, eax
    setnz     al
    movzx     eax, al
    RET
    TW_DC_BIG 0
%endmacro

TW_ONE 4
TW_ONE 8

;-----------------------------------------------------------------------------
; int trellis_wrap_dc4/dc8/dc16( dctcoef *dct, dctcoef *orig, x264_trellis_wrap_t *p )
; at least one nonzero level
;-----------------------------------------------------------------------------
%macro TW_DCN 1 ; num_coefs
cglobal trellis_wrap_dc%1, 3,15,6, TW_STACK
    mov    rbx, rdx
    mov    rbp, rdi
    mov    R14, rsi
    TW_LEVELS
%if %1 == 16
    mov    rsi, rbp
    TW_SCAN4
%elif %1 == 8
%if HIGH_BIT_DEPTH
    vmovdqu   ymm1, [tw_zz2x4d]
    vpermd    ymm0, ymm1, [rbp]
    vmovdqa   [rdi], ymm0
    vpxor     xmm1, xmm1, xmm1
    vpcmpeqd  ymm0, ymm0, ymm1
    vmovmskps eax, ymm0
%else
    vmovdqu   xmm0, [rbp]
    vpshufb   xmm0, xmm0, [tw_zz2x4w]
    vmovdqa   [rdi], xmm0
    vpxor     xmm1, xmm1, xmm1
    vpcmpeqw  xmm0, xmm0, xmm1
    vpacksswb xmm0, xmm0, xmm0
    vpmovmskb eax, xmm0
%endif
    vzeroupper
    not       eax
    and       eax, 0xff
%else
%if HIGH_BIT_DEPTH
    vmovdqu   xmm0, [rbp]
    vmovdqa   [rdi], xmm0
    vpxor     xmm1, xmm1, xmm1
    vpcmpeqd  xmm0, xmm0, xmm1
    vmovmskps eax, xmm0
%else
    vmovq     xmm0, [rbp]
    vmovq     [rdi], xmm0
    vpxor     xmm1, xmm1, xmm1
    vpcmpeqw  xmm0, xmm0, xmm1
    vpacksswb xmm0, xmm0, xmm0
    vpmovmskb eax, xmm0
%endif
    not       eax
    and       eax, 15
%endif
    bsr       ecx, eax
    xor       eax, eax
    TW_CALL
    RET
%endmacro

TW_DCN 4
TW_DCN 8
TW_DCN 16

;=============================================================================
; trellis_wrap avx512: the same wrappers with the zigzags in vpermw / vpermi2w
; (8-bit) and vpermd / vpermi2d (10-bit) and the nonzero masks from vptestm:
; the zero tests are kortest of the masks, last_nnz the bsr of the scan-order
; mask. m0-m5 are regs 16-21, so the trellis_cabac_* calls need no vzeroupper.
; zmm, and a ymm set (_ymm: 4x4x4, 10-bit 4x4 / dc16, 8-bit 8x8; the others
; are ymm or narrower already, the 10-bit 8x8 stays zmm).
;=============================================================================
%define TW512_STACK TW_STACK+64
%define TW_S        TW_STACK ; 4x4x4: the scan-order nonzero mask, 16 bits per block

; the stack aligned as ALLOC_STACK aligns it
%macro TW512_PROLOGUE 0
    %assign tw_pad TW512_STACK + ((-TW512_STACK-stack_offset-gprsize) & (STACK_ALIGNMENT-1))
    sub    rsp, tw_pad
    mov    rbx, rdx
    mov    rbp, rdi
    mov    R14, rsi
%endmacro

%macro TW512_RET 0
    add    rsp, tw_pad
    RET
%endmacro

; 4x4 zigzag of the raster block in m0 (zmm 10-bit), m0-m1 (ymm 10-bit) or
; ym0 (8-bit) to [rdi]; ecx = last nonzero scan position
%macro TW512_SCAN4 0
    mov    eax, [rbx+TW_FIELD]
    shl    eax, 6
    TW_LEVELS
%if HIGH_BIT_DEPTH
    lea    R8, [tw_zz4]
%if mmsize == 64
    movu   m2, [R8+rax]
    vpermd m2, m2, m0
    mova   [rdi], m2
    vptestmd k1, m2, m2
%else
    movu   m2, [R8+rax]
    movu   m3, [R8+rax+32]
    vpermi2d m2, m0, m1
    vpermi2d m3, m0, m1
    mova   [rdi], m2
    mova   [rdi+32], m3
    vptestmd k1, m2, m2
    vptestmd k2, m3, m3
    kunpckbw k1, k2, k1
%endif
%else
    lea    R8, [tw512_zz4w]
    movu   ym2, [R8+rax]
    vpermw ym2, ym2, ym0
    mova   [rdi], ym2
    vptestmw k1, ym2, ym2
%endif
    kmovd  ecx, k1
    bsr    ecx, ecx
%endmacro

; dc-only or all-zero block: trellis_dc_shortcut
%macro TW512_DCONLY 1 ; coef_weight2 table
    TW_LOAD   eax, TW_COEF [R14]
    TW_LOAD   ecx, TW_COEF [rbp]
    TW_DC     %1, 0
%if HIGH_BIT_DEPTH
    mov       [rbp], eax
%else
    mov       [rbp], ax
%endif
    test      eax, eax
    setnz     al
    movzx     eax, al
    TW512_RET
    TW_DC_BIG 0
%endmacro

;-----------------------------------------------------------------------------
; int trellis_wrap_4x4x4( dctcoef dct[4][16], dctcoef orig[4][16], x264_trellis_wrap_t *p )
;-----------------------------------------------------------------------------
; 10-bit ymm: block %1 in 2 ymm, its 16-bit mask in %2
%macro TW512Y_BLOCKD 2
    movu      m0, [rbp+64*%1]
    movu      m1, [rbp+64*%1+32]
    movu      m2, [R8]
    movu      m3, [R8+32]
    vpermi2d  m2, m0, m1
    vpermi2d  m3, m0, m1
    mova      [rdi+64*%1], m2
    mova      [rdi+64*%1+32], m3
    vptestmd  k5, m2, m2
    vptestmd  k6, m3, m3
    kunpckbw  %2, k6, k5
%endmacro

%macro TW512_4X4X4 1 ; name
cglobal %1, 3,15,6
    TW512_PROLOGUE
    ; the 4 blocks zigzagged, their 64-bit scan-order nonzero mask
    mov       eax, [rbx+TW_FIELD]
    shl       eax, 6
    TW_LEVELS
%if HIGH_BIT_DEPTH
    lea       R8, [tw_zz4]
%if mmsize == 64
    movu      m4, [R8+rax]
    vpermd    m0, m4, [rbp+  0]
    vpermd    m1, m4, [rbp+ 64]
    vpermd    m2, m4, [rbp+128]
    vpermd    m3, m4, [rbp+192]
    mova      [rdi+  0], m0
    mova      [rdi+ 64], m1
    mova      [rdi+128], m2
    mova      [rdi+192], m3
    vptestmd  k1, m0, m0
    vptestmd  k2, m1, m1
    vptestmd  k3, m2, m2
    vptestmd  k4, m3, m3
%else
    add       R8, rax
    TW512Y_BLOCKD 0, k1
    TW512Y_BLOCKD 1, k2
    TW512Y_BLOCKD 2, k3
    TW512Y_BLOCKD 3, k4
%endif
    kunpckwd  k1, k2, k1
    kunpckwd  k3, k4, k3
    kunpckdq  k1, k3, k1
%else
    lea       R8, [tw512_zz4w]
    movu      m4, [R8+rax]
%if mmsize == 64
    vpermw    m0, m4, [rbp+ 0]
    vpermw    m1, m4, [rbp+64]
    mova      [rdi+ 0], m0
    mova      [rdi+64], m1
    vptestmw  k1, m0, m0
    vptestmw  k2, m1, m1
%else
    vpermw    m0, m4, [rbp+ 0]
    vpermw    m1, m4, [rbp+32]
    vpermw    m2, m4, [rbp+64]
    vpermw    m3, m4, [rbp+96]
    mova      [rdi+ 0], m0
    mova      [rdi+32], m1
    mova      [rdi+64], m2
    mova      [rdi+96], m3
    vptestmw  k1, m0, m0
    vptestmw  k2, m1, m1
    vptestmw  k3, m2, m2
    vptestmw  k4, m3, m3
    kunpckwd  k1, k2, k1
    kunpckwd  k2, k4, k3
%endif
    kunpckdq  k1, k2, k1
%endif
    ; per block (a word of the mask): an ac level, dc only
    kmovq     rax, k1
    mov       [rsp+TW_S], rax
    vmovq     xm0, rax
    vptestmw  k2, xm0, [pw_m2]
    vpcmpeqw  k3, xm0, [pw_1]
    kmovd     R15d, k2
    kmovd     eax, k3
    xor       R12d, R12d
    test      eax, eax
    jnz .dc
.dc_done:
    test      R15d, R15d
    jz .end
.block:
    bsf       R13d, R15d
    movzx     ecx, word [rsp+TW_S+R13*2]
    bsr       ecx, ecx
    mov       eax, R13d
    shl       eax, TW_BLKSHIFT
    TW_CALL   1
    mov       ecx, R13d
    shl       eax, cl
    or        R12d, eax
    lea       eax, [R15-1]
    and       R15d, eax
    jnz .block
.end:
    mov       eax, R12d
    TW512_RET

    ; dc-only blocks: rare
.dc:
    mov       R13d, eax
.dc_loop:
    bsf       ecx, R13d
    shl       ecx, TW_BLKSHIFT
    TW_LOAD   eax, TW_COEF [R14+rcx]
    TW_LOAD   ecx, TW_COEF [rbp+rcx]
    TW_DC     dct4_weight2_tab, 0
    bsf       ecx, R13d
    mov       edx, ecx
    shl       edx, TW_BLKSHIFT
%if HIGH_BIT_DEPTH
    mov       [rbp+rdx], eax
%else
    mov       [rbp+rdx], ax
%endif
    test      eax, eax
    setnz     al
    movzx     eax, al
    shl       eax, cl
    or        R12d, eax
    lea       eax, [R13-1]
    and       R13d, eax
    jnz .dc_loop
    jmp .dc_done
    TW_DC_BIG 0
%endmacro

;-----------------------------------------------------------------------------
; int trellis_wrap_4x4( dctcoef dct[16], dctcoef orig[16], x264_trellis_wrap_t *p )
;-----------------------------------------------------------------------------
%macro TW512_4X4 1 ; name
cglobal %1, 3,15,6
    TW512_PROLOGUE
%if HIGH_BIT_DEPTH && mmsize == 64
    movu      m0, [rbp]
    vptestmd  k1, m0, [tw512_nodc]
    kortestw  k1, k1
%elif HIGH_BIT_DEPTH
    movu      m0, [rbp]
    movu      m1, [rbp+32]
    vptestmd  k1, m0, [tw512_nodc]
    vptestmd  k2, m1, m1
    kortestb  k1, k2
%else
    movu      ym0, [rbp]
    vptestmw  k1, ym0, [tw512_nodc]
    kortestw  k1, k1
%endif
    jz .dconly
    TW512_SCAN4
    xor       eax, eax
    TW_CALL
    TW512_RET
.dconly:
    TW512_DCONLY dct4_weight2_tab
%endmacro

;-----------------------------------------------------------------------------
; int trellis_wrap_8x8( dctcoef dct[64], dctcoef orig[64], x264_trellis_wrap_t *p )
;-----------------------------------------------------------------------------
; 4 registers of coefs (10-bit zmm, 8-bit ymm): output %1 of the zigzag is the
; 2-register permute of coefs 0-31 or 32-63, bit 5 picks; %2 its nonzero mask
%macro TW512_ZZ8Q 2
    movu      m4, [R8+mmsize*%1]
    movu      m5, [R8+mmsize*%1]
%if HIGH_BIT_DEPTH
    vpermi2d  m4, m0, m1
    vpermi2d  m5, m2, m3
    kmovw     k1, [R9+2*%1]
    vmovdqa32 m4 {k1}, m5
    mova      [rdi+mmsize*%1], m4
    vptestmd  %2, m4, m4
%else
    vpermi2w  m4, m0, m1
    vpermi2w  m5, m2, m3
    kmovw     k1, [R9+2*%1]
    vmovdqu16 m4 {k1}, m5
    mova      [rdi+mmsize*%1], m4
    vptestmw  %2, m4, m4
%endif
%endmacro

%macro TW512_8X8 1 ; name
cglobal %1, 3,15,6
    TW512_PROLOGUE
    ; an ac level?
%if mmsize*4 == 64*SIZEOF_DCTCOEF
    movu      m0, [rbp+mmsize*0]
    movu      m1, [rbp+mmsize*1]
    movu      m2, [rbp+mmsize*2]
    movu      m3, [rbp+mmsize*3]
%if HIGH_BIT_DEPTH
    vptestmd  k1, m0, [tw512_nodc]
%else
    vptestmw  k1, m0, [tw512_nodc]
%endif
    vpord     m4, m1, m2
    vpord     m4, m4, m3
%if HIGH_BIT_DEPTH
    vptestmd  k2, m4, m4
    kortestw  k1, k2
%else
    vptestmw  k2, m4, m4
    kortestw  k1, k2
%endif
%else
    movu      m0, [rbp+ 0]
    movu      m1, [rbp+64]
    vptestmw  k1, m0, [tw512_nodc]
    vptestmw  k2, m1, m1
    kortestd  k1, k2
%endif
    jz .dconly
    mov       eax, [rbx+TW_FIELD]
    TW_LEVELS
%if mmsize*4 == 64*SIZEOF_DCTCOEF
    lea       R9, [tw512_zz8k]
    lea       R9, [R9+rax*8]
    shl       eax, 5+HIGH_BIT_DEPTH+2
    lea       R8, [tw512_zz8]
    add       R8, rax
    TW512_ZZ8Q 0, k2
    TW512_ZZ8Q 1, k3
    TW512_ZZ8Q 2, k4
    TW512_ZZ8Q 3, k5
    kunpckwd  k2, k3, k2
    kunpckwd  k4, k5, k4
    kunpckdq  k2, k4, k2
    kmovq     rcx, k2
%else
    shl       eax, 7
    lea       R8, [tw512_zz8]
    movu      m2, [R8+rax]
    movu      m3, [R8+rax+64]
    vpermi2w  m2, m0, m1
    vpermi2w  m3, m0, m1
    mova      [rdi+ 0], m2
    mova      [rdi+64], m3
    vptestmw  k1, m2, m2
    vptestmw  k2, m3, m3
    kunpckdq  k1, k2, k1
    kmovq     rcx, k1
%endif
    bsr       rcx, rcx
    xor       eax, eax
    TW_CALL
    TW512_RET
.dconly:
    TW512_DCONLY dct8_weight2_tab
%endmacro

;-----------------------------------------------------------------------------
; int trellis_wrap_dc4/dc8/dc16( dctcoef *dct, dctcoef *orig, x264_trellis_wrap_t *p )
; at least one nonzero level
;-----------------------------------------------------------------------------
%macro TW512_DCN 2 ; name, num_coefs
cglobal %1, 3,15,6
    TW512_PROLOGUE
%if %2 == 16
%if HIGH_BIT_DEPTH && mmsize == 64
    movu      m0, [rbp]
%elif HIGH_BIT_DEPTH
    movu      m0, [rbp]
    movu      m1, [rbp+32]
%else
    movu      ym0, [rbp]
%endif
    TW512_SCAN4
%else
    TW_LEVELS
%if %2 == 8
%if HIGH_BIT_DEPTH
    movu      ym1, [tw_zz2x4d]
    vpermd    ym1, ym1, [rbp]
    mova      [rdi], ym1
    vptestmd  k1, ym1, ym1
%else
    movu      xm1, [rbp]
    vpshufb   xm1, xm1, [tw_zz2x4w]
    mova      [rdi], xm1
    vptestmw  k1, xm1, xm1
%endif
%else
%if HIGH_BIT_DEPTH
    movu      xm1, [rbp]
    mova      [rdi], xm1
    vptestmd  k1, xm1, xm1
%else
    vmovq     xm1, [rbp]
    vmovq     [rdi], xm1
    vptestmw  k1, xm1, xm1
%endif
%endif
    kmovd     ecx, k1
    bsr       ecx, ecx
%endif
    xor       eax, eax
    TW_CALL
    TW512_RET
%endmacro

INIT_ZMM avx512
TW512_4X4X4 trellis_wrap_4x4x4
TW512_4X4   trellis_wrap_4x4
TW512_8X8   trellis_wrap_8x8
TW512_DCN   trellis_wrap_dc4, 4
TW512_DCN   trellis_wrap_dc8, 8
TW512_DCN   trellis_wrap_dc16, 16

INIT_YMM avx512
TW512_4X4X4 trellis_wrap_4x4x4_ymm
%if HIGH_BIT_DEPTH
TW512_4X4   trellis_wrap_4x4_ymm
TW512_DCN   trellis_wrap_dc16_ymm, 16
%else
TW512_8X8   trellis_wrap_8x8_ymm
%endif

%endif ; UNIX64
