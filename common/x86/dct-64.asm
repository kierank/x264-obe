;*****************************************************************************
;* dct-64.asm: x86_64 transform and zigzag
;*****************************************************************************
;* Copyright (C) 2003-2014 x264 project
;*
;* Authors: Loren Merritt <lorenm@u.washington.edu>
;*          Holger Lubitz <holger@lubitz.org>
;*          Laurent Aimar <fenrir@via.ecp.fr>
;*          Min Chen <chenm001.163.com>
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
; add16x16_idct8 avx512icl: packed qwords to 16-pixel rows
idct8_zmm_pack: db 0,2,4,6,1,3,5,7
; sub16x16_dct8 avx512icl: 128-bit lanes of a row pair, blocks 0 1, then 2 3
dct8_zmm_pairs: db 0,1,8,9,2,3,10,11, 4,5,12,13,6,7,14,15
%if HIGH_BIT_DEPTH == 0
ALIGN 32
; inter_resid_8x8 field zigzag: pshufb masks of A A' B B' | A' B B' C C' | B' C C' D D' | C' D D',
; A-D = coefs 0-15 .. 48-63, ' = lanes swapped
ir_scan8field_avx2:
           db 0,1,2,3,4,5,-1,-1,-1,-1,6,7,8,9,-1,-1,-1,-1,6,7,-1,-1,-1,-1,-1,-1,8,9,-1,-1,-1,-1
           db -1,-1,-1,-1,-1,-1,0,1,2,3,-1,-1,-1,-1,4,5,-1,-1,-1,-1,10,11,12,13,14,15,-1,-1,-1,-1,-1,-1
           db -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,0,1
           db -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,0,1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,2,3,-1,-1
           db -1,-1,10,11,12,13,14,15,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1
           db 4,5,-1,-1,-1,-1,-1,-1,6,7,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,6,7,-1,-1,-1,-1,-1,-1
           db -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,2,3,-1,-1,4,5,8,9,10,11,12,13,14,15,-1,-1,-1,-1,-1,-1,-1,-1
           db -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,0,1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,0,1,-1,-1
           db -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,2,3,-1,-1,4,5
           db 8,9,10,11,12,13,14,15,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1
           db -1,-1,-1,-1,-1,-1,-1,-1,6,7,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,6,7,-1,-1,-1,-1,8,9
           db -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,2,3,-1,-1,4,5,8,9,10,11,12,13,14,15,-1,-1,-1,-1,-1,-1,-1,-1
           db -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,0,1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1
           db -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,2,3,4,5,-1,-1
           db 10,11,12,13,14,15,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1
           db -1,-1,-1,-1,-1,-1,6,7,-1,-1,-1,-1,8,9,10,11,-1,-1,-1,-1,4,5,6,7,8,9,10,11,12,13,14,15
           db -1,-1,-1,-1,-1,-1,-1,-1,0,1,2,3,-1,-1,-1,-1,12,13,14,15,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1
%else
ALIGN 32
; inter_resid_8x8: vpermd indices of the zigzag, the rows of each output octet in turn
ir8_scan_frame_hbd:
    dd 0,0,1,2,0,0,0,0
    dd 0,0,0,0,1,0,0,0
    dd 0,0,0,0,0,0,0,1
    dd 2,0,0,3,0,0,0,0
    dd 0,3,4,0,0,0,0,0
    dd 0,0,0,0,2,0,0,0
    dd 0,0,0,0,0,1,0,0
    dd 1,0,0,0,0,0,0,0
    dd 0,2,0,0,0,0,0,0
    dd 0,0,3,0,0,0,0,4
    dd 0,0,0,4,0,0,5,0
    dd 0,0,0,0,5,6,0,0
    dd 3,0,0,0,0,0,0,0
    dd 0,2,0,0,0,0,0,3
    dd 0,0,1,0,0,0,2,0
    dd 0,0,0,0,0,1,0,0
    dd 4,0,0,0,0,0,5,0
    dd 0,5,0,0,0,6,0,0
    dd 0,0,6,0,7,0,0,0
    dd 0,0,0,7,0,0,0,0
    dd 0,0,0,0,0,0,0,4
    dd 3,0,0,0,0,4,0,0
    dd 0,2,0,0,3,0,0,0
    dd 0,0,1,2,0,0,0,0
    dd 0,0,0,0,0,0,5,0
    dd 0,0,0,0,0,0,0,6
    dd 7,0,0,0,0,0,0,0
    dd 0,7,0,0,0,0,0,0
    dd 0,0,6,0,0,0,0,0
    dd 0,0,0,5,0,0,0,0
    dd 0,0,0,0,4,0,0,5
    dd 0,0,0,0,0,3,4,0
    dd 6,0,7,0,0,0,0,0
    dd 0,7,0,0,0,0,0,0
    dd 0,0,0,6,0,0,7,0
    dd 0,0,0,0,5,6,0,7
ir8_scan_field_hbd:
    dd 0,1,2,0,0,3,4,0
    dd 0,0,0,0,1,0,0,2
    dd 0,0,0,0,0,0,1,0
    dd 0,3,0,0,0,4,0,0
    dd 0,0,5,6,7,0,0,0
    dd 2,0,0,0,3,0,0,0
    dd 0,5,6,7,0,0,0,0
    dd 0,0,0,0,0,1,0,2
    dd 4,5,6,7,0,0,0,0
    dd 0,0,0,0,3,0,0,0
    dd 0,0,0,0,0,1,0,2
    dd 4,5,6,7,0,0,0,0
    dd 0,0,0,0,3,0,0,0
    dd 0,0,0,0,0,1,0,2
    dd 4,5,6,7,0,0,0,0
    dd 0,0,0,0,3,0,0,4
    dd 0,0,0,0,0,1,2,0
    dd 5,6,7,0,0,0,0,0
    dd 0,0,0,3,0,0,4,5
    dd 0,0,0,0,0,1,0,0
    dd 6,7,0,0,0,0,0,0
%endif
; inter_resid_8x8: nnz of two 8x8s from their coded bits
ir_nnz8: dd 0, 0x0101, 0x01010000, 0x01010101

SECTION .text

cextern pd_32
cextern pw_pixel_max
cextern pw_2
cextern pw_m2
cextern pw_32
cextern hsub_mul
cextern pb_1
cextern pw_1
%if HIGH_BIT_DEPTH == 0
cextern pb_scan8frame_avx2
%else
cextern qscan4_bytes
%endif

; zthr (r9m) to the broadcast thresholds at rsp+%1, before r9 and rstk are used
%macro IR8_ZSCREEN_INIT 1
    mov       r9, r9m
    vpbroadcastd m0, [r9]
    vpbroadcastd m1, [r9+4]
    mova [rsp+%1], m0
    mova [rsp+%1+32], m1
%endmacro

; in: size, m0..m7, temp, temp
; out: m0..m7
%macro DCT8_1D 11
    SUMSUB_BA %1, %6, %5, %11 ; %6=s34, %5=d34
    SUMSUB_BA %1, %7, %4, %11 ; %7=s25, %4=d25
    SUMSUB_BA %1, %8, %3, %11 ; %8=s16, %3=d16
    SUMSUB_BA %1, %9, %2, %11 ; %9=s07, %2=d07

    SUMSUB_BA %1, %7, %8, %11 ; %7=a1, %8=a3
    SUMSUB_BA %1, %6, %9, %11 ; %6=a0, %9=a2

    psra%1   m%10, m%2, 1
    padd%1   m%10, m%2
    padd%1   m%10, m%3
    padd%1   m%10, m%4 ; %10=a4

    psra%1   m%11, m%5, 1
    padd%1   m%11, m%5
    padd%1   m%11, m%3
    psub%1   m%11, m%4 ; %11=a7

    SUMSUB_BA %1, %5, %2
    psub%1   m%2, m%4
    psub%1   m%5, m%3
    psra%1   m%4, 1
    psra%1   m%3, 1
    psub%1   m%2, m%4 ; %2=a5
    psub%1   m%5, m%3 ; %5=a6

    psra%1   m%3, m%11, 2
    padd%1   m%3, m%10 ; %3=b1
    psra%1   m%10, 2
    psub%1   m%10, m%11 ; %10=b7

    SUMSUB_BA %1, %7, %6, %11 ; %7=b0, %6=b4

    psra%1   m%4, m%8, 1
    padd%1   m%4, m%9 ; %4=b2
    psra%1   m%9, 1
    psub%1   m%9, m%8 ; %9=b6

    psra%1   m%8, m%5, 2
    padd%1   m%8, m%2 ; %8=b3
    psra%1   m%2, 2
    psub%1   m%5, m%2 ; %5=b5

    SWAP %2, %7, %5, %8, %9, %10
%endmacro

%macro IDCT8_1D 11
    SUMSUB_BA %1, %6, %2, %10 ; %5=a0, %1=a2

    psra%1   m%10, m%3, 1
    padd%1   m%10, m%3
    padd%1   m%10, m%5
    padd%1   m%10, m%7  ; %9=a7

    psra%1   m%11, m%4, 1
    psub%1   m%11, m%8 ; %10=a4
    psra%1   m%8, 1
    padd%1   m%8, m%4  ; %7=a6

    psra%1   m%4, m%7, 1
    padd%1   m%4, m%7
    padd%1   m%4, m%9
    psub%1   m%4, m%3  ; %3=a5

    psub%1   m%3, m%5
    psub%1   m%7, m%5
    padd%1   m%3, m%9
    psub%1   m%7, m%9
    psra%1   m%5, 1
    psra%1   m%9, 1
    psub%1   m%3, m%5  ; %2=a3
    psub%1   m%7, m%9  ; %6=a1

    psra%1   m%5, m%10, 2
    padd%1   m%5, m%7  ; %4=b1
    psra%1   m%7, 2
    psub%1   m%10, m%7  ; %9=b7

    SUMSUB_BA %1, %8, %6, %7  ;  %7=b0, %5=b6
    SUMSUB_BA %1, %11, %2, %7 ; %10=b2, %1=b4

    psra%1   m%9, m%4, 2
    padd%1   m%9, m%3 ; %8=b3
    psra%1   m%3, 2
    psub%1   m%3, m%4 ; %2=b5

    SUMSUB_BA %1, %10, %8, %7  ; %9=c0,  %7=c7
    SUMSUB_BA %1, %3, %11, %7 ; %2=c1, %10=c6
    SUMSUB_BA %1, %9, %2, %7  ; %8=c2,  %1=c5
    SUMSUB_BA %1, %5, %6, %7  ; %4=c3,  %5=c4

    SWAP %11, %4
    SWAP  %2, %10, %7
    SWAP  %4, %9, %8
%endmacro

%if HIGH_BIT_DEPTH

