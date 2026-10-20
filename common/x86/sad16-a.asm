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

SECTION_RODATA 64

; pshufb: word 2p of an xmm splat over lanes 0-1, word 2p+1 over lanes 2-3
%assign i 0
isadhbd_hidx16:
%rep 8
    times 16 db 2*i, 2*i+1
%assign i i+1
%endrep
%undef i
; pshufb: word i of an xmm splat over lane i (rows 0-3), word i+4 (rows 4-7)
%assign i 0
isadhbd_hidx8:
%rep 8
    times 8 db 2*i, 2*i+1
%assign i i+1
%endrep
%undef i
; pshufb: { dc0 x4, dc1 x4 } and { dc2 x4, dc3 x4 } from dwords dc0-3
isadhbd_dcidx: times 4 db 0,1,0,1,0,1,0,1,4,5,4,5,4,5,4,5
               times 4 db 8,9,8,9,8,9,8,9,12,13,12,13,12,13,12,13
; chroma DC rounding: (s+2)>>2 = ((s>>1)+1)>>1, (s+4)>>3 = ((s>>2)+1)>>1
isadhbd_shift: dd 2, 1, 1, 2, 1, 2, 1, 2
; 8x16c DC: { s0 s1 s2 s3 s4 s4 s5 s5 } -> { s0, s1, s3, s1, s4, s1, s5, s1 } + { s2, 0, 0, s3, 0, s4, 0, s5 }
isadhbd_dcpa:  dd 0, 1, 3, 1, 4, 1, 6, 1
isadhbd_dcpb:  dd 2, 0, 0, 3, 0, 4, 0, 6
; 8x8 edge[7..14] = l7..l0 -> l0..l7
isadhbd_wrev:  db 14,15,12,13,10,11,8,9,6,7,4,5,2,3,0,1
; 4x4: { V rows 0-3 | H rows 0-3 } words from { l0 l1 l2 l3 t0 t1 t2 t3 }
isadhbd_p4idx: times 4 dw 4, 5, 6, 7
               dw 0,0,0,0, 1,1,1,1, 2,2,2,2, 3,3,3,3

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

%if ARCH_X86_64
;=============================================================================
; 10-bit 16 wide sad, sad_x3/sad_x4 (and _min), AVX-512: rows k, k+1 a zmm.
; The fenc pair is one 64 byte load (FENC_STRIDE apart), a reference pair a
; ymm load plus a merge-masked vbroadcasti64x4 into the upper half (k1 = 0xf0).
; Word sums, at most 8*1023 a lane.
;=============================================================================
; xm%1 = candidates, xm%2 = best in all lanes -> eax
%macro SAD_X_HBD_MIN_TREE 3 ; c, best, tmp
    pminsd       xm%2, xm%1
    pshufd       xm%3, xm%1, q1032
    pminsd       xm%1, xm%2, xm%3
    psrlq        xm%3, xm%1, 32
    pminsd       xm%1, xm%3
    movd          eax, xm%1
    RET
%endmacro

; m0..m3 = word sums of refs 1-4 (m3 zero for x3) -> xm0 = { sad1 sad2 sad3 sad4 },
; times %1 (pw_1 or pw_64)
%macro SAD_X_HBD16_ZMM_END 1
    vshufi64x2     m4, m0, m1, q1010
    vshufi64x2     m0, m0, m1, q3232
    vshufi64x2     m5, m2, m3, q1010
    vshufi64x2     m2, m2, m3, q3232
    paddw          m0, m4          ; { 1 | 2 }, at most 16*1023 a lane
    paddw          m2, m5          ; { 3 | 4 }
    vpbroadcastd   m6, [%1]
    pmaddwd        m0, m6
    pmaddwd        m2, m6
    vshufi64x2     m4, m0, m2, q2020
    vshufi64x2     m0, m0, m2, q3131
    paddd          m0, m4          ; lane i = ref i+1
    pshufd         m4, m0, q1032
    paddd          m0, m4
    pshufd         m4, m0, q2301
    paddd          m0, m4
    mov           r6d, 0x1111
    kmovw          k2, r6d
    vpcompressd    m0 {k2}{z}, m0
