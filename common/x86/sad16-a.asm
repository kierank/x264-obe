;*****************************************************************************
;* sad16-a.asm: x86 high depth sad functions
;*****************************************************************************
;* Copyright (C) 2010-2014 x264 project
;*
;* Authors: Oskar Arvidsson <oskar@irock.se>
;*          Henrik Gramner <henrik@gramner.com>
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

%include "x86inc.asm"
%include "x86util.asm"

SECTION_RODATA 32

; me_hex_16x16: candidate idx, 0 in the best lane (+0 hexagon step, +16 and +32 the first
; hexagon, +48 and +64 the square); +80 mod6m1; +90 + 2*t hex2[t mod 6] (dx, dy) for
; t = -1..8; +108 square1 (dx, dy)
ALIGN 16
me_hex_tab: dd 1, 2, 3, 0
            dd 2, 3, 4, 0
            dd 5, 6, 7, 0
            dd 1, 2, 3, 4
            dd 5, 6, 7, 8
            db 5, 0, 1, 2, 3, 4, 5, 0
            db 1,-2, -1,-2, -2,0, -1,2, 1,2, 2,0, 1,-2, -1,-2, -2,0, -1,2
            db 0,0, 0,-1, 0,1, -1,0, 1,0, -1,-1, -1,1, 1,-1, 1,1

SECTION .text

cextern pw_1
cextern pw_4
cextern pw_8
cextern pw_64
cextern pd_ffff

;=============================================================================
; SAD MMX
;=============================================================================

%macro SAD_INC_1x16P_MMX 0
    movu    m1, [r0+ 0]
    movu    m2, [r0+ 8]
    movu    m3, [r0+16]
    movu    m4, [r0+24]
    psubw   m1, [r2+ 0]
    psubw   m2, [r2+ 8]
    psubw   m3, [r2+16]
    psubw   m4, [r2+24]
    ABSW2   m1, m2, m1, m2, m5, m6
    ABSW2   m3, m4, m3, m4, m7, m5
    lea     r0, [r0+2*r1]
    lea     r2, [r2+2*r3]
    paddw   m1, m2
    paddw   m3, m4
    paddw   m0, m1
    paddw   m0, m3
%endmacro

%macro SAD_INC_2x8P_MMX 0
    movu    m1, [r0+0]
    movu    m2, [r0+8]
    movu    m3, [r0+2*r1+0]
    movu    m4, [r0+2*r1+8]
    psubw   m1, [r2+0]
    psubw   m2, [r2+8]
    psubw   m3, [r2+2*r3+0]
    psubw   m4, [r2+2*r3+8]
    ABSW2   m1, m2, m1, m2, m5, m6
    ABSW2   m3, m4, m3, m4, m7, m5
    lea     r0, [r0+4*r1]
    lea     r2, [r2+4*r3]
    paddw   m1, m2
    paddw   m3, m4
    paddw   m0, m1
    paddw   m0, m3
%endmacro

%macro SAD_INC_2x4P_MMX 0
    movu    m1, [r0]
    movu    m2, [r0+2*r1]
    psubw   m1, [r2]
    psubw   m2, [r2+2*r3]
    ABSW2   m1, m2, m1, m2, m3, m4
    lea     r0, [r0+4*r1]
    lea     r2, [r2+4*r3]
    paddw   m0, m1
    paddw   m0, m2
%endmacro

;-----------------------------------------------------------------------------
; int pixel_sad_NxM( uint16_t *, intptr_t, uint16_t *, intptr_t )
;-----------------------------------------------------------------------------
%macro SAD_MMX 3
cglobal pixel_sad_%1x%2, 4,5-(%2&4/4)
    pxor    m0, m0
%if %2 == 4
    SAD_INC_%3x%1P_MMX
    SAD_INC_%3x%1P_MMX
%else
    mov    r4d, %2/%3
.loop:
    SAD_INC_%3x%1P_MMX
    dec    r4d
    jg .loop
%endif
%if %1*%2 == 256
    HADDUW  m0, m1
%else
    HADDW   m0, m1
%endif
    movd   eax, m0
    RET
%endmacro

INIT_MMX mmx2
SAD_MMX 16, 16, 1
SAD_MMX 16,  8, 1
SAD_MMX  8, 16, 2
SAD_MMX  8,  8, 2
SAD_MMX  8,  4, 2
SAD_MMX  4,  8, 2
SAD_MMX  4,  4, 2
INIT_MMX ssse3
SAD_MMX  4,  8, 2
SAD_MMX  4,  4, 2

;=============================================================================
; SAD XMM
;=============================================================================

%macro SAD_INC_2ROW 1
%if 2*%1 > mmsize
    movu    m1, [r2+ 0]
    movu    m2, [r2+16]
    movu    m3, [r2+2*r3+ 0]
    movu    m4, [r2+2*r3+16]
    psubw   m1, [r0+ 0]
    psubw   m2, [r0+16]
    psubw   m3, [r0+2*r1+ 0]
    psubw   m4, [r0+2*r1+16]
    ABSW2   m1, m2, m1, m2, m5, m6
    lea     r0, [r0+4*r1]
    lea     r2, [r2+4*r3]
    ABSW2   m3, m4, m3, m4, m7, m5
    paddw   m1, m2
    paddw   m3, m4
    paddw   m0, m1
    paddw   m0, m3
%else
    movu    m1, [r2]
    movu    m2, [r2+2*r3]
    psubw   m1, [r0]
    psubw   m2, [r0+2*r1]
    ABSW2   m1, m2, m1, m2, m3, m4
    lea     r0, [r0+4*r1]
    lea     r2, [r2+4*r3]
    paddw   m0, m1
    paddw   m0, m2
%endif
%endmacro

;-----------------------------------------------------------------------------
; int pixel_sad_NxM( uint16_t *, intptr_t, uint16_t *, intptr_t )
;-----------------------------------------------------------------------------
%macro SAD 2
cglobal pixel_sad_%1x%2, 4,5-(%2&4/4),8*(%1/mmsize)
    pxor    m0, m0
%if %2 == 4
    SAD_INC_2ROW %1
    SAD_INC_2ROW %1
%else
    mov    r4d, %2/2
.loop:
    SAD_INC_2ROW %1
    dec    r4d
    jg .loop
%endif
    HADDW   m0, m1
    movd   eax, xm0
    RET
%endmacro

INIT_XMM sse2
SAD 16, 16
SAD 16,  8
SAD  8, 16
SAD  8,  8
SAD  8,  4
INIT_XMM sse2, aligned
SAD 16, 16
SAD 16,  8
SAD  8, 16
SAD  8,  8
INIT_XMM ssse3
SAD 16, 16
SAD 16,  8
SAD  8, 16
SAD  8,  8
SAD  8,  4
INIT_XMM ssse3, aligned
SAD 16, 16
SAD 16,  8
SAD  8, 16
SAD  8,  8

; 16 wide, AVX2: one row per ymm, 4 rows per pointer step, rows summed in
; pairs before the accumulator (at most 16*1023 a lane)
%macro SAD_HBD_16 1 ; height
cglobal pixel_sad_16x%1, 4,6,5
    lea            r4, [r1+2*r1]
    lea            r5, [r3+2*r3]
%assign sad_hbd_k 0
%rep %1/4
    movu           m1, [r2]
    movu           m2, [r2+2*r3]
    movu           m3, [r2+4*r3]
    movu           m4, [r2+2*r5]
    psubw          m1, [r0]
    psubw          m2, [r0+2*r1]
    psubw          m3, [r0+4*r1]
    psubw          m4, [r0+2*r4]
    pabsw          m1, m1
    pabsw          m2, m2
    pabsw          m3, m3
    pabsw          m4, m4
    paddw          m1, m2
    paddw          m3, m4
%if sad_hbd_k == 0
    paddw          m0, m1, m3
%else
    paddw          m1, m3
    paddw          m0, m1
%endif
%if sad_hbd_k < %1-4
    lea            r0, [r0+8*r1]
    lea            r2, [r2+8*r3]
%endif
%assign sad_hbd_k sad_hbd_k+4
%endrep
    HADDW          m0, m1
    movd          eax, xm0
    RET
%endmacro

INIT_YMM avx2
SAD_HBD_16 16
SAD_HBD_16  8

;=============================================================================
; SAD x3/x4
;=============================================================================

%macro SAD_X3_INC_P 0
    add     r0, 4*FENC_STRIDE
    lea     r1, [r1+4*r4]
    lea     r2, [r2+4*r4]
    lea     r3, [r3+4*r4]
%endmacro