%macro SUB8x8_DCT8 0
cglobal sub8x8_dct8, 3,3,14
    TAIL_CALL .skip_prologue, 0
global current_function %+ .skip_prologue
.skip_prologue:
    LOAD_DIFF8x4 0,1,2,3, none,none, r1, r2
    LOAD_DIFF8x4 4,5,6,7, none,none, r1, r2

    DCT8_1D w, 0,1,2,3,4,5,6,7, 8,9

    TRANSPOSE4x4W 0,1,2,3,8
    WIDEN_SXWD 0,8
    WIDEN_SXWD 1,9
    WIDEN_SXWD 2,10
    WIDEN_SXWD 3,11
    DCT8_1D d, 0,8,1,9,2,10,3,11, 12,13
    mova  [r0+0x00], m0
    mova  [r0+0x20], m8
    mova  [r0+0x40], m1
    mova  [r0+0x60], m9
    mova  [r0+0x80], m2
    mova  [r0+0xA0], m10
    mova  [r0+0xC0], m3
    mova  [r0+0xE0], m11

    TRANSPOSE4x4W 4,5,6,7,0
    WIDEN_SXWD 4,0
    WIDEN_SXWD 5,1
    WIDEN_SXWD 6,2
    WIDEN_SXWD 7,3
    DCT8_1D d,4,0,5,1,6,2,7,3, 8,9
    mova  [r0+0x10], m4
    mova  [r0+0x30], m0
    mova  [r0+0x50], m5
    mova  [r0+0x70], m1
    mova  [r0+0x90], m6
    mova  [r0+0xB0], m2
    mova  [r0+0xD0], m7
    mova  [r0+0xF0], m3
    ret
%endmacro ; SUB8x8_DCT8

INIT_XMM sse2
SUB8x8_DCT8
INIT_XMM sse4
SUB8x8_DCT8
INIT_XMM avx
SUB8x8_DCT8

;-----------------------------------------------------------------------------
; void sub8x8_dct8( int32_t dct[64], uint16_t *pix1, uint16_t *pix2 ), AVX2
; Word pass on xmm rows (upper lanes zero), then one 8x8 word transpose and
; sign extension, so the dword pass works on whole 8 coefficient rows and
; each row is one 32 byte store, which quant_8x8's 32 byte loads forward.
;-----------------------------------------------------------------------------
INIT_YMM avx2
cglobal sub8x8_dct8, 3,3,10
    TAIL_CALL .skip_prologue, 0
global current_function %+ .skip_prologue
.skip_prologue:
%assign dct8_hbd_i 0
%rep 8
    movu      xm %+ dct8_hbd_i, [r1+dct8_hbd_i*FENC_STRIDEB]
    psubw     xm %+ dct8_hbd_i, [r2+dct8_hbd_i*FDEC_STRIDEB]
%assign dct8_hbd_i dct8_hbd_i+1
%endrep
    DCT8_1D w, 0,1,2,3,4,5,6,7, 8,9
    TRANSPOSE8x8W 0,1,2,3,4,5,6,7, 8
%assign dct8_hbd_i 0
%rep 8
    pmovsxwd   m %+ dct8_hbd_i, xm %+ dct8_hbd_i
%assign dct8_hbd_i dct8_hbd_i+1
%endrep
    DCT8_1D d, 0,1,2,3,4,5,6,7, 8,9
%assign dct8_hbd_i 0
%rep 8
    mova [r0+dct8_hbd_i*32], m %+ dct8_hbd_i
%assign dct8_hbd_i dct8_hbd_i+1
%endrep
    ret

%macro ADD8x8_IDCT8 0
cglobal add8x8_idct8, 2,2,16
    add r1, 128
    TAIL_CALL .skip_prologue, 0
global current_function %+ .skip_prologue
.skip_prologue:
    mova     m0, [r1-128]
    mova     m1, [r1-96]
    mova     m2, [r1-64]
    mova     m3, [r1-32]
    mova     m4, [r1+ 0]
    mova     m5, [r1+32]
    mova     m6, [r1+64]
    mova     m7, [r1+96]
    IDCT8_1D d,0,1,2,3,4,5,6,7,8,9
    TRANSPOSE4x4D 0,1,2,3,8
    TRANSPOSE4x4D 4,5,6,7,8
    paddd     m0, [pd_32]
    paddd     m4, [pd_32]
    mova [r1+64], m6
    mova [r1+96], m7
    mova      m8, [r1-112]
    mova      m9, [r1-80]
    mova     m10, [r1-48]
    mova     m11, [r1-16]
    mova     m12, [r1+16]
    mova     m13, [r1+48]
    mova     m14, [r1+80]
    mova     m15, [r1+112]
    IDCT8_1D d,8,9,10,11,12,13,14,15,6,7
    TRANSPOSE4x4D 8,9,10,11,6
    TRANSPOSE4x4D 12,13,14,15,6
    IDCT8_1D d,0,1,2,3,8,9,10,11,6,7
    mova [r1-112], m8
    mova  [r1-80], m9
    mova       m6, [r1+64]
    mova       m7, [r1+96]
    IDCT8_1D d,4,5,6,7,12,13,14,15,8,9
    pxor       m8, m8
    mova       m9, [pw_pixel_max]
    STORE_DIFF m0, m4, m8, m9, [r0+0*FDEC_STRIDEB]
    STORE_DIFF m1, m5, m8, m9, [r0+1*FDEC_STRIDEB]
    STORE_DIFF m2, m6, m8, m9, [r0+2*FDEC_STRIDEB]
    STORE_DIFF m3, m7, m8, m9, [r0+3*FDEC_STRIDEB]
    mova       m0, [r1-112]
    mova       m1, [r1-80]
    STORE_DIFF  m0, m12, m8, m9, [r0+4*FDEC_STRIDEB]
    STORE_DIFF  m1, m13, m8, m9, [r0+5*FDEC_STRIDEB]
    STORE_DIFF m10, m14, m8, m9, [r0+6*FDEC_STRIDEB]
    STORE_DIFF m11, m15, m8, m9, [r0+7*FDEC_STRIDEB]
    ret
%endmacro ; ADD8x8_IDCT8

INIT_XMM sse2
ADD8x8_IDCT8
INIT_XMM avx
ADD8x8_IDCT8

;-----------------------------------------------------------------------------
; void add8x8_idct8( uint16_t *p_dst, int32_t dct[64] ), AVX2
; Each ymm holds a whole coefficient row, so both passes run once on 8
; registers, with one 8x8 dword transpose (in-lane 4x4 + vperm2i128) between.
;-----------------------------------------------------------------------------
INIT_YMM avx2
cglobal add8x8_idct8, 2,2,11
    add r1, 128
    TAIL_CALL .skip_prologue, 0
global current_function %+ .skip_prologue
.skip_prologue:
%assign idct8_hbd_i 0
%rep 8
    mova       m %+ idct8_hbd_i, [r1-128+idct8_hbd_i*32]
%assign idct8_hbd_i idct8_hbd_i+1
%endrep
    IDCT8_1D d,0,1,2,3,4,5,6,7,8,9
    TRANSPOSE4x4D 0,1,2,3,8
    TRANSPOSE4x4D 4,5,6,7,8
%assign idct8_hbd_i 0
%rep 4
    %assign idct8_hbd_j idct8_hbd_i+4
    vperm2i128 m8, m %+ idct8_hbd_i, m %+ idct8_hbd_j, 0x20
    vperm2i128 m %+ idct8_hbd_j, m %+ idct8_hbd_i, m %+ idct8_hbd_j, 0x31
    SWAP idct8_hbd_i, 8
%assign idct8_hbd_i idct8_hbd_i+1
%endrep
    vpbroadcastd m8, [pd_32]
    paddd      m0, m8
    IDCT8_1D d,0,1,2,3,4,5,6,7,8,9
    pxor       m8, m8
    mova       m9, [pw_pixel_max]
%assign idct8_hbd_i 0
%rep 4
    %assign idct8_hbd_j idct8_hbd_i+1
    psrad      m %+ idct8_hbd_i, 6
    psrad      m %+ idct8_hbd_j, 6
    packssdw   m %+ idct8_hbd_i, m %+ idct8_hbd_j
    vpermq     m %+ idct8_hbd_i, m %+ idct8_hbd_i, q3120
    mova      xm10, [r0+idct8_hbd_i*FDEC_STRIDEB]
    vinserti128 m10, m10, [r0+idct8_hbd_j*FDEC_STRIDEB], 1
    paddw      m %+ idct8_hbd_i, m10
    CLIPW      m %+ idct8_hbd_i, m8, m9
    mova       [r0+idct8_hbd_i*FDEC_STRIDEB], xm %+ idct8_hbd_i
    vextracti128 [r0+idct8_hbd_j*FDEC_STRIDEB], m %+ idct8_hbd_i, 1
%assign idct8_hbd_i idct8_hbd_i+2
%endrep
    ret

;-----------------------------------------------------------------------------
; void sub16x16_dct8( int32_t dct[4][64], uint16_t *pix1, uint16_t *pix2 ), AVX-512
; The four 8x8 blocks in the four lanes: zmm row r = rows r and r+8 of the
; 16x16. Word pass and 8x8 word transpose once for all four, then the dword
; pass on blocks 0+1 and 2+3.
;-----------------------------------------------------------------------------
INIT_ZMM avx512icl
cglobal sub16x16_dct8, 3,3,18
%assign dct8z_i 0
%rep 8
    movu          ym %+ dct8z_i, [r1+dct8z_i*FENC_STRIDEB]
    vinserti64x4   m %+ dct8z_i, m %+ dct8z_i, [r1+(dct8z_i+8)*FENC_STRIDEB], 1
    movu          ym8, [r2+dct8z_i*FDEC_STRIDEB]
    vinserti64x4   m8, m8, [r2+(dct8z_i+8)*FDEC_STRIDEB], 1
    psubw          m %+ dct8z_i, m8
%assign dct8z_i dct8z_i+1
%endrep
    DCT8_1D w, 0,1,2,3,4,5,6,7, 8,9
    TRANSPOSE8x8W 0,1,2,3,4,5,6,7, 8
%assign dct8z_i 0
%rep 8
%assign dct8z_j dct8z_i+10
    pmovsxwd       m %+ dct8z_j, ym %+ dct8z_i
%assign dct8z_i dct8z_i+1
%endrep
    DCT8_1D d, 10,11,12,13,14,15,16,17, 8,9
%assign dct8z_i 0
%rep 8
%assign dct8z_j dct8z_i+10
    mova  [r0+dct8z_i*32], ym %+ dct8z_j
    vextracti64x4 [r0+256+dct8z_i*32], m %+ dct8z_j, 1