%endmacro

; rows k, k+1 of ref %1 against the fenc pair in m4: acc m%2, tmp m%3
%macro SAD_X_HBD16_ZMM_REF 4 ; ref, acc, tmp, first
    movu          ym%3, [%1+sad_off0]
    vbroadcasti64x4 m%3 {k1}, [%1+sad_off]
    psubw          m%3, m4
%if %4
    pabsw          m%2, m%3
%else
    pabsw          m%3, m%3
    paddw          m%2, m%3
%endif
%endmacro

%macro SAD_X_HBD16_ZMM 2-3 0 ; refs, height, min
%if %1 == 3
%if %3
cglobal pixel_sad_x3_min_16x%2, 5,7,8
%else
cglobal pixel_sad_x3_16x%2, 6,7,8
%endif
    %define sad_stride r4
%else
%if %3
cglobal pixel_sad_x4_min_16x%2, 6,7,8
%else
cglobal pixel_sad_x4_16x%2, 6,7,8
%endif
    %define sad_stride r5
%endif
    mov           r6d, 0xf0
    kmovb          k1, r6d
    lea            r6, [sad_stride+2*sad_stride]
%assign sad_hbd_k 0
%rep %2/2
    SAD_HBD_ROWOFF sad_hbd_k&3, sad_stride, r6
    %xdefine sad_off0 sad_off
    SAD_HBD_ROWOFF (sad_hbd_k+1)&3, sad_stride, r6
    movu           m4, [r0+sad_hbd_k*FENC_STRIDEB]
    SAD_X_HBD16_ZMM_REF r1, 0, 5, sad_hbd_k == 0
    SAD_X_HBD16_ZMM_REF r2, 1, 6, sad_hbd_k == 0
    SAD_X_HBD16_ZMM_REF r3, 2, 7, sad_hbd_k == 0
%if %1 == 4
    SAD_X_HBD16_ZMM_REF r4, 3, 5, sad_hbd_k == 0
%endif
%if (sad_hbd_k&3) == 2 && sad_hbd_k < %2-2
    lea            r1, [r1+8*sad_stride]
    lea            r2, [r2+8*sad_stride]
    lea            r3, [r3+8*sad_stride]
%if %1 == 4
    lea            r4, [r4+8*sad_stride]
%endif
%endif
%assign sad_hbd_k sad_hbd_k+2
%endrep
%if %1 == 3
    pxor           m3, m3
%endif
%if %3
    SAD_X_HBD16_ZMM_END pw_64
%if %1 == 3
    movq          xm4, r5mp        ; b0 b1
    movhps        xm4, r6mp        ; b2 best
    pshufd        xm5, xm4, q3333
%else
    movq          xm4, r6mp        ; b0 b1
    movhps        xm4, r7mp        ; b2 b3
    vpbroadcastd  xm5, r8m
%endif
    paddd         xm0, xm4
    SAD_X_HBD_MIN_TREE 0, 5, 1
%else
    SAD_X_HBD16_ZMM_END pw_1
%if %1 == 3
    movq      [r5+0], xm0
    pextrd    [r5+8], xm0, 2
%else
    mov            r6, r6mp
    movu         [r6], xm0
%endif
    RET
%endif
    %undef sad_stride
%endmacro

; 8 wide: lane i of a zmm = row k of ref i+1 (x3: lane 3 unused), fenc row k
; broadcast; even/odd rows in m0/m1 (at most 8*1023 a lane each)
%macro SAD_X_HBD8_ZMM 2-3 0 ; refs, height, min
%if %1 == 3
%if %3
cglobal pixel_sad_x3_min_8x%2, 5,7,8
%else
cglobal pixel_sad_x3_8x%2, 6,7,8
%endif
    %define sad_stride r4
