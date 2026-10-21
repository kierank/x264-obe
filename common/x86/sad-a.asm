;*****************************************************************************
;* sad-a.asm: x86 sad functions
;*****************************************************************************
;* Copyright (C) 2003-2014 x264 project
;*
;* Authors: Loren Merritt <lorenm@u.washington.edu>
;*          Jason Garrett-Glaser <darkshikari@gmail.com>
;*          Laurent Aimar <fenrir@via.ecp.fr>
;*          Alex Izvorski <aizvorksi@gmail.com>
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

pb_shuf8x8c2: times 2 db 0,0,0,0,8,8,8,8,-1,-1,-1,-1,-1,-1,-1,-1
hpred_shuf: db 0,0,2,2,8,8,10,10,1,1,3,3,9,9,11,11

ALIGN 64
isad8c_qidx:   dq 0, 2, 4, 6, 8, 10, 12, 14
isad8c_hidx:   db 0,0,0,0,0,0,0,0, 1,1,1,1,1,1,1,1, 2,2,2,2,2,2,2,2, 3,3,3,3,3,3,3,3
               db 4,4,4,4,4,4,4,4, 5,5,5,5,5,5,5,5, 6,6,6,6,6,6,6,6, 7,7,7,7,7,7,7,7
isad8c_dcidx:  times 4 db 0,0,0,0,4,4,4,4
               times 4 db 8,8,8,8,12,12,12,12
isad16_hidx:   db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
               db 2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2, 3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3
               db 4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4, 5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5
               db 6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6, 7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7
               db 8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8, 9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9
               db 10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10, 11,11,11,11,11,11,11,11,11,11,11,11,11,11,11,11
               db 12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12, 13,13,13,13,13,13,13,13,13,13,13,13,13,13,13,13
               db 14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14, 15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15
; { s0 s0 s1 s1 s2 s2 s3 s3 } -> { s0+s2, s1, s3, s1+s3 } by vpermw + pmaddwd
isad8c_wperm:  dw 0, 4, 2, 2, 6, 6, 2, 6
isad8c_wmul:   dw 1, 1, 1, 0, 1, 0, 1, 1
isad8c_shift:  dd 2, 1, 1, 2
ALIGN 64
; 8x16c: dc4-dc7 (bytes 16-28) for rows 8-15; { s0+s2, s1, s3, s1+s3, s4, s1+s4, s5, s1+s5 }
isad816c_dcidx: times 4 db 16,16,16,16,20,20,20,20
                times 4 db 24,24,24,24,28,28,28,28
isad816c_wperm: dw 0, 4, 2, 2, 6, 6, 2, 6, 8, 8, 2, 8, 10, 10, 2, 10
isad816c_wmul:  dw 1, 1, 1, 0, 1, 0, 1, 1, 1, 0, 1, 1, 1, 0, 1, 1
isad816c_shift: dd 2, 1, 1, 2, 1, 2, 1, 2
ALIGN 64
; 8x8 H rows from edge[7..14] = l7..l0
isad8_hidxr:   db 7,7,7,7,7,7,7,7, 6,6,6,6,6,6,6,6, 5,5,5,5,5,5,5,5, 4,4,4,4,4,4,4,4
               db 3,3,3,3,3,3,3,3, 2,2,2,2,2,2,2,2, 1,1,1,1,1,1,1,1, 0,0,0,0,0,0,0,0
ALIGN 32
sad_sq_idx16:  dd 0, 0, 1, 1, 2, 2, 3, 3
sad_sq_idx8:   dd 0, 0, 1, 1, 4, 4, 5, 5
dbp_idx4:      dd 0, 0, 4, 4, 0, 0, 4, 4

SECTION .text

cextern pw_1
cextern pb_unpackbd1
cextern pb_3
cextern pb_shuf8x8c
cextern pw_8
cextern sw_64

;=============================================================================
; SAD MMX
;=============================================================================

%macro SAD_INC_2x16P 0
    movq    mm1,    [r0]
    movq    mm2,    [r0+8]
    movq    mm3,    [r0+r1]
    movq    mm4,    [r0+r1+8]
    psadbw  mm1,    [r2]
    psadbw  mm2,    [r2+8]
    psadbw  mm3,    [r2+r3]
    psadbw  mm4,    [r2+r3+8]
    lea     r0,     [r0+2*r1]
    paddw   mm1,    mm2
    paddw   mm3,    mm4
    lea     r2,     [r2+2*r3]
    paddw   mm0,    mm1
    paddw   mm0,    mm3
%endmacro

%macro SAD_INC_2x8P 0
    movq    mm1,    [r0]
    movq    mm2,    [r0+r1]
    psadbw  mm1,    [r2]
    psadbw  mm2,    [r2+r3]
    lea     r0,     [r0+2*r1]
    paddw   mm0,    mm1
    paddw   mm0,    mm2
    lea     r2,     [r2+2*r3]
%endmacro

%macro SAD_INC_2x4P 0
    movd    mm1,    [r0]
    movd    mm2,    [r2]
    punpckldq mm1,  [r0+r1]
    punpckldq mm2,  [r2+r3]
    psadbw  mm1,    mm2
    paddw   mm0,    mm1
    lea     r0,     [r0+2*r1]
    lea     r2,     [r2+2*r3]
%endmacro

;-----------------------------------------------------------------------------
; int pixel_sad_16x16( uint8_t *, intptr_t, uint8_t *, intptr_t )
;-----------------------------------------------------------------------------
%macro SAD 2
cglobal pixel_sad_%1x%2_mmx2, 4,4
    pxor    mm0, mm0
%rep %2/2
    SAD_INC_2x%1P
%endrep
    movd    eax, mm0
    RET
%endmacro

SAD 16, 16
SAD 16,  8
SAD  8, 16
SAD  8,  8
SAD  8,  4
SAD  4, 16
SAD  4,  8
SAD  4,  4



;=============================================================================
; SAD XMM
;=============================================================================

%macro SAD_END_SSE2 0
    movhlps m1, m0
    paddw   m0, m1
    movd   eax, m0
    RET
%endmacro

%macro SAD_W16 0
;-----------------------------------------------------------------------------
; int pixel_sad_16x16( uint8_t *, intptr_t, uint8_t *, intptr_t )
;-----------------------------------------------------------------------------
cglobal pixel_sad_16x16, 4,4,8
    movu    m0, [r2]
    movu    m1, [r2+r3]
    lea     r2, [r2+2*r3]
    movu    m2, [r2]
    movu    m3, [r2+r3]
    lea     r2, [r2+2*r3]
    psadbw  m0, [r0]
    psadbw  m1, [r0+r1]
    lea     r0, [r0+2*r1]
    movu    m4, [r2]
    paddw   m0, m1
    psadbw  m2, [r0]
    psadbw  m3, [r0+r1]
    lea     r0, [r0+2*r1]
    movu    m5, [r2+r3]
    lea     r2, [r2+2*r3]
    paddw   m2, m3
    movu    m6, [r2]
    movu    m7, [r2+r3]
    lea     r2, [r2+2*r3]
    paddw   m0, m2
    psadbw  m4, [r0]
    psadbw  m5, [r0+r1]
    lea     r0, [r0+2*r1]
    movu    m1, [r2]
    paddw   m4, m5
    psadbw  m6, [r0]
    psadbw  m7, [r0+r1]
    lea     r0, [r0+2*r1]
    movu    m2, [r2+r3]
    lea     r2, [r2+2*r3]
    paddw   m6, m7
    movu    m3, [r2]
    paddw   m0, m4
    movu    m4, [r2+r3]
    lea     r2, [r2+2*r3]
    paddw   m0, m6
    psadbw  m1, [r0]
    psadbw  m2, [r0+r1]
    lea     r0, [r0+2*r1]
    movu    m5, [r2]
    paddw   m1, m2
    psadbw  m3, [r0]
    psadbw  m4, [r0+r1]
    lea     r0, [r0+2*r1]
    movu    m6, [r2+r3]
    lea     r2, [r2+2*r3]
    paddw   m3, m4
    movu    m7, [r2]
    paddw   m0, m1
    movu    m1, [r2+r3]
    paddw   m0, m3
    psadbw  m5, [r0]
    psadbw  m6, [r0+r1]
    lea     r0, [r0+2*r1]
    paddw   m5, m6
    psadbw  m7, [r0]
    psadbw  m1, [r0+r1]
    paddw   m7, m1
    paddw   m0, m5
    paddw   m0, m7
    SAD_END_SSE2

;-----------------------------------------------------------------------------
; int pixel_sad_16x8( uint8_t *, intptr_t, uint8_t *, intptr_t )
;-----------------------------------------------------------------------------
cglobal pixel_sad_16x8, 4,4
    movu    m0, [r2]
    movu    m2, [r2+r3]
    lea     r2, [r2+2*r3]
    movu    m3, [r2]
    movu    m4, [r2+r3]
    psadbw  m0, [r0]
    psadbw  m2, [r0+r1]
    lea     r0, [r0+2*r1]
    psadbw  m3, [r0]
    psadbw  m4, [r0+r1]
    lea     r0, [r0+2*r1]
    lea     r2, [r2+2*r3]
    paddw   m0, m2
    paddw   m3, m4
    paddw   m0, m3
    movu    m1, [r2]
    movu    m2, [r2+r3]
    lea     r2, [r2+2*r3]
    movu    m3, [r2]
    movu    m4, [r2+r3]
    psadbw  m1, [r0]
    psadbw  m2, [r0+r1]
    lea     r0, [r0+2*r1]
    psadbw  m3, [r0]
    psadbw  m4, [r0+r1]
    lea     r0, [r0+2*r1]
    lea     r2, [r2+2*r3]
    paddw   m1, m2
    paddw   m3, m4
    paddw   m0, m1
    paddw   m0, m3
    SAD_END_SSE2
%endmacro

INIT_XMM sse2
SAD_W16
INIT_XMM sse3
SAD_W16
INIT_XMM sse2, aligned
SAD_W16

%macro SAD_INC_4x8P_SSE 1
    movq    m1, [r0]
    movq    m2, [r0+r1]
    lea     r0, [r0+2*r1]
    movq    m3, [r2]
    movq    m4, [r2+r3]
    lea     r2, [r2+2*r3]
    movhps  m1, [r0]
    movhps  m2, [r0+r1]
    movhps  m3, [r2]
    movhps  m4, [r2+r3]
    lea     r0, [r0+2*r1]
    psadbw  m1, m3
    psadbw  m2, m4
    lea     r2, [r2+2*r3]
    ACCUM paddw, 0, 1, %1
    paddw   m0, m2
%endmacro

INIT_XMM
;Even on Nehalem, no sizes other than 8x16 benefit from this method.
cglobal pixel_sad_8x16_sse2, 4,4
    SAD_INC_4x8P_SSE 0
    SAD_INC_4x8P_SSE 1
    SAD_INC_4x8P_SSE 1
    SAD_INC_4x8P_SSE 1
    SAD_END_SSE2
    RET

%macro SAD_W48_AVX512 3 ; w, h, d/q
cglobal pixel_sad_%1x%2, 4,4
    kxnorb        k1, k1, k1
    kaddb         k1, k1, k1
%assign %%i 0
%if ARCH_X86_64 && %2 != 4
    lea           r6, [3*r1]
    lea           r5, [3*r3]
%rep %2/4
    mov%3         m1,      [r0]
    vpbroadcast%3 m1 {k1}, [r0+r1]
    mov%3         m3,      [r2]
    vpbroadcast%3 m3 {k1}, [r2+r3]
    mov%3         m2,      [r0+2*r1]
    vpbroadcast%3 m2 {k1}, [r0+r6]
    mov%3         m4,      [r2+2*r3]
    vpbroadcast%3 m4 {k1}, [r2+r5]
%if %%i != %2/4-1
    lea           r0, [r0+4*r1]
    lea           r2, [r2+4*r3]
%endif
    psadbw        m1, m3
    psadbw        m2, m4
    ACCUM      paddd, 0, 1, %%i
    paddd         m0, m2
    %assign %%i %%i+1
%endrep
%else
%rep %2/2
    mov%3         m1,      [r0]
    vpbroadcast%3 m1 {k1}, [r0+r1]
    mov%3         m2,      [r2]
    vpbroadcast%3 m2 {k1}, [r2+r3]
%if %%i != %2/2-1
    lea           r0, [r0+2*r1]
    lea           r2, [r2+2*r3]
%endif
    psadbw        m1, m2
    ACCUM      paddd, 0, 1, %%i
    %assign %%i %%i+1
%endrep
%endif
%if %1 == 8
    punpckhqdq    m1, m0, m0
    paddd         m0, m1
%endif
    movd         eax, m0
    RET
%endmacro

INIT_XMM avx512
SAD_W48_AVX512 4,  4, d
SAD_W48_AVX512 4,  8, d
SAD_W48_AVX512 4, 16, d
SAD_W48_AVX512 8,  4, q
SAD_W48_AVX512 8,  8, q
SAD_W48_AVX512 8, 16, q

; The fallback is a plain tail call: the sse2 16x16 here declares 8 xmm
; registers, so entering it past its prologue is only safe on unix64.
%macro SAD_W16_AVX512_START 1 ; h
    cmp  r1d, FENC_STRIDE     ; optimized for the most common fenc case, which
    jne pixel_sad_16x%1_sse2  ; has the rows laid out contiguously in memory
    lea   r1, [3*r3]
%endmacro

%macro SAD_W16_AVX512_END 0
    paddd          m0, m1
    paddd          m2, m3
    paddd          m0, m2
%if mmsize == 64
    vextracti32x8 ym1, m0, 1
    paddd         ym0, ym1
%endif
    vextracti128  xm1, ym0, 1
    paddd        xmm0, xm0, xm1
    punpckhqdq   xmm1, xmm0, xmm0
    paddd        xmm0, xmm1
    movd          eax, xmm0
    RET
%endmacro

INIT_YMM avx512
cglobal pixel_sad_16x8, 4,4
    SAD_W16_AVX512_START 8
    movu         xm0, [r2]
    vinserti128   m0, [r2+r3], 1
    psadbw        m0, [r0+0*32]
    movu         xm1, [r2+2*r3]
    vinserti128   m1, [r2+r1], 1
    lea           r2, [r2+4*r3]
    psadbw        m1, [r0+1*32]
    movu         xm2, [r2]
    vinserti128   m2, [r2+r3], 1
    psadbw        m2, [r0+2*32]
    movu         xm3, [r2+2*r3]
    vinserti128   m3, [r2+r1], 1
    psadbw        m3, [r0+3*32]
    SAD_W16_AVX512_END

INIT_ZMM avx512
cglobal pixel_sad_16x16, 4,4
    SAD_W16_AVX512_START 16
    movu          xm0, [r2]
    vinserti128   ym0, [r2+r3],   1
    movu          xm1, [r2+4*r3]
    vinserti32x4   m0, [r2+2*r3], 2
    vinserti32x4   m1, [r2+2*r1], 2
    vinserti32x4   m0, [r2+r1],   3
    lea            r2, [r2+4*r3]
    vinserti32x4   m1, [r2+r3],   1
    psadbw         m0, [r0+0*64]
    vinserti32x4   m1, [r2+r1],   3
    lea            r2, [r2+4*r3]
    psadbw         m1, [r0+1*64]
    movu          xm2, [r2]
    vinserti128   ym2, [r2+r3],   1
    movu          xm3, [r2+4*r3]
    vinserti32x4   m2, [r2+2*r3], 2
    vinserti32x4   m3, [r2+2*r1], 2
    vinserti32x4   m2, [r2+r1],   3
    lea            r2, [r2+4*r3]
    vinserti32x4   m3, [r2+r3],   1
    psadbw         m2, [r0+2*64]
    vinserti32x4   m3, [r2+r1],   3
    psadbw         m3, [r0+3*64]
    SAD_W16_AVX512_END