%assign dct8z_i dct8z_i+1
%endrep
%assign dct8z_i 0
%rep 8
%assign dct8z_j dct8z_i+10
    vextracti64x4  ym8, m %+ dct8z_i, 1
    pmovsxwd       m %+ dct8z_j, ym8
%assign dct8z_i dct8z_i+1
%endrep
    DCT8_1D d, 10,11,12,13,14,15,16,17, 8,9
%assign dct8z_i 0
%rep 8
%assign dct8z_j dct8z_i+10
    mova  [r0+512+dct8z_i*32], ym %+ dct8z_j
    vextracti64x4 [r0+768+dct8z_i*32], m %+ dct8z_j, 1
%assign dct8z_i dct8z_i+1
%endrep
    RET

;-----------------------------------------------------------------------------
; void add16x16_idct8( uint16_t *p_dst, int32_t dct[4][64] ), AVX-512
; Two 8x8 blocks side by side per pass: zmm row r = row r of both, so after
; the pack each register half is one 16-pixel row of the 16x16.
;-----------------------------------------------------------------------------
cglobal add16x16_idct8, 2,3,18
    vpbroadcastd   m16, [pd_32]
    vpbroadcastw   m17, [pw_pixel_max]
    vpmovzxbq      m15, [idct8_zmm_pack]
    mov            r2d, 0x0f0f
    kmovw           k1, r2d
    knotw           k2, k1
    call .add16x8
    add             r0, 8*FDEC_STRIDEB
    add             r1, 512
    call .add16x8
    RET
.add16x8:
%assign dct8z_i 0
%rep 8
    movu          ym %+ dct8z_i, [r1+dct8z_i*32]
    vinserti64x4   m %+ dct8z_i, m %+ dct8z_i, [r1+256+dct8z_i*32], 1
%assign dct8z_i dct8z_i+1
%endrep
    IDCT8_1D d,0,1,2,3,4,5,6,7,8,9
    TRANSPOSE4x4D 0,1,2,3,8
    TRANSPOSE4x4D 4,5,6,7,8
    ; per 256-bit half (one block): row i = [i.lo, j.lo], row j = [i.hi, j.hi]
%assign dct8z_i 0
%rep 4
%assign dct8z_j dct8z_i+4
    mova           m8, m %+ dct8z_j
    vshufi32x4     m %+ dct8z_j {k1}, m %+ dct8z_i, m %+ dct8z_i, 0x31
    vshufi32x4     m %+ dct8z_i {k2}, m8, m8, 0x80
%assign dct8z_i dct8z_i+1
%endrep
    paddd          m0, m16
    IDCT8_1D d,0,1,2,3,4,5,6,7,8,9
    pxor           m8, m8
%assign dct8z_i 0
%rep 4
%assign dct8z_j dct8z_i+1
    psrad          m %+ dct8z_i, 6
    psrad          m %+ dct8z_j, 6
    packssdw       m %+ dct8z_i, m %+ dct8z_j
    vpermq         m %+ dct8z_i, m15, m %+ dct8z_i
    movu          ym9, [r0+dct8z_i*FDEC_STRIDEB]
    vinserti64x4   m9, m9, [r0+dct8z_j*FDEC_STRIDEB], 1
    paddw          m %+ dct8z_i, m9
    CLIPW          m %+ dct8z_i, m8, m17
    movu  [r0+dct8z_i*FDEC_STRIDEB], ym %+ dct8z_i
    vextracti64x4 [r0+dct8z_j*FDEC_STRIDEB], m %+ dct8z_i, 1
%assign dct8z_i dct8z_i+2
%endrep
    ret
%undef dct8z_i
%undef dct8z_j


;-----------------------------------------------------------------------------
; int inter_resid_8x8( dctcoef level[4][64], pixel *p_src, pixel *p_dst, uint8_t *nnz, udctcoef mf[64],
;                      udctcoef bias[64], int dequant_mf[6][64], int i_qp, int i_decimate_mb,
;                      const uint32_t zthr[4] )
;-----------------------------------------------------------------------------
; sub8x8_dct8, then quant_8x8_scan per 8x8, the decimation, nnz, and dequant + add8x8_idct8 of the coded
; 8x8s (dc-only ones by their dc). Returns the coded 8x8s | the summed score << 4 (0 without decimation).
%define IR8H_Q     0        ; levels in raster order, 256 bytes per 8x8
%define IR8H_DMF   1024     ; dmf[i_qp%6], << qbits if qbits >= 0
%define IR8H_RND   1280     ; qbits < 0: rounding, shift
%define IR8H_SHF   1312
%define IR8H_MODE  1328
%define IR8H_DC0   1332     ; dc dequant: dmf[0], shift left, rounding, shift right
%define IR8H_SL    1336
%define IR8H_F     1340
%define IR8H_SR    1344
%define IR8H_OFF   1348     ; 4 without decimation
%define IR8H_NNZ   1352
%define IR8H_ZT    1376     ; zero screen thresholds, broadcast
%define IR8H_SIZE  1440

%macro INTER_RESID_8x8_HBD 2 ; name, field
cglobal inter_resid_8x8_%1, 9,15,16,-IR8H_SIZE
    IR8_ZSCREEN_INIT IR8H_ZT
    mov [rsp+IR8H_NNZ], r3
    imul      r9d, r7d, 0x2b
    shr       r9d, 8            ; i_qp / 6
    lea       r11d, [r9*3]
    add       r11d, r11d
    sub       r7d, r11d         ; i_qp % 6
    shl       r7d, 8
    add       r6, r7
    mov       r7d, [r6]
    mov [rsp+IR8H_DC0], r7d
    xor       r7d, r7d
    sub       r9d, 6
    jl .rshift
    mov [rsp+IR8H_SL], r9d
    mov [rsp+IR8H_F], r7d
    mov [rsp+IR8H_SR], r7d
    movd      xm8, r9d
%assign ir8h_i 0
%rep 8
    mova      m0, [r6+ir8h_i*32]
    pslld     m0, xm8
    mova [rsp+IR8H_DMF+ir8h_i*32], m0
%assign ir8h_i ir8h_i+1
%endrep
    jmp .init
.rshift:
    neg       r9d
    mov [rsp+IR8H_SL], r7d
    mov [rsp+IR8H_SR], r9d
    lea       r11d, [r9-1]
    inc       r7d
    shlx      r11d, r7d, r11d   ; 1 << (shift-1)
    mov [rsp+IR8H_F], r11d
    movd      xm8, r11d
    vpbroadcastd m8, xm8
    mova [rsp+IR8H_RND], m8
    movd      xm8, r9d
    mova [rsp+IR8H_SHF], xm8
%assign ir8h_i 0
%rep 8
    mova      m0, [r6+ir8h_i*32]
    mova [rsp+IR8H_DMF+ir8h_i*32], m0
%assign ir8h_i ir8h_i+1
%endrep
.init:
    mov [rsp+IR8H_MODE], r7d
    ; r8: score, IR8H_OFF: 4 without decimation (every nonzero 8x8 coded, no MB threshold)
    xor       r10d, r10d
    mov       r7d, 6
    test      r8d, r8d
    sets      r10b
    cmovs     r8d, r7d
    shl       r10d, 2
    mov [rsp+IR8H_OFF], r10d
    xor       r12d, r12d        ; coded 8x8s | ac << 8
    xor       r13d, r13d        ; 256 * 8x8
.loop:
%assign ir8h_i 0
%rep 8
    movu      xm %+ ir8h_i, [r1+ir8h_i*FENC_STRIDEB]
    psubw     xm %+ ir8h_i, [r2+ir8h_i*FDEC_STRIDEB]
%assign ir8h_i ir8h_i+1
%endrep
    ; zero screen: 64*sum(r^2) - sum(r)^2 <= D_max (unsigned), |sum(r)| < t0
    pmaddwd   xm8, xm0, xm0
    pmaddwd   xm9, xm1, xm1
    paddd     xm8, xm9
    pmaddwd   xm9, xm2, xm2
    paddd     xm8, xm9
    pmaddwd   xm9, xm3, xm3
    paddd     xm8, xm9
    pmaddwd   xm9, xm4, xm4
    paddd     xm8, xm9
    pmaddwd   xm9, xm5, xm5
    paddd     xm8, xm9
    pmaddwd   xm9, xm6, xm6
    paddd     xm8, xm9
    pmaddwd   xm9, xm7, xm7
    paddd     xm8, xm9
    paddw     xm9, xm0, xm1
    paddw     xm10, xm2, xm3
    paddw     xm9, xm10
    paddw     xm10, xm4, xm5
    paddw     xm9, xm10
    paddw     xm10, xm6, xm7
    paddw     xm9, xm10
    pmaddwd   xm9, [pw_1]
    phaddd    xm8, xm9
    phaddd    xm8, xm8          ; E, S, E, S
    pshufd    xm9, xm8, q2301
    pabsd     xm9, xm9
    pmulld    xm10, xm9, xm9    ; S^2 < 2^32
    pslld     xm8, 6            ; 64*E < 2^32
    psubd     xm8, xm10
    pminud    xm10, xm8, [rsp+IR8H_ZT]
    pcmpeqd   xm8, xm10
    mova      xm10, [rsp+IR8H_ZT+32]
    pcmpgtd   xm10, xm9
    pand      xm8, xm10
    movd      r6d, xm8
    test      r6d, r6d
    jnz .zero
    DCT8_1D w, 0,1,2,3,4,5,6,7, 8,9
    TRANSPOSE8x8W 0,1,2,3,4,5,6,7, 8
%assign ir8h_i 0
%rep 8
    pmovsxwd   m %+ ir8h_i, xm %+ ir8h_i
%assign ir8h_i ir8h_i+1
%endrep
    DCT8_1D d, 0,1,2,3,4,5,6,7, 8,9
%assign ir8h_i 0
%rep 8
    pabsd     m8, m %+ ir8h_i
    paddd     m8, [r5+ir8h_i*32]
    pmulld    m8, [r4+ir8h_i*32]
    psrld     m8, 16
    psignd    m %+ ir8h_i, m8, m %+ ir8h_i
%assign ir8h_i ir8h_i+1
%endrep
    por       m8, m0, m1
    por       m9, m2, m3
    por       m10, m4, m5
    por       m11, m6, m7
    por       m8, m9
    por       m10, m11
    por       m8, m10
    ptest     m8, m8
    jz .zero
%assign ir8h_i 0
%rep 8
    mova [rsp+r13+IR8H_Q+ir8h_i*32], m %+ ir8h_i
%assign ir8h_i ir8h_i+1
%endrep
    ; zigzag: each output a vpblendd of vpermds of the rows
