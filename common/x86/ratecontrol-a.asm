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

; avx2: exp2_lut in four pshufb tables, m12-m15
%macro COST_SCALE_YMM 0 ; m1 = costs, m2 = qp
    pand        m1, [rc_pd_3fff]
    mulps       m2, [rc_pf_m64_6]
    addps       m2, [rc_pf_512_5]
    cvttps2dq   m2, m2
    pminsd      m2, [rc_pd_1024]
    psrad       m3, m2, 6
    pand        m2, [rc_pd_63]
    pslld       m4, m2, 3                    ; index bit 4 -> bit 7
    pshufb      m5, m12, m2                  ; bytes 1-3 take exp2_lut[0] = 0
    pshufb      m6, m13, m2
    pblendvb    m5, m6, m4
    pshufb      m6, m14, m2
    pshufb      m7, m15, m2
    pblendvb    m6, m7, m4
    pslld       m4, m2, 2                    ; index bit 5 -> bit 7
    pblendvb    m5, m6, m4
    por         m5, [rc_pd_256]
    vpsllvd     m5, m5, m3
    psrld       m5, 8
    pminud      m5, [rc_pd_ffff]
    pmulld      m1, m5
    paddd       m1, [rc_pd_128]
    psrad       m1, 8
    paddd       m0, m1
%endmacro

INIT_YMM avx2
cglobal mbtree_cost_scale, 3,5,16, 64
    vbroadcasti128 m12, [exp2_lut+ 0]
    vbroadcasti128 m13, [exp2_lut+16]
    vbroadcasti128 m14, [exp2_lut+32]
    vbroadcasti128 m15, [exp2_lut+48]
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
