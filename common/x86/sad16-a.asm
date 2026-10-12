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

; me_hex_16x16: +0 the hexagon's groups, +96 the square's (vpermd lanes of dx,
; dy; idx); +192 square1; +224 + 160*u a step in direction hex2[u]: lanes of
; hex2[u-1..u+1], (dy + 2, dx) of the pointers, the move, flags (V2)
ALIGN 16
me_hex_tab: dd 0, 2, 6, 0, 7, 6, 2, 0
            dd 4, 7, 7, 0, 4, 0, 0, 0
            dd 9, 18, 27, 0x7e000000, 36, 45, 48, 0x7e000000
            dd 4, 4, 2, 6, 2, 2, 6, 6
            dd 2, 6, 4, 4, 2, 6, 2, 6
            dd 1, 2, 3, 4, 5, 6, 7, 8
            db 0,0, 0,-1, 0,1, -1,0, 1,0, -1,-1, -1,1, 1,-1, 1,1
            dw 0, 0, 0, 0, 0, 0, 0
            dd 6, 2, 0, 0
            dd 0, 0, 4, 0
            dd 13, 16, 25, 0x7e000000
            dq 0, 0, 2, 0
            dq 2, -2, -4, 2
            dq -2, -2, -8, -16
            dd 1, 0, 0, 0
            dd 2, 0, 2, 0
            dd 0, 4, 7, 0
            dd 8, 17, 26, 0x7e000000
            dq 0, 2, 4, 0
            dq -2, -4, -2, -2
            dq 0, -4, -16, 0
            dd 1, 0, 0, 0
            dd 0, 2, 6, 0
            dd 4, 7, 7, 0
            dd 9, 18, 27, 0x7e000000
            dq 2, 4, 4, 2
            dq -4, -2, 2, -4
            dq 2, -2, -8, 16
            dd 1, 0, 0, 0
            dd 2, 6, 7, 0
            dd 7, 7, 4, 0
            dd 10, 19, 28, 0x7e000000
            dq 4, 4, 2, 4
            dq -2, 2, 4, -2
            dq 2, 2, 8, 16
            dd 1, 0, 0, 0
            dd 6, 7, 6, 0
            dd 7, 4, 0, 0
            dd 11, 20, 29, 0x7e000000
            dq 4, 2, 0, 4
            dq 2, 4, 2, 2
            dq 0, 4, 16, 0
            dd 1, 0, 0, 0
            dd 7, 6, 2, 0
            dd 4, 0, 0, 0
            dd 12, 21, 24, 0x7e000000
            dq 2, 0, 0, 2
            dq 4, 2, -2, 4
            dq -2, 2, 8, -16
            dd 1, 0, 0, 0

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
; me_hex_16x16, 10-bit: sads as in sad_x4 16x16 (fenc - ref, pabsw, word sums). AVX2
; keeps fenc rows 0-6 in m9-m15 (7-15 reloaded a group from r10), AVX-512 (ymm) all 16
; in m0-m15 (ymm16-31) with the work in m16-m27 (ymm0-11)
;=============================================================================
%if ARCH_X86_64
;-----------------------------------------------------------------------------
; uint64_t me_hex_16x16( pixel *fenc, pixel *ref, intptr_t stride, uint16_t *cost_mvx,
;                        uint16_t *cost_mvy, int bmx, int bmy, int bcost, uint32_t mv_min,
;                        uint32_t mv_max, int i_me_range )
; x264_me_hex_16x16_c in one function, the candidates in groups of 4 (HX_GROUP): the sads
; of the 16x16 at r0, r1, r6, r9, best = pminsd( best, 64*sad + bias ), bias = 64*mv cost
; + idx a lane. A group of 3 repeats its first pointer with idx 0x7e000000, above every
; candidate and 64*bcost for bcost < 2^25 - 2^19, and 64*sad + it does not overflow.
; idx: the hexagon's and a step's 8*(lane + 1) + u for a move to hex2[u] (u 0-5), the
; square's 1-8. The mv costs: Z = cost_mvx (low words), cost_mvy (high words) at -2..2
; from the centre in dwords 0, 2, 4, 6, 7, vpermd by the table's lanes.
; r7 ref at the centre - 2 rows, r2 stride (bytes), r3 3*stride, r4/r5 cost_mvy/x +
; 8*bmy/bmx, r8 a table block + 64, hxBX/hxBY cost_mvx/y, hxN hexagon steps left + 1
;-----------------------------------------------------------------------------
%define hxP0  r0
%define hxP1  r1
%define hxP2  r6
%define hxP3  r9
%define hxBLK r8