%if %2 == 0
    mova      m8, [ir8_scan_frame_hbd+0*32]
    vpermd    m10, m8, m0
    mova      m8, [ir8_scan_frame_hbd+1*32]
    vpermd    m9, m8, m1
    vpblendd  m10, m10, m9, 0x12
    mova      m8, [ir8_scan_frame_hbd+2*32]
    vpermd    m9, m8, m2
    vpblendd  m10, m10, m9, 0xa0
    vpbroadcastd m9, xm3
    vpblendd  m10, m10, m9, 0x40
    mova [r0+0], m10
    mova      m8, [ir8_scan_frame_hbd+3*32]
    vpermd    m11, m8, m1
    mova      m8, [ir8_scan_frame_hbd+4*32]
    vpermd    m9, m8, m0
    vpblendd  m11, m11, m9, 0x06
    mova      m8, [ir8_scan_frame_hbd+5*32]
    vpermd    m9, m8, m2
    vpblendd  m11, m11, m9, 0x10
    mova      m8, [ir8_scan_frame_hbd+6*32]
    vpermd    m9, m8, m3
    vpblendd  m11, m11, m9, 0x20
    vpbroadcastd m9, xm4
    vpblendd  m11, m11, m9, 0x40
    vpbroadcastd m9, xm5
    vpblendd  m11, m11, m9, 0x80
    mova [r0+32], m11
    packssdw  m12, m10, m11
    mova      m8, [ir8_scan_frame_hbd+7*32]
    vpermd    m10, m8, m4
    mova      m8, [ir8_scan_frame_hbd+8*32]
    vpermd    m9, m8, m3
    vpblendd  m10, m10, m9, 0x02
    mova      m8, [ir8_scan_frame_hbd+9*32]
    vpermd    m9, m8, m2
    vpblendd  m10, m10, m9, 0x84
    mova      m8, [ir8_scan_frame_hbd+10*32]
    vpermd    m9, m8, m1
    vpblendd  m10, m10, m9, 0x48
    mova      m8, [ir8_scan_frame_hbd+11*32]
    vpermd    m9, m8, m0
    vpblendd  m10, m10, m9, 0x30
    mova [r0+64], m10
    mova      m8, [ir8_scan_frame_hbd+12*32]
    vpermd    m11, m8, m3
    mova      m8, [ir8_scan_frame_hbd+13*32]
    vpermd    m9, m8, m4
    vpblendd  m11, m11, m9, 0x82
    mova      m8, [ir8_scan_frame_hbd+14*32]
    vpermd    m9, m8, m5
    vpblendd  m11, m11, m9, 0x44
    mova      m8, [ir8_scan_frame_hbd+15*32]
    vpermd    m9, m8, m6
    vpblendd  m11, m11, m9, 0x28
    vpbroadcastd m9, xm7
    vpblendd  m11, m11, m9, 0x10
    mova [r0+96], m11
    packssdw  m13, m10, m11
    mova      m8, [ir8_scan_frame_hbd+16*32]
    vpermd    m10, m8, m3
    mova      m8, [ir8_scan_frame_hbd+17*32]
    vpermd    m9, m8, m2
    vpblendd  m10, m10, m9, 0x22
    mova      m8, [ir8_scan_frame_hbd+18*32]
    vpermd    m9, m8, m1
    vpblendd  m10, m10, m9, 0x14
    mova      m8, [ir8_scan_frame_hbd+19*32]
    vpermd    m9, m8, m0
    vpblendd  m10, m10, m9, 0x08
    mova      m8, [ir8_scan_frame_hbd+20*32]
    vpermd    m9, m8, m4
    vpblendd  m10, m10, m9, 0x80
    mova [r0+128], m10
    mova      m8, [ir8_scan_frame_hbd+21*32]
    vpermd    m11, m8, m5
    mova      m8, [ir8_scan_frame_hbd+22*32]
    vpermd    m9, m8, m6
    vpblendd  m11, m11, m9, 0x12
    mova      m8, [ir8_scan_frame_hbd+23*32]
    vpermd    m9, m8, m7
    vpblendd  m11, m11, m9, 0x0c
    mova      m8, [ir8_scan_frame_hbd+24*32]
    vpermd    m9, m8, m4
    vpblendd  m11, m11, m9, 0x40
    mova      m8, [ir8_scan_frame_hbd+25*32]
    vpermd    m9, m8, m3
    vpblendd  m11, m11, m9, 0x80
    mova [r0+160], m11
    packssdw  m14, m10, m11
    mova      m8, [ir8_scan_frame_hbd+26*32]
    vpermd    m10, m8, m2
    mova      m8, [ir8_scan_frame_hbd+27*32]
    vpermd    m9, m8, m3
    vpblendd  m10, m10, m9, 0x02
    mova      m8, [ir8_scan_frame_hbd+28*32]
    vpermd    m9, m8, m4
    vpblendd  m10, m10, m9, 0x04
    mova      m8, [ir8_scan_frame_hbd+29*32]
    vpermd    m9, m8, m5
    vpblendd  m10, m10, m9, 0x08
    mova      m8, [ir8_scan_frame_hbd+30*32]
    vpermd    m9, m8, m6
    vpblendd  m10, m10, m9, 0x90
    mova      m8, [ir8_scan_frame_hbd+31*32]
    vpermd    m9, m8, m7
    vpblendd  m10, m10, m9, 0x60
    mova [r0+192], m10
    mova      m8, [ir8_scan_frame_hbd+32*32]
    vpermd    m11, m8, m5
    mova      m8, [ir8_scan_frame_hbd+33*32]
    vpermd    m9, m8, m4
    vpblendd  m11, m11, m9, 0x02
    mova      m8, [ir8_scan_frame_hbd+34*32]
    vpermd    m9, m8, m6
    vpblendd  m11, m11, m9, 0x48
    mova      m8, [ir8_scan_frame_hbd+35*32]
    vpermd    m9, m8, m7
    vpblendd  m11, m11, m9, 0xb0
    mova [r0+224], m11
    packssdw  m15, m10, m11
%else
    mova      m8, [ir8_scan_field_hbd+0*32]
    vpermd    m10, m8, m0
    mova      m8, [ir8_scan_field_hbd+1*32]
    vpermd    m9, m8, m1
    vpblendd  m10, m10, m9, 0x98
    mova [r0+0], m10
    mova      m8, [ir8_scan_field_hbd+2*32]
    vpermd    m11, m8, m2
    mova      m8, [ir8_scan_field_hbd+3*32]
    vpermd    m9, m8, m1
    vpblendd  m11, m11, m9, 0x22
    mova      m8, [ir8_scan_field_hbd+4*32]
    vpermd    m9, m8, m0
    vpblendd  m11, m11, m9, 0x1c
    vpbroadcastd m9, xm3
    vpblendd  m11, m11, m9, 0x80
    mova [r0+32], m11
    packssdw  m12, m10, m11
    mova      m8, [ir8_scan_field_hbd+5*32]
    vpermd    m10, m8, m2
    mova      m8, [ir8_scan_field_hbd+6*32]
    vpermd    m9, m8, m1
    vpblendd  m10, m10, m9, 0x0e
    mova      m8, [ir8_scan_field_hbd+7*32]
    vpermd    m9, m8, m3
    vpblendd  m10, m10, m9, 0xa0
    vpbroadcastd m9, xm4
    vpblendd  m10, m10, m9, 0x40
    mova [r0+64], m10
    mova      m8, [ir8_scan_field_hbd+8*32]
    vpermd    m11, m8, m2
    mova      m8, [ir8_scan_field_hbd+9*32]
    vpermd    m9, m8, m3
    vpblendd  m11, m11, m9, 0x10
    mova      m8, [ir8_scan_field_hbd+10*32]
    vpermd    m9, m8, m4
    vpblendd  m11, m11, m9, 0xa0
    vpbroadcastd m9, xm5
    vpblendd  m11, m11, m9, 0x40
    mova [r0+96], m11
    packssdw  m13, m10, m11
    mova      m8, [ir8_scan_field_hbd+11*32]
    vpermd    m10, m8, m3
    mova      m8, [ir8_scan_field_hbd+12*32]
    vpermd    m9, m8, m4
    vpblendd  m10, m10, m9, 0x10
    mova      m8, [ir8_scan_field_hbd+13*32]
    vpermd    m9, m8, m5
    vpblendd  m10, m10, m9, 0xa0
    vpbroadcastd m9, xm6
    vpblendd  m10, m10, m9, 0x40
    mova [r0+128], m10
    mova      m8, [ir8_scan_field_hbd+14*32]
    vpermd    m11, m8, m4
    mova      m8, [ir8_scan_field_hbd+15*32]
    vpermd    m9, m8, m5
    vpblendd  m11, m11, m9, 0x90
    mova      m8, [ir8_scan_field_hbd+16*32]
    vpermd    m9, m8, m6
    vpblendd  m11, m11, m9, 0x60
    mova [r0+160], m11
    packssdw  m14, m10, m11
    mova      m8, [ir8_scan_field_hbd+17*32]
    vpermd    m10, m8, m5
    mova      m8, [ir8_scan_field_hbd+18*32]
    vpermd    m9, m8, m6
    vpblendd  m10, m10, m9, 0xc8
    mova      m8, [ir8_scan_field_hbd+19*32]
    vpermd    m9, m8, m7
    vpblendd  m10, m10, m9, 0x30
    mova [r0+192], m10
    mova      m8, [ir8_scan_field_hbd+20*32]
    vpermd    m11, m8, m6
    vpblendd  m11, m11, m7, 0xfc
    mova [r0+224], m11
    packssdw  m15, m10, m11
%endif
    ; levels as bytes in scan order: m12 0-31, m14 32-63
    packsswb  m12, m13
    packsswb  m14, m15
    mova      m13, [qscan4_bytes]
    vpermd    m12, m13, m12
    vpermd    m14, m13, m14
    ; score = sum over nonzero levels of [run<4] + [run<12] + [run<24], run = zeros below; 9 if a |level| > 1
    pabsb     m10, m12
    pabsb     m11, m14
    por       m10, m11
    psubusb   m10, [pb_1]
    pxor      m11, m11
    pcmpeqb   m12, m11
    pcmpeqb   m14, m11
    pmovmskb  r6d, m12
    pmovmskb  r7d, m14
    shl       r7, 32
    or        r6, r7
    not       r6                ; nonzero levels in scan order
    lea       r7, [r6+r6]
    lea       r9, [r6*4]
    lea       r11, [r6*8]
    mov       r14, r6
    shl       r14, 4
    or        r7, r9
    or        r11, r14
    or        r7, r11           ; shifts 1-4
    mov       r9, r7
    mov       r11, r7
    shl       r9, 4
    shl       r11, 8
    or        r9, r11
    or        r9, r7            ; shifts 1-12
    mov       r11, r9
    shl       r11, 12
    or        r11, r9           ; shifts 1-24
    or        r7, 0xf
    or        r9, 0xfff
    or        r11, 0xffffff
    and       r7, r6
    and       r9, r6
    and       r11, r6
    popcnt    r7, r7
    popcnt    r9, r9
    popcnt    r11, r11
    add       r11d, r7d
    add       r11d, r9d
    mov       r7d, 9
    cmp       r11d, r7d
    cmova     r11d, r7d
    ptest     m10, m10
    cmovnz    r11d, r7d         ; score
    xor       r9d, r9d
    shr       r6, 1
    setnz     r9b               ; a nonzero ac level
    add       r8d, r11d
    add       r11d, [rsp+IR8H_OFF]
    xor       r7d, r7d
    cmp       r11d, 4
    setae     r7b
    shl       r9d, 11
    shl       r7d, 3
    or        r9d, r7d
    shr       r12d, 1
    or        r12d, r9d
    jmp .next
