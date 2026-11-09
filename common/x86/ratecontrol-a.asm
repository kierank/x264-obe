;*****************************************************************************
;* ratecontrol-a.asm: x86 per-macroblock ratecontrol and mbtree tails
;*****************************************************************************
;* Copyright (C) 2026 Open Broadcast Systems Ltd
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
;*****************************************************************************

; Float steps are in the C order, one rounding each (no fma), so the results
; equal a -fno-fast-math -ffp-contract=off build of the C.

%include "x86inc.asm"
%include "x86util.asm"

SECTION_RODATA 32

rc_pf_m64_6:  times 8 dd 0xc12aaaab ; -64.f/6.f
rc_pf_512_5:  times 8 dd 0x44002000 ; 512.5f
rc_pd_1024:   times 8 dd 1024
rc_pd_256:    times 8 dd 256
rc_pd_128:    times 8 dd 128
rc_pd_ffff:   times 8 dd 0xffff
rc_pd_3fff:   times 8 dd 0x3fff
rc_pd_63:     times 8 dd 63
rc_pd_127:    times 8 dd 127
rc_pd_7f:     times 8 dd 0x7f
rc_pd_8:      times 8 dd 8
rc_lanes:     times 8 dd -1                ; the first n lanes: rc_lanes+32-4*n
              times 8 dd 0
rc_pd_1:      dd 1
rc_pd_32:     dd 32
rc_pd_64:     dd 64

SECTION .text

cextern_common exp2_lut
cextern_common log2_lut

; x264_exp2fix8 of the floats in %1, as dwords; 65536 where it is 0xffff.
; avx512icl: %3 = exp2_lut, k1 = byte 0 of each dword
%macro EXP2FIX8_ZMM 3 ; dst/src, tmp, lut
    vmulps      %1, %1, [rc_pf_m64_6] {1to16}
    vaddps      %1, %1, [rc_pf_512_5] {1to16}
    vcvttps2dq  %1, %1
    vpminsd     %1, %1, [rc_pd_1024] {1to16} ; > 1023: lut[0] << 16 >> 8
    vpsrad      %2, %1, 6                    ; < 0: shift >= 32, so 0
    vpermb      %1 {k1}{z}, %1, %3
    vpord       %1, %1, [rc_pd_256] {1to16}
    vpsllvd     %1, %1, %2
    vpsrld      %1, %1, 8
%endmacro

; x264_log2 of the nonzero dwords in %2 (clobbered); m8-m15 = log2_lut
%macro LOG2_ZMM 4 ; dst, src, tmp, tmp
    vcvtudq2ps  %2, %2, {rz-sae}             ; leading 24 bits, no carry into the exponent
    vgetexpps   %1, %2                       ; 31-lz
    vpsrld      %2, %2, 16                   ; lut index in bits 0-6
    vptestmd    k5, %2, [rc_pd_32] {1to16}
    vptestmd    k6, %2, [rc_pd_64] {1to16}
    vmovdqa32   %3, %2
    vpermi2ps   %3, m8, m9
    vmovdqa32   %4, %2
    vpermi2ps   %4, m10, m11
    vmovaps     %3 {k5}, %4
    vmovdqa32   %4, %2
    vpermi2ps   %4, m12, m13
    vpermi2ps   %2, m14, m15
    vmovaps     %4 {k5}, %2
    vmovaps     %3 {k6}, %4
    vaddps      %1, %3, %1
%endmacro

%macro LOAD_LOG2_LUT 0
    vmovups     m8,  [log2_lut+0*64]
    vmovups     m9,  [log2_lut+1*64]
    vmovups     m10, [log2_lut+2*64]
    vmovups     m11, [log2_lut+3*64]
    vmovups     m12, [log2_lut+4*64]
    vmovups     m13, [log2_lut+5*64]
    vmovups     m14, [log2_lut+6*64]
    vmovups     m15, [log2_lut+7*64]
%endmacro

; k2 = (1 << %1) - 1, %1 in 1..15
%macro TAIL_MASK 2 ; count, tmp
    mov         %2, -1
    bzhi        %2, %2, %1
    kmovw       k2, %2
%endmacro