%macro SAD_X3_ONE_START 0
    mova    m3, [r0]
    movu    m0, [r1]
    movu    m1, [r2]
    movu    m2, [r3]
    psubw   m0, m3
    psubw   m1, m3
    psubw   m2, m3
    ABSW2   m0, m1, m0, m1, m4, m5
    ABSW    m2, m2, m6
%endmacro

%macro SAD_X3_ONE 2
    mova    m6, [r0+%1]
    movu    m3, [r1+%2]
    movu    m4, [r2+%2]
    movu    m5, [r3+%2]
    psubw   m3, m6
    psubw   m4, m6
    psubw   m5, m6
    ABSW2   m3, m4, m3, m4, m7, m6
    ABSW    m5, m5, m6
    paddw   m0, m3
    paddw   m1, m4
    paddw   m2, m5
%endmacro

%macro SAD_X3_END 2
%if mmsize == 8 && %1*%2 == 256
    HADDUW   m0, m3
    HADDUW   m1, m4
    HADDUW   m2, m5
%else
    HADDW    m0, m3
    HADDW    m1, m4
    HADDW    m2, m5
%endif
%if UNIX64
    movd [r5+0], xm0
    movd [r5+4], xm1
    movd [r5+8], xm2
%else
    mov      r0, r5mp
    movd [r0+0], xm0
    movd [r0+4], xm1
    movd [r0+8], xm2
%endif
    RET
%endmacro

%macro SAD_X4_INC_P 0
    add     r0, 4*FENC_STRIDE
    lea     r1, [r1+4*r5]
    lea     r2, [r2+4*r5]
    lea     r3, [r3+4*r5]
    lea     r4, [r4+4*r5]
%endmacro

%macro SAD_X4_ONE_START 0
    mova    m4, [r0]
    movu    m0, [r1]
    movu    m1, [r2]
    movu    m2, [r3]
    movu    m3, [r4]
    psubw   m0, m4
    psubw   m1, m4
    psubw   m2, m4
    psubw   m3, m4
    ABSW2   m0, m1, m0, m1, m5, m6
    ABSW2   m2, m3, m2, m3, m4, m7
%endmacro

%macro SAD_X4_ONE 2
    mova    m4, [r0+%1]
    movu    m5, [r1+%2]
    movu    m6, [r2+%2]
%if num_mmregs > 8
    movu    m7, [r3+%2]
    movu    m8, [r4+%2]
    psubw   m5, m4
    psubw   m6, m4
    psubw   m7, m4
    psubw   m8, m4
    ABSW2   m5, m6, m5, m6, m9, m10
    ABSW2   m7, m8, m7, m8, m9, m10
    paddw   m0, m5
    paddw   m1, m6
    paddw   m2, m7
    paddw   m3, m8
%elif cpuflag(ssse3)
    movu    m7, [r3+%2]
    psubw   m5, m4
    psubw   m6, m4
    psubw   m7, m4
    movu    m4, [r4+%2]
    pabsw   m5, m5
    psubw   m4, [r0+%1]
    pabsw   m6, m6
    pabsw   m7, m7
    pabsw   m4, m4
    paddw   m0, m5
    paddw   m1, m6
    paddw   m2, m7
    paddw   m3, m4
%else ; num_mmregs == 8 && !ssse3
    psubw   m5, m4
    psubw   m6, m4
    ABSW    m5, m5, m7
    ABSW    m6, m6, m7
    paddw   m0, m5
    paddw   m1, m6
    movu    m5, [r3+%2]
    movu    m6, [r4+%2]
    psubw   m5, m4
    psubw   m6, m4
    ABSW2   m5, m6, m5, m6, m7, m4
    paddw   m2, m5
    paddw   m3, m6
%endif
%endmacro

%macro SAD_X4_END 2
%if mmsize == 8 && %1*%2 == 256
    HADDUW    m0, m4
    HADDUW    m1, m5
    HADDUW    m2, m6
    HADDUW    m3, m7
%else
    HADDW     m0, m4
    HADDW     m1, m5
    HADDW     m2, m6
    HADDW     m3, m7
%endif
    mov       r0, r6mp
    movd [r0+ 0], xm0
    movd [r0+ 4], xm1
    movd [r0+ 8], xm2
    movd [r0+12], xm3
    RET
%endmacro

%macro SAD_X_2xNP 4
    %assign x %3
%rep %4
    SAD_X%1_ONE x*mmsize, x*mmsize
    SAD_X%1_ONE 2*FENC_STRIDE+x*mmsize, 2*%2+x*mmsize
    %assign x x+1
%endrep
%endmacro

%macro PIXEL_VSAD 0
cglobal pixel_vsad, 3,3,8
    mova      m0, [r0]
    mova      m1, [r0+16]
    mova      m2, [r0+2*r1]
    mova      m3, [r0+2*r1+16]
    lea       r0, [r0+4*r1]
    psubw     m0, m2
    psubw     m1, m3
    ABSW2     m0, m1, m0, m1, m4, m5
    paddw     m0, m1
    sub      r2d, 2
    je .end
.loop:
    mova      m4, [r0]
    mova      m5, [r0+16]
    mova      m6, [r0+2*r1]
    mova      m7, [r0+2*r1+16]
    lea       r0, [r0+4*r1]
    psubw     m2, m4
    psubw     m3, m5
    psubw     m4, m6
    psubw     m5, m7
    ABSW      m2, m2, m1
    ABSW      m3, m3, m1
    ABSW      m4, m4, m1
    ABSW      m5, m5, m1
    paddw     m0, m2
    paddw     m0, m3
    paddw     m0, m4
    paddw     m0, m5
    mova      m2, m6
    mova      m3, m7
    sub r2d, 2
    jg .loop
.end:
%if BIT_DEPTH == 9
    HADDW     m0, m1 ; max sum: 62(pixel diffs)*511(pixel_max)=31682
%else
    HADDUW    m0, m1 ; max sum: 62(pixel diffs)*1023(pixel_max)=63426
%endif
    movd     eax, m0
    RET
%endmacro
INIT_XMM sse2
PIXEL_VSAD
INIT_XMM ssse3
PIXEL_VSAD
INIT_XMM xop
PIXEL_VSAD

INIT_YMM avx2
cglobal pixel_vsad, 3,3
    mova      m0, [r0]
    mova      m1, [r0+2*r1]
    lea       r0, [r0+4*r1]
    psubw     m0, m1
    pabsw     m0, m0
    sub      r2d, 2
    je .end
.loop:
    mova      m2, [r0]
    mova      m3, [r0+2*r1]
    lea       r0, [r0+4*r1]
    psubw     m1, m2
    psubw     m2, m3
    pabsw     m1, m1
    pabsw     m2, m2
    paddw     m0, m1
    paddw     m0, m2
    mova      m1, m3
    sub      r2d, 2
    jg .loop
.end:
%if BIT_DEPTH == 9
    HADDW     m0, m1
%else
    HADDUW    m0, m1
%endif
    movd     eax, xm0
    RET

;-----------------------------------------------------------------------------
; void pixel_sad_xN_WxH( uint16_t *fenc, uint16_t *pix0, uint16_t *pix1,
;                        uint16_t *pix2, intptr_t i_stride, int scores[3] )
;-----------------------------------------------------------------------------
%macro SAD_X 3
cglobal pixel_sad_x%1_%2x%3, 6,7,XMM_REGS
    %assign regnum %1+1
    %xdefine STRIDE r %+ regnum
    mov     r6, %3/2-1
    SAD_X%1_ONE_START
    SAD_X%1_ONE 2*FENC_STRIDE, 2*STRIDE
    SAD_X_2xNP %1, STRIDE, 1, %2/(mmsize/2)-1
.loop:
    SAD_X%1_INC_P
    SAD_X_2xNP %1, STRIDE, 0, %2/(mmsize/2)
    dec     r6
    jg .loop
%if %1 == 4
    mov     r6, r6m
%endif
    SAD_X%1_END %2, %3
%endmacro