.zero:
    shr       r12d, 1
.next:
    add       r0, 256
    add       r1, 8*SIZEOF_PIXEL
    add       r2, 8*SIZEOF_PIXEL
    add       r13d, 256
    cmp       r13d, 512
    jne .next2
    add       r1, 8*FENC_STRIDEB-16*SIZEOF_PIXEL
    add       r2, 8*FDEC_STRIDEB-16*SIZEOF_PIXEL
.next2:
    cmp       r13d, 1024
    jl .loop

    ; MB decimation
    xor       r7d, r7d
    cmp       r8d, 6
    cmovl     r12d, r7d
    cmp dword [rsp+IR8H_OFF], 0
    cmovnz    r8d, r7d
    shl       r8d, 4
    mov       r4d, r12d
    and       r4d, 0xf
    or        r8d, r4d          ; return value
    mov       r3, [rsp+IR8H_NNZ]
    lea       r6, [ir_nnz8]
    mov       r7d, r4d
    and       r7d, 3
    mov       r7d, [r6+r7*4]
    mov  [r3+0*8], r7d
    mov  [r3+1*8], r7d
    mov       r7d, r4d
    shr       r7d, 2
    mov       r7d, [r6+r7*4]
    mov  [r3+2*8], r7d
    mov  [r3+3*8], r7d
    test      r4d, r4d
    jz .end
    sub       r2, 8*FDEC_STRIDEB+16*SIZEOF_PIXEL ; p_dst
    mov       r3, r2
.recon:
    tzcnt     r5d, r4d
    mov       r6d, r5d
    and       r6d, 1
    mov       r7d, r5d
    shr       r7d, 1
    imul      r7d, 8*FDEC_STRIDEB
    lea       r0, [r3+r7]
    shl       r6d, 4
    add       r0, r6            ; dst of the 8x8
    mov       r6d, r5d
    shl       r6d, 8
    lea       r1, [rsp+r6+IR8H_Q]
    lea       r6d, [r5+8]
    bt        r12d, r6d
    jnc .dc
%assign ir8h_i 0
%rep 8
    mova      m %+ ir8h_i, [r1+ir8h_i*32]
    pmulld    m %+ ir8h_i, [rsp+IR8H_DMF+ir8h_i*32]
%assign ir8h_i ir8h_i+1
%endrep
    cmp dword [rsp+IR8H_MODE], 0
    jz .idct
    mova      m8, [rsp+IR8H_RND]
    mova     xm9, [rsp+IR8H_SHF]
%assign ir8h_i 0
%rep 8
    paddd     m %+ ir8h_i, m8
    psrad     m %+ ir8h_i, xm9
%assign ir8h_i ir8h_i+1
%endrep
.idct:
    ; as add8x8_idct8 avx2
    IDCT8_1D d,0,1,2,3,4,5,6,7,8,9
    TRANSPOSE4x4D 0,1,2,3,8
    TRANSPOSE4x4D 4,5,6,7,8
%assign ir8h_i 0
%rep 4
    %assign ir8h_j ir8h_i+4
    vperm2i128 m8, m %+ ir8h_i, m %+ ir8h_j, 0x20
    vperm2i128 m %+ ir8h_j, m %+ ir8h_i, m %+ ir8h_j, 0x31
    SWAP ir8h_i, 8
%assign ir8h_i ir8h_i+1
%endrep
    vpbroadcastd m8, [pd_32]
    paddd      m0, m8
    IDCT8_1D d,0,1,2,3,4,5,6,7,8,9
    pxor       m8, m8
    mova       m9, [pw_pixel_max]
%assign ir8h_i 0
%rep 4
    %assign ir8h_j ir8h_i+1
    psrad      m %+ ir8h_i, 6
    psrad      m %+ ir8h_j, 6
    packssdw   m %+ ir8h_i, m %+ ir8h_j
    vpermq     m %+ ir8h_i, m %+ ir8h_i, q3120
    movu      xm10, [r0+ir8h_i*FDEC_STRIDEB]
    vinserti128 m10, m10, [r0+ir8h_j*FDEC_STRIDEB], 1
    paddw      m %+ ir8h_i, m10
    CLIPW      m %+ ir8h_i, m8, m9
    movu       [r0+ir8h_i*FDEC_STRIDEB], xm %+ ir8h_i
    vextracti128 [r0+ir8h_j*FDEC_STRIDEB], m %+ ir8h_i, 1
%assign ir8h_i ir8h_i+2
%endrep
    jmp .recon_next
.dc:
    ; (dc+32)>>6 of the dequantised dc on every pixel
    mov       r9d, [r1]
    imul      r9d, [rsp+IR8H_DC0]
    mov       r11d, [rsp+IR8H_SL]
    shlx      r9d, r9d, r11d
    add       r9d, [rsp+IR8H_F]
    mov       r11d, [rsp+IR8H_SR]
    sarx      r9d, r9d, r11d
    add       r9d, 32
    sar       r9d, 6
    movd      xm0, r9d
    packssdw  xm0, xm0
    vpbroadcastw m0, xm0
    pxor      m8, m8
    mova      m9, [pw_pixel_max]
%assign ir8h_i 0
%rep 4
    movu         xm1, [r0+ir8h_i*FDEC_STRIDEB]
    vinserti128   m1, m1, [r0+(ir8h_i+1)*FDEC_STRIDEB], 1
    paddw         m1, m0
    CLIPW         m1, m8, m9
    movu [r0+ir8h_i*FDEC_STRIDEB], xm1
    vextracti128 [r0+(ir8h_i+1)*FDEC_STRIDEB], m1, 1
%assign ir8h_i ir8h_i+2
%endrep
.recon_next:
    blsr      r4d, r4d
    jnz .recon
.end:
    mov       eax, r8d
    RET
%endmacro

INIT_YMM avx2
INTER_RESID_8x8_HBD frame, 0
INTER_RESID_8x8_HBD field, 1
%undef ir8h_i
%undef ir8h_j

%else ; !HIGH_BIT_DEPTH

%macro DCT_SUB8 0
cglobal sub8x8_dct, 3,3,10
    add r2, 4*FDEC_STRIDE
%if cpuflag(ssse3)
    mova m7, [hsub_mul]
%endif
    TAIL_CALL .skip_prologue, 0
global current_function %+ .skip_prologue
.skip_prologue:
    SWAP 7, 9
    LOAD_DIFF8x4 0, 1, 2, 3, 8, 9, r1, r2-4*FDEC_STRIDE
    LOAD_DIFF8x4 4, 5, 6, 7, 8, 9, r1, r2-4*FDEC_STRIDE
    DCT4_1D 0, 1, 2, 3, 8
    TRANSPOSE2x4x4W 0, 1, 2, 3, 8
    DCT4_1D 4, 5, 6, 7, 8
    TRANSPOSE2x4x4W 4, 5, 6, 7, 8
    DCT4_1D 0, 1, 2, 3, 8
    STORE_DCT 0, 1, 2, 3, r0, 0
    DCT4_1D 4, 5, 6, 7, 8
    STORE_DCT 4, 5, 6, 7, r0, 64
    ret

;-----------------------------------------------------------------------------
; void sub8x8_dct8( int16_t dct[8][8], uint8_t *pix1, uint8_t *pix2 )
;-----------------------------------------------------------------------------
cglobal sub8x8_dct8, 3,3,11
    add r2, 4*FDEC_STRIDE
%if cpuflag(ssse3)
    mova m7, [hsub_mul]
%endif
    TAIL_CALL .skip_prologue, 0
global current_function %+ .skip_prologue
.skip_prologue:
    SWAP 7, 10
    LOAD_DIFF8x4  0, 1, 2, 3, 4, 10, r1, r2-4*FDEC_STRIDE
    LOAD_DIFF8x4  4, 5, 6, 7, 8, 10, r1, r2-4*FDEC_STRIDE
    DCT8_1D    w, 0,1,2,3,4,5,6,7,8,9
    TRANSPOSE8x8W 0,1,2,3,4,5,6,7,8
    DCT8_1D    w, 0,1,2,3,4,5,6,7,8,9
    movdqa  [r0+0x00], m0
    movdqa  [r0+0x10], m1
    movdqa  [r0+0x20], m2
    movdqa  [r0+0x30], m3
    movdqa  [r0+0x40], m4
    movdqa  [r0+0x50], m5
    movdqa  [r0+0x60], m6
    movdqa  [r0+0x70], m7
    ret
%endmacro

INIT_XMM sse2
%define movdqa movaps
%define punpcklqdq movlhps
DCT_SUB8
%undef movdqa
%undef punpcklqdq
INIT_XMM ssse3
DCT_SUB8
INIT_XMM avx
DCT_SUB8
INIT_XMM xop
DCT_SUB8

INIT_YMM avx2
cglobal sub16x16_dct8, 3,3,10
    add  r0, 128
    add  r2, 4*FDEC_STRIDE
    call .sub16x8_dct8
    add  r0, 256
    add  r1, FENC_STRIDE*8
    add  r2, FDEC_STRIDE*8
    call .sub16x8_dct8
    RET
.sub16x8_dct8:
    LOAD_DIFF16x2_AVX2 0, 1, 2, 3, 0, 1
    LOAD_DIFF16x2_AVX2 2, 3, 4, 5, 2, 3
    LOAD_DIFF16x2_AVX2 4, 5, 6, 7, 4, 5
    LOAD_DIFF16x2_AVX2 6, 7, 8, 9, 6, 7
    DCT8_1D    w, 0,1,2,3,4,5,6,7,8,9
    TRANSPOSE8x8W 0,1,2,3,4,5,6,7,8
    DCT8_1D    w, 0,1,2,3,4,5,6,7,8,9
    ; one 32 byte store per row pair, so quant_8x8's 32 byte loads can forward