;-----------------------------------------------------------------------------
; int mbtree_cost_scale( uint16_t *lowres_costs, float *qp_offset, int len )
; sum of ((lowres_costs[i] & LOWRES_COST_MASK) * x264_exp2fix8( qp_offset[i] ) + 128) >> 8
;-----------------------------------------------------------------------------
%macro COST_SCALE_ZMM 0 ; m1 = costs, m2 = qp
    vpandd      m1, m1, [rc_pd_3fff] {1to16}
    EXP2FIX8_ZMM m2, m3, m7
    vpminud     m2, m2, [rc_pd_ffff] {1to16}
    vpmulld     m1, m1, m2
    vpaddd      m1, m1, [rc_pd_128] {1to16}
    vpsrad      m1, m1, 8
    vpaddd      m0, m0, m1
%endmacro

INIT_ZMM avx512icl
cglobal mbtree_cost_scale, 3,4
    vmovdqu8    m7, [exp2_lut]
    mov          r3, 0x1111111111111111
    kmovq       k1, r3
    vpxord      m0, m0, m0
    sub         r2d, 16
    jl .tail
.loop:
    vpmovzxwd   m1, [r0]
    vmovups     m2, [r1]
    COST_SCALE_ZMM
    add          r0, 32
    add          r1, 64
    sub         r2d, 16
    jge .loop
.tail:
    add         r2d, 16
    jz .end
    TAIL_MASK   r2d, r3d
    vmovdqu16   ym1 {k2}{z}, [r0]
    vpmovzxwd   m1, ym1
    vmovups     m2 {k2}{z}, [r1]
    COST_SCALE_ZMM
.end:
    vextracti64x4 ym1, m0, 1
    vpaddd      ym0, ym0, ym1
    vextracti32x4 xm1, ym0, 1
    vpaddd      xm0, xm0, xm1
    vpshufd     xm1, xm0, q1032
    vpaddd      xm0, xm0, xm1
    vpshufd     xm1, xm0, q2301
    vpaddd      xm0, xm0, xm1
    vmovd       eax, xm0
    RET

; avx2 EXP2FIX8_ZMM: exp2_lut in four pshufb tables, m12-m15
%macro EXP2FIX8_YMM 6 ; dst/src, tmp x5
    mulps       %1, [rc_pf_m64_6]
    addps       %1, [rc_pf_512_5]
    cvttps2dq   %1, %1
    pminsd      %1, [rc_pd_1024]
    psrad       %2, %1, 6
    pand        %1, [rc_pd_63]
    pslld       %3, %1, 3                    ; index bit 4 -> bit 7
    pshufb      %4, m12, %1                  ; bytes 1-3 take exp2_lut[0] = 0
    pshufb      %5, m13, %1
    pblendvb    %4, %5, %3
    pshufb      %5, m14, %1
    pshufb      %6, m15, %1
    pblendvb    %5, %6, %3
    pslld       %3, %1, 2                    ; index bit 5 -> bit 7
    pblendvb    %4, %5, %3
    por         %4, [rc_pd_256]
    vpsllvd     %1, %4, %2
    psrld       %1, 8
%endmacro

%macro LOAD_EXP2_LUT_YMM 0
    vbroadcasti128 m12, [exp2_lut+ 0]
    vbroadcasti128 m13, [exp2_lut+16]
    vbroadcasti128 m14, [exp2_lut+32]
    vbroadcasti128 m15, [exp2_lut+48]
%endmacro

; avx2 LOG2_ZMM: the float of x is exact (x >= 2^24 shifted down 8 first), so its
; exponent is 31-lz less the shift and its mantissa bits 22-16 the lut index.
; %2 nonzero, clobbered; %5 = log2_lut; small: %2 < 2^24
%macro LOG2_YMM 5-6 0 ; dst, src, tmp, tmp, lut, small
%if %6 == 0
    psrld       %3, %2, 24
    pxor        %4, %4
    pcmpeqd     %3, %4
    pandn       %3, [rc_pd_8]                ; the shift
    vpsrlvd     %2, %2, %3
    psubd       %3, [rc_pd_127]
%endif
    cvtdq2ps    %2, %2
    psrld       %4, %2, 23
%if %6 == 0
    paddd       %4, %3
%else
    psubd       %4, [rc_pd_127]