INIT_MMX mmx2
%define XMM_REGS 0
SAD_X 3, 16, 16
SAD_X 3, 16,  8
SAD_X 3,  8, 16
SAD_X 3,  8,  8
SAD_X 3,  8,  4
SAD_X 3,  4,  8
SAD_X 3,  4,  4
SAD_X 4, 16, 16
SAD_X 4, 16,  8
SAD_X 4,  8, 16
SAD_X 4,  8,  8
SAD_X 4,  8,  4
SAD_X 4,  4,  8
SAD_X 4,  4,  4
INIT_MMX ssse3
SAD_X 3,  4,  8
SAD_X 3,  4,  4
SAD_X 4,  4,  8
SAD_X 4,  4,  4
INIT_XMM ssse3
%define XMM_REGS 7
SAD_X 3, 16, 16
SAD_X 3, 16,  8
SAD_X 3,  8, 16
SAD_X 3,  8,  8
SAD_X 3,  8,  4
%define XMM_REGS 9
SAD_X 4, 16, 16
SAD_X 4, 16,  8
SAD_X 4,  8, 16
SAD_X 4,  8,  8
SAD_X 4,  8,  4
INIT_XMM sse2
%define XMM_REGS 8
SAD_X 3, 16, 16
SAD_X 3, 16,  8
SAD_X 3,  8, 16
SAD_X 3,  8,  8
SAD_X 3,  8,  4
%define XMM_REGS 11
SAD_X 4, 16, 16
SAD_X 4, 16,  8
SAD_X 4,  8, 16
SAD_X 4,  8,  8
SAD_X 4,  8,  4

;=============================================================================
; 10-bit SAD 8x8 and 8x16, AVX2: one 8 pixel row per xmm, the other source as
; the memory operand, so no row waits on a vinserti128 and the end has no lane
; fold. Even rows accumulate in xm0, odd rows in xm1 (at most 8*1023 a word).
;=============================================================================
; row %1 of a 4 row group, bytes: sad_off = %1*%2 (%3 = 3*%2)
%macro SAD_HBD_XOFF 3 ; j, stride, 3*stride
%if %1 == 0
    %xdefine sad_off 0
%elif %1 == 1
    %xdefine sad_off %2
%elif %1 == 2
    %xdefine sad_off 2*%2
%else
    %xdefine sad_off %3
%endif
%endmacro

; |xm2| into the row %1 accumulator (xm0 even, xm1 odd)
%macro SAD_HBD_XACC 1 ; row
%if %1 == 0
    pabsw         xm0, xm2
%elif %1 == 1
    pabsw         xm1, xm2
%else
    pabsw         xm2, xm2
%if %1 & 1
    paddw         xm1, xm2
%else
    paddw         xm0, xm2
%endif
%endif
%endmacro

; xm0 + xm1 (words, at most 16*1023) -> eax: two word folds, then the words
; of each dword added as dwords (pand pd_ffff + psrld 16), then a dword fold
%macro SAD_HBD_XEND 0
    paddw         xm0, xm1
    punpckhqdq    xm1, xm0, xm0
    paddw         xm0, xm1
    psrld         xm1, xm0, 16
    pand          xm0, [pd_ffff]
    paddd         xm0, xm1
    pshuflw       xm1, xm0, q1032
    paddd         xm0, xm1
    movd          eax, xm0
    RET
%endmacro

%macro SAD_HBD_Y 1 ; height
cglobal pixel_sad_8x%1, 4,6,3
    FIX_STRIDES   r1, r3
    lea           r4, [r1+2*r1]
    lea           r5, [r3+2*r3]
%assign sad_hbd_k 0
%rep %1
    SAD_HBD_XOFF  sad_hbd_k&3, r3, r5
    movu          xm2, [r2+sad_off]
    SAD_HBD_XOFF  sad_hbd_k&3, r1, r4
    psubw         xm2, [r0+sad_off]
    SAD_HBD_XACC  sad_hbd_k
%if (sad_hbd_k&3) == 3 && sad_hbd_k < %1-1
    lea           r0, [r0+4*r1]
    lea           r2, [r2+4*r3]
%endif
%assign sad_hbd_k sad_hbd_k+1
%endrep
    SAD_HBD_XEND
%endmacro

; row j of a 4 row group: sad_off = j*stride in bytes, %2 = stride, %3 = 3*stride (pixels)
%macro SAD_HBD_ROWOFF 3 ; j, stride, stride3
%if %1 == 0
    %xdefine sad_off 0
%elif %1 == 1
    %xdefine sad_off 2*%2
%elif %1 == 2
    %xdefine sad_off 4*%2
%else
    %xdefine sad_off 2*%3
%endif
%endmacro

; m0 = { ref1 | ref2 }, m%2 = { ref3 | ref4 } (4 or 8 sums a lane; words, at most
; 16*1023, if %1, else dwords) -> xm%3 = { sad1, sad2, sad3, sad4 },
; xm%2 = { sad2, sad4, _, _ }, xm0 = { sad1, sad3, _, _ }
%macro SAD_HBD_X_END 3 ; pmaddwd?, b (number), tmp (number)
%if %1
    pmaddwd        m0, [pw_1]
    pmaddwd       m%2, [pw_1]
%endif
    punpckldq     m%3, m0, m%2
    punpckhdq      m0, m%2
    paddd          m0, m%3
    punpckhqdq    m%2, m0, m0
    paddd          m0, m%2        ; { sad1, sad3 | sad2, sad4 }
    vextracti128 xm%2, m0, 1
    punpckldq    xm%3, xm0, xm%2
%endmacro

;-----------------------------------------------------------------------------
; int pixel_sad_x3_min_16x16( uint16_t *fenc, uint16_t *pix0, uint16_t *pix1, uint16_t *pix2,
;                             intptr_t i_stride, uint64_t bias01, uint64_t bias2_best )
; int pixel_sad_x4_min_16x16( uint16_t *fenc, uint16_t *pix0, uint16_t *pix1, uint16_t *pix2,
;                             uint16_t *pix3, intptr_t i_stride, uint64_t bias01,
;                             uint64_t bias23, int best )
; min( best, (sad_i << 6) + bias_i ), signed; bias01 = bias_0 | bias_1 << 32, etc.
; The sums are 64*sad from pmaddwd by pw_64. Each bias is added beside the
; last in-lane qword swap and the candidates of the two ymm lanes meet in the
; first pminsd, so the cross-lane step is one vextracti128.
;-----------------------------------------------------------------------------
%macro SAD_X3_HBD_Y 1-2 0 ; h, min
%if %2
cglobal pixel_sad_x3_min_8x%1, 5,7,7
%else
cglobal pixel_sad_x3_8x%1, 6,7,6
%endif
    lea            r6, [r4+2*r4]
%assign sad_hbd_k 0
%rep %1/2
    SAD_HBD_ROWOFF sad_hbd_k&3, r4, r6
    %xdefine sad_off0 sad_off
    SAD_HBD_ROWOFF (sad_hbd_k+1)&3, r4, r6
    vbroadcasti128 m2, [r0+sad_hbd_k*FENC_STRIDEB]
    vbroadcasti128 m3, [r0+(sad_hbd_k+1)*FENC_STRIDEB]
    movu          xm4, [r1+sad_off0]
    vinserti128    m4, m4, [r2+sad_off0], 1
    movu          xm5, [r1+sad_off]
    vinserti128    m5, m5, [r2+sad_off], 1
%if sad_hbd_k == 0
    psubw          m0, m4, m2
    pabsw          m0, m0
%else
    psubw          m4, m2
    pabsw          m4, m4
    paddw          m0, m4
%endif
    psubw          m5, m3
    pabsw          m5, m5
    paddw          m0, m5
    vpblendd       m2, m2, m3, 0xf0
    movu          xm4, [r3+sad_off0]
    vinserti128    m4, m4, [r3+sad_off], 1
%if sad_hbd_k == 0
    psubw          m1, m4, m2
    pabsw          m1, m1
%else
    psubw          m4, m2
    pabsw          m4, m4
    paddw          m1, m4
%endif
%if (sad_hbd_k&3) == 2 && sad_hbd_k < %1-2
    lea            r1, [r1+8*r4]
    lea            r2, [r2+8*r4]
    lea            r3, [r3+8*r4]
%endif
%assign sad_hbd_k sad_hbd_k+2
%endrep
%if %2
    ; m0 = { ref1 | ref2 }, m1 = { ref3 even rows | ref3 odd rows }
    vpbroadcastd   m6, [pw_64]
    movq          xm3, r5mp        ; b0 b1
    movq          xm4, r6mp        ; b2 best
    pmaddwd        m0, m6
    pmaddwd        m1, m6
    psrlq         xm5, xm3, 32     ; b1
    punpckldq     xm3, xm4         ; b0 b2 b1 best
    psrlq         xm4, 32          ; best
    vinserti128    m3, m3, xm5, 1  ; b0 b2 _ _ | b1 0 _ _
    punpckldq      m2, m0, m1
    punpckhdq      m0, m1
    paddd          m0, m2
    punpckhqdq     m1, m0, m0
    paddd          m0, m3
    paddd          m0, m1          ; c0, ref3 even + b2 | c1, ref3 odd
    vextracti128  xm1, m0, 1
    paddd         xm2, xm0, xm1    ; _ c2
    pminsd        xm0, xm1
    psrlq         xm2, 32
    pminsd        xm0, xm4
    pminsd        xm0, xm2
    movd          eax, xm0
    RET