%else
%if %3
cglobal pixel_sad_x4_min_8x%2, 6,7,8
%else
cglobal pixel_sad_x4_8x%2, 6,7,8
%endif
    %define sad_stride r5
%endif
    lea            r6, [sad_stride+2*sad_stride]
%assign sad_hbd_k 0
%rep %2
    SAD_HBD_ROWOFF sad_hbd_k&3, sad_stride, r6
    vbroadcasti32x4 m4, [r0+sad_hbd_k*FENC_STRIDEB]
    movu          xm5, [r1+sad_off]
    vinserti32x4   m5, [r2+sad_off], 1
    vinserti32x4   m5, [r3+sad_off], 2
%if %1 == 4
    vinserti32x4   m5, [r4+sad_off], 3
%endif
    psubw          m5, m4
%assign sad_acc sad_hbd_k&1
%if sad_hbd_k < 2
    pabsw m %+ sad_acc, m5
%else
    pabsw          m5, m5
    paddw m %+ sad_acc, m5
%endif
%if (sad_hbd_k&3) == 3 && sad_hbd_k < %2-1
    lea            r1, [r1+8*sad_stride]
    lea            r2, [r2+8*sad_stride]
    lea            r3, [r3+8*sad_stride]
%if %1 == 4
    lea            r4, [r4+8*sad_stride]
%endif
%endif
%assign sad_hbd_k sad_hbd_k+1
%endrep
    paddw          m0, m1          ; at most 16*1023 a lane
%if %3
    vpbroadcastd   m6, [pw_64]
%else
    vpbroadcastd   m6, [pw_1]
%endif
    pmaddwd        m0, m6
    pshufd         m1, m0, q1032
    paddd          m0, m1
    pshufd         m1, m0, q2301
    paddd          m0, m1
%if %1 == 3
    mov           r6d, 0x0111
%else
    mov           r6d, 0x1111
%endif
    kmovw          k1, r6d
    vpcompressd    m0 {k1}{z}, m0  ; x3: lane 3 zero
%if %3
%if %1 == 3
    movq          xm4, r5mp        ; b0 b1
    movhps        xm4, r6mp        ; b2 best
    pshufd        xm5, xm4, q3333
%else
    movq          xm4, r6mp        ; b0 b1
    movhps        xm4, r7mp        ; b2 b3
    vpbroadcastd  xm5, r8m
%endif
    paddd         xm0, xm4
    SAD_X_HBD_MIN_TREE 0, 5, 1
%else
%if %1 == 3
    movq      [r5+0], xm0
    pextrd    [r5+8], xm0, 2
%else
    mov            r6, r6mp
    movu         [r6], xm0
%endif
    RET
%endif
    %undef sad_stride
%endmacro

; sad( fenc, (src1+src2+1)>>1 ), 16 wide: rows k, k+1 a zmm for both sources
%macro SAD_AVG2_HBD16_ZMM 1 ; height
cglobal pixel_sad_avg2_16x%1, 4,5,4
    mov           r4d, 0xf0
    kmovb          k1, r4d
    lea            r4, [r3+2*r3]
%assign sad_hbd_k 0
%rep %1/2
    SAD_HBD_ROWOFF sad_hbd_k&3, r3, r4
    %xdefine sad_off0 sad_off
    SAD_HBD_ROWOFF (sad_hbd_k+1)&3, r3, r4
    movu          ym1, [r1+sad_off0]
    movu          ym3, [r2+sad_off0]
    vbroadcasti64x4 m1 {k1}, [r1+sad_off]
    vbroadcasti64x4 m3 {k1}, [r2+sad_off]
    pavgw          m1, m3
    psubw          m1, [r0+sad_hbd_k*FENC_STRIDEB]
%if sad_hbd_k == 0
    pabsw          m0, m1