%assign dct8_i 0
%rep 4
    %assign dct8_j dct8_i+1
    vperm2i128   m8, m %+ dct8_i, m %+ dct8_j, 0x20
    vperm2i128   m %+ dct8_i, m %+ dct8_i, m %+ dct8_j, 0x31
    mova [r0-0x80+dct8_i*0x10], m8
    mova [r0+dct8_i*0x10], m %+ dct8_i
%assign dct8_i dct8_i+2
%endrep
    ret

;-----------------------------------------------------------------------------
; void sub8x8_dct8( int16_t dct[8][8], uint8_t *pix1, uint8_t *pix2 ), AVX2
; As the AVX version, but rows are joined in pairs for 32 byte stores, so
; quant_8x8's 32 byte loads can forward from them.
;-----------------------------------------------------------------------------
cglobal sub8x8_dct8, 3,3,11
    add       r2, 4*FDEC_STRIDE
    mova     xm10, [hsub_mul]
%assign dct8_i 0
%rep 8
    movq     xm8, [r2+(dct8_i-4)*FDEC_STRIDE]
    movq     xm %+ dct8_i, [r1+dct8_i*FENC_STRIDE]
    punpcklbw xm %+ dct8_i, xm8
    pmaddubsw xm %+ dct8_i, xm10
%assign dct8_i dct8_i+1
%endrep
    DCT8_1D    w, 0,1,2,3,4,5,6,7,8,9
    TRANSPOSE8x8W 0,1,2,3,4,5,6,7,8
    DCT8_1D    w, 0,1,2,3,4,5,6,7,8,9
%assign dct8_i 0
%rep 4
    %assign dct8_j dct8_i+1
    vinserti128  m %+ dct8_i, m %+ dct8_i, xm %+ dct8_j, 1
    mova [r0+dct8_i*0x10], m %+ dct8_i
%assign dct8_i dct8_i+2
%endrep
    RET

;-----------------------------------------------------------------------------
; void add8x8_idct8( uint8_t *p_dst, int16_t dct[8][8] )
;-----------------------------------------------------------------------------
%macro ADD8x8_IDCT8 0
cglobal add8x8_idct8, 2,2,11
    add r0, 4*FDEC_STRIDE
    pxor m7, m7
    TAIL_CALL .skip_prologue, 0
global current_function %+ .skip_prologue
.skip_prologue:
    SWAP 7, 9
    movdqa  m0, [r1+0x00]
    movdqa  m1, [r1+0x10]
    movdqa  m2, [r1+0x20]
    movdqa  m3, [r1+0x30]
    movdqa  m4, [r1+0x40]
    movdqa  m5, [r1+0x50]
    movdqa  m6, [r1+0x60]
    movdqa  m7, [r1+0x70]
    IDCT8_1D      w,0,1,2,3,4,5,6,7,8,10
    TRANSPOSE8x8W 0,1,2,3,4,5,6,7,8
    paddw         m0, [pw_32] ; rounding for the >>6 at the end
    IDCT8_1D      w,0,1,2,3,4,5,6,7,8,10
    DIFFx2 m0, m1, m8, m9, [r0-4*FDEC_STRIDE], [r0-3*FDEC_STRIDE]
    DIFFx2 m2, m3, m8, m9, [r0-2*FDEC_STRIDE], [r0-1*FDEC_STRIDE]
    DIFFx2 m4, m5, m8, m9, [r0+0*FDEC_STRIDE], [r0+1*FDEC_STRIDE]
    DIFFx2 m6, m7, m8, m9, [r0+2*FDEC_STRIDE], [r0+3*FDEC_STRIDE]
    STORE_IDCT m1, m3, m5, m7
    ret
%endmacro ; ADD8x8_IDCT8

INIT_XMM sse2
ADD8x8_IDCT8
INIT_XMM avx
ADD8x8_IDCT8

;-----------------------------------------------------------------------------
; void add8x8_idct( uint8_t *pix, int16_t dct[4][4][4] )
;-----------------------------------------------------------------------------
%macro ADD8x8 0
cglobal add8x8_idct, 2,2,11
    add  r0, 4*FDEC_STRIDE
    pxor m7, m7
    TAIL_CALL .skip_prologue, 0
global current_function %+ .skip_prologue
.skip_prologue:
    SWAP 7, 9
    mova   m0, [r1+ 0]
    mova   m2, [r1+16]
    mova   m1, [r1+32]
    mova   m3, [r1+48]
    SBUTTERFLY qdq, 0, 1, 4
    SBUTTERFLY qdq, 2, 3, 4
    mova   m4, [r1+64]
    mova   m6, [r1+80]
    mova   m5, [r1+96]
    mova   m7, [r1+112]
    SBUTTERFLY qdq, 4, 5, 8
    SBUTTERFLY qdq, 6, 7, 8
    IDCT4_1D w,0,1,2,3,8,10
    TRANSPOSE2x4x4W 0,1,2,3,8
    IDCT4_1D w,4,5,6,7,8,10
    TRANSPOSE2x4x4W 4,5,6,7,8
    paddw m0, [pw_32]
    IDCT4_1D w,0,1,2,3,8,10
    paddw m4, [pw_32]
    IDCT4_1D w,4,5,6,7,8,10
    DIFFx2 m0, m1, m8, m9, [r0-4*FDEC_STRIDE], [r0-3*FDEC_STRIDE]
    DIFFx2 m2, m3, m8, m9, [r0-2*FDEC_STRIDE], [r0-1*FDEC_STRIDE]
    DIFFx2 m4, m5, m8, m9, [r0+0*FDEC_STRIDE], [r0+1*FDEC_STRIDE]
    DIFFx2 m6, m7, m8, m9, [r0+2*FDEC_STRIDE], [r0+3*FDEC_STRIDE]
    STORE_IDCT m1, m3, m5, m7
    ret
%endmacro ; ADD8x8

INIT_XMM sse2
ADD8x8
INIT_XMM avx
ADD8x8

;-----------------------------------------------------------------------------
; void sub16x16_dct8( int16_t dct[4][64], uint8_t *pix1, uint8_t *pix2 ), AVX-512
; The four 8x8 blocks in the four lanes: zmm row r = rows r and r+8 of the
; 16x16, so both passes and the transpose run once. Row pairs of a block are
; joined for 32 byte stores, so quant_8x8's 32 byte loads can forward.
;-----------------------------------------------------------------------------
INIT_ZMM avx512icl
cglobal sub16x16_dct8, 3,3,12
%assign dct8z_i 0
%rep 8
    movu           xm %+ dct8z_i, [r1+dct8z_i*FENC_STRIDE]
    vinserti32x4   ym %+ dct8z_i, ym %+ dct8z_i, [r1+(dct8z_i+8)*FENC_STRIDE], 1
    movu           xm8, [r2+dct8z_i*FDEC_STRIDE]
    vinserti32x4   ym8, ym8, [r2+(dct8z_i+8)*FDEC_STRIDE], 1
    pmovzxbw        m %+ dct8z_i, ym %+ dct8z_i
    pmovzxbw        m8, ym8
    psubw           m %+ dct8z_i, m8
%assign dct8z_i dct8z_i+1
%endrep
    DCT8_1D    w, 0,1,2,3,4,5,6,7,8,9
    TRANSPOSE8x8W 0,1,2,3,4,5,6,7,8
    DCT8_1D    w, 0,1,2,3,4,5,6,7,8,9
    vpmovzxbq      m10, [dct8_zmm_pairs]
    vpmovzxbq      m11, [dct8_zmm_pairs+8]
%assign dct8z_i 0
%rep 4
%assign dct8z_j dct8z_i+1
    mova            m8, m10
    vpermi2q        m8, m %+ dct8z_i, m %+ dct8z_j ; blocks 0, 1
    vpermt2q        m %+ dct8z_i, m11, m %+ dct8z_j ; blocks 2, 3
    mova  [r0+    dct8z_i*16], ym8
    vextracti64x4 [r0+128+dct8z_i*16], m8, 1
    mova  [r0+256+dct8z_i*16], ym %+ dct8z_i
    vextracti64x4 [r0+384+dct8z_i*16], m %+ dct8z_i, 1
%assign dct8z_i dct8z_i+2
%endrep
    RET

;-----------------------------------------------------------------------------
; void add16x16_idct8( uint8_t *p_dst, int16_t dct[4][64] ), AVX-512
; As sub16x16_dct8: block b in lane b, so lanes 0-1 of an output row are
; pixel row r and lanes 2-3 pixel row r+8.
;-----------------------------------------------------------------------------
cglobal add16x16_idct8, 2,2,12
%assign dct8z_i 0
%rep 8
    movu           xm %+ dct8z_i, [r1+dct8z_i*16]
    vinserti32x4   ym %+ dct8z_i, ym %+ dct8z_i, [r1+128+dct8z_i*16], 1
    vinserti32x4    m %+ dct8z_i, m %+ dct8z_i, [r1+256+dct8z_i*16], 2
    vinserti32x4    m %+ dct8z_i, m %+ dct8z_i, [r1+384+dct8z_i*16], 3
%assign dct8z_i dct8z_i+1
%endrep
    IDCT8_1D      w,0,1,2,3,4,5,6,7,8,9
    TRANSPOSE8x8W 0,1,2,3,4,5,6,7,8
    vpbroadcastw    m9, [pw_32]
    paddw           m0, m9 ; rounding for the >>6 at the end
    IDCT8_1D      w,0,1,2,3,4,5,6,7,8,9
    vpmovzxbq      m10, [idct8_zmm_pack]
%assign dct8z_i 0
%rep 4
%assign dct8z_j dct8z_i+1
    psraw           m %+ dct8z_i, 6
    psraw           m %+ dct8z_j, 6
    movu           xm8, [r0+dct8z_i*FDEC_STRIDE]
    vinserti32x4   ym8, ym8, [r0+(dct8z_i+8)*FDEC_STRIDE], 1
    movu           xm9, [r0+dct8z_j*FDEC_STRIDE]
    vinserti32x4   ym9, ym9, [r0+(dct8z_j+8)*FDEC_STRIDE], 1
    pmovzxbw        m8, ym8
    pmovzxbw        m9, ym9
    paddsw          m %+ dct8z_i, m8
    paddsw          m %+ dct8z_j, m9
    packuswb        m %+ dct8z_i, m %+ dct8z_j
    vpermq          m %+ dct8z_i, m10, m %+ dct8z_i
    movu  [r0+dct8z_i*FDEC_STRIDE], xm %+ dct8z_i
    vextracti32x4 [r0+(dct8z_i+8)*FDEC_STRIDE], m %+ dct8z_i, 1
    vextracti32x4 [r0+dct8z_j*FDEC_STRIDE], m %+ dct8z_i, 2
    vextracti32x4 [r0+(dct8z_j+8)*FDEC_STRIDE], m %+ dct8z_i, 3