; bx, by, n
%macro HX_GPRS 3
    %xdefine hxBX  r%1
    %xdefine hxBY  r%2
    %xdefine hxN   r%3
    %xdefine hxNd  r%3d
%endmacro

; a, t, best, b, s, u: acc a..a+3, temp, best, bias, S (V1) or Z (V2), setup temps u..u+2
%macro HX_REGS 6
    %assign HXA %1
    %xdefine hxA0    m%1
    %xdefine xhxA0   xm%1
    %xdefine hxT     m%2
    %xdefine xhxT    xm%2
    %xdefine xhxBEST xm%3
    %xdefine hxB     m%4
    %xdefine xhxB    xm%4
    %xdefine hxS     m%5
    %xdefine hxU0    m%6
    %assign hx_u %6+1
    %xdefine hxU1    m %+ hx_u
    %xdefine xhxU1   xm %+ hx_u
    %assign hx_u %6+2
    %xdefine hxU2    m %+ hx_u
    %xdefine xhxU2   xm %+ hx_u
    %assign hx_u %1+1
    %xdefine hxA1    m %+ hx_u
    %assign hx_u %1+2
    %xdefine hxA2    m %+ hx_u
    %assign hx_u %1+3
    %xdefine hxA3    m %+ hx_u
%endmacro

%macro HX_PROLOGUE 0
    movsxd         r6, r5m                 ; bmx, first: r5 itself on unix64
    movsxd         r8, r6m                 ; bmy
    mov          hxNd, r10m
%if HIGH_BIT_DEPTH
    add            r2, r2
%endif
    sar          hxNd, 1
    mov          hxBX, r3
    mov          hxBY, r4
    lea            r5, [r3+r6*8]
    lea            r4, [r4+r8*8]
    lea            r7, [r1+r6*SIZEOF_PIXEL]
    sub            r8, 2
    imul           r8, r2
    add            r7, r8
    lea            r3, [r2*3]
    vpbroadcastd xhxBEST, r7m
    pslld     xhxBEST, 6
%endmacro

; %1 = Z at the centre
%macro HX_COSTS 1
    movu           %1, [r5-16]
    vpbroadcastd  hxU1, [r5+16]
    vpblendd       %1, %1, hxU1, 0x80
    movu          hxU1, [r4-18]
    vpbroadcastd  hxU2, [r4+14]
    vpblendd      hxU1, hxU1, hxU2, 0x80
    pblendw        %1, %1, hxU1, 0xaa
%endmacro

; %2 = 64*mv cost + idx of 4 (%1 = 1) or 8 (%1 = 2) lanes from Z %3 and the lanes at
; %4 + %5 (dx), %4 + %6 (dy), the idx at %4 + %7
%macro HX_BIAS 7
%if %1 == 1
    %define hx_a xhxU1
    %define hx_i xhxU2
%else
    %define hx_a hxU1
    %define hx_i hxU2
%endif
    movu         hx_i, [%4+%5]
    vpermd       hxU1, hxU2, %3
    movu         hx_i, [%4+%6]
    vpermd       hxU2, hxU2, %3
    psrld        hx_i, 16
    pblendw      hx_a, hx_a, hx_i, 0xaa
    paddd        hx_a, hx_i
    pslld        hx_a, 6
    paddd          %2, hx_a, [%4+%7]
%endmacro

; candidate %1 at (%2, %3) from the centre
%macro HX_PTR 3
%if %3 == -2
    lea        hxP%1, [r7+%2*SIZEOF_PIXEL]
%elif %3 == -1
    lea        hxP%1, [r7+r2+%2*SIZEOF_PIXEL]
%elif %3 == 0
    lea        hxP%1, [r7+r2*2+%2*SIZEOF_PIXEL]
%elif %3 == 1
    lea        hxP%1, [r7+r3+%2*SIZEOF_PIXEL]
%else
    lea        hxP%1, [r7+r2*4+%2*SIZEOF_PIXEL]
%endif
%endmacro

; the first %1 pointers from the block, a group of 3 repeats the first
%macro HX_PTRS_BLK 1
%assign hx_k 0
%rep %1
    %xdefine hx_pk hxP %+ hx_k
    mov         hx_pk, r2
    imul        hx_pk, [hxBLK+HX_DY+8*hx_k]
    add         hx_pk, r7
    add         hx_pk, [hxBLK+HX_DX+8*hx_k]