%elif sad_hbd_k == 2
    pabsw          m2, m1
%else
    pabsw          m1, m1
%if sad_hbd_k & 2
    paddw          m2, m1
%else
    paddw          m0, m1
%endif
%endif
%if (sad_hbd_k&3) == 2 && sad_hbd_k < %1-2
    lea            r1, [r1+8*r3]
    lea            r2, [r2+8*r3]
%endif
%assign sad_hbd_k sad_hbd_k+2
%endrep
    SAD_HBD16_ZMM_END
%endmacro

; m0 + m2 (word sums, at most 8*1023 a lane) -> eax
%macro SAD_HBD16_ZMM_END 0
    paddw          m0, m2
    vextracti64x4 ym1, m0, 1
    paddw         ym0, ym1
    vpbroadcastd  ym1, [pw_1]
    pmaddwd       ym0, ym1
    vextracti128  xm1, ym0, 1
    paddd         xm0, xm1
    pshufd        xm1, xm0, q1032
    paddd         xm0, xm1
    psrlq         xm1, xm0, 32
    paddd         xm0, xm1
    movd          eax, xm0
    RET
%endmacro

; fenc rows FENC_STRIDE apart only, else the avx2 version (before the prologue)
%macro SAD_HBD16_ZMM 1 ; height
cglobal pixel_sad_16x%1
    cmp          r1mp, FENC_STRIDE
    jne pixel_sad_16x%1_avx2
    PROLOGUE 4,5,3
    mov           r4d, 0xf0
    kmovb          k1, r4d
    lea            r4, [r3+2*r3]
%assign sad_hbd_k 0
%rep %1/2
    SAD_HBD_ROWOFF sad_hbd_k&3, r3, r4
    %xdefine sad_off0 sad_off
    SAD_HBD_ROWOFF (sad_hbd_k+1)&3, r3, r4
    movu          ym1, [r2+sad_off0]
    vbroadcasti64x4 m1 {k1}, [r2+sad_off]
    psubw          m1, [r0+sad_hbd_k*FENC_STRIDEB]
%if sad_hbd_k == 0
    pabsw          m0, m1
%elif sad_hbd_k == 2
    pabsw          m2, m1
%else
    pabsw          m1, m1
%if sad_hbd_k & 2
    paddw          m2, m1
%else
    paddw          m0, m1
%endif
%endif
%if (sad_hbd_k&3) == 2 && sad_hbd_k < %1-2
    lea            r2, [r2+8*r3]
%endif
%assign sad_hbd_k sad_hbd_k+2
%endrep
    SAD_HBD16_ZMM_END
%endmacro

INIT_ZMM avx512
SAD_HBD16_ZMM 16
SAD_HBD16_ZMM  8
SAD_X_HBD16_ZMM 3, 16
SAD_X_HBD16_ZMM 3,  8
SAD_X_HBD16_ZMM 4, 16
SAD_X_HBD16_ZMM 4,  8
SAD_X_HBD16_ZMM 3, 16, 1
SAD_X_HBD16_ZMM 3,  8, 1
SAD_X_HBD16_ZMM 4, 16, 1
SAD_X_HBD16_ZMM 4,  8, 1
SAD_X_HBD8_ZMM 3, 16
SAD_X_HBD8_ZMM 3,  8
SAD_X_HBD8_ZMM 4, 16
SAD_X_HBD8_ZMM 4,  8
SAD_X_HBD8_ZMM 3, 16, 1
SAD_X_HBD8_ZMM 3,  8, 1
SAD_X_HBD8_ZMM 4, 16, 1
SAD_X_HBD8_ZMM 4,  8, 1
SAD_AVG2_HBD16_ZMM 16
SAD_AVG2_HBD16_ZMM  8