%endif
    psrld       %2, 16
    pand        %2, [rc_pd_7f]
    pcmpeqd     %3, %3
    pxor        %1, %1
    vgatherdps  %1, [%5+%2*4], %3
    cvtdq2ps    %4, %4
    addps       %1, %4
%endmacro

%macro COST_SCALE_YMM 0 ; m1 = costs, m2 = qp
    pand        m1, [rc_pd_3fff]
    EXP2FIX8_YMM m2, m3, m4, m5, m6, m7
    pminud      m2, [rc_pd_ffff]
    pmulld      m1, m2
    paddd       m1, [rc_pd_128]
    psrad       m1, 8
    paddd       m0, m1
%endmacro

INIT_YMM avx2
cglobal mbtree_cost_scale, 3,5,16, 64
    LOAD_EXP2_LUT_YMM
    pxor        m0, m0
    sub         r2d, 8
    jl .tail
.loop:
    pmovzxwd    m1, [r0]
    movu        m2, [r1]
    COST_SCALE_YMM
    add          r0, 16
    add          r1, 32
    sub         r2d, 8
    jge .loop
.tail:
    add         r2d, 8
    jz .end
    pxor        m1, m1                       ; the rest of the row through the stack, 0 past it
    movu   [rsp+ 0], m1
    movu   [rsp+32], xm1
    xor         r3d, r3d
.copy:
    movzx       r4d, word [r0+r3*2]
    mov  [rsp+32+r3*2], r4w
    mov         r4d, [r1+r3*4]
    mov   [rsp+r3*4], r4d
    inc         r3d
    cmp         r3d, r2d
    jl .copy
    pmovzxwd    m1, [rsp+32]
    movu        m2, [rsp]
    COST_SCALE_YMM
.end:
    vextracti128 xm1, m0, 1
    paddd       xm0, xm1
    pshufd      xm1, xm0, q1032
    paddd       xm0, xm1
    pshufd      xm1, xm0, q2301
    paddd       xm0, xm1
    movd        eax, xm0
    RET

;-----------------------------------------------------------------------------
; void mbtree_finish( float *qp_offset, float *qp_offset_aq, uint16_t *intra_costs, uint16_t *inv_qscales,
;                     uint16_t *propagate_costs, float *params, int fps_factor, int len )
; params: strength, weightdelta
;-----------------------------------------------------------------------------
%macro MBTREE_FINISH_ZMM 1 ; tail
%if %1
    vmovdqu16   ym0 {k2}{z}, [r2]
    vmovdqu16   ym1 {k2}{z}, [r3]
    vpmovzxwd   m0, ym0
    vpmovzxwd   m1, ym1
%else
    vpmovzxwd   m0, [r2]
    vpmovzxwd   m1, [r3]
%endif
    vpmulld     m0, m0, m1
    vpaddd      m0, m0, [rc_pd_128] {1to16}
    vpsrad      m0, m0, 8                    ; intra_cost, 0 past the row
    vptestmd    k7, m0, m0
%if %1
    vmovdqu16   ym1 {k2}{z}, [r4]
    vpmovzxwd   m1, ym1
%else
    vpmovzxwd   m1, [r4]
%endif
    vpmulld     m1, m1, m6
    vpaddd      m1, m1, [rc_pd_128] {1to16}
    vpsrad      m1, m1, 8                    ; propagate_cost
    vpaddd      m1, m1, m0
    LOG2_ZMM    m2, m1, m3, m4
    LOG2_ZMM    m5, m0, m3, m4
    vsubps      m2, m2, m5
    vaddps      m2, m2, [r5+4] {1to16}       ; + weightdelta
    vmulps      m2, m2, [r5] {1to16}         ; * strength
%if %1
    vmovups     m1 {k2}{z}, [r1]
%else
    vmovups     m1, [r1]
%endif
    vsubps      m1, m1, m2
    vmovups     [r0] {k7}, m1
%endmacro

INIT_ZMM avx512
cglobal mbtree_finish, 8,9
    LOAD_LOG2_LUT
    vpbroadcastd m6, r6d
    sub         r7d, 16
    jl .tail