; AVX2: two rows a ymm, and fenc rows FENC_STRIDE apart are one 32 byte load
%macro SAD_W16_AVX2_8ROWS 0 ; rows 0-7 into m0-m3, r1 = 3*stride
    movu         xm0, [r2]
    vinserti128   m0, m0, [r2+r3], 1
    psadbw        m0, [r0+0*32]
    movu         xm1, [r2+2*r3]
    vinserti128   m1, m1, [r2+r1], 1
    lea           r2, [r2+4*r3]
    psadbw        m1, [r0+1*32]
    movu         xm2, [r2]
    vinserti128   m2, m2, [r2+r3], 1
    psadbw        m2, [r0+2*32]
    movu         xm3, [r2+2*r3]
    vinserti128   m3, m3, [r2+r1], 1
    psadbw        m3, [r0+3*32]
%endmacro

; rows 4-7 of the next 8 rows (fenc offset %1) added into m%2, m%3
%macro SAD_W16_AVX2_ACC4 3
    movu         xm4, [r2]
    vinserti128   m4, m4, [r2+r3], 1
    movu         xm5, [r2+2*r3]
    vinserti128   m5, m5, [r2+r1], 1
    psadbw        m4, [r0+%1]
    psadbw        m5, [r0+%1+32]
    paddd        m%2, m4
    paddd        m%3, m5
%endmacro

INIT_YMM avx2
cglobal pixel_sad_16x8, 4,4,4
    SAD_W16_AVX512_START 8
    SAD_W16_AVX2_8ROWS
    SAD_W16_AVX512_END

cglobal pixel_sad_16x16, 4,4,6
    SAD_W16_AVX512_START 16
    SAD_W16_AVX2_8ROWS
    lea           r2, [r2+4*r3]
    SAD_W16_AVX2_ACC4 4*32, 0, 1
    lea           r2, [r2+4*r3]
    SAD_W16_AVX2_ACC4 6*32, 2, 3
    SAD_W16_AVX512_END

;-----------------------------------------------------------------------------
; int pixel_sad_avg2_WxH( uint8_t *fenc, uint8_t *src1, uint8_t *src2, intptr_t stride )
; sad( fenc, (src1+src2+1)>>1 ): qpel candidates of the motion search without
; storing the average. fenc has FENC_STRIDE.
;-----------------------------------------------------------------------------
; 16 wide, rows k, k+1 a ymm: %1 = dst (number), %2 = row k
%macro SAD_AVG2_W16_ROW2 2
%if %2
    lea           r1, [r1+2*r3]
    lea           r2, [r2+2*r3]
%endif
    movu         xm%1, [r1]
    vinserti128   m%1, m%1, [r1+r3], 1
    movu         xm4, [r2]
    vinserti128   m4, m4, [r2+r3], 1
    pavgb         m%1, m4
    psadbw        m%1, [r0+%2*FENC_STRIDE]
%endmacro