;-----------------------------------------------------------------------------
; void intra_sad_x3_16x16( uint16_t *fenc, uint16_t *fdec, int res[3] )
; AVX-512: a fenc row pair a zmm, the three predictions built in registers
; (no fdec stores), word sums (at most 8*1023 a lane) reduced by
; SAD_X_HBD16_ZMM_END.
;-----------------------------------------------------------------------------
; xm%1 = words -1 of rows 4*%2 .. 4*%2+3 of fdec (r1)
%macro INTRA_SAD_HBD_LEFT4 2
    movq          xm%1, [r1+FDEC_STRIDEB*(4*%2+3)-8]
    pinsrw        xm%1, [r1+FDEC_STRIDEB*(4*%2+0)-2], 0
    pinsrw        xm%1, [r1+FDEC_STRIDEB*(4*%2+1)-2], 1
    pinsrw        xm%1, [r1+FDEC_STRIDEB*(4*%2+2)-2], 2
%endmacro

cglobal intra_sad_x3_16x16, 3,7,12
    INTRA_SAD_HBD_LEFT4 0, 0
    INTRA_SAD_HBD_LEFT4 1, 1
    INTRA_SAD_HBD_LEFT4 2, 2
    INTRA_SAD_HBD_LEFT4 3, 3
    punpcklqdq    xm8, xm0, xm1        ; left 0-7
    punpcklqdq    xm9, xm2, xm3        ; left 8-15
    movu         ym10, [r1-FDEC_STRIDEB]
    paddw         xm1, xm8, xm9
    paddw         xm1, xm10
    vextracti128  xm2, ym10, 1
    paddw         xm1, xm2             ; at most 4*1023 a word
    pmaddwd       xm1, [pw_1]
    pshufd        xm2, xm1, q1032
    paddd         xm1, xm2
    pshufd        xm2, xm1, q2301
    paddd         xm1, xm2             ; sum, at most 32*1023
    psrld         xm1, 4
    pxor          xm2, xm2
    pavgw         xm1, xm2             ; (sum+16)>>5
    vpbroadcastw  m11, xm1             ; DC prediction
    vshufi64x2    m10, m10, m10, q1010 ; V prediction
    vshufi32x4     m8, m8, m8, 0
    vshufi32x4     m9, m9, m9, 0
%assign isad_g 0
%rep 8
    movu           m7, [r0+isad_g*2*FENC_STRIDEB]
%if isad_g < 4
    pshufb         m4, m8, [isadhbd_hidx16+isad_g*64]
%else
    pshufb         m4, m9, [isadhbd_hidx16+(isad_g-4)*64]
%endif
    psubw          m4, m7              ; H
    psubw          m5, m7, m10         ; V
    psubw          m6, m7, m11         ; DC
%if isad_g == 0
    pabsw          m1, m4
    pabsw          m0, m5
    pabsw          m2, m6
%else
    pabsw          m4, m4
    pabsw          m5, m5
    pabsw          m6, m6
    paddw          m1, m4
    paddw          m0, m5
    paddw          m2, m6
%endif
%assign isad_g isad_g+1
%endrep
%undef isad_g
    pxor           m3, m3
    SAD_X_HBD16_ZMM_END pw_1           ; V H DC
    movq       [r2+0], xm0
    pextrd     [r2+8], xm0, 2
    RET

;-----------------------------------------------------------------------------
; void intra_sad_x3_8x8c( uint16_t *fenc, uint16_t *fdec, int res[3] )
; four 8 pixel rows a zmm from 16 byte loads merged by k3-k5 (no line splits)
;-----------------------------------------------------------------------------
; k3-k5 = 128-bit lanes 1-3
%macro INTRA_SAD_HBD_FENC4_K 0
    mov           r6d, 0xf0
    kmovw          k3, r6d
    shl           r6d, 4
    kmovw          k4, r6d
    shl           r6d, 4
    kmovw          k5, r6d
%endmacro