%else
    SAD_HBD_X_END  1, 1, 2
    paddd         xm0, xm1
    movq      [r5+0], xm2
    pextrd    [r5+8], xm0, 1
    RET
%endif
%endmacro

%macro SAD_X4_HBD_Y 1-2 0 ; h, min
%if %2
cglobal pixel_sad_x4_min_8x%1, 6,7,6
%else
cglobal pixel_sad_x4_8x%1, 6,7,5
%endif
    lea            r6, [r5+2*r5]
%assign sad_hbd_k 0
%rep %1
    SAD_HBD_ROWOFF sad_hbd_k&3, r5, r6
    vbroadcasti128 m2, [r0+sad_hbd_k*FENC_STRIDEB]
    movu          xm3, [r1+sad_off]
    vinserti128    m3, m3, [r2+sad_off], 1
    movu          xm4, [r3+sad_off]
    vinserti128    m4, m4, [r4+sad_off], 1
%if sad_hbd_k == 0
    psubw          m0, m3, m2
    psubw          m1, m4, m2
    pabsw          m0, m0
    pabsw          m1, m1
%else
    psubw          m3, m2
    psubw          m4, m2
    pabsw          m3, m3
    pabsw          m4, m4
    paddw          m0, m3
    paddw          m1, m4
%endif
%if (sad_hbd_k&3) == 3 && sad_hbd_k < %1-1
    lea            r1, [r1+8*r5]
    lea            r2, [r2+8*r5]
    lea            r3, [r3+8*r5]
    lea            r4, [r4+8*r5]
%endif
%assign sad_hbd_k sad_hbd_k+1
%endrep
%if %2
    ; m0 = { ref1 | ref2 }, m1 = { ref3 | ref4 }
    vpbroadcastd   m5, [pw_64]
    movq          xm3, r6mp        ; b0 b1
    movq          xm4, r7mp        ; b2 b3
    pmaddwd        m0, m5
    pmaddwd        m1, m5
    punpckldq     xm3, xm4         ; b0 b2 b1 b3
    vpbroadcastd  xm4, r8m
    vpermq         m3, m3, q1100   ; b0 b2 _ _ | b1 b3 _ _
    punpckldq      m2, m0, m1
    punpckhdq      m0, m1
    paddd          m0, m2
    punpckhqdq     m1, m0, m0
    paddd          m0, m3
    paddd          m0, m1          ; c0 c2 | c1 c3
    vextracti128  xm1, m0, 1
    pminsd        xm0, xm1
    psrlq         xm1, xm0, 32
    pminsd        xm0, xm4
    pminsd        xm0, xm1
    movd          eax, xm0
    RET
%else
    SAD_HBD_X_END  1, 1, 2
    mov            r6, r6mp
    movu         [r6], xm2
    RET
%endif
%endmacro

INIT_XMM avx2
SAD_HBD_Y 8
SAD_HBD_Y 16
INIT_YMM avx2
SAD_X3_HBD_Y 8
SAD_X3_HBD_Y 16
SAD_X4_HBD_Y 8
SAD_X4_HBD_Y 16

;=============================================================================
; 10-bit sad_x3/sad_x4 16x16 and 16x8, AVX2: one row per ymm, fenc - ref with
; the reference as the memory operand, 4 rows per pointer step.
;=============================================================================
; m0..m%1-1 = 16 word sums each (at most 16*1023 a lane) -> 8 dword sums each
; folded to m0 = { sad1 | sad2 } and, for x4, m1 = { sad3 | sad4 } (4 dwords a lane)
%macro SAD_X_HBD16_FOLD 1 ; refs
    pmaddwd        m0, [pw_1]
    pmaddwd        m1, [pw_1]
    pmaddwd        m2, [pw_1]
%if %1 == 4
    pmaddwd        m3, [pw_1]
%endif
    vperm2i128     m%1, m0, m1, q0301
    vinserti128    m0, m0, xm1, 1
    paddd          m0, m%1
%if %1 == 4
    vperm2i128     m4, m2, m3, q0301
    vinserti128    m2, m2, xm3, 1
    paddd          m1, m2, m4
%endif
%endmacro

; m0 = { 1 2 1 2 | 1 2 1 2 }, m2 = { 3 4 3 4 | 3 4 3 4 } dword sums of refs 1-4,
; xm4 = { b0 b1 }, xm6 = { b2 b3 }; %1 = best, or none if ref 4 is best
%macro SAD_X_HBD16_MIN_END 0-1
    pshufd         m1, m0, q1032
    pshufd         m3, m2, q1032
    paddd          m0, m4
    paddd          m2, m6
    paddd          m0, m1
    paddd          m2, m3
%if %0
    vpbroadcastd  xm5, %1
%endif
    vextracti128  xm1, m0, 1
    vextracti128  xm3, m2, 1
    paddd         xm0, xm1         ; c0 c1
    paddd         xm2, xm3         ; c2 c3
    pminsd        xm0, xm2
    psrlq         xm1, xm0, 32
%if %0
    pminsd        xm0, xm5
%endif
    pminsd        xm0, xm1
    movd          eax, xm0
    RET
%endmacro

%macro SAD_X3_HBD16 1-2 0 ; height, min
%if %2
cglobal pixel_sad_x3_min_16x%1, 5,7,7
%else
cglobal pixel_sad_x3_16x%1, 6,7,6
%endif
    lea            r6, [r4+2*r4]
%assign sad_hbd_k 0
%rep %1
    SAD_HBD_ROWOFF sad_hbd_k&3, r4, r6
    mova           m3, [r0+sad_hbd_k*FENC_STRIDEB]
%if sad_hbd_k == 0
    psubw          m0, m3, [r1]
    psubw          m1, m3, [r2]
    psubw          m2, m3, [r3]
    pabsw          m0, m0
    pabsw          m1, m1
    pabsw          m2, m2
%else
    psubw          m4, m3, [r1+sad_off]
    psubw          m5, m3, [r2+sad_off]
    psubw          m3, [r3+sad_off]
    pabsw          m4, m4
    pabsw          m5, m5
    pabsw          m3, m3
    paddw          m0, m4
    paddw          m1, m5
    paddw          m2, m3
%endif
%if (sad_hbd_k&3) == 3 && sad_hbd_k < %1-1
    lea            r1, [r1+8*r4]
    lea            r2, [r2+8*r4]
    lea            r3, [r3+8*r4]
%endif
%assign sad_hbd_k sad_hbd_k+1
%endrep
%if %2
    ; m0, m1, m2 = refs 1, 2, 3; ref 4 is zero with bias best
    vpbroadcastd   m6, [pw_64]
    pmaddwd        m0, m6
    pmaddwd        m1, m6
    pmaddwd        m2, m6
    pxor          xm3, xm3
    movq          xm6, r6mp        ; b2 best
    punpckldq      m4, m0, m1
    punpckhdq      m0, m1
    punpckldq      m5, m2, m3
    punpckhdq      m2, m3
    paddd          m0, m4
    paddd          m2, m5
    movq          xm4, r5mp        ; b0 b1
    SAD_X_HBD16_MIN_END
%else
    SAD_X_HBD16_FOLD 3
    SAD_HBD_X_END  0, 2, 3
    paddd         xm0, xm2
    movq      [r5+0], xm3
    pextrd    [r5+8], xm0, 1
    RET
%endif
%endmacro

%macro SAD_X4_HBD16 1-2 0 ; height, min
%if %2
cglobal pixel_sad_x4_min_16x%1, 6,7,8
%else
cglobal pixel_sad_x4_16x%1, 6,7,8
%endif
    lea            r6, [r5+2*r5]
%assign sad_hbd_k 0
%rep %1
    SAD_HBD_ROWOFF sad_hbd_k&3, r5, r6
    mova           m4, [r0+sad_hbd_k*FENC_STRIDEB]
%if sad_hbd_k == 0
    psubw          m0, m4, [r1]
    psubw          m1, m4, [r2]
    psubw          m2, m4, [r3]
    psubw          m3, m4, [r4]
    pabsw          m0, m0
    pabsw          m1, m1
    pabsw          m2, m2
    pabsw          m3, m3