; 8 wide, rows k, k+1 and k+2, k+3 a ymm each, loaded as 16 wide (8 bytes past
; the block, inside the planes' PADH): qword 1 of each lane is junk, dropped at the end
%macro SAD_AVG2_W8_ROW4 3 ; 2*dst (numbers), row k; r4 = 3*stride
%if %3
    lea           r1, [r1+4*r3]
    lea           r2, [r2+4*r3]
%endif
    movu         xm%1, [r1]
    vinserti128   m%1, m%1, [r1+r3], 1
    movu         xm4, [r2]
    vinserti128   m4, m4, [r2+r3], 1
    pavgb         m%1, m4
    psadbw        m%1, [r0+%3*FENC_STRIDE]
    movu         xm%2, [r1+2*r3]
    vinserti128   m%2, m%2, [r1+r4], 1
    movu         xm4, [r2+2*r3]
    vinserti128   m4, m4, [r2+r4], 1
    pavgb         m%2, m4
    psadbw        m%2, [r0+(%3+2)*FENC_STRIDE]
%endmacro

%macro SAD_AVG2_END 1-2 16 ; number of accumulators, width
%if %1 > 1
    paddd         m0, m1
%endif
%if %1 > 2
    paddd         m2, m3
    paddd         m0, m2
%endif
    vextracti128 xm1, m0, 1
    paddd        xm0, xm1
%if %2 == 16
    punpckhqdq   xm1, xm0, xm0
    paddd        xm0, xm1
%endif
    movd         eax, xm0
    RET
%endmacro

cglobal pixel_sad_avg2_16x16, 4,4,6
    SAD_AVG2_W16_ROW2 0, 0
    SAD_AVG2_W16_ROW2 1, 2
    SAD_AVG2_W16_ROW2 2, 4
    SAD_AVG2_W16_ROW2 3, 6
%assign sad_avg2_k 8
%rep 4
    %assign sad_avg2_d (sad_avg2_k-8)/2
    SAD_AVG2_W16_ROW2 5, sad_avg2_k
    paddd          m %+ sad_avg2_d, m5
%assign sad_avg2_k sad_avg2_k+2
%endrep
    SAD_AVG2_END 4

cglobal pixel_sad_avg2_16x8, 4,4,5
    SAD_AVG2_W16_ROW2 0, 0
    SAD_AVG2_W16_ROW2 1, 2
    SAD_AVG2_W16_ROW2 2, 4
    SAD_AVG2_W16_ROW2 3, 6
    SAD_AVG2_END 4

cglobal pixel_sad_avg2_8x16, 4,5,5
    lea           r4, [3*r3]
    SAD_AVG2_W8_ROW4 0, 1, 0
    SAD_AVG2_W8_ROW4 2, 3, 4
    paddd         m0, m2
    paddd         m1, m3
    SAD_AVG2_W8_ROW4 2, 3, 8
    paddd         m0, m2
    paddd         m1, m3
    SAD_AVG2_W8_ROW4 2, 3, 12
    SAD_AVG2_END 4, 8

cglobal pixel_sad_avg2_8x8, 4,5,5
    lea           r4, [3*r3]
    SAD_AVG2_W8_ROW4 0, 1, 0
    SAD_AVG2_W8_ROW4 2, 3, 4
    SAD_AVG2_END 4, 8

;-----------------------------------------------------------------------------
; int pixel_sad_8x16( uint8_t *, intptr_t, uint8_t *, intptr_t )
; The 16 wide loads: fenc rows k, k+1 are one 32 byte load at FENC_STRIDE,
; the ref rows are read 8 bytes past the block and qword 1 of each lane is
; dropped. The stride check is before the prologue, so the fallback is a plain
; tail call on every ABI.
;-----------------------------------------------------------------------------
%macro SAD_W8_AVX2_START 2 ; h, xmm regs
    cmp        r1mp, FENC_STRIDE
    jne pixel_sad_8x%1_mmx2
    PROLOGUE 4,4,%2
    lea           r1, [3*r3]
%endmacro

cglobal pixel_sad_8x8
    SAD_W8_AVX2_START 8, 4
    SAD_W16_AVX2_8ROWS
    SAD_AVG2_END 4, 8

cglobal pixel_sad_8x16
    SAD_W8_AVX2_START 16, 6
    SAD_W16_AVX2_8ROWS
    lea           r2, [r2+4*r3]
    SAD_W16_AVX2_ACC4 4*32, 0, 1
    lea           r2, [r2+4*r3]
    SAD_W16_AVX2_ACC4 6*32, 2, 3
    SAD_AVG2_END 4, 8

;-----------------------------------------------------------------------------
; void pixel_vsad( pixel *src, intptr_t stride );
;-----------------------------------------------------------------------------

%if ARCH_X86_64 == 0
INIT_MMX
cglobal pixel_vsad_mmx2, 3,3
    mova      m0, [r0]
    mova      m1, [r0+8]
    mova      m2, [r0+r1]
    mova      m3, [r0+r1+8]
    lea       r0, [r0+r1*2]
    psadbw    m0, m2
    psadbw    m1, m3
    paddw     m0, m1
    sub      r2d, 2
    je .end
.loop:
    mova      m4, [r0]
    mova      m5, [r0+8]
    mova      m6, [r0+r1]
    mova      m7, [r0+r1+8]
    lea       r0, [r0+r1*2]
    psadbw    m2, m4
    psadbw    m3, m5
    psadbw    m4, m6
    psadbw    m5, m7
    ;max sum: 31*16*255(pixel_max)=126480
    paddd     m0, m2
    paddd     m0, m3
    paddd     m0, m4
    paddd     m0, m5
    mova      m2, m6
    mova      m3, m7
    sub      r2d, 2
    jg .loop
.end:
    movd     eax, m0
    RET
%endif

INIT_XMM
cglobal pixel_vsad_sse2, 3,3
    mova      m0, [r0]
    mova      m1, [r0+r1]
    lea       r0, [r0+r1*2]
    psadbw    m0, m1
    sub      r2d, 2
    je .end
.loop:
    mova      m2, [r0]
    mova      m3, [r0+r1]
    lea       r0, [r0+r1*2]
    psadbw    m1, m2
    psadbw    m2, m3
    paddw     m1, m2
    paddw     m0, m1
    mova      m1, m3
    sub      r2d, 2
    jg .loop
.end:
    movhlps   m1, m0
    ;max sum: 31*16*255(pixel_max)=126480
    paddd     m0, m1
    movd     eax, m0
    RET

;-----------------------------------------------------------------------------
; void intra_sad_x3_4x4( uint8_t *fenc, uint8_t *fdec, int res[3] );
;-----------------------------------------------------------------------------

cglobal intra_sad_x3_4x4_mmx2, 3,3
    pxor      mm7, mm7
    movd      mm0, [r1-FDEC_STRIDE]
    movd      mm1, [r0+FENC_STRIDE*0]
    movd      mm2, [r0+FENC_STRIDE*2]
    punpckldq mm0, mm0
    punpckldq mm1, [r0+FENC_STRIDE*1]
    punpckldq mm2, [r0+FENC_STRIDE*3]
    movq      mm6, mm0
    movq      mm3, mm1
    psadbw    mm3, mm0
    psadbw    mm0, mm2
    paddw     mm0, mm3
    movd     [r2], mm0 ;V prediction cost
    movd      mm3, [r1+FDEC_STRIDE*0-4]
    movd      mm0, [r1+FDEC_STRIDE*1-4]
    movd      mm4, [r1+FDEC_STRIDE*2-4]
    movd      mm5, [r1+FDEC_STRIDE*3-4]
    punpcklbw mm3, mm0
    punpcklbw mm4, mm5
    movq      mm5, mm3
    punpckhwd mm5, mm4
    punpckhdq mm5, mm6
    psadbw    mm5, mm7
    punpckhbw mm3, mm3
    punpckhbw mm4, mm4
    punpckhwd mm3, mm3
    punpckhwd mm4, mm4
    psraw     mm5, 2
    pavgw     mm5, mm7
    punpcklbw mm5, mm5
    pshufw    mm5, mm5, 0 ;DC prediction
    movq      mm6, mm5
    psadbw    mm5, mm1
    psadbw    mm6, mm2
    psadbw    mm1, mm3
    psadbw    mm2, mm4
    paddw     mm5, mm6
    paddw     mm1, mm2
    movd   [r2+8], mm5 ;DC prediction cost
    movd   [r2+4], mm1 ;H prediction cost
    RET

;-----------------------------------------------------------------------------
; void intra_sad_x3_8x8( uint8_t *fenc, uint8_t edge[36], int res[3]);
;-----------------------------------------------------------------------------

;m0 = DC
;m6 = V
;m7 = H
;m1 = DC score
;m2 = V score
;m3 = H score
;m5 = pixel row
;m4 = temp

%macro INTRA_SAD_HVDC_ITER 2
    movq      m5, [r0+FENC_STRIDE*%1]
    movq      m4, m5
    psadbw    m4, m0
    ACCUM  paddw, 1, 4, %1
    movq      m4, m5
    psadbw    m4, m6
    ACCUM  paddw, 2, 4, %1
    pshufw    m4, m7, %2
    psadbw    m5, m4
    ACCUM  paddw, 3, 5, %1
%endmacro

INIT_MMX
cglobal intra_sad_x3_8x8_mmx2, 3,3
    movq      m7, [r1+7]
    pxor      m0, m0
    movq      m6, [r1+16]  ;V prediction
    pxor      m1, m1
    psadbw    m0, m7
    psadbw    m1, m6
    paddw     m0, m1
    paddw     m0, [pw_8]
    psrlw     m0, 4
    punpcklbw m0, m0
    pshufw    m0, m0, q0000 ;DC prediction
    punpckhbw m7, m7
    INTRA_SAD_HVDC_ITER 0, q3333
    INTRA_SAD_HVDC_ITER 1, q2222
    INTRA_SAD_HVDC_ITER 2, q1111
    INTRA_SAD_HVDC_ITER 3, q0000
    movq      m7, [r1+7]
    punpcklbw m7, m7
    INTRA_SAD_HVDC_ITER 4, q3333
    INTRA_SAD_HVDC_ITER 5, q2222
    INTRA_SAD_HVDC_ITER 6, q1111
    INTRA_SAD_HVDC_ITER 7, q0000
    movd  [r2+0], m2
    movd  [r2+4], m3
    movd  [r2+8], m1
    RET

;-----------------------------------------------------------------------------
; void intra_sad_x3_8x8c( uint8_t *fenc, uint8_t *fdec, int res[3] );
;-----------------------------------------------------------------------------

%macro INTRA_SAD_HV_ITER 1
%if cpuflag(ssse3)
    movd        m1, [r1 + FDEC_STRIDE*(%1-4) - 4]
    movd        m3, [r1 + FDEC_STRIDE*(%1-3) - 4]
    pshufb      m1, m7
    pshufb      m3, m7
%else
    movq        m1, [r1 + FDEC_STRIDE*(%1-4) - 8]
    movq        m3, [r1 + FDEC_STRIDE*(%1-3) - 8]
    punpckhbw   m1, m1
    punpckhbw   m3, m3
    pshufw      m1, m1, q3333
    pshufw      m3, m3, q3333
%endif
    movq        m4, [r0 + FENC_STRIDE*(%1+0)]
    movq        m5, [r0 + FENC_STRIDE*(%1+1)]
    psadbw      m1, m4
    psadbw      m3, m5
    psadbw      m4, m6
    psadbw      m5, m6
    paddw       m1, m3
    paddw       m4, m5
    ACCUM    paddw, 0, 1, %1
    ACCUM    paddw, 2, 4, %1
%endmacro

%macro INTRA_SAD_8x8C 0
cglobal intra_sad_x3_8x8c, 3,3
    movq        m6, [r1 - FDEC_STRIDE]
    add         r1, FDEC_STRIDE*4
%if cpuflag(ssse3)
    movq        m7, [pb_3]
%endif
    INTRA_SAD_HV_ITER 0
    INTRA_SAD_HV_ITER 2
    INTRA_SAD_HV_ITER 4
    INTRA_SAD_HV_ITER 6
    movd    [r2+4], m0
    movd    [r2+8], m2
    pxor        m7, m7
    movq        m2, [r1 + FDEC_STRIDE*-4 - 8]
    movq        m4, [r1 + FDEC_STRIDE*-2 - 8]
    movq        m3, [r1 + FDEC_STRIDE* 0 - 8]
    movq        m5, [r1 + FDEC_STRIDE* 2 - 8]
    punpckhbw   m2, [r1 + FDEC_STRIDE*-3 - 8]
    punpckhbw   m4, [r1 + FDEC_STRIDE*-1 - 8]
    punpckhbw   m3, [r1 + FDEC_STRIDE* 1 - 8]
    punpckhbw   m5, [r1 + FDEC_STRIDE* 3 - 8]
    punpckhbw   m2, m4
    punpckhbw   m3, m5
    psrlq       m2, 32
    psrlq       m3, 32
    psadbw      m2, m7 ; s2
    psadbw      m3, m7 ; s3
    movq        m1, m6
    SWAP        0, 6
    punpckldq   m0, m7
    punpckhdq   m1, m7
    psadbw      m0, m7 ; s0
    psadbw      m1, m7 ; s1
    punpcklwd   m0, m1
    punpcklwd   m2, m3
    punpckldq   m0, m2 ;s0 s1 s2 s3
    pshufw      m3, m0, q3312 ;s2,s1,s3,s3
    pshufw      m0, m0, q1310 ;s0,s1,s3,s1
    paddw       m0, m3
    psrlw       m0, 2
    pavgw       m0, m7 ; s0+s2, s1, s3, s1+s3
%if cpuflag(ssse3)
    movq2dq   xmm0, m0
    pshufb    xmm0, [pb_shuf8x8c]
    movq      xmm1, [r0+FENC_STRIDE*0]
    movq      xmm2, [r0+FENC_STRIDE*1]
    movq      xmm3, [r0+FENC_STRIDE*2]
    movq      xmm4, [r0+FENC_STRIDE*3]
    movhps    xmm1, [r0+FENC_STRIDE*4]
    movhps    xmm2, [r0+FENC_STRIDE*5]
    movhps    xmm3, [r0+FENC_STRIDE*6]
    movhps    xmm4, [r0+FENC_STRIDE*7]
    psadbw    xmm1, xmm0
    psadbw    xmm2, xmm0
    psadbw    xmm3, xmm0
    psadbw    xmm4, xmm0
    paddw     xmm1, xmm2
    paddw     xmm1, xmm3
    paddw     xmm1, xmm4
    movhlps   xmm0, xmm1
    paddw     xmm1, xmm0
    movd      [r2], xmm1
%else
    packuswb    m0, m0
    punpcklbw   m0, m0
    movq        m1, m0
    punpcklbw   m0, m0 ; 4x dc0 4x dc1
    punpckhbw   m1, m1 ; 4x dc2 4x dc3
    movq        m2, [r0+FENC_STRIDE*0]
    movq        m3, [r0+FENC_STRIDE*1]
    movq        m4, [r0+FENC_STRIDE*2]
    movq        m5, [r0+FENC_STRIDE*3]
    movq        m6, [r0+FENC_STRIDE*4]
    movq        m7, [r0+FENC_STRIDE*5]
    psadbw      m2, m0
    psadbw      m3, m0
    psadbw      m4, m0
    psadbw      m5, m0
    movq        m0, [r0+FENC_STRIDE*6]
    psadbw      m6, m1
    psadbw      m7, m1
    psadbw      m0, m1
    psadbw      m1, [r0+FENC_STRIDE*7]
    paddw       m2, m3
    paddw       m4, m5
    paddw       m6, m7
    paddw       m0, m1
    paddw       m2, m4
    paddw       m6, m0
    paddw       m2, m6
    movd      [r2], m2
%endif
    RET
%endmacro

INIT_MMX mmx2
INTRA_SAD_8x8C
INIT_MMX ssse3
INTRA_SAD_8x8C

INIT_YMM avx2
cglobal intra_sad_x3_8x8c, 3,3,7
    vpbroadcastq m2, [r1 - FDEC_STRIDE]         ; V pred
    add          r1, FDEC_STRIDE*4-1
    pxor        xm5, xm5
    punpckldq   xm3, xm2, xm5                   ; V0 _ V1 _
    movd        xm0, [r1 + FDEC_STRIDE*-1 - 3]
    movd        xm1, [r1 + FDEC_STRIDE* 3 - 3]
    pinsrb      xm0, [r1 + FDEC_STRIDE*-4], 0
    pinsrb      xm1, [r1 + FDEC_STRIDE* 0], 0
    pinsrb      xm0, [r1 + FDEC_STRIDE*-3], 1
    pinsrb      xm1, [r1 + FDEC_STRIDE* 1], 1
    pinsrb      xm0, [r1 + FDEC_STRIDE*-2], 2
    pinsrb      xm1, [r1 + FDEC_STRIDE* 2], 2
    punpcklqdq  xm0, xm1                        ; H0 _ H1 _
    vinserti128  m3, m3, xm0, 1                 ; V0 V1 H0 H1
    pshufb      xm0, [hpred_shuf]               ; H00224466 H11335577
    psadbw       m3, m5                         ; s0 s1 s2 s3
    vpermq       m4, m3, q3312                  ; s2 s1 s3 s3
    vpermq       m3, m3, q1310                  ; s0 s1 s3 s1
    paddw        m3, m4
    psrlw        m3, 2
    pavgw        m3, m5                         ; s0+s2 s1 s3 s1+s3
    pshufb       m3, [pb_shuf8x8c2]             ; DC0 _ DC1 _
    vpblendd     m3, m3, m2, 11001100b          ; DC0 V DC1 V
    vinserti128  m1, m3, xm3, 1                 ; DC0 V DC0 V
    vperm2i128   m6, m3, m3, q0101              ; DC1 V DC1 V
    vpermq       m0, m0, q3120                  ; H00224466 _ H11335577 _
    movddup      m2, [r0+FENC_STRIDE*0]
    movddup      m4, [r0+FENC_STRIDE*2]
    pshuflw      m3, m0, q0000
    psadbw       m3, m2
    psadbw       m2, m1
    pshuflw      m5, m0, q1111
    psadbw       m5, m4
    psadbw       m4, m1
    paddw        m2, m4
    paddw        m3, m5
    movddup      m4, [r0+FENC_STRIDE*4]
    pshuflw      m5, m0, q2222
    psadbw       m5, m4
    psadbw       m4, m6
    paddw        m2, m4
    paddw        m3, m5
    movddup      m4, [r0+FENC_STRIDE*6]
    pshuflw      m5, m0, q3333
    psadbw       m5, m4
    psadbw       m4, m6
    paddw        m2, m4
    paddw        m3, m5
    vextracti128 xm0, m2, 1
    vextracti128 xm1, m3, 1
    paddw       xm2, xm0 ; DC V
    paddw       xm3, xm1 ; H
    pextrd   [r2+8], xm2, 2 ; V
    movd     [r2+4], xm3    ; H
    movd     [r2+0], xm2    ; DC
    RET


;-----------------------------------------------------------------------------
; void intra_sad_x3_16x16( uint8_t *fenc, uint8_t *fdec, int res[3] );
;-----------------------------------------------------------------------------

;xmm7: DC prediction    xmm6: H prediction  xmm5: V prediction
;xmm4: DC pred score    xmm3: H pred score  xmm2: V pred score
%macro INTRA_SAD16 0
cglobal intra_sad_x3_16x16, 3,5,8
    pxor    mm0, mm0
    pxor    mm1, mm1
    psadbw  mm0, [r1-FDEC_STRIDE+0]
    psadbw  mm1, [r1-FDEC_STRIDE+8]
    paddw   mm0, mm1
    movd    r3d, mm0
%if cpuflag(ssse3)
    mova  m1, [pb_3]
%endif
%assign x 0
%rep 16
    movzx   r4d, byte [r1-1+FDEC_STRIDE*(x&3)]
%if (x&3)==3 && x!=15
    add      r1, FDEC_STRIDE*4
%endif
    add     r3d, r4d
%assign x x+1
%endrep
    sub      r1, FDEC_STRIDE*12
    add     r3d, 16
    shr     r3d, 5
    imul    r3d, 0x01010101
    movd    m7, r3d
    mova    m5, [r1-FDEC_STRIDE]
%if mmsize==16
    pshufd  m7, m7, 0
%else
    mova    m1, [r1-FDEC_STRIDE+8]
    punpckldq m7, m7
%endif
    pxor    m4, m4
    pxor    m3, m3
    pxor    m2, m2
    mov     r3d, 15*FENC_STRIDE
.vloop:
    SPLATB_LOAD m6, r1+r3*2-1, m1
    mova    m0, [r0+r3]
    psadbw  m0, m7
    paddw   m4, m0
    mova    m0, [r0+r3]
    psadbw  m0, m5
    paddw   m2, m0
%if mmsize==8
    mova    m0, [r0+r3]
    psadbw  m0, m6
    paddw   m3, m0
    mova    m0, [r0+r3+8]
    psadbw  m0, m7
    paddw   m4, m0
    mova    m0, [r0+r3+8]
    psadbw  m0, m1
    paddw   m2, m0
    psadbw  m6, [r0+r3+8]
    paddw   m3, m6
%else
    psadbw  m6, [r0+r3]
    paddw   m3, m6
%endif
    add     r3d, -FENC_STRIDE
    jge .vloop
%if mmsize==16
    pslldq  m3, 4
    por     m3, m2
    movhlps m1, m3
    paddw   m3, m1
    movq  [r2+0], m3
    movhlps m1, m4
    paddw   m4, m1
%else
    movd  [r2+0], m2
    movd  [r2+4], m3
%endif
    movd  [r2+8], m4
    RET
%endmacro

INIT_MMX mmx2
INTRA_SAD16
INIT_XMM sse2
INTRA_SAD16
INIT_XMM ssse3
INTRA_SAD16

INIT_YMM avx2
cglobal intra_sad_x3_16x16, 3,5,6
    pxor   xm0, xm0
    psadbw xm0, [r1-FDEC_STRIDE]
    movhlps xm1, xm0
    paddw  xm0, xm1
    movd   r3d, xm0
%assign x 0
%rep 16
    movzx  r4d, byte [r1-1+FDEC_STRIDE*(x&3)]
%if (x&3)==3 && x!=15
    add     r1, FDEC_STRIDE*4
%endif
    add    r3d, r4d
%assign x x+1
%endrep
    sub     r1, FDEC_STRIDE*12
    add    r3d, 16
    shr    r3d, 5
    movd   xm5, r3d
    vpbroadcastb xm5, xm5
    vinserti128 m5, m5, [r1-FDEC_STRIDE], 1 ; m5 contains DC and V prediction

    pxor    m4, m4  ; DC / V accumulator
    pxor   xm3, xm3 ; H accumulator
    mov    r3d, 15*FENC_STRIDE
.vloop:
    vpbroadcastb  xm2, [r1+r3*2-1]
    vbroadcasti128 m0, [r0+r3]
    psadbw  m1, m0, m5
    psadbw xm0, xm2
    paddw   m4, m1
    paddw  xm3, xm0
    add    r3d, -FENC_STRIDE
    jge .vloop
    punpckhqdq m5, m4, m4
    movhlps xm2, xm3
    paddw   m4, m5      ; DC / V
    paddw  xm3, xm2     ; H
    vextracti128 xm2, m4, 1
    movd  [r2+0], xm2
    movd  [r2+4], xm3
    movd  [r2+8], xm4
    RET

;-----------------------------------------------------------------------------
; AVX512ICL intra_sad_x3: all rows of a mode in one zmm, the three sums packed
; into the words of one qword (each at most 16*16*255) and reduced together.
;-----------------------------------------------------------------------------
%if ARCH_X86_64
; m%1 = { m%1 | m%2 << 16 | m%3 << 32 } qword sums -> words 0-2 to [r2], [r2+4], [r2+8]
%macro INTRA_SAD_PACK3_END 3
    psllq         m%2, 16
    psllq         m%3, 32
    vpternlogq    m%1, m%2, m%3, 0xfe
    vextracti64x4 ym%2, m%1, 1
    paddq         ym%1, ym%2
    vextracti128  xm%2, ym%1, 1
    paddq         xm%1, xm%2
    punpckhqdq    xm%2, xm%1, xm%1
    paddq         xm%1, xm%2
    vpmovzxwd     xm%1, xm%1
    movq      [r2+0], xm%1
    pextrd    [r2+8], xm%1, 2
    RET
%endmacro

; xm%1 = bytes -1 of rows %2*4 .. %2*4+3 of fdec (r1)
%macro INTRA_SAD_LEFT4 2
    movd          xm%1, [r1+FDEC_STRIDE*(%2*4+3)-4]
    pinsrb        xm%1, [r1+FDEC_STRIDE*(%2*4+0)-1], 0
    pinsrb        xm%1, [r1+FDEC_STRIDE*(%2*4+1)-1], 1
    pinsrb        xm%1, [r1+FDEC_STRIDE*(%2*4+2)-1], 2
%endmacro

INIT_ZMM avx512icl
cglobal intra_sad_x3_8x8c, 3,3,8
    INTRA_SAD_LEFT4 0, 0
    INTRA_SAD_LEFT4 2, 1
    movq          xm1, [r1-FDEC_STRIDE]
    punpckldq     xm0, xm2              ; left 0-7
    pxor          xm3, xm3
    punpcklqdq    xm2, xm1, xm0         ; top 0-7, left 0-7
    vdbpsadbw     xm2, xm2, xm3, 0      ; s0 s0 s1 s1 s2 s2 s3 s3
    movu          xm4, [isad8c_wperm]
    vpermw        xm2, xm4, xm2
    pmaddwd       xm2, [isad8c_wmul]    ; s0+s2, s1, s3, s1+s3
    vpsrlvd       xm2, xm2, [isad8c_shift]
    pavgw         xm2, xm3              ; dc0 dc1 dc2 dc3
    mova           m4, [isad8c_dcidx]
    vpermb         m4, m4, m2           ; DC prediction
    mova           m5, [isad8c_hidx]
    vpermb         m5, m5, m0           ; H prediction
    vpbroadcastq   m1, [r1-FDEC_STRIDE] ; V prediction
    movu           m6, [r0]
    movu           m7, [r0+4*FENC_STRIDE]
    mova           m3, [isad8c_qidx]
    vpermt2q       m6, m3, m7           ; fenc rows 0-7
    psadbw         m4, m6
    psadbw         m5, m6
    psadbw         m1, m6
    INTRA_SAD_PACK3_END 4, 5, 1         ; DC H V

cglobal intra_sad_x3_16x16, 3,3,10
    INTRA_SAD_LEFT4 0, 0
    INTRA_SAD_LEFT4 2, 1
    INTRA_SAD_LEFT4 1, 2
    INTRA_SAD_LEFT4 4, 3
    punpckldq     xm0, xm2
    punpckldq     xm1, xm4
    movu          xm3, [r1-FDEC_STRIDE]
    pxor          xm5, xm5
    punpcklqdq    xm0, xm1              ; left 0-15
    psadbw        xm2, xm0, xm5
    psadbw        xm3, xm5
    paddw         xm2, xm3
    punpckhqdq    xm3, xm2, xm2
    paddw         xm2, xm3
    psrlw         xm2, 4
    pavgw         xm2, xm5              ; (sum+16)>>5
    vpbroadcastb   m2, xm2              ; DC prediction
    vbroadcasti32x4 m1, [r1-FDEC_STRIDE] ; V prediction
    vshufi32x4     m0, m0, m0, 0        ; left in every lane
%assign isad_g 0
%rep 4
    movu           m7, [r0+isad_g*4*FENC_STRIDE]
    mova           m3, [isad16_hidx+isad_g*64]
    pshufb         m3, m0, m3           ; H prediction, rows 4g..4g+3
    psadbw         m3, m7
    psadbw         m8, m1, m7
    psadbw         m9, m2, m7
    ACCUM       paddq, 6, 3, isad_g
    ACCUM       paddq, 4, 8, isad_g
    ACCUM       paddq, 5, 9, isad_g
%assign isad_g isad_g+1
%endrep
%undef isad_g
    INTRA_SAD_PACK3_END 4, 6, 5         ; V H DC

; 8x16c: as 8x8c with { s4, s5 } from left 8-15 in lane 1 of the vdbpsadbw,
; dc4-dc7 as bytes 16-28 of the vpermb source, H rows 8-15 from left 8-15
cglobal intra_sad_x3_8x16c, 3,3,12
    INTRA_SAD_LEFT4 0, 0
    INTRA_SAD_LEFT4 2, 1
    INTRA_SAD_LEFT4 3, 2
    INTRA_SAD_LEFT4 4, 3
    punpckldq     xm0, xm2              ; left 0-7
    punpckldq     xm3, xm4              ; left 8-15
    movq          xm1, [r1-FDEC_STRIDE]
    pxor          xm5, xm5
    punpcklqdq    xm2, xm1, xm0         ; top 0-7, left 0-7
    movq          xm4, xm3
    vinserti32x4  ym2, ym2, xm4, 1      ; | left 8-15, 0
    vdbpsadbw     ym2, ym2, ym5, 0      ; s0 s0 s1 s1 s2 s2 s3 s3 | s4 s4 s5 s5 0 0 0 0
    movu          ym4, [isad816c_wperm]
    vpermw        ym2, ym4, ym2
    pmaddwd       ym2, [isad816c_wmul]  ; s0+s2 s1 s3 s1+s3 s4 s1+s4 s5 s1+s5
    vpsrlvd       ym2, ym2, [isad816c_shift]
    pavgw         ym2, ym5              ; dc0 .. dc7
    mova           m4, [isad8c_dcidx]
    vpermb         m4, m4, m2           ; DC rows 0-7
    mova           m6, [isad816c_dcidx]
    vpermb         m6, m6, m2           ; DC rows 8-15
    mova           m5, [isad8c_hidx]
    vpermb         m7, m5, m0           ; H rows 0-7
    vpermb         m8, m5, m3           ; H rows 8-15
    vpbroadcastq   m1, [r1-FDEC_STRIDE] ; V prediction
    mova          m11, [isad8c_qidx]
    movu           m9, [r0]
    movu           m5, [r0+4*FENC_STRIDE]
    vpermt2q       m9, m11, m5          ; fenc rows 0-7
    movu          m10, [r0+8*FENC_STRIDE]
    movu           m5, [r0+12*FENC_STRIDE]
    vpermt2q      m10, m11, m5          ; fenc rows 8-15
    psadbw         m4, m9
    psadbw         m6, m10
    paddq          m4, m6
    psadbw         m7, m9
    psadbw         m8, m10
    paddq          m7, m8
    psadbw         m9, m1
    psadbw         m1, m10
    paddq          m1, m9
    INTRA_SAD_PACK3_END 4, 7, 1         ; DC H V

;-----------------------------------------------------------------------------
; void intra_sad_x3_4x4( uint8_t *fenc, uint8_t *fdec, int res[3] )
; reached where intra_sad_x9_4x4 isn't used (frame edges, lossless)
; fenc rows k-merged by vpbroadcastd and broadcast to every lane against
; { V | H | DC } lanes: one psadbw. Tail: vpmovqw, pmaddwd (2 ops).
;-----------------------------------------------------------------------------
cglobal intra_sad_x3_4x4, 3,4,5
    mov           r3d, 2
    kmovb          k1, r3d
    add           r3d, r3d
    kmovb          k2, r3d
    add           r3d, r3d
    kmovb          k3, r3d
    movd          xm0, [r0]
    vpbroadcastd  xm0 {k1}, [r0+1*FENC_STRIDE]
    vpbroadcastd  xm0 {k2}, [r0+2*FENC_STRIDE]
    vpbroadcastd  xm0 {k3}, [r0+3*FENC_STRIDE]
    vshufi32x4     m0, m0, m0, 0        ; fenc in every lane
    movd          xm1, [r1+3*FDEC_STRIDE-4]
    pinsrb        xm1, [r1+0*FDEC_STRIDE-1], 0
    pinsrb        xm1, [r1+1*FDEC_STRIDE-1], 1
    pinsrb        xm1, [r1+2*FDEC_STRIDE-1], 2
    movd          xm2, [r1-FDEC_STRIDE]
    punpckldq     xm3, xm1, xm2         ; left 0-3, top 0-3
    pxor          xm4, xm4
    psadbw        xm3, xm4
    psrlw         xm3, 2
    pavgw         xm3, xm4              ; (sum+4)>>3
    pshufb        xm3, xm4              ; DC
    pshufb        xm1, [pb_unpackbd1]   ; H
    vpbroadcastd  xm2, xm2              ; V
    vinserti32x4  ym2, ym2, xm1, 1
    vinserti32x4   m2, m2, xm3, 2       ; V | H | DC | 0
    psadbw         m2, m0
    vpmovqw       xm2, m2
    pmaddwd       xm2, [pw_1]           ; V H DC _
    movq      [r2+0], xm2
    pextrd    [r2+8], xm2, 2
    RET

;-----------------------------------------------------------------------------
; void intra_sad_x3_8x8( uint8_t *fenc, uint8_t edge[36], int res[3] )
; reached where intra_sad_x9_8x8 isn't used (frame edges, lossless)
; all 8 rows of a mode in one zmm, the sums packed as in the 8x8c kernel
;-----------------------------------------------------------------------------
cglobal intra_sad_x3_8x8, 3,3,8
    movq          xm0, [r1+7]           ; l7 .. l0
    movq          xm1, [r1+16]          ; t0 .. t7
    punpcklqdq    xm2, xm0, xm1
    pxor          xm3, xm3
    psadbw        xm2, xm3
    punpckhqdq    xm4, xm2, xm2
    paddw         xm2, xm4
    psrlw         xm2, 3
    pavgw         xm2, xm3              ; (sum+8)>>4
    vpbroadcastb   m2, xm2              ; DC
    mova           m4, [isad8_hidxr]
    vpermb         m4, m4, m0           ; H
    vpbroadcastq   m1, xm1              ; V
    movu           m6, [r0]
    movu           m7, [r0+4*FENC_STRIDE]
    mova           m5, [isad8c_qidx]
    vpermt2q       m6, m5, m7           ; fenc rows 0-7
    psadbw         m1, m6
    psadbw         m4, m6
    psadbw         m2, m6
    INTRA_SAD_PACK3_END 1, 4, 2         ; V H DC
%endif ; ARCH_X86_64

;=============================================================================
; SAD x3/x4 MMX
;=============================================================================

%macro SAD_X3_START_1x8P 0
    movq    mm3,    [r0]
    movq    mm0,    [r1]
    movq    mm1,    [r2]
    movq    mm2,    [r3]
    psadbw  mm0,    mm3
    psadbw  mm1,    mm3
    psadbw  mm2,    mm3
%endmacro

%macro SAD_X3_1x8P 2
    movq    mm3,    [r0+%1]
    movq    mm4,    [r1+%2]
    movq    mm5,    [r2+%2]
    movq    mm6,    [r3+%2]
    psadbw  mm4,    mm3
    psadbw  mm5,    mm3
    psadbw  mm6,    mm3
    paddw   mm0,    mm4
    paddw   mm1,    mm5
    paddw   mm2,    mm6
%endmacro

%macro SAD_X3_START_2x4P 3
    movd      mm3,  [r0]
    movd      %1,   [r1]
    movd      %2,   [r2]
    movd      %3,   [r3]
    punpckldq mm3,  [r0+FENC_STRIDE]
    punpckldq %1,   [r1+r4]
    punpckldq %2,   [r2+r4]
    punpckldq %3,   [r3+r4]
    psadbw    %1,   mm3
    psadbw    %2,   mm3
    psadbw    %3,   mm3
%endmacro

%macro SAD_X3_2x16P 1
%if %1
    SAD_X3_START_1x8P
%else
    SAD_X3_1x8P 0, 0
%endif
    SAD_X3_1x8P 8, 8
    SAD_X3_1x8P FENC_STRIDE, r4
    SAD_X3_1x8P FENC_STRIDE+8, r4+8
    add     r0, 2*FENC_STRIDE
    lea     r1, [r1+2*r4]
    lea     r2, [r2+2*r4]
    lea     r3, [r3+2*r4]
%endmacro

%macro SAD_X3_2x8P 1
%if %1
    SAD_X3_START_1x8P
%else
    SAD_X3_1x8P 0, 0
%endif
    SAD_X3_1x8P FENC_STRIDE, r4
    add     r0, 2*FENC_STRIDE
    lea     r1, [r1+2*r4]
    lea     r2, [r2+2*r4]
    lea     r3, [r3+2*r4]
%endmacro

%macro SAD_X3_2x4P 1
%if %1
    SAD_X3_START_2x4P mm0, mm1, mm2
%else
    SAD_X3_START_2x4P mm4, mm5, mm6
    paddw     mm0,  mm4
    paddw     mm1,  mm5
    paddw     mm2,  mm6
%endif
    add     r0, 2*FENC_STRIDE
    lea     r1, [r1+2*r4]
    lea     r2, [r2+2*r4]
    lea     r3, [r3+2*r4]
%endmacro

%macro SAD_X4_START_1x8P 0
    movq    mm7,    [r0]
    movq    mm0,    [r1]
    movq    mm1,    [r2]
    movq    mm2,    [r3]
    movq    mm3,    [r4]
    psadbw  mm0,    mm7
    psadbw  mm1,    mm7
    psadbw  mm2,    mm7
    psadbw  mm3,    mm7
%endmacro

%macro SAD_X4_1x8P 2
    movq    mm7,    [r0+%1]
    movq    mm4,    [r1+%2]
    movq    mm5,    [r2+%2]
    movq    mm6,    [r3+%2]
    psadbw  mm4,    mm7
    psadbw  mm5,    mm7
    psadbw  mm6,    mm7
    psadbw  mm7,    [r4+%2]
    paddw   mm0,    mm4
    paddw   mm1,    mm5
    paddw   mm2,    mm6
    paddw   mm3,    mm7
%endmacro

%macro SAD_X4_START_2x4P 0
    movd      mm7,  [r0]
    movd      mm0,  [r1]
    movd      mm1,  [r2]
    movd      mm2,  [r3]
    movd      mm3,  [r4]
    punpckldq mm7,  [r0+FENC_STRIDE]
    punpckldq mm0,  [r1+r5]
    punpckldq mm1,  [r2+r5]
    punpckldq mm2,  [r3+r5]
    punpckldq mm3,  [r4+r5]
    psadbw    mm0,  mm7
    psadbw    mm1,  mm7
    psadbw    mm2,  mm7
    psadbw    mm3,  mm7
%endmacro

%macro SAD_X4_INC_2x4P 0
    movd      mm7,  [r0]
    movd      mm4,  [r1]
    movd      mm5,  [r2]
    punpckldq mm7,  [r0+FENC_STRIDE]
    punpckldq mm4,  [r1+r5]
    punpckldq mm5,  [r2+r5]
    psadbw    mm4,  mm7
    psadbw    mm5,  mm7
    paddw     mm0,  mm4
    paddw     mm1,  mm5
    movd      mm4,  [r3]
    movd      mm5,  [r4]
    punpckldq mm4,  [r3+r5]
    punpckldq mm5,  [r4+r5]
    psadbw    mm4,  mm7
    psadbw    mm5,  mm7
    paddw     mm2,  mm4
    paddw     mm3,  mm5
%endmacro

%macro SAD_X4_2x16P 1
%if %1
    SAD_X4_START_1x8P
%else
    SAD_X4_1x8P 0, 0
%endif
    SAD_X4_1x8P 8, 8
    SAD_X4_1x8P FENC_STRIDE, r5
    SAD_X4_1x8P FENC_STRIDE+8, r5+8
    add     r0, 2*FENC_STRIDE
    lea     r1, [r1+2*r5]
    lea     r2, [r2+2*r5]
    lea     r3, [r3+2*r5]
    lea     r4, [r4+2*r5]
%endmacro

%macro SAD_X4_2x8P 1
%if %1
    SAD_X4_START_1x8P
%else
    SAD_X4_1x8P 0, 0
%endif
    SAD_X4_1x8P FENC_STRIDE, r5
    add     r0, 2*FENC_STRIDE
    lea     r1, [r1+2*r5]
    lea     r2, [r2+2*r5]
    lea     r3, [r3+2*r5]
    lea     r4, [r4+2*r5]
%endmacro

%macro SAD_X4_2x4P 1
%if %1
    SAD_X4_START_2x4P
%else
    SAD_X4_INC_2x4P
%endif
    add     r0, 2*FENC_STRIDE
    lea     r1, [r1+2*r5]
    lea     r2, [r2+2*r5]
    lea     r3, [r3+2*r5]
    lea     r4, [r4+2*r5]
%endmacro

%macro SAD_X3_END 0
%if UNIX64
    movd    [r5+0], mm0
    movd    [r5+4], mm1
    movd    [r5+8], mm2
%else
    mov     r0, r5mp
    movd    [r0+0], mm0
    movd    [r0+4], mm1
    movd    [r0+8], mm2
%endif
    RET
%endmacro

%macro SAD_X4_END 0
    mov     r0, r6mp
    movd    [r0+0], mm0
    movd    [r0+4], mm1
    movd    [r0+8], mm2
    movd    [r0+12], mm3
    RET
%endmacro

;-----------------------------------------------------------------------------
; void pixel_sad_x3_16x16( uint8_t *fenc, uint8_t *pix0, uint8_t *pix1,
;                          uint8_t *pix2, intptr_t i_stride, int scores[3] )
;-----------------------------------------------------------------------------
%macro SAD_X 3
cglobal pixel_sad_x%1_%2x%3_mmx2, %1+2, %1+2
    SAD_X%1_2x%2P 1
%rep %3/2-1
    SAD_X%1_2x%2P 0
%endrep
    SAD_X%1_END
%endmacro

INIT_MMX
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



;=============================================================================
; SAD x3/x4 XMM
;=============================================================================

%macro SAD_X3_START_1x16P_SSE2 0
    mova     m2, [r0]
%if cpuflag(avx)
    psadbw   m0, m2, [r1]
    psadbw   m1, m2, [r2]
    psadbw   m2, [r3]
%else
    movu     m0, [r1]
    movu     m1, [r2]
    movu     m3, [r3]
    psadbw   m0, m2
    psadbw   m1, m2
    psadbw   m2, m3
%endif
%endmacro

%macro SAD_X3_1x16P_SSE2 2
    mova     m3, [r0+%1]
%if cpuflag(avx)
    psadbw   m4, m3, [r1+%2]
    psadbw   m5, m3, [r2+%2]
    psadbw   m3, [r3+%2]
%else
    movu     m4, [r1+%2]
    movu     m5, [r2+%2]
    movu     m6, [r3+%2]
    psadbw   m4, m3
    psadbw   m5, m3
    psadbw   m3, m6
%endif
    paddw    m0, m4
    paddw    m1, m5
    paddw    m2, m3
%endmacro

%if ARCH_X86_64
    DECLARE_REG_TMP 6
%else
    DECLARE_REG_TMP 5
%endif

%macro SAD_X3_4x16P_SSE2 2
%if %1==0
    lea  t0, [r4*3]
    SAD_X3_START_1x16P_SSE2
%else
    SAD_X3_1x16P_SSE2 FENC_STRIDE*(0+(%1&1)*4), r4*0
%endif
    SAD_X3_1x16P_SSE2 FENC_STRIDE*(1+(%1&1)*4), r4*1
    SAD_X3_1x16P_SSE2 FENC_STRIDE*(2+(%1&1)*4), r4*2
    SAD_X3_1x16P_SSE2 FENC_STRIDE*(3+(%1&1)*4), t0
%if %1 != %2-1
%if (%1&1) != 0
    add  r0, 8*FENC_STRIDE
%endif
    lea  r1, [r1+4*r4]
    lea  r2, [r2+4*r4]
    lea  r3, [r3+4*r4]
%endif
%endmacro

%macro SAD_X3_START_2x8P_SSE2 0
    movq     m3, [r0]
    movq     m0, [r1]
    movq     m1, [r2]
    movq     m2, [r3]
    movhps   m3, [r0+FENC_STRIDE]
    movhps   m0, [r1+r4]
    movhps   m1, [r2+r4]
    movhps   m2, [r3+r4]
    psadbw   m0, m3
    psadbw   m1, m3
    psadbw   m2, m3
%endmacro

%macro SAD_X3_2x8P_SSE2 4
    movq     m6, [r0+%1]
    movq     m3, [r1+%2]
    movq     m4, [r2+%2]
    movq     m5, [r3+%2]
    movhps   m6, [r0+%3]
    movhps   m3, [r1+%4]
    movhps   m4, [r2+%4]
    movhps   m5, [r3+%4]
    psadbw   m3, m6
    psadbw   m4, m6
    psadbw   m5, m6
    paddw    m0, m3
    paddw    m1, m4
    paddw    m2, m5
%endmacro

%macro SAD_X4_START_2x8P_SSE2 0
    movq     m4, [r0]
    movq     m0, [r1]
    movq     m1, [r2]
    movq     m2, [r3]
    movq     m3, [r4]
    movhps   m4, [r0+FENC_STRIDE]
    movhps   m0, [r1+r5]
    movhps   m1, [r2+r5]
    movhps   m2, [r3+r5]
    movhps   m3, [r4+r5]
    psadbw   m0, m4
    psadbw   m1, m4
    psadbw   m2, m4
    psadbw   m3, m4
%endmacro

%macro SAD_X4_2x8P_SSE2 4
    movq     m6, [r0+%1]
    movq     m4, [r1+%2]
    movq     m5, [r2+%2]
    movhps   m6, [r0+%3]
    movhps   m4, [r1+%4]
    movhps   m5, [r2+%4]
    psadbw   m4, m6
    psadbw   m5, m6
    paddw    m0, m4
    paddw    m1, m5
    movq     m4, [r3+%2]
    movq     m5, [r4+%2]
    movhps   m4, [r3+%4]
    movhps   m5, [r4+%4]
    psadbw   m4, m6
    psadbw   m5, m6
    paddw    m2, m4
    paddw    m3, m5
%endmacro

%macro SAD_X4_START_1x16P_SSE2 0
    mova     m3, [r0]
%if cpuflag(avx)
    psadbw   m0, m3, [r1]
    psadbw   m1, m3, [r2]
    psadbw   m2, m3, [r3]
    psadbw   m3, [r4]
%else
    movu     m0, [r1]
    movu     m1, [r2]
    movu     m2, [r3]
    movu     m4, [r4]
    psadbw   m0, m3
    psadbw   m1, m3
    psadbw   m2, m3
    psadbw   m3, m4
%endif
%endmacro

%macro SAD_X4_1x16P_SSE2 2
    mova     m6, [r0+%1]
%if cpuflag(avx)
    psadbw   m4, m6, [r1+%2]
    psadbw   m5, m6, [r2+%2]
%else
    movu     m4, [r1+%2]
    movu     m5, [r2+%2]
    psadbw   m4, m6
    psadbw   m5, m6
%endif
    paddw    m0, m4
    paddw    m1, m5
%if cpuflag(avx)
    psadbw   m4, m6, [r3+%2]
    psadbw   m5, m6, [r4+%2]
%else
    movu     m4, [r3+%2]
    movu     m5, [r4+%2]
    psadbw   m4, m6
    psadbw   m5, m6
%endif
    paddw    m2, m4
    paddw    m3, m5
%endmacro

%macro SAD_X4_4x16P_SSE2 2
%if %1==0
    lea  r6, [r5*3]
    SAD_X4_START_1x16P_SSE2
%else
    SAD_X4_1x16P_SSE2 FENC_STRIDE*(0+(%1&1)*4), r5*0
%endif
    SAD_X4_1x16P_SSE2 FENC_STRIDE*(1+(%1&1)*4), r5*1
    SAD_X4_1x16P_SSE2 FENC_STRIDE*(2+(%1&1)*4), r5*2
    SAD_X4_1x16P_SSE2 FENC_STRIDE*(3+(%1&1)*4), r6
%if %1 != %2-1
%if (%1&1) != 0
    add  r0, 8*FENC_STRIDE
%endif
    lea  r1, [r1+4*r5]
    lea  r2, [r2+4*r5]
    lea  r3, [r3+4*r5]
    lea  r4, [r4+4*r5]
%endif
%endmacro

%macro SAD_X3_4x8P_SSE2 2
%if %1==0
    lea  t0, [r4*3]
    SAD_X3_START_2x8P_SSE2
%else
    SAD_X3_2x8P_SSE2 FENC_STRIDE*(0+(%1&1)*4), r4*0, FENC_STRIDE*(1+(%1&1)*4), r4*1
%endif
    SAD_X3_2x8P_SSE2 FENC_STRIDE*(2+(%1&1)*4), r4*2, FENC_STRIDE*(3+(%1&1)*4), t0
%if %1 != %2-1
%if (%1&1) != 0
    add  r0, 8*FENC_STRIDE
%endif
    lea  r1, [r1+4*r4]
    lea  r2, [r2+4*r4]
    lea  r3, [r3+4*r4]
%endif
%endmacro

%macro SAD_X4_4x8P_SSE2 2
%if %1==0
    lea    r6, [r5*3]
    SAD_X4_START_2x8P_SSE2
%else
    SAD_X4_2x8P_SSE2 FENC_STRIDE*(0+(%1&1)*4), r5*0, FENC_STRIDE*(1+(%1&1)*4), r5*1
%endif
    SAD_X4_2x8P_SSE2 FENC_STRIDE*(2+(%1&1)*4), r5*2, FENC_STRIDE*(3+(%1&1)*4), r6
%if %1 != %2-1
%if (%1&1) != 0
    add  r0, 8*FENC_STRIDE
%endif
    lea  r1, [r1+4*r5]
    lea  r2, [r2+4*r5]
    lea  r3, [r3+4*r5]
    lea  r4, [r4+4*r5]
%endif
%endmacro

%macro SAD_X3_END_SSE2 0
    movifnidn r5, r5mp
%if cpuflag(ssse3)
    packssdw m0, m1
    packssdw m2, m2
    phaddd   m0, m2
    mova   [r5], m0
%else
    movhlps  m3, m0
    movhlps  m4, m1
    movhlps  m5, m2
    paddw    m0, m3
    paddw    m1, m4
    paddw    m2, m5
    movd [r5+0], m0
    movd [r5+4], m1
    movd [r5+8], m2
%endif
    RET
%endmacro

%macro SAD_X4_END_SSE2 0
    mov      r0, r6mp
%if cpuflag(ssse3)
    packssdw m0, m1
    packssdw m2, m3
    phaddd   m0, m2
    mova   [r0], m0
%else
    psllq    m1, 32
    psllq    m3, 32
    paddw    m0, m1
    paddw    m2, m3
    movhlps  m1, m0
    movhlps  m3, m2
    paddw    m0, m1
    paddw    m2, m3
    movq [r0+0], m0
    movq [r0+8], m2
%endif
    RET
%endmacro

%macro SAD_X4_START_2x8P_SSSE3 0
    movddup  m4, [r0]
    movq     m0, [r1]
    movq     m1, [r3]
    movhps   m0, [r2]
    movhps   m1, [r4]
    movddup  m5, [r0+FENC_STRIDE]
    movq     m2, [r1+r5]
    movq     m3, [r3+r5]
    movhps   m2, [r2+r5]
    movhps   m3, [r4+r5]
    psadbw   m0, m4
    psadbw   m1, m4
    psadbw   m2, m5
    psadbw   m3, m5
    paddw    m0, m2
    paddw    m1, m3
%endmacro

%macro SAD_X4_2x8P_SSSE3 4
    movddup  m6, [r0+%1]
    movq     m2, [r1+%2]
    movq     m3, [r3+%2]
    movhps   m2, [r2+%2]
    movhps   m3, [r4+%2]
    movddup  m7, [r0+%3]
    movq     m4, [r1+%4]
    movq     m5, [r3+%4]
    movhps   m4, [r2+%4]
    movhps   m5, [r4+%4]
    psadbw   m2, m6
    psadbw   m3, m6
    psadbw   m4, m7
    psadbw   m5, m7
    paddw    m0, m2
    paddw    m1, m3
    paddw    m0, m4
    paddw    m1, m5
%endmacro

%macro SAD_X4_4x8P_SSSE3 2
%if %1==0
    lea    r6, [r5*3]
    SAD_X4_START_2x8P_SSSE3
%else
    SAD_X4_2x8P_SSSE3 FENC_STRIDE*(0+(%1&1)*4), r5*0, FENC_STRIDE*(1+(%1&1)*4), r5*1
%endif
    SAD_X4_2x8P_SSSE3 FENC_STRIDE*(2+(%1&1)*4), r5*2, FENC_STRIDE*(3+(%1&1)*4), r6
%if %1 != %2-1
%if (%1&1) != 0
    add  r0, 8*FENC_STRIDE
%endif
    lea  r1, [r1+4*r5]
    lea  r2, [r2+4*r5]
    lea  r3, [r3+4*r5]
    lea  r4, [r4+4*r5]
%endif
%endmacro

%macro SAD_X4_END_SSSE3 0
    mov      r0, r6mp
    packssdw m0, m1
    mova   [r0], m0
    RET
%endmacro

%macro SAD_X3_START_2x16P_AVX2 0
    movu    m3, [r0] ; assumes FENC_STRIDE == 16
    movu   xm0, [r1]
    movu   xm1, [r2]
    movu   xm2, [r3]
    vinserti128  m0, m0, [r1+r4], 1
    vinserti128  m1, m1, [r2+r4], 1
    vinserti128  m2, m2, [r3+r4], 1
    psadbw  m0, m3
    psadbw  m1, m3
    psadbw  m2, m3
%endmacro

%macro SAD_X3_2x16P_AVX2 3
    movu    m3, [r0+%1] ; assumes FENC_STRIDE == 16
    movu   xm4, [r1+%2]
    movu   xm5, [r2+%2]
    movu   xm6, [r3+%2]
    vinserti128  m4, m4, [r1+%3], 1
    vinserti128  m5, m5, [r2+%3], 1
    vinserti128  m6, m6, [r3+%3], 1
    psadbw  m4, m3
    psadbw  m5, m3
    psadbw  m6, m3
    paddw   m0, m4
    paddw   m1, m5
    paddw   m2, m6
%endmacro

%macro SAD_X3_4x16P_AVX2 2
%if %1==0
    lea  t0, [r4*3]
    SAD_X3_START_2x16P_AVX2
%else
    SAD_X3_2x16P_AVX2 FENC_STRIDE*(0+(%1&1)*4), r4*0, r4*1
%endif
    SAD_X3_2x16P_AVX2 FENC_STRIDE*(2+(%1&1)*4), r4*2, t0
%if %1 != %2-1
%if (%1&1) != 0
    add  r0, 8*FENC_STRIDE
%endif
    lea  r1, [r1+4*r4]
    lea  r2, [r2+4*r4]
    lea  r3, [r3+4*r4]
%endif
%endmacro

; x4 as x3: one 32-byte load of fenc rows j | j+1 (FENC_STRIDE == 16), one accumulator
; per reference with rows j | j+1 in its lanes
%macro SAD_X4_START_2x16P_AVX2 0
    movu    m4, [r0]
    movu   xm0, [r1]
    movu   xm1, [r2]
    movu   xm2, [r3]
    movu   xm3, [r4]
    vinserti128 m0, m0, [r1+r5], 1
    vinserti128 m1, m1, [r2+r5], 1
    vinserti128 m2, m2, [r3+r5], 1
    vinserti128 m3, m3, [r4+r5], 1
    psadbw  m0, m4
    psadbw  m1, m4
    psadbw  m2, m4
    psadbw  m3, m4
%endmacro

%macro SAD_X4_2x16P_AVX2 3 ; fenc offset of row j, ref offsets of rows j, j+1
    movu    m6, [r0+%1]
    movu   xm4, [r1+%2]
    movu   xm5, [r2+%2]
    vinserti128 m4, m4, [r1+%3], 1
    vinserti128 m5, m5, [r2+%3], 1
    psadbw  m4, m6
    psadbw  m5, m6
    paddw   m0, m4
    paddw   m1, m5
    movu   xm4, [r3+%2]
    movu   xm5, [r4+%2]
    vinserti128 m4, m4, [r3+%3], 1
    vinserti128 m5, m5, [r4+%3], 1
    psadbw  m4, m6
    psadbw  m5, m6
    paddw   m2, m4
    paddw   m3, m5
%endmacro

%macro SAD_X4_4x16P_AVX2 2
%if %1==0
    lea  r6, [r5*3]
    SAD_X4_START_2x16P_AVX2
%else
    SAD_X4_2x16P_AVX2 FENC_STRIDE*(0+(%1&1)*4), r5*0, r5*1
%endif
    SAD_X4_2x16P_AVX2 FENC_STRIDE*(2+(%1&1)*4), r5*2, r6
%if %1 != %2-1
%if (%1&1) != 0
    add  r0, 8*FENC_STRIDE
%endif
    lea  r1, [r1+4*r5]
    lea  r2, [r2+4*r5]
    lea  r3, [r3+4*r5]
    lea  r4, [r4+4*r5]
%endif
%endmacro

%macro SAD_X3_END_AVX2 0
    movifnidn r5, r5mp
    packssdw  m0, m1        ; 0 0 1 1 0 0 1 1
    packssdw  m2, m2        ; 2 2 _ _ 2 2 _ _
    phaddd    m0, m2        ; 0 1 2 _ 0 1 2 _
    vextracti128 xm1, m0, 1
    paddd    xm0, xm1       ; 0 1 2 _
    mova    [r5], xm0
    RET
%endmacro

%macro SAD_X4_END_AVX2 0
    mov       r0, r6mp
    packssdw  m0, m1        ; 0 0 1 1 | 0 0 1 1
    packssdw  m2, m3        ; 2 2 3 3 | 2 2 3 3
    phaddd    m0, m2        ; 0 1 2 3 | 0 1 2 3
    vextracti128 xm1, m0, 1
    paddd    xm0, xm1
    mova    [r0], xm0
    RET
%endmacro

;-----------------------------------------------------------------------------
; void pixel_sad_x3_16x16( uint8_t *fenc, uint8_t *pix0, uint8_t *pix1,
;                          uint8_t *pix2, intptr_t i_stride, int scores[3] )
;-----------------------------------------------------------------------------
%macro SAD_X_SSE2 4
cglobal pixel_sad_x%1_%2x%3, 2+%1,3+%1,%4
%assign x 0
%rep %3/4
    SAD_X%1_4x%2P_SSE2 x, %3/4
%assign x x+1
%endrep
    SAD_X%1_END_SSE2
%endmacro

INIT_XMM sse2
SAD_X_SSE2 3, 16, 16, 7
SAD_X_SSE2 3, 16,  8, 7
SAD_X_SSE2 3,  8, 16, 7
SAD_X_SSE2 3,  8,  8, 7
SAD_X_SSE2 3,  8,  4, 7
SAD_X_SSE2 4, 16, 16, 7
SAD_X_SSE2 4, 16,  8, 7
SAD_X_SSE2 4,  8, 16, 7
SAD_X_SSE2 4,  8,  8, 7
SAD_X_SSE2 4,  8,  4, 7

INIT_XMM sse3
SAD_X_SSE2 3, 16, 16, 7
SAD_X_SSE2 3, 16,  8, 7
SAD_X_SSE2 4, 16, 16, 7
SAD_X_SSE2 4, 16,  8, 7

%macro SAD_X_SSSE3 3
cglobal pixel_sad_x%1_%2x%3, 2+%1,3+%1,8
%assign x 0
%rep %3/4
    SAD_X%1_4x%2P_SSSE3 x, %3/4
%assign x x+1
%endrep
    SAD_X%1_END_SSSE3
%endmacro

INIT_XMM ssse3
SAD_X_SSE2  3, 16, 16, 7
SAD_X_SSE2  3, 16,  8, 7
SAD_X_SSE2  4, 16, 16, 7
SAD_X_SSE2  4, 16,  8, 7
SAD_X_SSSE3 4,  8, 16
SAD_X_SSSE3 4,  8,  8
SAD_X_SSSE3 4,  8,  4

INIT_XMM avx
SAD_X_SSE2 3, 16, 16, 6
SAD_X_SSE2 3, 16,  8, 6
SAD_X_SSE2 4, 16, 16, 7
SAD_X_SSE2 4, 16,  8, 7

%macro SAD_X_AVX2 4
cglobal pixel_sad_x%1_%2x%3, 2+%1,3+%1,%4
%assign x 0
%rep %3/4
    SAD_X%1_4x%2P_AVX2 x, %3/4
%assign x x+1
%endrep
    SAD_X%1_END_AVX2
%endmacro

INIT_YMM avx2
SAD_X_AVX2 3, 16, 16, 7
SAD_X_AVX2 3, 16,  8, 7
SAD_X_AVX2 4, 16, 16, 7
SAD_X_AVX2 4, 16,  8, 7

;-----------------------------------------------------------------------------
; int pixel_sad_x3_min_16x16( uint8_t *fenc, uint8_t *pix0, uint8_t *pix1, uint8_t *pix2,
;                             intptr_t i_stride, uint64_t bias01, uint64_t bias2_best )
; int pixel_sad_x4_min_16x16( uint8_t *fenc, uint8_t *pix0, uint8_t *pix1, uint8_t *pix2,
;                             uint8_t *pix3, intptr_t i_stride, uint64_t bias01,
;                             uint64_t bias23, int best )
; min( best, (sad_i << 6) + bias_i ), signed; bias01 = bias_0 | bias_1 << 32, etc.
;-----------------------------------------------------------------------------
%if ARCH_X86_64
; xm%1 = { b0 b1 b2 best }, xm%2 = best in all lanes
%macro SAD_X3_MIN_ARGS 2
    movq         xm%1, r5mp
    vpbroadcastq xm%2, r6mp
    vpblendd     xm%1, xm%1, xm%2, 1100b
    pshufd       xm%2, xm%2, q1111
%endmacro

; xm%1 = { b0 b1 b2 b3 }, xm%2 = best in all lanes
%macro SAD_X4_MIN_ARGS 2
    movq         xm%1, r6mp
    movhps       xm%1, r7mp
    vpbroadcastd xm%2, r8m
%endmacro

; xm%1 = candidates, xm%2 = best in all lanes -> eax
%macro SAD_X_MIN_TREE 3 ; c, best, tmp
    pminsd       xm%2, xm%1
    pshufd       xm%3, xm%1, q1032
    pminsd       xm%1, xm%2, xm%3
    psrlq        xm%3, xm%1, 32
    pminsd       xm%1, xm%3
    movd          eax, xm%1
    RET
%endmacro

%macro SAD_X3_MIN_END_AVX2 0
    SAD_X3_MIN_ARGS 4, 5
    packssdw  m0, m1
    packssdw  m2, m2
    phaddd    m0, m2        ; 0 1 2 2 | 0 1 2 2
    pslld     m0, 6
    vextracti128 xm1, m0, 1
    paddd    xm0, xm4       ; lane 3 is best + 64*sad_2
    paddd    xm0, xm1
    SAD_X_MIN_TREE 0, 5, 1
%endmacro

%macro SAD_X4_MIN_END_AVX2 0
    SAD_X4_MIN_ARGS 4, 5
    packssdw  m0, m1        ; 0 0 1 1 | 0 0 1 1
    packssdw  m2, m3        ; 2 2 3 3 | 2 2 3 3
    phaddd    m0, m2        ; 0 1 2 3 | 0 1 2 3
    vextracti128 xm1, m0, 1
    paddd    xm0, xm1
    pslld    xm0, 6
    paddd    xm0, xm4
    SAD_X_MIN_TREE 0, 5, 1
%endmacro

%macro SAD_X_MIN_AVX2 4
cglobal pixel_sad_x%1_min_%2x%3, 2+%1,7,%4
%assign x 0
%rep %3/4
    SAD_X%1_4x%2P_AVX2 x, %3/4
%assign x x+1
%endrep
    SAD_X%1_MIN_END_AVX2
%endmacro

SAD_X_MIN_AVX2 3, 16, 16, 7
SAD_X_MIN_AVX2 3, 16,  8, 7
SAD_X_MIN_AVX2 4, 16, 16, 7
SAD_X_MIN_AVX2 4, 16,  8, 7
%endif ; ARCH_X86_64

; 8 wide: ymm = { p row j, q row j | p row j+1, q row j+1 } against a vmovddup
; of fenc rows j, j+1. Lane 1 of p is a 16 byte load (reads 8 bytes past the
; row, as pixel_sad_8x8_avx2 does), q row j+1 a broadcast + blend.
%macro SAD_X_W8_PAIR_AVX2 6 ; dst, tmp, p, q, row j offset, row j+1 offset
    movq          xm%1, [%3+%5]
    movhps        xm%1, [%4+%5]
    vinserti128    m%1, m%1, [%3+%6], 1
    vpbroadcastq   m%2, [%4+%6]
    vpblendd       m%1, m%1, m%2, 0xc0
%endmacro

; rows of a 4 row group: 0, stride, 2*stride, 3*stride
%macro SAD_X_W8_ROWOFF 3 ; row pair, stride, 3*stride
%if %1 & 2
    %xdefine sad_o0 2*%2
    %xdefine sad_o1 %3
%else
    %xdefine sad_o0 0
    %xdefine sad_o1 %2
%endif
%endmacro

%macro SAD_X3_W8_AVX2 1-2 0 ; h, min
%if %2
cglobal pixel_sad_x3_min_8x%1, 5,6,6
%else
cglobal pixel_sad_x3_8x%1, 5,6,6
%endif
    lea            t0, [3*r4]
%assign %%k 0
%rep %1/2
    SAD_X_W8_ROWOFF %%k, r4, t0
    vmovddup       m3, [r0+%%k*FENC_STRIDE]
    SAD_X_W8_PAIR_AVX2 2, 4, r1, r2, sad_o0, sad_o1
    movq          xm5, [r3+sad_o0]
    vinserti128    m5, m5, [r3+sad_o1], 1
%if %%k == 0
    psadbw         m0, m2, m3
    psadbw         m1, m5, m3
%else
    psadbw         m2, m3
    psadbw         m5, m3
    paddd          m0, m2
    paddd          m1, m5
%endif
%if (%%k & 3) == 2 && %%k < %1-2
    lea            r1, [r1+4*r4]
    lea            r2, [r2+4*r4]
    lea            r3, [r3+4*r4]
%endif
%assign %%k %%k+2
%endrep
%if %2
    SAD_X3_MIN_ARGS 2, 3
    packssdw       m0, m1
    pslld          m0, 6
    vextracti128  xm1, m0, 1
    paddd         xm0, xm2       ; lane 3 is best + 64*sad(fenc, 0)
    paddd         xm0, xm1
    SAD_X_MIN_TREE 0, 3, 1
%else
    movifnidn      r5, r5mp
    packssdw       m0, m1         ; { s0 s1 s2 _ | s0 s1 s2 _ }
    vextracti128  xm1, m0, 1
    paddd         xm0, xm1
    mova         [r5], xm0
    RET
%endif
%endmacro

%macro SAD_X4_W8_AVX2 1-2 0 ; h, min
%if %2
cglobal pixel_sad_x4_min_8x%1, 6,7,6
%else
cglobal pixel_sad_x4_8x%1, 6,7,6
%endif
    lea            r6, [3*r5]
%assign %%k 0
%rep %1/2
    SAD_X_W8_ROWOFF %%k, r5, r6
    vmovddup       m4, [r0+%%k*FENC_STRIDE]
    SAD_X_W8_PAIR_AVX2 2, 5, r1, r2, sad_o0, sad_o1
    SAD_X_W8_PAIR_AVX2 3, 5, r3, r4, sad_o0, sad_o1
%if %%k == 0
    psadbw         m0, m2, m4
    psadbw         m1, m3, m4
%else
    psadbw         m2, m4
    psadbw         m3, m4
    paddd          m0, m2
    paddd          m1, m3
%endif
%if (%%k & 3) == 2 && %%k < %1-2
    lea            r1, [r1+4*r5]
    lea            r2, [r2+4*r5]
    lea            r3, [r3+4*r5]
    lea            r4, [r4+4*r5]
%endif
%assign %%k %%k+2
%endrep
%if %2
    SAD_X4_MIN_ARGS 2, 3
    packssdw       m0, m1
    pslld          m0, 6
    vextracti128  xm1, m0, 1
    paddd         xm0, xm2
    paddd         xm0, xm1
    SAD_X_MIN_TREE 0, 3, 1
%else
    mov            r0, r6mp
    packssdw       m0, m1         ; { s0 s1 s2 s3 | s0 s1 s2 s3 }
    vextracti128  xm1, m0, 1
    paddd         xm0, xm1
    mova         [r0], xm0
    RET
%endif
%endmacro

SAD_X3_W8_AVX2 16
SAD_X3_W8_AVX2 8
SAD_X3_W8_AVX2 4
SAD_X4_W8_AVX2 16
SAD_X4_W8_AVX2 8
SAD_X4_W8_AVX2 4
%if ARCH_X86_64
SAD_X3_W8_AVX2 16, 1
SAD_X3_W8_AVX2 8, 1
SAD_X4_W8_AVX2 16, 1
SAD_X4_W8_AVX2 8, 1
%endif

;-----------------------------------------------------------------------------
; int pixel_sad_sq_min_16x16( uint8_t *fenc, uint8_t *pix, intptr_t i_stride,
;                             const int32_t bias[12], int best )
; the 12 candidates pix + dx + dy*i_stride, dx -1..2, bias[] by dy -1, 1, 0:
; min( best, (sad_i << 6) + bias_i ), signed
;
; vdbpsadbw of fenc dword g, duplicated in its qword, against ref dwords 0 1 | 1 2
; from x-1+4g: word k is that dword's sad at dx k-1. 16 wide: lane l holds g 2l
; and 2l+1, ref from x-1+8l, and each ref row serves dy -1, 0 and 1. 8 wide: the
; lanes are a row pair, g 0 and 1. The word sums reach at most 16*16*255.
;-----------------------------------------------------------------------------
%if ARCH_X86_64
INIT_YMM avx512

; m0/m1/m2: dy -1/0/1, words by lane, g, dx -> eax
%macro SAD_SQ_MIN_END 0
    vshufi64x2     m3, m0, m2, 0x3
    vinserti128    m0, m0, xm2, 1
    paddw          m0, m3         ; dy -1 g 0+2, 1+3 | dy 1 g 0+2, 1+3
    vpermq         m0, m0, q3120
    vextracti128  xm3, m1, 1
    paddw         xm1, xm3        ; dy 0 g 0+2, 1+3
    vextracti128  xm2, m0, 1
    paddw         xm0, xm2        ; dy -1, dy 1
    punpckhqdq    xm3, xm1, xm1
    paddw         xm1, xm3        ; dy 0
    pmovzxwd       m0, xm0
    pmovzxwd      xm1, xm1
    pslld          m0, 6
    pslld         xm1, 6
    paddd          m0, [r3]
    paddd         xm1, [r3+32]
    vextracti128  xm2, m0, 1
    pminsd        xm0, xm1
    pminsd        xm0, xm2
    pshufd        xm1, xm0, q1032
    pminsd        xm0, xm1
    pshufd        xm1, xm0, q2301
    pminsd        xm0, xm1
    movd          eax, xm0
    cmp           eax, r4d
    cmovg         eax, r4d
    RET
%endmacro

%macro SAD_SQ_ACC 4 ; acc, fenc, ref, first
%if %4
    vdbpsadbw     m%1, m%2, m%3, 0x94
%else
    vdbpsadbw      m8, m%2, m%3, 0x94
    paddw         m%1, m8
%endif
%endmacro

cglobal pixel_sad_sq_min_16x16, 5,5,9
    sub            r1, r2
    dec            r1
    mova           m3, [sad_sq_idx16]
%assign sq_j -1
%rep 18
    %assign sq_y sq_j+1
    %assign sq_f 4+(sq_y % 3)
    %if sq_y < 15
        vpermd     m%[sq_f], m3, [r0+sq_y*FENC_STRIDE]
    %elif sq_y == 15
        vbroadcasti128 m%[sq_f], [r0+15*FENC_STRIDE]
        vpermd     m%[sq_f], m3, m%[sq_f]
    %endif
    movu          xm7, [r1]
    vinserti128    m7, m7, [r1+8], 1
    %if sq_j < 16
        add        r1, r2
    %endif
    %if sq_j < 15
        SAD_SQ_ACC 0, %[sq_f], 7, sq_j == -1
    %endif
    %if sq_j >= 0 && sq_j < 16
        %assign sq_f 4+(sq_j % 3)
        SAD_SQ_ACC 1, %[sq_f], 7, sq_j == 0
    %endif
    %if sq_j >= 1
        %assign sq_f 4+((sq_j-1) % 3)
        SAD_SQ_ACC 2, %[sq_f], 7, sq_j == 1
    %endif
    %assign sq_j sq_j+1
%endrep
    SAD_SQ_MIN_END

cglobal pixel_sad_sq_min_8x8, 5,5,10
    sub            r1, r2
    dec            r1
    mova           m3, [sad_sq_idx8]
    vpermd         m4, m3, [r0+0*FENC_STRIDE]
    vpermd         m5, m3, [r0+2*FENC_STRIDE]
    vpermd         m6, m3, [r0+4*FENC_STRIDE]
    vpermd         m7, m3, [r0+6*FENC_STRIDE]
%assign sq_j -1
%rep 9
    movu          xm9, [r1]
    vinserti128    m9, m9, [r1+r2], 1
    %if sq_j < 7
        add        r1, r2
    %endif
    %if sq_j & 1
        %if sq_j < 7
            %assign sq_f 4+(sq_j+1)/2
            SAD_SQ_ACC 0, %[sq_f], 9, sq_j == -1
        %endif
        %if sq_j > 0
            %assign sq_f 4+(sq_j-1)/2
            SAD_SQ_ACC 2, %[sq_f], 9, sq_j == 1
        %endif
    %else
        %assign sq_f 4+sq_j/2
        SAD_SQ_ACC 1, %[sq_f], 9, sq_j == 0
    %endif
    %assign sq_j sq_j+1
%endrep
    SAD_SQ_MIN_END
%undef sq_j
%undef sq_y
%undef sq_f

;-----------------------------------------------------------------------------
; min( best, (sad_i << s) + bias_i ) over a few candidates around pix
;
; A window is vdbpsadbw of the fenc dwords, each duplicated in its qword, against
; the ref row at pix + dy*i_stride + bx: words 0-3 of the qword are the dword's
; sads at dx bx..bx+3. Its zero-mask keeps the candidates' words, so the windows
; of a group add up to the candidates of the group by word, summed over the
; qwords at the end. 16 wide: a row per ymm, lane l fenc dwords 2l, 2l+1, ref
; from x+bx+8l; 8 wide: a row pair, a row per lane; 4 wide: a row pair, a row
; per qword (xmm). The word sums reach at most 16*16*255.
;-----------------------------------------------------------------------------
; window w: ref dbp_p<w> (+dbp_o: row r, +dbp_o1: row r+1), mask k<w+1>, sum m<w>
; m4: fenc, m5: ref, m6: sad, m7: fenc dword permutation
%macro DBP_SAD 4 ; width, sum, mask, first
%if %1 == 4
    %if %4
    vdbpsadbw     xm%2 {k%3}{z}, xm4, xm5, 0xe4
    %else
    vdbpsadbw     xm6 {k%3}{z}, xm4, xm5, 0xe4
    paddw         xm%2, xm6
    %endif
%else
    %if %4
    vdbpsadbw      m%2 {k%3}{z}, m4, m5, 0x94
    %else
    vdbpsadbw      m6 {k%3}{z}, m4, m5, 0x94
    paddw          m%2, m6
    %endif
%endif
%endmacro

%macro DBP_ROWS 3 ; width, height, windows
%if %1 == 16
    %assign %%step 1
%else
    %assign %%step 2
%endif
%assign %%r 0
%rep %2 / %%step
    %if %1 == 16 && %%r == %2-1
    vbroadcasti128  m4, [r0+%%r*FENC_STRIDE]
    vpermd          m4, m7, m4
    %else
    vpermd          m4, m7, [r0+%%r*FENC_STRIDE]
    %endif
    %assign %%w 0
    %rep %3
        %assign %%k %%w+1
        %if %1 == 16
    movu           xm5, [dbp_p%[%%w]+dbp_o]
    vinserti128     m5, m5, [dbp_p%[%%w]+dbp_o+8], 1
        %elif %1 == 8
    movu           xm5, [dbp_p%[%%w]+dbp_o]
    vinserti128     m5, m5, [dbp_p%[%%w]+dbp_o1], 1
        %else
    movq           xm5, [dbp_p%[%%w]+dbp_o]
    movhps         xm5, [dbp_p%[%%w]+dbp_o1]
        %endif
    DBP_SAD %1, %[%%w], %[%%k], %%r == 0
        %assign %%w %%w+1
    %endrep
    %assign %%r %%r+%%step
    %if %%r < %2
        %if %%step == 1
    add          dbp_o, r2
        %else
    lea          dbp_o, [dbp_o+r2*2]
    lea         dbp_o1, [dbp_o1+r2*2]
        %endif
    %endif
%endrep
%endmacro

%macro DBP_INIT 1 ; width: fenc permutation, row offsets
%if %1 == 16
    mova            m7, [sad_sq_idx16]
%elif %1 == 8
    mova            m7, [sad_sq_idx8]
%else
    mova            m7, [dbp_idx4]
%endif
    xor          dbp_o, dbp_o
%if %1 < 16
    mov         dbp_o1, r2
%endif
%endmacro

; m0 -> xm0: words 0-3 summed over the qwords
%macro DBP_FOLD1 1 ; width
%if %1 > 4
    vextracti128   xm1, m0, 1
    paddw          xm0, xm1
%endif
    punpckhqdq     xm1, xm0, xm0
    paddw          xm0, xm1
%endmacro

; m0, m2 -> xm0: words 0-3 of m0, 4-7 of m2, summed over the qwords
%macro DBP_FOLD2 1 ; width
%if %1 > 4
    punpcklqdq      m1, m0, m2
    punpckhqdq      m0, m0, m2
    paddw           m0, m1
    vextracti128   xm1, m0, 1
    paddw          xm0, xm1
%else
    punpcklqdq     xm1, xm0, xm2
    punpckhqdq     xm0, xm0, xm2
    paddw          xm0, xm1
%endif
%endmacro

; min of the dwords of xm0 -> eax
%macro DBP_MIN4 0
    pshufd         xm1, xm0, q1032
    pminsd         xm0, xm1
    pshufd         xm1, xm0, q2301
    pminsd         xm0, xm1
    movd           eax, xm0
%endmacro

;-----------------------------------------------------------------------------
; int pixel_sad_dia_min_WxH( uint8_t *fenc, uint8_t *pix, intptr_t i_stride,
;                            const int32_t bias[4], int best )
; candidates (0,-1) (0,1) (-1,0) (1,0), s = 4. Windows: dy 0 bx -2 words 1, 3;
; dy -1 bx 0 word 0; dy 1 bx -2 word 2: (0,-1) (-1,0) (0,1) (1,0) by word
;-----------------------------------------------------------------------------
%macro SAD_DIA_MIN 2 ; width, height
cglobal pixel_sad_dia_min_%1x%2, 5,10,10
    %define dbp_o  r5
    %define dbp_o1 r6
    %define dbp_p0 r7
    %define dbp_p1 r8
    %define dbp_p2 r9
    mov            r5d, 0xaaaa
    kmovw           k1, r5d
    mov            r5d, 0x1111
    kmovw           k2, r5d
    mov            r5d, 0x4444
    kmovw           k3, r5d
    lea         dbp_p0, [r1-2]
    mov         dbp_p1, r1
    sub         dbp_p1, r2
    lea         dbp_p2, [r1+r2-2]
    DBP_INIT %1
    movu           xm8, [r3]
    pshufd         xm8, xm8, q3120
    vpbroadcastd   xm9, r4d
    DBP_ROWS %1, %2, 3
%if %1 == 4
    paddw          xm0, xm1
    paddw          xm0, xm2
%else
    paddw           m0, m1
    paddw           m0, m2
%endif
    DBP_FOLD1 %1
    pmovzxwd       xm0, xm0
    pslld          xm0, 4
    paddd          xm0, xm8
    pminsd         xm0, xm9
    DBP_MIN4
    RET
%endmacro

SAD_DIA_MIN 16, 16
SAD_DIA_MIN 16, 8
SAD_DIA_MIN 8, 16
SAD_DIA_MIN 8, 8
SAD_DIA_MIN 8, 4
SAD_DIA_MIN 4, 8
SAD_DIA_MIN 4, 4

INIT_YMM avx2
%endif ; ARCH_X86_64

%macro SAD_X_W4_AVX512 2 ; x, h
cglobal pixel_sad_x%1_4x%2, %1+2,%1+3
    mov           t1d, 0xa
    kmovb          k1, t1d
    lea            t1, [3*t0]
    kaddb          k2, k1, k1
    kshiftlb       k3, k1, 2
%assign %%i 0
%rep %2/4
    movu           m6,      [r0+%%i*64]
    vmovddup       m6 {k1}, [r0+%%i*64+32]
    movd         xmm2,      [r1]
    movd         xmm4,      [r1+t0]
    vpbroadcastd xmm2 {k1}, [r1+2*t0]
    vpbroadcastd xmm4 {k1}, [r1+t1]
    vpbroadcastd xmm2 {k2}, [r2+t0]
    vpbroadcastd xmm4 {k2}, [r2]
    vpbroadcastd xmm2 {k3}, [r2+t1]   ; a0 a2 b1 b3
    vpbroadcastd xmm4 {k3}, [r2+2*t0] ; a1 a3 b0 b2
    vpmovqd        s1, m6             ; s0 s2 s1 s3
    movd         xmm3,      [r3]
    movd         xmm5,      [r3+t0]
    vpbroadcastd xmm3 {k1}, [r3+2*t0]
    vpbroadcastd xmm5 {k1}, [r3+t1]
%if %1 == 4
    vpbroadcastd xmm3 {k2}, [r4+t0]
    vpbroadcastd xmm5 {k2}, [r4]
    vpbroadcastd xmm3 {k3}, [r4+t1]   ; c0 c2 d1 d3
    vpbroadcastd xmm5 {k3}, [r4+2*t0] ; c1 c3 d0 d2
%endif
%if %%i != %2/4-1
%assign %%j 1
%rep %1
    lea        r%+%%j, [r%+%%j+4*t0]
    %assign %%j %%j+1
%endrep
%endif
    pshufd         s2, s1, q1032
    psadbw       xmm2, s1
    psadbw       xmm4, s2
    psadbw       xmm3, s1
    psadbw       xmm5, s2
%if %%i
    paddd        xmm0, xmm2
    paddd        xmm1, xmm3
    paddd        xmm0, xmm4
    paddd        xmm1, xmm5
%else
    paddd        xmm0, xmm2, xmm4
    paddd        xmm1, xmm3, xmm5
%endif
    %assign %%i %%i+1
%endrep
%if %1 == 4
    movifnidn      t2, r6mp
%else
    movifnidn      t2, r5mp
%endif
    packusdw     xmm0, xmm1
    mova         [t2], xmm0
    RET
%endmacro

%macro SAD_X_W8_AVX512 2 ; x, h
cglobal pixel_sad_x%1_8x%2, %1+2,%1+3
    kxnorb        k3, k3, k3
    lea           t1, [3*t0]
    kaddb         k1, k3, k3
    kshiftlb      k2, k3, 2
    kshiftlb      k3, k3, 3
%assign %%i 0
%rep %2/4
    movddup       m6, [r0+%%i*64]    ; s0 s0 s1 s1
    movq         xm2,      [r1]
    movq         xm4,      [r1+2*t0]
    vpbroadcastq xm2 {k1}, [r2]
    vpbroadcastq xm4 {k1}, [r2+2*t0]
    vpbroadcastq  m2 {k2}, [r1+t0]
    vpbroadcastq  m4 {k2}, [r1+t1]
    vpbroadcastq  m2 {k3}, [r2+t0]   ; a0 b0 a1 b1
    vpbroadcastq  m4 {k3}, [r2+t1]   ; a2 b2 a3 b3
    movddup       m7, [r0+%%i*64+32] ; s2 s2 s3 s3
    movq         xm3,      [r3]
    movq         xm5,      [r3+2*t0]
%if %1 == 4
    vpbroadcastq xm3 {k1}, [r4]
    vpbroadcastq xm5 {k1}, [r4+2*t0]
%endif
    vpbroadcastq  m3 {k2}, [r3+t0]
    vpbroadcastq  m5 {k2}, [r3+t1]
%if %1 == 4
    vpbroadcastq  m3 {k3}, [r4+t0]   ; c0 d0 c1 d1
    vpbroadcastq  m5 {k3}, [r4+t1]   ; c2 d2 c3 d3
%endif
%if %%i != %2/4-1
%assign %%j 1
%rep %1
    lea       r%+%%j, [r%+%%j+4*t0]
    %assign %%j %%j+1
%endrep
%endif
    psadbw        m2, m6
    psadbw        m4, m7
    psadbw        m3, m6
    psadbw        m5, m7
    ACCUM      paddd, 0, 2, %%i
    ACCUM      paddd, 1, 3, %%i
    paddd         m0, m4
    paddd         m1, m5
    %assign %%i %%i+1
%endrep
%if %1 == 4
    movifnidn     t2, r6mp
%else
    movifnidn     t2, r5mp
%endif
    packusdw      m0, m1
    vextracti128 xm1, m0, 1
    paddd        xm0, xm1
    mova        [t2], xm0
    RET
%endmacro

%macro SAD_X_W16_AVX512 2 ; x, h
cglobal pixel_sad_x%1_16x%2, %1+2,%1+3
    lea           t1, [3*t0]
%assign %%i 0
%rep %2/4
    mova          m6, [r0+%%i*64]  ; s0 s1 s2 s3
    movu         xm2, [r3]
    movu         xm4, [r3+t0]
%if %1 == 4
    vinserti128  ym2, [r4+t0],   1
    vinserti128  ym4, [r4],      1
%endif
    vinserti32x4  m2, [r1+2*t0], 2
    vinserti32x4  m4, [r1+t1],   2
    vinserti32x4  m2, [r2+t1],   3 ; c0 d1 a2 b3
    vinserti32x4  m4, [r2+2*t0], 3 ; c1 d0 a3 b2
    vpermq        m7, m6, q1032    ; s1 s0 s3 s2
    movu         xm3, [r1]
    movu         xm5, [r1+t0]
    vinserti128  ym3, [r2+t0],   1
    vinserti128  ym5, [r2],      1
    vinserti32x4  m3, [r3+2*t0], 2
    vinserti32x4  m5, [r3+t1],   2
%if %1 == 4
    vinserti32x4  m3, [r4+t1],   3 ; a0 b1 c2 d3
    vinserti32x4  m5, [r4+2*t0], 3 ; a1 b0 c3 d2
%endif
%if %%i != %2/4-1
%assign %%j 1
%rep %1
    lea       r%+%%j, [r%+%%j+4*t0]
    %assign %%j %%j+1
%endrep
%endif
    psadbw        m2, m6
    psadbw        m4, m7
    psadbw        m3, m6
    psadbw        m5, m7
    ACCUM      paddd, 0, 2, %%i
    ACCUM      paddd, 1, 3, %%i
    paddd         m0, m4
    paddd         m1, m5
    %assign %%i %%i+1
%endrep
%if %1 == 4
    movifnidn     t2, r6mp
%else
    movifnidn     t2, r5mp
%endif
    mov          t1d, 0x1111
    kmovw         k1, t1d
    vshufi32x4    m0, m0, q1032
    paddd         m0, m1
    punpckhqdq    m1, m0, m0
    paddd         m0, m1
    vpcompressd   m0 {k1}{z}, m0
    mova        [t2], xm0
    RET
%endmacro

; t0 = stride, t1 = tmp/stride3, t2 = scores
%if WIN64
    %define s1 xmm16 ; xmm6 and xmm7 reduces code size, but
    %define s2 xmm17 ; they're callee-saved on win64
    DECLARE_REG_TMP 4, 6, 0
%else
    %define s1 xmm6
    %define s2 xmm7
%if ARCH_X86_64
    DECLARE_REG_TMP 4, 6, 5 ; scores is passed in a register on unix64
%else
    DECLARE_REG_TMP 4, 5, 0
%endif
%endif

INIT_YMM avx512
SAD_X_W4_AVX512  3, 4  ; x3_4x4
SAD_X_W4_AVX512  3, 8  ; x3_4x8
SAD_X_W8_AVX512  3, 4  ; x3_8x4
SAD_X_W8_AVX512  3, 8  ; x3_8x8
SAD_X_W8_AVX512  3, 16 ; x3_8x16
INIT_ZMM avx512
SAD_X_W16_AVX512 3, 8  ; x3_16x8
SAD_X_W16_AVX512 3, 16 ; x3_16x16

DECLARE_REG_TMP 5, 6, 0
INIT_YMM avx512
SAD_X_W4_AVX512  4, 4  ; x4_4x4
SAD_X_W4_AVX512  4, 8  ; x4_4x8
SAD_X_W8_AVX512  4, 4  ; x4_8x4
SAD_X_W8_AVX512  4, 8  ; x4_8x8
SAD_X_W8_AVX512  4, 16 ; x4_8x16
INIT_ZMM avx512
SAD_X_W16_AVX512 4, 8  ; x4_16x8
SAD_X_W16_AVX512 4, 16 ; x4_16x16

;=============================================================================
; SAD cacheline split
;=============================================================================

; Core2 (Conroe) can load unaligned data just as quickly as aligned data...
; unless the unaligned data spans the border between 2 cachelines, in which
; case it's really slow. The exact numbers may differ, but all Intel cpus prior
; to Nehalem have a large penalty for cacheline splits.
; (8-byte alignment exactly half way between two cachelines is ok though.)
; LDDQU was supposed to fix this, but it only works on Pentium 4.
; So in the split case we load aligned data and explicitly perform the
; alignment between registers. Like on archs that have only aligned loads,
; except complicated by the fact that PALIGNR takes only an immediate, not
; a variable alignment.
; It is also possible to hoist the realignment to the macroblock level (keep
; 2 copies of the reference frame, offset by 32 bytes), but the extra memory
; needed for that method makes it often slower.

; sad 16x16 costs on Core2:
; good offsets: 49 cycles (50/64 of all mvs)
; cacheline split: 234 cycles (14/64 of all mvs. ammortized: +40 cycles)
; page split: 3600 cycles (14/4096 of all mvs. ammortized: +11.5 cycles)
; cache or page split with palignr: 57 cycles (ammortized: +2 cycles)

; computed jump assumes this loop is exactly 80 bytes
%macro SAD16_CACHELINE_LOOP_SSE2 1 ; alignment
ALIGN 16
sad_w16_align%1_sse2:
    movdqa  xmm1, [r2+16]
    movdqa  xmm2, [r2+r3+16]
    movdqa  xmm3, [r2]
    movdqa  xmm4, [r2+r3]
    pslldq  xmm1, 16-%1
    pslldq  xmm2, 16-%1
    psrldq  xmm3, %1
    psrldq  xmm4, %1
    por     xmm1, xmm3
    por     xmm2, xmm4
    psadbw  xmm1, [r0]
    psadbw  xmm2, [r0+r1]
    paddw   xmm0, xmm1
    paddw   xmm0, xmm2
    lea     r0,   [r0+2*r1]
    lea     r2,   [r2+2*r3]
    dec     r4
    jg sad_w16_align%1_sse2
    ret
%endmacro

; computed jump assumes this loop is exactly 64 bytes
%macro SAD16_CACHELINE_LOOP_SSSE3 1 ; alignment
ALIGN 16
sad_w16_align%1_ssse3:
    movdqa  xmm1, [r2+16]
    movdqa  xmm2, [r2+r3+16]
    palignr xmm1, [r2], %1
    palignr xmm2, [r2+r3], %1
    psadbw  xmm1, [r0]
    psadbw  xmm2, [r0+r1]
    paddw   xmm0, xmm1
    paddw   xmm0, xmm2
    lea     r0,   [r0+2*r1]
    lea     r2,   [r2+2*r3]
    dec     r4
    jg sad_w16_align%1_ssse3
    ret
%endmacro

%macro SAD16_CACHELINE_FUNC 2 ; cpu, height
cglobal pixel_sad_16x%2_cache64_%1
    mov     eax, r2m
    and     eax, 0x37
    cmp     eax, 0x30
    jle pixel_sad_16x%2_sse2
    PROLOGUE 4,6
    mov     r4d, r2d
    and     r4d, 15
%ifidn %1, ssse3
    shl     r4d, 6  ; code size = 64
%else
    lea     r4, [r4*5]
    shl     r4d, 4  ; code size = 80
%endif
%define sad_w16_addr (sad_w16_align1_%1 + (sad_w16_align1_%1 - sad_w16_align2_%1))
%ifdef PIC
    lea     r5, [sad_w16_addr]
    add     r5, r4
%else
    lea     r5, [sad_w16_addr + r4]
%endif
    and     r2, ~15
    mov     r4d, %2/2
    pxor    xmm0, xmm0
    call    r5
    movhlps xmm1, xmm0
    paddw   xmm0, xmm1
    movd    eax,  xmm0
    RET
%endmacro

%macro SAD_CACHELINE_START_MMX2 4 ; width, height, iterations, cacheline
    mov    eax, r2m
    and    eax, 0x17|%1|(%4>>1)
    cmp    eax, 0x10|%1|(%4>>1)
    jle pixel_sad_%1x%2_mmx2
    and    eax, 7
    shl    eax, 3
    movd   mm6, [sw_64]
    movd   mm7, eax
    psubw  mm6, mm7
    PROLOGUE 4,5
    and    r2, ~7
    mov    r4d, %3
    pxor   mm0, mm0
%endmacro

%macro SAD16_CACHELINE_FUNC_MMX2 2 ; height, cacheline
cglobal pixel_sad_16x%1_cache%2_mmx2
    SAD_CACHELINE_START_MMX2 16, %1, %1, %2
.loop:
    movq   mm1, [r2]
    movq   mm2, [r2+8]
    movq   mm3, [r2+16]
    movq   mm4, mm2
    psrlq  mm1, mm7
    psllq  mm2, mm6
    psllq  mm3, mm6
    psrlq  mm4, mm7
    por    mm1, mm2
    por    mm3, mm4
    psadbw mm1, [r0]
    psadbw mm3, [r0+8]
    paddw  mm0, mm1
    paddw  mm0, mm3
    add    r2, r3
    add    r0, r1
    dec    r4
    jg .loop
    movd   eax, mm0
    RET
%endmacro

%macro SAD8_CACHELINE_FUNC_MMX2 2 ; height, cacheline
cglobal pixel_sad_8x%1_cache%2_mmx2
    SAD_CACHELINE_START_MMX2 8, %1, %1/2, %2
.loop:
    movq   mm1, [r2+8]
    movq   mm2, [r2+r3+8]
    movq   mm3, [r2]
    movq   mm4, [r2+r3]
    psllq  mm1, mm6
    psllq  mm2, mm6
    psrlq  mm3, mm7
    psrlq  mm4, mm7
    por    mm1, mm3
    por    mm2, mm4
    psadbw mm1, [r0]
    psadbw mm2, [r0+r1]
    paddw  mm0, mm1
    paddw  mm0, mm2
    lea    r2, [r2+2*r3]
    lea    r0, [r0+2*r1]
    dec    r4
    jg .loop
    movd   eax, mm0
    RET
%endmacro

; sad_x3/x4_cache64: check each mv.
; if they're all within a cacheline, use normal sad_x3/x4.
; otherwise, send them individually to sad_cache64.
%macro CHECK_SPLIT 3 ; pix, width, cacheline
    mov  eax, %1
    and  eax, 0x17|%2|(%3>>1)
    cmp  eax, 0x10|%2|(%3>>1)
    jg .split
%endmacro

%macro SADX3_CACHELINE_FUNC 6 ; width, height, cacheline, normal_ver, split_ver, name
cglobal pixel_sad_x3_%1x%2_cache%3_%6
    CHECK_SPLIT r1m, %1, %3
    CHECK_SPLIT r2m, %1, %3
    CHECK_SPLIT r3m, %1, %3
    jmp pixel_sad_x3_%1x%2_%4
.split:
%if ARCH_X86_64
    PROLOGUE 6,9
    push r3
    push r2
%if WIN64
    movsxd r4, r4d
    sub rsp, 40 ; shadow space and alignment
%endif
    mov  r2, r1
    mov  r1, FENC_STRIDE
    mov  r3, r4
    mov  r7, r0
    mov  r8, r5
    call pixel_sad_%1x%2_cache%3_%5
    mov  [r8], eax
%if WIN64
    mov  r2, [rsp+40+0*8]
%else
    pop  r2
%endif
    mov  r0, r7
    call pixel_sad_%1x%2_cache%3_%5
    mov  [r8+4], eax
%if WIN64
    mov  r2, [rsp+40+1*8]
%else
    pop  r2
%endif
    mov  r0, r7
    call pixel_sad_%1x%2_cache%3_%5
    mov  [r8+8], eax
%if WIN64
    add  rsp, 40+2*8
%endif
    RET
%else
    push edi
    mov  edi, [esp+28]
    push dword [esp+24]
    push dword [esp+16]
    push dword 16
    push dword [esp+20]
    call pixel_sad_%1x%2_cache%3_%5
    mov  ecx, [esp+32]
    mov  [edi], eax
    mov  [esp+8], ecx
    call pixel_sad_%1x%2_cache%3_%5
    mov  ecx, [esp+36]
    mov  [edi+4], eax
    mov  [esp+8], ecx
    call pixel_sad_%1x%2_cache%3_%5
    mov  [edi+8], eax
    add  esp, 16
    pop  edi
    ret
%endif
%endmacro

%macro SADX4_CACHELINE_FUNC 6 ; width, height, cacheline, normal_ver, split_ver, name
cglobal pixel_sad_x4_%1x%2_cache%3_%6
    CHECK_SPLIT r1m, %1, %3
    CHECK_SPLIT r2m, %1, %3
    CHECK_SPLIT r3m, %1, %3
    CHECK_SPLIT r4m, %1, %3
    jmp pixel_sad_x4_%1x%2_%4
.split:
%if ARCH_X86_64
    PROLOGUE 6,9
    mov  r8,  r6mp
    push r4
    push r3
    push r2
%if WIN64
    sub rsp, 32 ; shadow space
%endif
    mov  r2, r1
    mov  r1, FENC_STRIDE
    mov  r3, r5
    mov  r7, r0
    call pixel_sad_%1x%2_cache%3_%5
    mov  [r8], eax
%if WIN64
    mov  r2, [rsp+32+0*8]
%else
    pop  r2
%endif
    mov  r0, r7
    call pixel_sad_%1x%2_cache%3_%5
    mov  [r8+4], eax
%if WIN64
    mov  r2, [rsp+32+1*8]
%else
    pop  r2
%endif
    mov  r0, r7
    call pixel_sad_%1x%2_cache%3_%5
    mov  [r8+8], eax
%if WIN64
    mov  r2, [rsp+32+2*8]
%else
    pop  r2
%endif
    mov  r0, r7
    call pixel_sad_%1x%2_cache%3_%5
    mov  [r8+12], eax
%if WIN64
    add  rsp, 32+3*8
%endif
    RET
%else
    push edi
    mov  edi, [esp+32]
    push dword [esp+28]
    push dword [esp+16]
    push dword 16
    push dword [esp+20]
    call pixel_sad_%1x%2_cache%3_%5
    mov  ecx, [esp+32]
    mov  [edi], eax
    mov  [esp+8], ecx
    call pixel_sad_%1x%2_cache%3_%5
    mov  ecx, [esp+36]
    mov  [edi+4], eax
    mov  [esp+8], ecx
    call pixel_sad_%1x%2_cache%3_%5
    mov  ecx, [esp+40]
    mov  [edi+8], eax
    mov  [esp+8], ecx
    call pixel_sad_%1x%2_cache%3_%5
    mov  [edi+12], eax
    add  esp, 16
    pop  edi
    ret
%endif
%endmacro

%macro SADX34_CACHELINE_FUNC 1+
    SADX3_CACHELINE_FUNC %1
    SADX4_CACHELINE_FUNC %1
%endmacro


; instantiate the aligned sads

INIT_MMX
%if ARCH_X86_64 == 0
SAD16_CACHELINE_FUNC_MMX2  8, 32
SAD16_CACHELINE_FUNC_MMX2 16, 32
SAD8_CACHELINE_FUNC_MMX2   4, 32
SAD8_CACHELINE_FUNC_MMX2   8, 32
SAD8_CACHELINE_FUNC_MMX2  16, 32
SAD16_CACHELINE_FUNC_MMX2  8, 64
SAD16_CACHELINE_FUNC_MMX2 16, 64
%endif ; !ARCH_X86_64
SAD8_CACHELINE_FUNC_MMX2   4, 64
SAD8_CACHELINE_FUNC_MMX2   8, 64
SAD8_CACHELINE_FUNC_MMX2  16, 64

%if ARCH_X86_64 == 0
SADX34_CACHELINE_FUNC 16, 16, 32, mmx2, mmx2, mmx2
SADX34_CACHELINE_FUNC 16,  8, 32, mmx2, mmx2, mmx2
SADX34_CACHELINE_FUNC  8, 16, 32, mmx2, mmx2, mmx2
SADX34_CACHELINE_FUNC  8,  8, 32, mmx2, mmx2, mmx2
SADX34_CACHELINE_FUNC 16, 16, 64, mmx2, mmx2, mmx2
SADX34_CACHELINE_FUNC 16,  8, 64, mmx2, mmx2, mmx2
%endif ; !ARCH_X86_64
SADX34_CACHELINE_FUNC  8, 16, 64, mmx2, mmx2, mmx2
SADX34_CACHELINE_FUNC  8,  8, 64, mmx2, mmx2, mmx2

%if ARCH_X86_64 == 0
SAD16_CACHELINE_FUNC sse2, 8
SAD16_CACHELINE_FUNC sse2, 16
%assign i 1
%rep 15
SAD16_CACHELINE_LOOP_SSE2 i
%assign i i+1
%endrep
SADX34_CACHELINE_FUNC 16, 16, 64, sse2, sse2, sse2
SADX34_CACHELINE_FUNC 16,  8, 64, sse2, sse2, sse2
%endif ; !ARCH_X86_64
SADX34_CACHELINE_FUNC  8, 16, 64, sse2, mmx2, sse2

SAD16_CACHELINE_FUNC ssse3, 8
SAD16_CACHELINE_FUNC ssse3, 16
%assign i 1
%rep 15
SAD16_CACHELINE_LOOP_SSSE3 i
%assign i i+1
%endrep
SADX34_CACHELINE_FUNC 16, 16, 64, sse2, ssse3, ssse3
SADX34_CACHELINE_FUNC 16,  8, 64, sse2, ssse3, ssse3