; m%1 = fenc rows 4*%2 .. 4*%2+3
%macro INTRA_SAD_HBD_FENC4 2
    movu          xm%1, [r0+(4*%2)*FENC_STRIDEB]
    vbroadcasti32x4 m%1 {k3}, [r0+(4*%2+1)*FENC_STRIDEB]
    vbroadcasti32x4 m%1 {k4}, [r0+(4*%2+2)*FENC_STRIDEB]
    vbroadcasti32x4 m%1 {k5}, [r0+(4*%2+3)*FENC_STRIDEB]
%endmacro

; xm%1 = { s0, s1, s2, s3 } (4 pixel sums) from words top xm%2, left xm%3
%macro INTRA_SAD_HBD_SUM4 4 ; dst, top, left, tmp
    pmaddwd       xm%1, xm%2, [pw_1]
    pmaddwd       xm%4, xm%3, [pw_1]
    shufps        xm%2, xm%1, xm%4, q2020
    shufps        xm%1, xm%4, q3131
    paddd         xm%1, xm%2
%endmacro

cglobal intra_sad_x3_8x8c, 3,7,13
    INTRA_SAD_HBD_LEFT4 8, 0
    INTRA_SAD_HBD_LEFT4 1, 1
    movu          xm9, [r1-FDEC_STRIDEB]
    punpcklqdq    xm8, xm1              ; left 0-7
    INTRA_SAD_HBD_SUM4 1, 9, 8, 2       ; s0 s1 s2 s3
    mov           r6d, 9
    kmovb          k1, r6d
    pshufd        xm2, xm1, q1310       ; s0 s1 s3 s1
    vpshufd       xm3 {k1}{z}, xm1, q3002 ; s2 0 0 s3
    paddd         xm2, xm3
    vpsrlvd       xm2, xm2, [isadhbd_shift]
    pxor          xm3, xm3
    pavgw         xm2, xm3              ; dc0 dc1 dc2 dc3
    vshufi32x4     m2, m2, m2, 0
    pshufb        m11, m2, [isadhbd_dcidx]    ; DC rows 0-3
    pshufb        m12, m2, [isadhbd_dcidx+64] ; DC rows 4-7
    vbroadcasti32x4 m10, [r1-FDEC_STRIDEB]    ; V
    vshufi32x4     m8, m8, m8, 0
    INTRA_SAD_HBD_FENC4_K
    INTRA_SAD_HBD_FENC4 7, 0
    psubw          m0, m7, m11
    pshufb         m1, m8, [isadhbd_hidx8]
    psubw          m1, m7
    psubw          m2, m7, m10
    pabsw          m0, m0
    pabsw          m1, m1
    pabsw          m2, m2
    INTRA_SAD_HBD_FENC4 7, 1
    psubw          m4, m7, m12
    pshufb         m5, m8, [isadhbd_hidx8+64]
    psubw          m5, m7
    psubw          m6, m7, m10
    pabsw          m4, m4
    pabsw          m5, m5
    pabsw          m6, m6
    paddw          m0, m4
    paddw          m1, m5
    paddw          m2, m6
    pxor           m3, m3
    SAD_X_HBD16_ZMM_END pw_1            ; DC H V
    movq       [r2+0], xm0
    pextrd     [r2+8], xm0, 2
    RET