%assign hx_k hx_k+1
%endrep
%if %1 == 3
    mov         hxP3, hxP0
%endif
%endmacro

; best = its min in every lane
%macro HX_REDUCE 0
    pshufd       xhxT, xhxBEST, q1032
    pminsd    xhxBEST, xhxT
    pshufd       xhxT, xhxBEST, q2301
    pminsd    xhxBEST, xhxT
%endmacro

; r6 = u: the block of a step to hex2[u], move the centre, bcost &= ~63,
; Z at the new centre in %1
%macro HX_MOVE 1
    lea            r6, [r6+r6*4]
    shl            r6, 5
    lea         hxBLK, [me_hex_tab+HX_STEPB+64]
    add         hxBLK, r6
    add            r5, [hxBLK+HX_MCX]
    add            r4, [hxBLK+HX_MCY]
    add            r7, [hxBLK+HX_MVX]
    mov            r6, r2
    imul           r6, [hxBLK+HX_MVY]
    add            r7, r6
    psrld     xhxBEST, 6
    pslld     xhxBEST, 6
    HX_COSTS       %1
%endmacro

; CHECK_MVRANGE of the centre from the cost pointers, else jump to %1
%macro HX_CHECK_RANGE 1
    mov            r6, r5
    sub            r6, hxBX
    shl           r6d, 13                  ; bmx << 16
    mov            r9, r4
    sub            r9, hxBY
    shr           r9d, 3
    and           r9d, 0x7fff
    or            r6d, r9d
    mov           r9d, r9m                 ; mv_max
    sub           r9d, r6d
    add           r6d, r8m                 ; mv_min
    or            r6d, r9d
    test          r6d, 0x80004000
    jnz %1
%endmacro

; bcost | pack16to32_mask( bmx, bmy ) << 32
%macro HX_END 0
    movd          eax, xhxBEST
    mov           r1d, eax
    and           r1d, 63
    sar           eax, 6
    lea            r0, [me_hex_tab+HX_SQ1]
    movsx          r9, byte [r0+r1*2+1]
    movsx          r1, byte [r0+r1*2]
    sub            r5, hxBX
    sub            r4, hxBY
    sar            r5, 3
    sar            r4, 3
    add            r5, r1
    add            r4, r9
    shl           r4d, 16
    movzx         r5d, r5w
    or            r5d, r4d
    shl            r5, 32
    or            rax, r5
    RET
%endmacro

; a block (the steps', V2's groups), 160 bytes, from r8 = its start + 64: dword lanes of
; dx, dy (vpermd) and idx, qword (dy + 2, dx) of the pointers from r7, the move (dy, dx,
; 8*dx, 8*dy), V2's flags
%assign HX_IX  -64
%assign HX_IY  -48
%assign HX_ID  -32
%assign HX_DY  -16
%assign HX_DX  16
%assign HX_MVY 48
%assign HX_MVX 56
%assign HX_MCX 64
%assign HX_MCY 72
%assign HX_FL  80
; me_hex_tab from r8 = me_hex_tab + 96: the hexagon's groups (8 dword lanes of dx, dy,
; idx), the square's, square1, the step blocks
%assign HX_HIX   -96
%assign HX_HIY   -64
%assign HX_HID   -32
%assign HX_SIX   0
%assign HX_SIY   32
%assign HX_SID   64
%assign HX_SQ1   192
%assign HX_STEPB 224