%else
    psubw          m5, m4, [r1+sad_off]
    psubw          m6, m4, [r2+sad_off]
    psubw          m7, m4, [r3+sad_off]
    psubw          m4, [r4+sad_off]
    pabsw          m5, m5
    pabsw          m6, m6
    pabsw          m7, m7
    pabsw          m4, m4
    paddw          m0, m5
    paddw          m1, m6
    paddw          m2, m7
    paddw          m3, m4
%endif
%if (sad_hbd_k&3) == 3 && sad_hbd_k < %1-1
    lea            r1, [r1+8*r5]
    lea            r2, [r2+8*r5]
    lea            r3, [r3+8*r5]
    lea            r4, [r4+8*r5]
%endif
%assign sad_hbd_k sad_hbd_k+1
%endrep
%if %2
    ; m0, m1, m2, m3 = refs 1, 2, 3, 4
    vpbroadcastd   m5, [pw_64]
    pmaddwd        m0, m5
    pmaddwd        m1, m5
    pmaddwd        m2, m5
    pmaddwd        m3, m5
    movq          xm6, r7mp        ; b2 b3
    punpckldq      m4, m0, m1
    punpckhdq      m0, m1
    punpckldq      m5, m2, m3
    punpckhdq      m2, m3
    paddd          m0, m4
    paddd          m2, m5
    movq          xm4, r6mp        ; b0 b1
    SAD_X_HBD16_MIN_END r8m
%else
    SAD_X_HBD16_FOLD 4
    SAD_HBD_X_END  0, 1, 2
    mov            r6, r6mp
    movu         [r6], xm2
    RET
%endif
%endmacro

SAD_X3_HBD16 16
SAD_X3_HBD16  8
SAD_X4_HBD16 16
SAD_X4_HBD16  8

%if ARCH_X86_64
SAD_X3_HBD_Y 8, 1
SAD_X3_HBD_Y 16, 1
SAD_X4_HBD_Y 8, 1
SAD_X4_HBD_Y 16, 1
SAD_X3_HBD16 16, 1
SAD_X3_HBD16  8, 1
SAD_X4_HBD16 16, 1
SAD_X4_HBD16  8, 1
%endif

;-----------------------------------------------------------------------------
; int pixel_sad_avg2_WxH( uint16_t *fenc, uint16_t *src1, uint16_t *src2, intptr_t stride )
; sad( fenc, (src1+src2+1)>>1 ), word sums (at most 16*1023 a lane)
;-----------------------------------------------------------------------------
; 16 wide, row k: rows k..k+3 share a pointer step (r4 = 3*stride), even rows
; accumulate in m0 and odd rows in m2 (at most 8*1023 a lane each)
%macro SAD_AVG2_HBD_ROW16 1 ; row
    SAD_HBD_ROWOFF %1&3, r3, r4
    movu          m1, [r1+sad_off]
    pavgw         m1, [r2+sad_off]
    psubw         m1, [r0+%1*FENC_STRIDEB]
%if %1 == 0
    pabsw         m0, m1
%elif %1 == 1
    pabsw         m2, m1
%else
    pabsw         m1, m1
%if %1 & 1
    paddw         m2, m1
%else
    paddw         m0, m1
%endif
%endif
%if (%1&3) == 3 && %1 < sad_avg2_h-1
    lea           r1, [r1+8*r3]
    lea           r2, [r2+8*r3]
%endif
%endmacro

; 8 wide, row k: one row per xmm (as pixel_sad_8x8), src2 and fenc as memory
; operands, even/odd row accumulators xm0/xm1
%macro SAD_AVG2_HBD_ROW8 1 ; row
    SAD_HBD_XOFF  %1&3, r3, r4
    movu          xm2, [r1+sad_off]
    pavgw         xm2, [r2+sad_off]
    psubw         xm2, [r0+%1*FENC_STRIDEB]
    SAD_HBD_XACC  %1
%if (%1&3) == 3 && %1 < sad_avg2_h-1
    lea           r1, [r1+4*r3]
    lea           r2, [r2+4*r3]
%endif
%endmacro

%macro SAD_AVG2_HBD 2 ; width, height
%assign sad_avg2_h %2
%if %1 == 16
cglobal pixel_sad_avg2_%1x%2, 4,5,4
    lea           r4, [r3+2*r3]
%assign sad_avg2_k 0
%rep %2
    SAD_AVG2_HBD_ROW16 sad_avg2_k
%assign sad_avg2_k sad_avg2_k+1
%endrep
    paddw         m0, m2
    HADDW         m0, m1
    movd         eax, xm0
    RET
%else
cglobal pixel_sad_avg2_%1x%2, 4,5,3
    FIX_STRIDES   r3
    lea           r4, [r3+2*r3]
%assign sad_avg2_k 0
%rep %2
    SAD_AVG2_HBD_ROW8 sad_avg2_k
%assign sad_avg2_k sad_avg2_k+1
%endrep
    SAD_HBD_XEND
%endif
%endmacro

SAD_AVG2_HBD 16, 16
SAD_AVG2_HBD 16,  8
INIT_XMM avx2
SAD_AVG2_HBD  8, 16
SAD_AVG2_HBD  8,  8

;-----------------------------------------------------------------------------
; void intra_sad_x3_4x4( uint16_t *fenc, uint16_t *fdec, int res[3] );
;-----------------------------------------------------------------------------

%macro INTRA_SAD_X3_4x4 0
cglobal intra_sad_x3_4x4, 3,3,7
%if cpuflag(ssse3)
    movddup   m0, [r1-1*FDEC_STRIDEB]
%else
    movq      m0, [r1-1*FDEC_STRIDEB]
    punpcklqdq m0, m0
%endif
    movq      m1, [r0+0*FENC_STRIDEB]
    movq      m2, [r0+2*FENC_STRIDEB]
    pshuflw   m6, m0, q1032
    paddw     m6, m0
    pshuflw   m5, m6, q2301
    paddw     m6, m5
    punpcklqdq m6, m6       ; A+B+C+D 8 times
    movhps    m1, [r0+1*FENC_STRIDEB]
    movhps    m2, [r0+3*FENC_STRIDEB]
    psubw     m3, m1, m0
    psubw     m0, m2
    ABSW2     m3, m0, m3, m0, m4, m5
    paddw     m0, m3
    movd      m3, [r1+0*FDEC_STRIDEB-4]
    movd      m4, [r1+2*FDEC_STRIDEB-4]
    movhps    m3, [r1+1*FDEC_STRIDEB-8]
    movhps    m4, [r1+3*FDEC_STRIDEB-8]
    pshufhw   m3, m3, q3333
    pshufhw   m4, m4, q3333
    pshuflw   m3, m3, q1111 ; FF FF EE EE
    pshuflw   m4, m4, q1111 ; HH HH GG GG
    paddw     m5, m3, m4
    paddw     m6, [pw_4]
    paddw     m6, m5
    pshufd    m5, m5, q1032
    paddw     m5, m6
    psrlw     m5, 3
    psubw     m6, m5, m2
    psubw     m5, m1
    psubw     m1, m3
    psubw     m2, m4
    ABSW2     m5, m6, m5, m6, m3, m4
    ABSW2     m1, m2, m1, m2, m3, m4
    paddw     m5, m6
    paddw     m1, m2
%if cpuflag(ssse3)
    phaddw    m0, m1
    movhlps   m3, m5
    paddw     m5, m3
    phaddw    m0, m5
    pmaddwd   m0, [pw_1]
    mova    [r2], m0
%else
    HADDW     m0, m3
    HADDW     m1, m3
    HADDW     m5, m3
    movd    [r2], m0 ; V prediction cost
    movd  [r2+4], m1 ; H prediction cost
    movd  [r2+8], m5 ; DC prediction cost
%endif
    RET
%endmacro

INIT_XMM sse2
INTRA_SAD_X3_4x4
INIT_XMM ssse3
INTRA_SAD_X3_4x4
INIT_XMM avx
INTRA_SAD_X3_4x4

;-----------------------------------------------------------------------------
; void intra_sad_x3_8x8( pixel *fenc, pixel edge[36], int res[3] );
;-----------------------------------------------------------------------------

;m0 = DC
;m6 = V
;m7 = H
;m1 = DC score
;m2 = V score
;m3 = H score
;m5 = temp
;m4 = pixel row

%macro INTRA_SAD_HVDC_ITER 2
    mova        m4, [r0+(%1-4)*FENC_STRIDEB]
    psubw       m4, m0
    ABSW        m4, m4, m5
    ACCUM    paddw, 1, 4, %1
    mova        m4, [r0+(%1-4)*FENC_STRIDEB]
    psubw       m4, m6
    ABSW        m4, m4, m5
    ACCUM    paddw, 2, 4, %1
    pshufd      m5, m7, %2
    psubw       m5, [r0+(%1-4)*FENC_STRIDEB]
    ABSW        m5, m5, m4
    ACCUM    paddw, 3, 5, %1