.loop:
    MBTREE_FINISH_ZMM 0
    add          r0, 64
    add          r1, 64
    add          r2, 32
    add          r3, 32
    add          r4, 32
    sub         r7d, 16
    jge .loop
.tail:
    add         r7d, 16
    jz .end
    TAIL_MASK   r7d, r8d
    MBTREE_FINISH_ZMM 1
.end:
    RET

; avx2: intra_cost, propagate_cost < 2^23 where the C's int products don't
; overflow, so LOG2_YMM small. m8 = strength, m9 = weightdelta, m10 = fps_factor,
; m11 = pd_128, m13 = 0, r9 = log2_lut; tail: the rest of the row's costs on
; the stack (0 past it), m7 = its lanes
%macro MBTREE_FINISH_YMM 1 ; tail
%if %1
    pmovzxwd    m0, [rsp]
    pmovzxwd    m1, [rsp+16]
%else
    pmovzxwd    m0, [r2+r8*2]
    pmovzxwd    m1, [r3+r8*2]
%endif
    pmulld      m0, m1
    paddd       m0, m11
    psrad       m0, 8                        ; intra_cost
%if %1
    pmovzxwd    m1, [rsp+32]
%else
    pmovzxwd    m1, [r4+r8*2]
%endif
    pmulld      m1, m10
    paddd       m1, m11
    psrad       m1, 8                        ; propagate_cost
    paddd       m1, m0
    pcmpeqd     m6, m0, m13                  ; intra_cost == 0: unchanged
    LOG2_YMM    m2, m1, m3, m4, r9, 1
    LOG2_YMM    m5, m0, m3, m4, r9, 1
    subps       m2, m5
    addps       m2, m9                       ; + weightdelta
    mulps       m2, m8                       ; * strength
%if %1
    vmaskmovps  m1, m7, [r1+r8*4]
    subps       m1, m2
    pandn       m6, m7
    vmaskmovps  [r0+r8*4], m6, m1
%else
    movu        m1, [r1+r8*4]
    subps       m1, m2
    vblendvps   m1, m1, [r0+r8*4], m6
    movu        [r0+r8*4], m1
%endif
%endmacro

INIT_YMM avx2
cglobal mbtree_finish, 8,11,14, 48
    vbroadcastss m8, [r5]
    vbroadcastss m9, [r5+4]
    movd        xm10, r6d
    vpbroadcastd m10, xm10
    mova        m11, [rc_pd_128]
    pxor        m13, m13
    lea          r9, [log2_lut]
    xor         r8d, r8d
    sub         r7d, 8
    jl .tail
.loop:
    MBTREE_FINISH_YMM 0
    add         r8d, 8
    sub         r7d, 8
    jge .loop
.tail:
    add         r7d, 8
    jz .end
    pxor        xm0, xm0
    mova   [rsp+ 0], xm0
    mova   [rsp+16], xm0
    mova   [rsp+32], xm0
    lea          r2, [r2+r8*2]
    lea          r3, [r3+r8*2]
    lea          r4, [r4+r8*2]
    xor         r5d, r5d
.copy:
    movzx       r6d, word [r2+r5*2]
    mov  [rsp+ 0+r5*2], r6w
    movzx       r6d, word [r3+r5*2]
    mov  [rsp+16+r5*2], r6w
    movzx       r6d, word [r4+r5*2]
    mov  [rsp+32+r5*2], r6w
    inc         r5d
    cmp         r5d, r7d
    jl .copy
    neg          r7
    lea         r10, [rc_lanes+32]
    movu         m7, [r10+r7*4]
    MBTREE_FINISH_YMM 1
.end:
    RET

;-----------------------------------------------------------------------------
; void aq_variance_tail( float *qp_offset, float *qp_offset_aq, uint16_t *inv_qscale, uint32_t *energy,
;                        float *quant_offsets, float *params, int len )
; params: strength, bias; inv_qscale and quant_offsets may be NULL
;-----------------------------------------------------------------------------
%macro AQ_VARIANCE_ZMM 1 ; tail
%if %1
    vmovdqu32   m0 {k2}{z}, [r3+r7*4]
%else
    vmovdqu32   m0, [r3+r7*4]