%assign dct8z_i dct8z_i+2
%endrep
    RET
%undef dct8z_i
%undef dct8z_j


;-----------------------------------------------------------------------------
; int inter_resid_8x8( dctcoef level[4][64], pixel *p_src, pixel *p_dst, uint8_t *nnz, udctcoef mf[64],
;                      udctcoef bias[64], int dequant_mf[6][64], int i_qp, int i_decimate_mb,
;                      const uint32_t zthr[4] )
;-----------------------------------------------------------------------------
; sub16x8 dct8 per 8x8 row, then quant_8x8_scan per 8x8, the decimation, nnz, and dequant + add8x8_idct8
; of the coded 8x8s (dc-only ones by their dc). Returns the coded 8x8s | the summed score << 4 (0 without
; decimation).
%define IR8_Q     0         ; levels in raster order, 128 bytes per 8x8
%define IR8_T     512       ; dct of an 8x8 row: left, right
%define IR8_DMF   768       ; dmf as words, << qbits if qbits >= 0
%define IR8_RND   896       ; qbits < 0: the rounding bit of the product, shift, 16 - shift
%define IR8_SHF   928
%define IR8_SHF2  944
%define IR8_MODE  960
%define IR8_DC0   964       ; dc dequant: dmf[0], shift left, rounding, shift right
%define IR8_SL    968
%define IR8_F     972
%define IR8_SR    976
%define IR8_ZM    980       ; 8x8s of the current 8x8 row proven zero
%define IR8_ZT    992       ; zero screen thresholds, broadcast
%define IR8_SIZE  1056

; rows a, b (b = a+1) to dst r7 (+4*FDEC_STRIDE); m9: 0
%macro IR8_ADD2 3
    movq       xm8, [r7+(%3-4)*FDEC_STRIDE]
    movq      xm10, [r7+(%3-3)*FDEC_STRIDE]
    punpcklbw  xm8, xm9
    punpcklbw xm10, xm9
    psraw     xm%1, 6
    psraw     xm%2, 6
    paddsw    xm%1, xm8
    paddsw    xm%2, xm10
    packuswb  xm%1, xm%2
    movq   [r7+(%3-4)*FDEC_STRIDE], xm%1
    movhps [r7+(%3-3)*FDEC_STRIDE], xm%1
%endmacro

; dst, k: dequant the levels at r6+32*k; m13: rounding bit, xm14: shift, xm15: 16-shift
%macro IR8_DQ_RSHIFT 2
    mova       m%1, [r6+32*%2]
    mova       m11, [rsp+IR8_DMF+32*%2]
    pmulhw     m12, m%1, m11
    pmullw     m%1, m11
    pand       m11, m%1, m13
    pcmpeqw    m11, m13
    psrlw      m%1, xm14
    psllw      m12, xm15
    por        m%1, m12
    psubw      m%1, m11
%endmacro

%macro INTER_RESID_8x8 2 ; name, field
cglobal inter_resid_8x8_%1, 9,15,16,-IR8_SIZE
    IR8_ZSCREEN_INIT IR8_ZT
    imul      r9d, r7d, 0x2b
    shr       r9d, 8            ; i_qp / 6
    lea       r11d, [r9*3]
    add       r11d, r11d
    sub       r7d, r11d         ; i_qp % 6
    shl       r7d, 8
    add       r6, r7
    mov       r7d, [r6]
    mov [rsp+IR8_DC0], r7d
    mova      m0, [r6+  0]
    mova      m1, [r6+ 64]
    mova      m2, [r6+128]
    mova      m3, [r6+192]
    packssdw  m0, [r6+ 32]
    packssdw  m1, [r6+ 96]
    packssdw  m2, [r6+160]
    packssdw  m3, [r6+224]
    vpermq    m0, m0, q3120
    vpermq    m1, m1, q3120
    vpermq    m2, m2, q3120
    vpermq    m3, m3, q3120
    xor       r7d, r7d
    sub       r9d, 6
    jl .rshift
    mov [rsp+IR8_SL], r9d
    mov [rsp+IR8_F], r7d
    mov [rsp+IR8_SR], r7d
    movd      xm4, r9d
    psllw     m0, xm4
    psllw     m1, xm4
    psllw     m2, xm4
    psllw     m3, xm4
    jmp .init
.rshift:
    neg       r9d
    mov [rsp+IR8_SL], r7d
    mov [rsp+IR8_SR], r9d
    lea       r11d, [r9-1]
    inc       r7d
    shlx      r11d, r7d, r11d   ; 1 << (shift-1)
    mov [rsp+IR8_F], r11d
    movd      xm4, r11d
    vpbroadcastw m4, xm4
    mova [rsp+IR8_RND], m4
    movd      xm4, r9d
    mova [rsp+IR8_SHF], xm4
    neg       r9d
    add       r9d, 16
    movd      xm4, r9d
    mova [rsp+IR8_SHF2], xm4
.init:
    mov [rsp+IR8_MODE], r7d
    mova [rsp+IR8_DMF+ 0], m0
    mova [rsp+IR8_DMF+32], m1
    mova [rsp+IR8_DMF+64], m2
    mova [rsp+IR8_DMF+96], m3
    ; r8: score, r10: 4 without decimation (every nonzero 8x8 coded, no MB threshold)
    xor       r10d, r10d
    mov       r7d, 6
    test      r8d, r8d
    sets      r10b
    cmovs     r8d, r7d
    shl       r10d, 2
    add       r2, 4*FDEC_STRIDE
    xor       r12d, r12d        ; coded 8x8s | ac << 8
    xor       r13d, r13d        ; 128 * 8x8
.loop:
    test      r13d, 128
    jnz .block
    LOAD_DIFF16x2_AVX2 0, 1, 2, 3, 0, 1
    LOAD_DIFF16x2_AVX2 2, 3, 4, 5, 2, 3
    LOAD_DIFF16x2_AVX2 4, 5, 6, 7, 4, 5
    LOAD_DIFF16x2_AVX2 6, 7, 8, 9, 6, 7
    ; zero screen of the left, right 8x8: 64*sum(r^2) - sum(r)^2 <= D_max (unsigned), |sum(r)| < t0
    pmaddwd   m8, m0, m0
    pmaddwd   m9, m1, m1
    paddd     m8, m9
    pmaddwd   m9, m2, m2
    paddd     m8, m9
    pmaddwd   m9, m3, m3
    paddd     m8, m9
    pmaddwd   m9, m4, m4
    paddd     m8, m9
    pmaddwd   m9, m5, m5
    paddd     m8, m9
    pmaddwd   m9, m6, m6
    paddd     m8, m9
    pmaddwd   m9, m7, m7
    paddd     m8, m9
    paddw     m9, m0, m1
    paddw     m10, m2, m3
    paddw     m9, m10
    paddw     m10, m4, m5
    paddw     m9, m10
    paddw     m10, m6, m7
    paddw     m9, m10
    pmaddwd   m9, [pw_1]
    phaddd    m8, m9
    phaddd    m8, m8            ; E, S, E, S | of the right 8x8
    pshufd    m9, m8, q2301
    pabsd     m9, m9
    pmaddwd   m10, m9, m9       ; S^2, |S| < 2^15
    pslld     m8, 6
    psubd     m8, m10
    pminud    m10, m8, [rsp+IR8_ZT]
    pcmpeqd   m8, m10
    mova      m10, [rsp+IR8_ZT+32]
    pcmpgtd   m10, m9
    pand      m8, m10
    movmskps  r6d, m8
    and       r6d, 0x11
    mov       r7d, r6d
    shr       r7d, 3
    or        r6d, r7d
    and       r6d, 3            ; proven zero: left, right
    mov [rsp+IR8_ZM], r6d
    cmp       r6d, 3
    je .no_dct
    DCT8_1D    w, 0,1,2,3,4,5,6,7,8,9
    TRANSPOSE8x8W 0,1,2,3,4,5,6,7,8
    DCT8_1D    w, 0,1,2,3,4,5,6,7,8,9
%assign ir8_i 0
%rep 4
    %assign ir8_j ir8_i+1
    vperm2i128   m8, m %+ ir8_i, m %+ ir8_j, 0x20
    vperm2i128   m %+ ir8_i, m %+ ir8_i, m %+ ir8_j, 0x31
    mova [rsp+IR8_T+ir8_i*16], m8
    mova [rsp+IR8_T+128+ir8_i*16], m %+ ir8_i
%assign ir8_i ir8_i+2
%endrep
.no_dct:
    add       r1, 8*FENC_STRIDE
    add       r2, 8*FDEC_STRIDE
.block:
    mov       r6d, r13d
    shr       r6d, 7
    and       r6d, 1            ; left, right
    mov       r7d, [rsp+IR8_ZM]
    bt        r7d, r6d
    jc .zero
    mov       r6d, r13d
    and       r6d, 128
    mova      m0, [rsp+r6+IR8_T+ 0]
    mova      m1, [rsp+r6+IR8_T+32]
    mova      m2, [rsp+r6+IR8_T+64]
    mova      m3, [rsp+r6+IR8_T+96]
    pabsw     m4, m0
    pabsw     m5, m1
    pabsw     m6, m2
    pabsw     m7, m3
    paddusw   m4, [r5+ 0]
    paddusw   m5, [r5+32]
    paddusw   m6, [r5+64]
    paddusw   m7, [r5+96]
    pmulhuw   m4, [r4+ 0]
    pmulhuw   m5, [r4+32]
    pmulhuw   m6, [r4+64]
    pmulhuw   m7, [r4+96]
    psignw    m0, m4, m0
    psignw    m1, m5, m1
    psignw    m2, m6, m2
    psignw    m3, m7, m3
    por       m4, m0, m1
    por       m5, m2, m3
    por       m4, m5
    ptest     m4, m4
    jz .zero
    mova [rsp+r13+IR8_Q+ 0], m0
    mova [rsp+r13+IR8_Q+32], m1
    mova [rsp+r13+IR8_Q+64], m2
    mova [rsp+r13+IR8_Q+96], m3
    ; zigzag: each output a por of pshufbs of A-D (m0-m3) and their lane swaps
    vperm2i128 m4, m0, m0, 0x01
    vperm2i128 m5, m1, m1, 0x01
    vperm2i128 m6, m2, m2, 0x01
    vperm2i128 m7, m3, m3, 0x01