%endmacro

%macro INTRA_SAD_X3_8x8 0
cglobal intra_sad_x3_8x8, 3,3,8
    add         r0, 4*FENC_STRIDEB
    movu        m0, [r1+7*SIZEOF_PIXEL]
    mova        m6, [r1+16*SIZEOF_PIXEL] ;V prediction
    mova        m7, m0
    paddw       m0, m6
    punpckhwd   m7, m7
    HADDW       m0, m4
    paddw       m0, [pw_8]
    psrlw       m0, 4
    SPLATW      m0, m0
    INTRA_SAD_HVDC_ITER 0, q3333
    INTRA_SAD_HVDC_ITER 1, q2222
    INTRA_SAD_HVDC_ITER 2, q1111
    INTRA_SAD_HVDC_ITER 3, q0000
    movq        m7, [r1+7*SIZEOF_PIXEL]
    punpcklwd   m7, m7
    INTRA_SAD_HVDC_ITER 4, q3333
    INTRA_SAD_HVDC_ITER 5, q2222
    INTRA_SAD_HVDC_ITER 6, q1111
    INTRA_SAD_HVDC_ITER 7, q0000
%if cpuflag(ssse3)
    phaddw      m2, m3     ; 2 2 2 2 3 3 3 3
    movhlps     m3, m1
    paddw       m1, m3     ; 1 1 1 1 _ _ _ _
    phaddw      m2, m1     ; 2 2 3 3 1 1 _ _
    pmaddwd     m2, [pw_1] ; 2 3 1 _
    mova      [r2], m2
%else
    HADDW       m2, m4
    HADDW       m3, m4
    HADDW       m1, m4
    movd    [r2+0], m2
    movd    [r2+4], m3
    movd    [r2+8], m1
%endif
    RET
%endmacro

INIT_XMM sse2
INTRA_SAD_X3_8x8
INIT_XMM ssse3
INTRA_SAD_X3_8x8

%macro INTRA_SAD_HVDC_ITER_YMM 2
    mova       xm4, [r0+(%1-4)*FENC_STRIDEB]
    vinserti128 m4, m4, [r0+%1*FENC_STRIDEB], 1
    pshufd      m5, m7, %2
    psubw       m5, m4
    pabsw       m5, m5
    ACCUM    paddw, 2, 5, %1 ; H
    psubw       m5, m4, m6
    psubw       m4, m0
    pabsw       m5, m5
    pabsw       m4, m4
    ACCUM    paddw, 1, 5, %1 ; V
    ACCUM    paddw, 3, 4, %1 ; DC
%endmacro

INIT_YMM avx2
cglobal intra_sad_x3_8x8, 3,3,8
    add            r0, 4*FENC_STRIDEB
    movu          xm0, [r1+7*SIZEOF_PIXEL]
    vbroadcasti128 m6, [r1+16*SIZEOF_PIXEL] ; V prediction
    vpermq         m7, m0, q0011
    paddw         xm0, xm6
    paddw         xm0, [pw_1] ; equal to +8 after HADDW
    HADDW         xm0, xm4
    psrld         xm0, 4
    vpbroadcastw   m0, xm0
    punpcklwd      m7, m7
    INTRA_SAD_HVDC_ITER_YMM 0, q3333
    INTRA_SAD_HVDC_ITER_YMM 1, q2222
    INTRA_SAD_HVDC_ITER_YMM 2, q1111
    INTRA_SAD_HVDC_ITER_YMM 3, q0000
    phaddw         m1, m2     ; 1 1 1 1 2 2 2 2 1 1 1 1 2 2 2 2
    punpckhqdq     m2, m3, m3
    paddw          m3, m2     ; 3 3 3 3 _ _ _ _ 3 3 3 3 _ _ _ _
    phaddw         m1, m3     ; 1 1 2 2 3 3 _ _ 1 1 2 2 3 3 _ _
    vextracti128  xm2, m1, 1
    paddw         xm1, xm2    ; 1 1 2 2 3 3 _ _
    pmaddwd       xm1, [pw_1] ; 1 2 3 _
    mova         [r2], xm1
    RET