; V1: .group called; hxB the biases of a pair of groups (the second's in the high lane),
; hxS the square's from the start
%macro HX_BODY 0
    HX_PROLOGUE
    HX_LOAD_FENC
    HX_COSTS      hxU0
    lea         hxBLK, [me_hex_tab+96]
    HX_BIAS 2, hxB, hxU0, hxBLK, HX_HIX, HX_HIY, HX_HID
    HX_BIAS 2, hxS, hxU0, hxBLK, HX_SIX, HX_SIY, HX_SID
    ; hexagon: hex2[1..3], hex2[4..6]
    HX_PTR 0, -2, 0
    HX_PTR 1, -1, 2
    HX_PTR 2,  1, 2
    mov          hxP3, hxP0
    call .group
    vextracti128 xhxB, hxB, 1
    HX_PTR 0,  2, 0
    HX_PTR 1,  1,-2
    HX_PTR 2, -1,-2
    mov          hxP3, hxP0
    call .group
    HX_REDUCE
    movd          r6d, xhxBEST
    and           r6d, 63
    jnz .step
.square:
    ; square1[1..4], square1[5..8]
    mova          hxB, hxS
    HX_PTR 0,  0,-1
    HX_PTR 1,  0, 1
    HX_PTR 2, -1, 0
    HX_PTR 3,  1, 0
    call .group
    vextracti128 xhxB, hxB, 1
    HX_PTR 0, -1,-1
    HX_PTR 1, -1, 1
    HX_PTR 2,  1,-1
    HX_PTR 3,  1, 1
    call .group
    HX_REDUCE
    HX_END
.group:
    HX_GROUP
    ret
.step:
    and           r6d, 7
    HX_MOVE       hxU0
    dec          hxNd
    jle .square_moved
    HX_CHECK_RANGE .square_moved
    HX_BIAS 1, xhxB, hxU0, hxBLK, HX_IX, HX_IY, HX_ID
    HX_PTRS_BLK 3
    call .group
    HX_REDUCE
    movd          r6d, xhxBEST
    and           r6d, 63
    jnz .step
    HX_COSTS      hxU0
.square_moved:
    HX_BIAS 2, hxS, hxU0, me_hex_tab+96, HX_SIX, HX_SIY, HX_SID
    jmp .square
%endmacro
%macro HX_LOAD_FENC 0
%if cpuflag(avx512)
%assign hx_r 0
%rep 16
    mova      m %+ hx_r, [r0+hx_r*FENC_STRIDEB]
%assign hx_r hx_r+1
%endrep
    vpbroadcastd  m27, [pw_64]
%else
    lea           r10, [r0+11*FENC_STRIDEB]
    sub            r0, -128
%assign hx_r 0
%rep 7
%assign hx_m hx_r+9
    mova      m %+ hx_m, [r0+hx_r*FENC_STRIDEB-128]
%assign hx_r hx_r+1
%endrep
%endif
%endmacro

; the word sads of the 16x16 at r0, r1, r6, r9 (advanced 12 rows), then the group's min
; into best
%macro HX_GROUP 0
%assign hx_r 0
%rep 16
%if (hx_r & 3) == 0
    %xdefine hx_off 0
%elif (hx_r & 3) == 1
    %xdefine hx_off r2
%elif (hx_r & 3) == 2
    %xdefine hx_off r2*2
%else
    %xdefine hx_off r3
%endif
%if cpuflag(avx512)
    %xdefine hx_f m %+ hx_r
%elif hx_r < 7
%assign hx_m hx_r+9
    %xdefine hx_f m %+ hx_m
%else
    mova           m7, [r10+(hx_r-11)*FENC_STRIDEB]
    %xdefine hx_f m7
%endif
%assign hx_k 0
%rep 4
    %xdefine hx_pk hxP %+ hx_k
%assign hx_ak HXA+hx_k
    %xdefine hx_a m %+ hx_ak
%if hx_r == 0
    psubw        hx_a, hx_f, [hx_pk]
    pabsw        hx_a, hx_a
%else
    psubw         hxT, hx_f, [hx_pk+hx_off]
    pabsw         hxT, hxT
    paddw        hx_a, hxT
%endif
%assign hx_k hx_k+1
%endrep
%if (hx_r & 3) == 3 && hx_r < 15
    lea          hxP0, [hxP0+r2*4]
    lea          hxP1, [hxP1+r2*4]
    lea          hxP2, [hxP2+r2*4]
    lea          hxP3, [hxP3+r2*4]
%endif
%assign hx_r hx_r+1
%endrep
    phaddw        hxA0, hxA1               ; a b | a b
    phaddw        hxA2, hxA3
%if cpuflag(avx512)
    pmaddwd       hxA0, m27
    pmaddwd       hxA2, m27
%else
    pmaddwd       hxA0, [pw_1]
    pmaddwd       hxA2, [pw_1]
%endif
    phaddd        hxA0, hxA2               ; a b c d | a b c d
    vextracti128  xhxT, hxA0, 1
    paddd        xhxA0, xhxT
%if notcpuflag(avx512)
    pslld        xhxA0, 6
%endif
    paddd        xhxA0, xhxB
    pminsd     xhxBEST, xhxA0
%endmacro

INIT_YMM avx2
HX_GPRS 11, 12, 13
HX_REGS 0, 4, 5, 6, 8, 0
cglobal me_hex_16x16, 5,14,16
    HX_BODY

INIT_YMM avx512
HX_GPRS 10, 11, 12
HX_REGS 16, 20, 21, 22, 23, 24
cglobal me_hex_16x16, 5,13,28
    HX_BODY
%endif ; ARCH_X86_64