%endif
    vpmaxud     m0, m0, [rc_pd_1] {1to16}
    LOG2_ZMM    m1, m0, m2, m3
    vsubps      m1, m1, [r5+4] {1to16}       ; - bias
    vmulps      m1, m1, [r5] {1to16}         ; * strength
    test         r4, r4
    jz %%no_offsets
%if %1
    vmovups     m2 {k2}{z}, [r4+r7*4]
    vaddps      m1, m1, m2
%else
    vaddps      m1, m1, [r4+r7*4]
%endif
%%no_offsets:
%if %1
    vmovups     [r0+r7*4] {k2}, m1
    vmovups     [r1+r7*4] {k2}, m1
%else
    vmovups     [r0+r7*4], m1
    vmovups     [r1+r7*4], m1
%endif
    test         r2, r2
    jz %%no_qscale
    EXP2FIX8_ZMM m1, m2, m7
%if %1
    vpmovusdw   [r2+r7*2] {k2}, m1           ; 65536 -> 0xffff
%else
    vpmovusdw   [r2+r7*2], m1
%endif
%%no_qscale:
%endmacro

INIT_ZMM avx512icl
cglobal aq_variance_tail, 7,9
    LOAD_LOG2_LUT
    vmovdqu8    m7, [exp2_lut]
    mov          r7, 0x1111111111111111
    kmovq       k1, r7
    xor         r7d, r7d
    sub         r6d, 16
    jl .tail
.loop:
    AQ_VARIANCE_ZMM 0
    add         r7d, 16
    sub         r6d, 16
    jge .loop
.tail:
    add         r6d, 16
    jz .end
    TAIL_MASK   r6d, r8d
    AQ_VARIANCE_ZMM 1
.end:
    RET

; avx2: m8 = strength, m9 = bias, m10 = pd_1, r8 = log2_lut; tail: r6d < 8 lanes,
; m7 = their mask
%macro AQ_VARIANCE_YMM 1 ; tail
%if %1
    vpmaskmovd  m0, m7, [r3+r7*4]
%else
    movu        m0, [r3+r7*4]
%endif
    pmaxud      m0, m10
    LOG2_YMM    m1, m0, m2, m3, r8
    subps       m1, m9                       ; - bias
    mulps       m1, m8                       ; * strength
    test         r4, r4
    jz %%no_offsets
%if %1
    vmaskmovps  m2, m7, [r4+r7*4]
    addps       m1, m2
%else
    addps       m1, [r4+r7*4]
%endif
%%no_offsets:
%if %1
    vmaskmovps  [r0+r7*4], m7, m1
    vmaskmovps  [r1+r7*4], m7, m1
%else
    movu        [r0+r7*4], m1
    movu        [r1+r7*4], m1
%endif
    test         r2, r2
    jz %%no_qscale
    EXP2FIX8_YMM m1, m2, m3, m4, m5, m6
    vextracti128 xm2, m1, 1
    packusdw    xm1, xm2                     ; 65536 -> 0xffff
%if %1
    lea          r5, [r2+r7*2]
    test        r6b, 4
    jz %%w2
    movq       [r5], xm1
    psrldq      xm1, 8
    add          r5, 8
%%w2:
    test        r6b, 2
    jz %%w1
    movd       [r5], xm1
    psrldq      xm1, 4
    add          r5, 4
%%w1:
    test        r6b, 1
    jz %%no_qscale
    pextrw     [r5], xm1, 0
%else
    movu  [r2+r7*2], xm1
%endif
%%no_qscale:
%endmacro

INIT_YMM avx2
cglobal aq_variance_tail, 7,10,16
    LOAD_EXP2_LUT_YMM
    vbroadcastss m8, [r5]
    vbroadcastss m9, [r5+4]
    vpbroadcastd m10, [rc_pd_1]
    lea          r8, [log2_lut]
    xor         r7d, r7d
    sub         r6d, 8
    jl .tail
.loop:
    AQ_VARIANCE_YMM 0
    add         r7d, 8
    sub         r6d, 8
    jge .loop
.tail:
    add         r6d, 8
    jz .end
    mov         r9d, r6d
    neg          r9
    lea          r5, [rc_lanes+32]
    movu         m7, [r5+r9*4]
    AQ_VARIANCE_YMM 1
.end:
    RET
