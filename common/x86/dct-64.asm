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

%if HIGH_BIT_DEPTH
SECTION_RODATA
; add16x16_idct8 avx512icl: packssdw qwords to two 16-pixel rows
idct8_zmm_pack: db 0,2,4,6,1,3,5,7
%endif

SECTION .text

cextern pd_32
cextern pw_pixel_max
cextern pw_2
cextern pw_m2
cextern pw_32
cextern hsub_mul

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

%endif ; !HIGH_BIT_DEPTH