;-----------------------------------------------------------------------------
; void intra_sad_x3_8x16c( uint16_t *fenc, uint16_t *fdec, int res[3] )
;-----------------------------------------------------------------------------
cglobal intra_sad_x3_8x16c, 3,7,15
    INTRA_SAD_HBD_LEFT4 8, 0
    INTRA_SAD_HBD_LEFT4 1, 1
    INTRA_SAD_HBD_LEFT4 9, 2
    INTRA_SAD_HBD_LEFT4 2, 3
    punpcklqdq    xm8, xm1              ; left 0-7
    punpcklqdq    xm9, xm2              ; left 8-15
    movu          xm3, [r1-FDEC_STRIDEB]
    INTRA_SAD_HBD_SUM4 1, 3, 8, 2       ; s0 s1 s2 s3
    pmaddwd       xm2, xm9, [pw_1]
    pshufd        xm3, xm2, q2301
    paddd         xm2, xm3              ; s4 s4 s5 s5
    vinserti32x4  ym1, ym1, xm2, 1
    mov           r6d, 0xa9
    kmovb          k1, r6d
    mova          ym2, [isadhbd_dcpa]
    vpermd        ym2, ym2, ym1
    mova          ym3, [isadhbd_dcpb]
    vpermd        ym3 {k1}{z}, ym3, ym1
    paddd         ym2, ym3              ; s0+s2 s1 s3 s1+s3 s4 s1+s4 s5 s1+s5
    vpsrlvd       ym2, ym2, [isadhbd_shift]
    pxor          xm3, xm3
    pavgw         ym2, ym3              ; dc0 .. dc7
    vshufi32x4     m3, m2, m2, q1111
    vshufi32x4     m2, m2, m2, 0
    pshufb        m10, m2, [isadhbd_dcidx]    ; DC rows 0-3
    pshufb        m11, m2, [isadhbd_dcidx+64] ; DC rows 4-7
    pshufb        m12, m3, [isadhbd_dcidx]    ; DC rows 8-11
    pshufb        m13, m3, [isadhbd_dcidx+64] ; DC rows 12-15
    vbroadcasti32x4 m14, [r1-FDEC_STRIDEB]    ; V
    vshufi32x4     m8, m8, m8, 0
    vshufi32x4     m9, m9, m9, 0
    INTRA_SAD_HBD_FENC4_K
%assign isad_g 0
%rep 4
    INTRA_SAD_HBD_FENC4 7, isad_g
%assign isad_dc 10+isad_g
    psubw          m4, m7, m %+ isad_dc
%if isad_g < 2
    pshufb         m5, m8, [isadhbd_hidx8+isad_g*64]
%else
    pshufb         m5, m9, [isadhbd_hidx8+(isad_g-2)*64]
%endif
    psubw          m5, m7
    psubw          m6, m7, m14
%if isad_g == 0
    pabsw          m0, m4
    pabsw          m1, m5
    pabsw          m2, m6
%else
    pabsw          m4, m4
    pabsw          m5, m5
    pabsw          m6, m6
    paddw          m0, m4
    paddw          m1, m5
    paddw          m2, m6
%endif
%assign isad_g isad_g+1
%endrep
%undef isad_g
%undef isad_dc
    pxor           m3, m3
    SAD_X_HBD16_ZMM_END pw_1            ; DC H V
    movq       [r2+0], xm0
    pextrd     [r2+8], xm0, 2
    RET

;-----------------------------------------------------------------------------
; void intra_sad_x3_8x8( uint16_t *fenc, uint16_t edge[36], int res[3] )
;-----------------------------------------------------------------------------
cglobal intra_sad_x3_8x8, 3,7,12
    movu          xm8, [r1+7*SIZEOF_PIXEL]  ; l7 .. l0
    movu          xm9, [r1+16*SIZEOF_PIXEL] ; t0 .. t7
    paddw         xm1, xm8, xm9
    pmaddwd       xm1, [pw_1]
    pshufd        xm2, xm1, q1032
    paddd         xm1, xm2
    pshufd        xm2, xm1, q2301
    paddd         xm1, xm2              ; sum, at most 16*1023
    psrld         xm1, 3
    pxor          xm2, xm2
    pavgw         xm1, xm2              ; (sum+8)>>4
    vpbroadcastw  m11, xm1              ; DC
    vbroadcasti32x4 m10, [r1+16*SIZEOF_PIXEL] ; V
    pshufb        xm8, [isadhbd_wrev]
    vshufi32x4     m8, m8, m8, 0
    INTRA_SAD_HBD_FENC4_K
    INTRA_SAD_HBD_FENC4 7, 0
    psubw          m0, m7, m10
    pshufb         m1, m8, [isadhbd_hidx8]
    psubw          m1, m7
    psubw          m2, m7, m11
    pabsw          m0, m0
    pabsw          m1, m1
    pabsw          m2, m2
    INTRA_SAD_HBD_FENC4 7, 1
    psubw          m4, m7, m10
    pshufb         m5, m8, [isadhbd_hidx8+64]
    psubw          m5, m7
    psubw          m6, m7, m11
    pabsw          m4, m4
    pabsw          m5, m5
    pabsw          m6, m6
    paddw          m0, m4
    paddw          m1, m5
    paddw          m2, m6
    pxor           m3, m3
    SAD_X_HBD16_ZMM_END pw_1            ; V H DC
    movq       [r2+0], xm0
    pextrd     [r2+8], xm0, 2
    RET