%if %2
    pshufb    m8, m0, [ir_scan8field_avx2+ 0*32]
    pshufb    m9, m4, [ir_scan8field_avx2+ 1*32]
    pshufb   m10, m1, [ir_scan8field_avx2+ 2*32]
    pshufb   m11, m5, [ir_scan8field_avx2+ 3*32]
    por       m8, m9
    por      m10, m11
    por      m14, m8, m10       ; 0-15
    pshufb    m8, m4, [ir_scan8field_avx2+ 4*32]
    pshufb    m9, m1, [ir_scan8field_avx2+ 5*32]
    pshufb   m10, m5, [ir_scan8field_avx2+ 6*32]
    pshufb   m11, m2, [ir_scan8field_avx2+ 7*32]
    pshufb   m12, m6, [ir_scan8field_avx2+ 8*32]
    por       m8, m9
    por      m10, m11
    por       m8, m12
    por       m8, m10           ; 16-31
    pshufb    m9, m5, [ir_scan8field_avx2+ 9*32]
    pshufb   m10, m2, [ir_scan8field_avx2+10*32]
    pshufb   m11, m6, [ir_scan8field_avx2+11*32]
    pshufb   m12, m3, [ir_scan8field_avx2+12*32]
    pshufb   m13, m7, [ir_scan8field_avx2+13*32]
    por       m9, m10
    por      m11, m12
    por       m9, m13
    por       m4, m9, m11       ; 32-47
    pshufb   m10, m6, [ir_scan8field_avx2+14*32]
    pshufb   m11, m3, [ir_scan8field_avx2+15*32]
    pshufb   m12, m7, [ir_scan8field_avx2+16*32]
    por      m10, m11
    por      m15, m10, m12      ; 48-63
%else
    ; as zigzag_scan_8x8_frame avx2
    pshufb    m8, m0, [pb_scan8frame_avx2+ 0*32]
    pshufb    m9, m4, [pb_scan8frame_avx2+ 1*32]
    pshufb   m10, m1, [pb_scan8frame_avx2+ 2*32]
    pshufb   m11, m5, [pb_scan8frame_avx2+ 3*32]
    pshufb   m12, m2, [pb_scan8frame_avx2+ 4*32]
    pshufb   m13, m6, [pb_scan8frame_avx2+ 5*32]
    por       m8, m9
    por      m10, m11
    por      m12, m13
    por       m8, m10
    por      m14, m8, m12       ; 0-15
    pshufb    m8, m1, [pb_scan8frame_avx2+16*32]
    pshufb    m9, m5, [pb_scan8frame_avx2+17*32]
    pshufb   m10, m2, [pb_scan8frame_avx2+18*32]
    pshufb   m11, m6, [pb_scan8frame_avx2+19*32]
    pshufb   m12, m3, [pb_scan8frame_avx2+20*32]
    pshufb   m13, m7, [pb_scan8frame_avx2+21*32]
    por       m8, m9
    por      m10, m11
    por      m12, m13
    por       m8, m10
    por      m15, m8, m12       ; 48-63
    vpblendd  m4, m0, m1, 0xf0
    vperm2i128 m5, m0, m2, 0x21
    vpblendd  m6, m1, m2, 0xf0
    vperm2i128 m7, m1, m3, 0x21
    vpblendd  m0, m2, m3, 0xf0
    pshufb    m8, m4, [pb_scan8frame_avx2+ 6*32]
    pshufb    m9, m5, [pb_scan8frame_avx2+ 7*32]
    pshufb   m10, m6, [pb_scan8frame_avx2+ 8*32]
    pshufb   m11, m7, [pb_scan8frame_avx2+ 9*32]
    pshufb   m12, m0, [pb_scan8frame_avx2+10*32]
    por       m8, m9
    por      m10, m11
    por       m8, m12
    por       m8, m10           ; 16-31
    pshufb    m4, [pb_scan8frame_avx2+11*32]
    pshufb    m5, [pb_scan8frame_avx2+12*32]
    pshufb    m6, [pb_scan8frame_avx2+13*32]
    pshufb    m7, [pb_scan8frame_avx2+14*32]
    pshufb    m0, [pb_scan8frame_avx2+15*32]
    por       m4, m5
    por       m6, m7
    por       m4, m0
    por       m4, m6            ; 32-47
%endif
    mova [r0+ 0], m14
    mova [r0+32], m8
    mova [r0+64], m4
    mova [r0+96], m15
    ; score = sum over nonzero levels of [run<4] + [run<12] + [run<24], run = zeros below; 9 if a |level| > 1
    packsswb  m9, m14, m8
    packsswb m10, m4, m15
    vpermq    m9, m9, q3120
    vpermq   m10, m10, q3120
    pabsb    m11, m9
    pabsb    m12, m10
    por      m11, m12
    psubusb  m11, [pb_1]
    pxor     m12, m12
    pcmpeqb   m9, m12
    pcmpeqb  m10, m12
    pmovmskb r6d, m9
    pmovmskb r7d, m10
    shl       r7, 32
    or        r6, r7
    not       r6                ; nonzero levels in scan order
    lea       r7, [r6+r6]
    lea       r9, [r6*4]
    lea       r11, [r6*8]
    mov       r14, r6
    shl       r14, 4
    or        r7, r9
    or        r11, r14
    or        r7, r11           ; shifts 1-4
    mov       r9, r7
    mov       r11, r7
    shl       r9, 4
    shl       r11, 8
    or        r9, r11
    or        r9, r7            ; shifts 1-12
    mov       r11, r9
    shl       r11, 12
    or        r11, r9           ; shifts 1-24
    or        r7, 0xf
    or        r9, 0xfff
    or        r11, 0xffffff
    and       r7, r6
    and       r9, r6
    and       r11, r6
    popcnt    r7, r7
    popcnt    r9, r9
    popcnt    r11, r11
    add       r11d, r7d
    add       r11d, r9d
    mov       r7d, 9
    cmp       r11d, r7d
    cmova     r11d, r7d
    ptest     m11, m11
    cmovnz    r11d, r7d         ; score
    xor       r9d, r9d
    shr       r6, 1
    setnz     r9b               ; a nonzero ac level
    add       r8d, r11d
    add       r11d, r10d
    xor       r7d, r7d
    cmp       r11d, 4
    setae     r7b
    shl       r9d, 11
    shl       r7d, 3
    or        r9d, r7d
    shr       r12d, 1
    or        r12d, r9d
    jmp .next
.zero:
    shr       r12d, 1
.next:
    sub       r0, -128
    add       r13d, 128
    cmp       r13d, 512
    jl .loop

    ; MB decimation
    xor       r7d, r7d
    cmp       r8d, 6
    cmovl     r12d, r7d
    test      r10d, r10d
    cmovnz    r8d, r7d
    shl       r8d, 4
    mov       r4d, r12d
    and       r4d, 0xf
    or        r8d, r4d          ; return value
    lea       r6, [ir_nnz8]
    mov       r7d, r4d
    and       r7d, 3
    mov       r7d, [r6+r7*4]
    mov  [r3+0*8], r7d
    mov  [r3+1*8], r7d
    mov       r7d, r4d
    shr       r7d, 2
    mov       r7d, [r6+r7*4]
    mov  [r3+2*8], r7d
    mov  [r3+3*8], r7d
    test      r4d, r4d
    jz .end
    sub       r2, 16*FDEC_STRIDE ; p_dst + 4*FDEC_STRIDE
    pxor      m9, m9
    mova     m13, [rsp+IR8_RND]
    mova    xm14, [rsp+IR8_SHF]
    mova    xm15, [rsp+IR8_SHF2]
.recon:
    tzcnt     r5d, r4d
    mov       r6d, r5d
    and       r6d, 1
    mov       r7d, r5d
    shr       r7d, 1
    imul      r7d, 8*FDEC_STRIDE
    add       r7, r2
    lea       r7, [r7+r6*8]     ; dst of the 8x8 + 4*FDEC_STRIDE
    mov       r6d, r5d
    shl       r6d, 7
    lea       r6, [rsp+r6+IR8_Q]
    lea       r9d, [r5+8]
    bt        r12d, r9d
    jnc .dc
    cmp dword [rsp+IR8_MODE], 0
    jnz .dq_rshift
    mova      m0, [r6+ 0]
    mova      m2, [r6+32]
    mova      m4, [r6+64]
    mova      m6, [r6+96]
    pmullw    m0, [rsp+IR8_DMF+ 0]
    pmullw    m2, [rsp+IR8_DMF+32]
    pmullw    m4, [rsp+IR8_DMF+64]
    pmullw    m6, [rsp+IR8_DMF+96]
    jmp .idct
.dq_rshift:
    IR8_DQ_RSHIFT 0, 0
    IR8_DQ_RSHIFT 2, 1
    IR8_DQ_RSHIFT 4, 2
    IR8_DQ_RSHIFT 6, 3
.idct:
    vextracti128 xm1, m0, 1
    vextracti128 xm3, m2, 1
    vextracti128 xm5, m4, 1
    vextracti128 xm7, m6, 1
    IDCT8_1D      w,0,1,2,3,4,5,6,7,8,10
    TRANSPOSE8x8W 0,1,2,3,4,5,6,7,8
    paddw         m0, [pw_32] ; rounding for the >>6 at the end
    IDCT8_1D      w,0,1,2,3,4,5,6,7,8,10
    IR8_ADD2 0, 1, 0
    IR8_ADD2 2, 3, 2
    IR8_ADD2 4, 5, 4
    IR8_ADD2 6, 7, 6
    jmp .recon_next
.dc:
    ; (dc+32)>>6 of the dequantised dc on every pixel
    movsx     r9d, word [r6]
    imul      r9d, [rsp+IR8_DC0]
    mov       r11d, [rsp+IR8_SL]
    shlx      r9d, r9d, r11d
    add       r9d, [rsp+IR8_F]
    mov       r11d, [rsp+IR8_SR]
    sarx      r9d, r9d, r11d
    movsx     r9d, r9w
    add       r9d, 32
    sar       r9d, 6
    movd      xm0, r9d
    psubw     xm1, xm9, xm0
    packuswb  xm0, xm0
    packuswb  xm1, xm1
    vpbroadcastb xm0, xm0
    vpbroadcastb xm1, xm1
%assign ir8_i -4
%rep 4
    movq      xm2, [r7+(ir8_i+0)*FDEC_STRIDE]
    movhps    xm2, [r7+(ir8_i+1)*FDEC_STRIDE]
    paddusb   xm2, xm0
    psubusb   xm2, xm1
    movq   [r7+(ir8_i+0)*FDEC_STRIDE], xm2
    movhps [r7+(ir8_i+1)*FDEC_STRIDE], xm2
%assign ir8_i ir8_i+2
%endrep
.recon_next:
    blsr      r4d, r4d
    jnz .recon
.end:
    mov       eax, r8d
    RET
%endmacro

INIT_YMM avx2
INTER_RESID_8x8 frame, 0
INTER_RESID_8x8 field, 1
%undef ir8_i
%undef ir8_j

%endif ; !HIGH_BIT_DEPTH