;=============================================================================
; me_hex_16x16, 10-bit: sads as in sad_x3/sad_x4 16x16 (fenc - ref, pabsw, word sums),
; AVX2 reloads fenc a row at a time, AVX-512 (ymm) keeps it in m0-m15 (ymm16-31)
;=============================================================================
%if ARCH_X86_64
;-----------------------------------------------------------------------------
; uint64_t me_hex_16x16( pixel *fenc, pixel *ref, intptr_t stride, uint16_t *cost_mvx,
;                        uint16_t *cost_mvy, int bmx, int bmy, int bcost, uint32_t mv_min,
;                        uint32_t mv_max, int i_me_range )
; x264_me_hex_16x16_c in one function. Candidates are 64*(sad + mv cost) + idx, the best
; 64*bcost + idx, reduced with pminsd as in sad_x3_min/sad_x4_min.
;
; uint64_t me_hex_walk_16x16( pixel *fenc, pixel *ref, intptr_t stride, uint16_t *cost_mvx,
;                             uint16_t *cost_mvy, int bmx, int bmy, int bcost, uint32_t mv_min,
;                             uint32_t mv_max, int i, int dir )
; x264_me_hex_walk_16x16_c: the same from me.c's state after the hexagon moved, entered at
; the loop test: bmx, bmy the moved centre (CHECK_MVRANGE'd here, as before each step), bcost
; (cost << 6) | idx with idx not read, i the loop count (me.c: (i_me_range>>1) - 1, <= 0 is
; the square refine alone), dir 0..5 (r10 = dir+1, the hex2 index of the move).
; r1 ref at the centre, r2 stride (bytes), r3/r4 cost_mvx/y + 8*bmx/bmy, r5 3*stride,
; eax best, r7-r9/r14 candidates, r10 hex2 index, r11/r12 temps, r13 me_hex_tab
;-----------------------------------------------------------------------------
%assign HX_OFF   0    ; stack: hex2[t mod 6] in bytes at 8*(t+1), t = -1..8
%assign HX_BASEX 80   ; cost_mvx
%assign HX_BASEY 88   ; cost_mvy
%assign HX_ICNT  96   ; hexagon steps left (+ 1 in me_hex_16x16)
%assign HX_STACK 104
%assign HX_IDX   0    ; me_hex_tab
%assign HX_MOD6  80
%assign HX_HEX   90
%assign HX_SQ    108

; in: r11 = bmx, r12 = bmy, r10d = i_me_range (%1 = 1) or the count (%1 = 0), the stack
; allocated; r10 is kept
%macro HX_PROLOGUE 1
%if HIGH_BIT_DEPTH
    add            r2, r2
%endif
%if %1
    sar          r10d, 1
%endif
    mov  [rsp+HX_ICNT], r10d
    mov  [rsp+HX_BASEX], r3
    mov  [rsp+HX_BASEY], r4
    lea            r3, [r3+r11*8]
    lea            r4, [r4+r12*8]
    imul          r12, r2
    lea            r1, [r1+r11*SIZEOF_PIXEL]
    add            r1, r12
    lea            r5, [r2*3]
    lea           r13, [me_hex_tab]
    lea           r11, [r2*2+SIZEOF_PIXEL] ; ( 1, 2)
    lea           r12, [r2*2-SIZEOF_PIXEL] ; (-1, 2)
    mov  [rsp+HX_OFF+4*8], r11
    mov  [rsp+HX_OFF+3*8], r12
    mov  [rsp+HX_OFF+9*8], r12
    neg           r11                      ; (-1,-2)
    neg           r12                      ; ( 1,-2)
    mov  [rsp+HX_OFF+1*8], r11
    mov  [rsp+HX_OFF+7*8], r11
    mov  [rsp+HX_OFF+0*8], r12
    mov  [rsp+HX_OFF+6*8], r12
    mov qword [rsp+HX_OFF+2*8], -2*SIZEOF_PIXEL ; (-2, 0)
    mov qword [rsp+HX_OFF+8*8], -2*SIZEOF_PIXEL
    mov qword [rsp+HX_OFF+5*8], 2*SIZEOF_PIXEL  ; ( 2, 0)
%endmacro

; r11d = cost_mvx + cost_mvy at byte offsets %1, %2 from the centre
%macro HX_MVCOST 2
    movzx        r11d, word [r3+%1]
    movzx        r12d, word [r4+%2]
    add          r11d, r12d
%endmacro

; the same at hex2[r10-1+%1]
%macro HX_MVCOST_DIR 1
    movsx         r11, byte [r13+r10*2+HX_HEX+2*%1-2]
    movsx         r12, byte [r13+r10*2+HX_HEX+2*%1-1]
    movzx        r11d, word [r3+r11*8]
    movzx        r12d, word [r4+r12*8]
    add          r11d, r12d
%endmacro

; %1 = { c0 c1 }, %2 = { c2 c3 } mv costs -> %1 = (c << 6) | idx, %2 = %1 lanes 2, 3
%macro HX_BIAS 3 ; x, x, me_hex_tab offset of the idx
    punpcklqdq     %1, %2
    pslld          %1, 6
    por            %1, [r13+%3]
    pshufd         %2, %1, q1032
%endmacro

; CHECK_MVRANGE of the centre from the cost pointers, else jump to %1
%macro HX_CHECK_RANGE 1
    mov           r11, r3
    sub           r11, [rsp+HX_BASEX]
    shl          r11d, 13                  ; bmx << 16
    mov           r12, r4
    sub           r12, [rsp+HX_BASEY]
    shr          r12d, 3
    and          r12d, 0x7fff
    or           r11d, r12d
    mov          r12d, r9m                 ; mv_max
    sub          r12d, r11d
    add          r11d, r8m                 ; mv_min
    or           r11d, r12d
    test         r11d, 0x80004000
    jnz %1
%endmacro

; %1 = { min( c0, c2 ), min( c1, c3 ) } -> eax
%macro HX_MIN_END 2 ; x, x tmp
    psrlq          %2, %1, 32
    pminsd         %1, %2
    movd          eax, %1
%endmacro

; move the centre by hex2[r10]
%macro HX_MOVE 0
    add            r1, [rsp+r10*8+HX_OFF+8]
    movsx         r11, byte [r13+r10*2+HX_HEX]
    movsx         r12, byte [r13+r10*2+HX_HEX+1]
    lea            r3, [r3+r11*8]
    lea            r4, [r4+r12*8]
%endmacro

; a hexagon step's candidates hex2[r10-1..r10+1] around the centre, eax the best; then
; r10 = the hex2 index of the next move, zf if none was better
%macro HX_STEP 0
    mov            r7, [rsp+r10*8+HX_OFF]
    mov            r8, [rsp+r10*8+HX_OFF+8]
    mov            r9, [rsp+r10*8+HX_OFF+16]
    add            r7, r1
    add            r8, r1
    add            r9, r1
    HX_MVCOST_DIR   0
    vmovd       xhxB0, r11d
    HX_MVCOST_DIR   1
    vpinsrd     xhxB0, xhxB0, r11d, 1
    HX_MVCOST_DIR   2
    vmovd       xhxB1, r11d
    mov          r11d, eax
    shr          r11d, 6
    vpinsrd     xhxB1, xhxB1, r11d, 1
    movzx        r10d, byte [r13+r10+HX_MOD6]
    HX_BIAS     xhxB0, xhxB1, HX_IDX
    HX_SAD_X3      r7, r8, r9
    HX_END_X3
    HX_MIN_END  xhxA0, xhxA1
    mov          r11d, eax
    and          r11d, 63
    lea           r10, [r10+r11-1]
%endmacro

; needs HX_LOAD_FENC, HX_SAD_X3/X4 (pointers) and HX_END_X3/X4 (xhxA0 = the pairwise
; min of the candidates and the bias registers hxB0/hxB1) and the xmm names xhxA0,
; xhxA1, xhxB0, xhxB1, xhxP, xhxBEST
%macro HX_BODY 0
    movsxd        r11, r5m                 ; first: r5 itself on unix64
    movsxd        r12, r6m
    mov           eax, r7m
    mov          r10d, r10m
    SUB           rsp, HX_STACK
    HX_PROLOGUE 1
    HX_LOAD_FENC
    ; hexagon: hex2[1..3] (idx 2-4), then hex2[4..6] (idx 5-7)
    lea            r7, [r1-2*SIZEOF_PIXEL]
    lea            r8, [r1+r2*2-SIZEOF_PIXEL]
    lea            r9, [r1+r2*2+SIZEOF_PIXEL]
    HX_MVCOST     -16, 0
    vmovd       xhxB0, r11d
    HX_MVCOST      -8, 16
    vpinsrd     xhxB0, xhxB0, r11d, 1
    HX_MVCOST       8, 16
    vmovd       xhxB1, r11d
    vpinsrd     xhxB1, xhxB1, eax, 1
    HX_BIAS     xhxB0, xhxB1, HX_IDX+16
    HX_SAD_X3      r7, r8, r9
    HX_END_X3
    mova         xhxP, xhxA0
    lea           r12, [r2*2]
    mov            r9, r1
    sub            r9, r12
    lea            r8, [r9+SIZEOF_PIXEL]
    sub            r9, SIZEOF_PIXEL
    lea            r7, [r1+2*SIZEOF_PIXEL]
    HX_MVCOST      16, 0
    vmovd       xhxB0, r11d
    HX_MVCOST       8, -16
    vpinsrd     xhxB0, xhxB0, r11d, 1
    HX_MVCOST      -8, -16
    vmovd       xhxB1, r11d
    vpinsrd     xhxB1, xhxB1, eax, 1
    HX_BIAS     xhxB0, xhxB1, HX_IDX+32
    HX_SAD_X3      r7, r8, r9
    HX_END_X3
    pminsd      xhxA0, xhxP
    HX_MIN_END  xhxA0, xhxA1
    mov          r11d, eax
    and          r11d, 63
    lea           r10, [r11-1]
    jz .square
.step:
    ; move by hex2[r10], the candidates are hex2[r10-1..r10+1] around the new centre
    HX_MOVE
    dec dword [rsp+HX_ICNT]
    jle .square
    HX_CHECK_RANGE .square
    HX_STEP
    jnz .step
    HX_SQUARE
%endmacro

; the square refine around the centre and the result
%macro HX_SQUARE 0
.square:
    ; square1[1..4] (idx 1-4), then square1[5..8] (idx 5-8)
    and           eax, ~63
    mov            r7, r1
    sub            r7, r2
    lea            r8, [r1+r2]
    lea            r9, [r1-SIZEOF_PIXEL]
    lea           r14, [r1+SIZEOF_PIXEL]
    HX_MVCOST       0, -8
    vmovd       xhxB0, r11d
    HX_MVCOST       0, 8
    vpinsrd     xhxB0, xhxB0, r11d, 1
    HX_MVCOST      -8, 0
    vmovd       xhxB1, r11d
    HX_MVCOST       8, 0
    vpinsrd     xhxB1, xhxB1, r11d, 1
    HX_BIAS     xhxB0, xhxB1, HX_IDX+48
    HX_SAD_X4      r7, r8, r9, r14
    vmovd     xhxBEST, eax
    pshufd    xhxBEST, xhxBEST, 0
    HX_END_X4
    pminsd       xhxP, xhxA0, xhxBEST
    mov            r8, r1
    sub            r8, r2
    lea            r7, [r8-SIZEOF_PIXEL]
    lea            r9, [r8+SIZEOF_PIXEL]
    lea            r8, [r1+r2-SIZEOF_PIXEL]
    lea           r14, [r1+r2+SIZEOF_PIXEL]
    HX_MVCOST      -8, -8
    vmovd       xhxB0, r11d
    HX_MVCOST      -8, 8
    vpinsrd     xhxB0, xhxB0, r11d, 1
    HX_MVCOST       8, -8
    vmovd       xhxB1, r11d
    HX_MVCOST       8, 8
    vpinsrd     xhxB1, xhxB1, r11d, 1
    HX_BIAS     xhxB0, xhxB1, HX_IDX+64
    HX_SAD_X4      r7, r8, r9, r14
    HX_END_X4
    pminsd      xhxA0, xhxP
    HX_MIN_END  xhxA0, xhxA1
    ; bcost | pack16to32_mask( bmx, bmy ) << 32
    mov          r11d, eax
    and          r11d, 63
    sar           eax, 6                   ; bcost >>= 6
    movsx         r12, byte [r13+r11*2+HX_SQ+1]
    movsx         r11, byte [r13+r11*2+HX_SQ]
    sub            r3, [rsp+HX_BASEX]
    sub            r4, [rsp+HX_BASEY]
    sar            r3, 3
    sar            r4, 3
    add            r3, r11
    add            r4, r12
    shl           r4d, 16
    movzx         r3d, r3w
    or            r3d, r4d
    shl            r3, 32
    or            rax, r3
    ADD           rsp, HX_STACK
    RET
%endmacro

; me_hex_walk_16x16: HX_BODY entered at its loop test after the hexagon's move
%macro HX_WALK_BODY 0
    movsxd        r11, r5m                 ; first: r5 itself on unix64
    movsxd        r12, r6m
    mov           eax, r7m
    mov          r10d, r10m                ; i
    SUB           rsp, HX_STACK
    HX_PROLOGUE 0
    HX_LOAD_FENC
    test         r10d, r10d
    mov          r10d, r11m                ; dir
    lea          r10d, [r10+1]
    jle .square
.step:
    HX_CHECK_RANGE .square
    HX_STEP
    jz .square
    HX_MOVE
    dec dword [rsp+HX_ICNT]
    jg .step
    HX_SQUARE
%endmacro

%macro HX10_REGS 0
%if cpuflag(avx512)
    %define hxA0 m16
    %define hxA1 m17
    %define hxA2 m18
    %define hxA3 m19
    %define hxT0 m20
    %define hxT1 m21
    %define hxT2 m22
    %define hxT3 m23
    %define hxB0 m24
    %define hxB1 m25
    %define hxPW m26
    %define hxZ  m27
    %define xhxA0   xm16
    %define xhxA1   xm17
    %define xhxA2   xm18
    %define xhxA3   xm19
    %define xhxT0   xm20
    %define xhxB0   xm24
    %define xhxB1   xm25
    %define xhxP    xm28
    %define xhxBEST xm29
%else
    %define hxA0 m0
    %define hxA1 m1
    %define hxA2 m2
    %define hxA3 m3
    %define hxF  m4
    %define hxT0 m5
    %define hxT1 m8
    %define hxT2 m9
    %define hxT3 m4                 ; fenc, last use
    %define hxB0 m6
    %define hxB1 m7
    %define hxPW m10
    %define hxZ  m11
    %define xhxA0   xm0
    %define xhxA1   xm1
    %define xhxA2   xm2
    %define xhxA3   xm3
    %define xhxT0   xm5
    %define xhxB0   xm6
    %define xhxB1   xm7
    %define xhxP    xm12
    %define xhxBEST xm13
%endif
%endmacro

%macro HX_LOAD_FENC 0
%if cpuflag(avx512)
%assign hx_r 0
%rep 16
    mova      m %+ hx_r, [r0+hx_r*FENC_STRIDEB]
%assign hx_r hx_r+1
%endrep
%endif
    vpbroadcastd hxPW, [pw_64]
    pxor         hxZ, hxZ
%endmacro

; row hx_r: hx_f = fenc row, hx_off = its offset in a group of 4 rows
%macro HX_ROW 0
%if (hx_r & 3) == 0
    %xdefine hx_off 0
%elif (hx_r & 3) == 1
    %xdefine hx_off r2
%elif (hx_r & 3) == 2
    %xdefine hx_off r2*2
%else
    %xdefine hx_off r5
%endif
%if cpuflag(avx512)
    %xdefine hx_f m %+ hx_r
%else
    mova          hxF, [r0+hx_r*FENC_STRIDEB]
    %xdefine hx_f hxF
%endif
%endmacro

; A0-A2 = word sads of the 16x16 at %1-%3 (the pointers advance 12 rows)
%macro HX_SAD_X3 3
%assign hx_r 0
%rep 16
    HX_ROW
%if hx_r == 0
    psubw        hxA0, hx_f, [%1]
    psubw        hxA1, hx_f, [%2]
    psubw        hxA2, hx_f, [%3]
    pabsw        hxA0, hxA0
    pabsw        hxA1, hxA1
    pabsw        hxA2, hxA2
%else
    psubw        hxT0, hx_f, [%1+hx_off]
    psubw        hxT1, hx_f, [%2+hx_off]
    psubw        hxT2, hx_f, [%3+hx_off]
    pabsw        hxT0, hxT0
    pabsw        hxT1, hxT1
    pabsw        hxT2, hxT2
    paddw        hxA0, hxT0
    paddw        hxA1, hxT1
    paddw        hxA2, hxT2
%endif
%if (hx_r & 3) == 3 && hx_r < 15
    lea            %1, [%1+r2*4]
    lea            %2, [%2+r2*4]
    lea            %3, [%3+r2*4]
%endif
%assign hx_r hx_r+1
%endrep
%endmacro

; A0-A3 = word sads of the 16x16 at %1-%4
%macro HX_SAD_X4 4
%assign hx_r 0
%rep 16
    HX_ROW
%if hx_r == 0
    psubw        hxA0, hx_f, [%1]
    psubw        hxA1, hx_f, [%2]
    psubw        hxA2, hx_f, [%3]
    psubw        hxA3, hx_f, [%4]
    pabsw        hxA0, hxA0
    pabsw        hxA1, hxA1
    pabsw        hxA2, hxA2
    pabsw        hxA3, hxA3
%else
    psubw        hxT0, hx_f, [%1+hx_off]
    psubw        hxT1, hx_f, [%2+hx_off]
    psubw        hxT2, hx_f, [%3+hx_off]
    psubw        hxT3, hx_f, [%4+hx_off]
    pabsw        hxT0, hxT0
    pabsw        hxT1, hxT1
    pabsw        hxT2, hxT2
    pabsw        hxT3, hxT3
    paddw        hxA0, hxT0
    paddw        hxA1, hxT1
    paddw        hxA2, hxT2
    paddw        hxA3, hxT3
%endif
%if (hx_r & 3) == 3 && hx_r < 15
    lea            %1, [%1+r2*4]
    lea            %2, [%2+r2*4]
    lea            %3, [%3+r2*4]
    lea            %4, [%4+r2*4]
%endif
%assign hx_r hx_r+1
%endrep
%endmacro

; A0-A2 word sads, B0 = { b0 b1 }, B1 = { b2 best } -> xA0 = { min( c0, c2 ), min( c1, best ) }
%macro HX_END_X3 0
    pmaddwd      hxA0, hxPW
    pmaddwd      hxA1, hxPW
    pmaddwd      hxA2, hxPW
    punpckldq    hxT0, hxA0, hxA1
    punpckhdq    hxA0, hxA1
    punpckldq    hxA1, hxA2, hxZ
    punpckhdq    hxA2, hxZ
    paddd        hxA0, hxT0          ; { a02 b02 a13 b13 | a46 b46 a57 b57 }
    paddd        hxA2, hxA1          ; { c02 0 c13 0 | c46 0 c57 0 }
    pshufd       hxA1, hxA0, q1032
    pshufd       hxT0, hxA2, q1032
    paddd        hxA0, hxB0
    paddd        hxA2, hxB1
    paddd        hxA0, hxA1
    paddd        hxA2, hxT0
    vextracti128 xhxA1, hxA0, 1
    vextracti128 xhxT0, hxA2, 1
    paddd       xhxA0, xhxA1
    paddd       xhxA2, xhxT0
    pminsd      xhxA0, xhxA2
%endmacro

; A0-A3 word sads, B0 = { b0 b1 }, B1 = { b2 b3 } -> xA0 = { min( c0, c2 ), min( c1, c3 ) }
%macro HX_END_X4 0
    pmaddwd      hxA0, hxPW
    pmaddwd      hxA1, hxPW
    pmaddwd      hxA2, hxPW
    pmaddwd      hxA3, hxPW
    punpckldq    hxT0, hxA0, hxA1
    punpckhdq    hxA0, hxA1
    punpckldq    hxT1, hxA2, hxA3
    punpckhdq    hxA2, hxA3
    paddd        hxA0, hxT0
    paddd        hxA2, hxT1
    pshufd       hxA1, hxA0, q1032
    pshufd       hxA3, hxA2, q1032
    paddd        hxA0, hxB0
    paddd        hxA2, hxB1
    paddd        hxA0, hxA1
    paddd        hxA2, hxA3
    vextracti128 xhxA1, hxA0, 1
    vextracti128 xhxA3, hxA2, 1
    paddd       xhxA0, xhxA1
    paddd       xhxA2, xhxA3
    pminsd      xhxA0, xhxA2
%endmacro

INIT_YMM avx2
HX10_REGS
cglobal me_hex_16x16, 5,15,14
    HX_BODY

cglobal pixel_me_hex_walk_16x16, 5,15,14
    HX_WALK_BODY

INIT_YMM avx512
HX10_REGS
cglobal me_hex_16x16, 5,15,30
    HX_BODY

cglobal pixel_me_hex_walk_16x16, 5,15,30
    HX_WALK_BODY
%endif ; ARCH_X86_64