;-----------------------------------------------------------------------------
; void intra_sad_x3_4x4( uint16_t *fenc, uint16_t *fdec, int res[3] )
; fenc rows k-merged by vpbroadcastq into { 0 1 2 3 | 0 1 2 3 } against
; { V | H } (one vpermw of { left, top }), DC in a ymm.
; Tail: 2 vshufi64x2, paddw, pmaddwd, 2 pshufd + paddd, vpcompressd (9 ops).
;-----------------------------------------------------------------------------
cglobal intra_sad_x3_4x4, 3,4,8
    mov           r3d, 0x22
    kmovb          k3, r3d
    add           r3d, r3d
    kmovb          k4, r3d
    add           r3d, r3d
    kmovb          k5, r3d
    movq          xm0, [r1+3*FDEC_STRIDEB-8]
    pinsrw        xm0, [r1+0*FDEC_STRIDEB-2], 0
    pinsrw        xm0, [r1+1*FDEC_STRIDEB-2], 1
    pinsrw        xm0, [r1+2*FDEC_STRIDEB-2], 2
    movhps        xm0, [r1-FDEC_STRIDEB]     ; l0 l1 l2 l3 t0 t1 t2 t3
    vpbroadcastq   m7, [r0]
    vpbroadcastq   m7 {k3}, [r0+1*FENC_STRIDEB]
    vpbroadcastq   m7 {k4}, [r0+2*FENC_STRIDEB]
    vpbroadcastq   m7 {k5}, [r0+3*FENC_STRIDEB]
    pmaddwd       xm1, xm0, [pw_1]
    pshufd        xm2, xm1, q1032
    paddd         xm1, xm2
    pshufd        xm2, xm1, q2301
    paddd         xm1, xm2                   ; sum, at most 8*1023
    psrld         xm1, 2
    pxor          xm2, xm2
    pavgw         xm1, xm2                   ; (sum+4)>>3
    vpbroadcastw  ym2, xm1                   ; DC
    movu           m3, [isadhbd_p4idx]
    vpermw         m3, m3, m0                ; V rows 0-3 | H rows 0-3
    psubw          m3, m7
    psubw         ym5, ym7, ym2
    pabsw          m3, m3
    pabsw         ym5, ym5
    vshufi64x2     m4, m3, m5, 0x88          ; V0 H0 DC0 0
    vshufi64x2     m3, m3, m5, 0xdd          ; V1 H1 DC1 0
    paddw          m3, m4                    ; at most 2*1023 a word
    vpbroadcastd   m4, [pw_1]
    pmaddwd        m3, m4
    pshufd         m4, m3, q1032
    paddd          m3, m4
    pshufd         m4, m3, q2301
    paddd          m3, m4
    mov           r3d, 0x1111
    kmovw          k1, r3d
    vpcompressd    m3 {k1}{z}, m3
    movq       [r2+0], xm3
    pextrd     [r2+8], xm3, 2
    RET

INIT_YMM avx2
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
