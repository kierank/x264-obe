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

SECTION_RODATA
; add16x16_idct8 avx512icl: packed qwords to 16-pixel rows
idct8_zmm_pack: db 0,2,4,6,1,3,5,7
; sub16x16_dct8 avx512icl: 128-bit lanes of a row pair, blocks 0 1, then 2 3
dct8_zmm_pairs: db 0,1,8,9,2,3,10,11, 4,5,12,13,6,7,14,15
; add8x8_idct8 avx2/avx512icl (8-bit): lane and qword-half signs for the paired
; 1-D passes, dst rows to the residual's column order (0,7,3,4 | 2,5,1,6) as
; words, packed rows back to pixel order
idct8_lsign: times 8 dw 1
             times 8 dw -1
idct8_qsign: times 2 dw 1,1,1,1,-1,-1,-1,-1
idct8_dstw:  db 0,-1,7,-1,3,-1,4,-1, 8,-1,15,-1,11,-1,12,-1
             db 2,-1,5,-1,1,-1,6,-1, 10,-1,13,-1,9,-1,14,-1
idct8_rowb:  db 0,6,4,2,3,5,7,1, 8,14,12,10,11,13,15,9
idct8_rowd:  dd 0,4,1,5, 2,6,3,7, 0,4,1,5

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
; void add16x16_idct8( uint8_t *p_dst, int16_t dct[4][64] ), AVX2
; Blocks 0 1, then 2 3: the left block in lane 0, the right one in lane 1, so
; a ymm row is a 16-pixel row and both passes and the transpose run once per
; pair, as the AVX version's do per block.
;-----------------------------------------------------------------------------
INIT_YMM avx2
cglobal add16x16_idct8, 2,2,11
    call .add16x8_idct8
    add            r0, 8*FDEC_STRIDE
    add            r1, 256
    call .add16x8_idct8
    RET
.add16x8_idct8:
%assign idct8_i 0
%rep 8
    movu          xm %+ idct8_i, [r1+idct8_i*16]
    vinserti128    m %+ idct8_i, m %+ idct8_i, [r1+128+idct8_i*16], 1
%assign idct8_i idct8_i+1
%endrep
    IDCT8_1D      w,0,1,2,3,4,5,6,7,8,9
    TRANSPOSE8x8W 0,1,2,3,4,5,6,7,8
    paddw          m0, [pw_32] ; rounding for the >>6 at the end
    IDCT8_1D      w,0,1,2,3,4,5,6,7,8,9
%assign idct8_i 0
%rep 4
%assign idct8_j idct8_i+1
    psraw          m %+ idct8_i, 6
    psraw          m %+ idct8_j, 6
    pmovzxbw       m8, [r0+idct8_i*FDEC_STRIDE]
    pmovzxbw       m9, [r0+idct8_j*FDEC_STRIDE]
    paddsw         m %+ idct8_i, m8
    paddsw         m %+ idct8_j, m9
    packuswb       m %+ idct8_i, m %+ idct8_j
    vpermq         m %+ idct8_i, m %+ idct8_i, q3120
    movu  [r0+idct8_i*FDEC_STRIDE], xm %+ idct8_i
    vextracti128 [r0+idct8_j*FDEC_STRIDE], m %+ idct8_i, 1
%assign idct8_i idct8_i+2
%endrep
    ret
%undef idct8_i
%undef idct8_j

;-----------------------------------------------------------------------------
; void add8x8_idct8( uint8_t *p_dst, int16_t dct[8][8] ), AVX2 / AVX-512
; One block, 16 useful words per op: each 1-D pass splits into pairs that run
; the same ops in both halves of a register, (x|y) = x in one half, y in the
; other, the y half negated where the two sides differ in sign (psignw, or a
; masked vpsubw). Pass 1 halves are 128-bit lanes; the in-lane transpose
; leaves pass 2 halves as the even/odd qwords of each lane, so a pass-2 row is
; split over the lanes in column order (0,7,3,4 | 2,5,1,6): dst is loaded in
; that order and the packed rows are put back in pixel order. Every op is the
; avx version's op mod 2^16, so the output is identical to it for all inputs.
;-----------------------------------------------------------------------------
; in: pass (1, 2), x0, y0, s26, s62, s13, s31, s57, s75, tmp, tmp
; pass inputs as pairs (s0|s0)/(s4|s4) in x0/y0 (pass 1) or (t4|t0)/(t0|t4)
; (pass 2), s26 = (s2|s6), s62 = (s6|s2) and so on
; out: (o0|o2) %3, (o7|o5) %10, (o3|o1) %4, (o4|o6) %2
%macro IDCT8_PAIRS 11
    LSIGN       %3, %1
    paddw       m%2, m%3              ; a0|a2
    psraw       m%5, 1
    LSIGN       %5, %1
    paddw       m%4, m%5              ; a6|-a4
    psraw       m%10, m%6, 1          ; sign each term: 3 deep, not 4
    LSIGN       %6, %1
    LSIGN       %10, %1
    psubw       m%11, m%8, m%7
    paddw       m%7, m%8
    paddw       m%6, m%7
    paddw       m%6, m%10             ; a7|a3
    psraw       m%10, m%9, 1
    LSIGN       %9, %1
    LSIGN       %10, %1
    psubw       m%11, m%9
    psubw       m%11, m%10            ; a1|a5
    psraw       m%10, m%11, 2
    LSIGN       %10, %1
    psubw       m%8, m%6, m%10        ; b7|b3
    psraw       m%6, 2
    LSIGN       %11, %1
    paddw       m%6, m%11             ; b1|b5
    paddw       m%10, m%2, m%4        ; b0|b4
    psubw       m%2, m%4              ; b6|b2
    paddw       m%3, m%10, m%8        ; o0|o2
    psubw       m%10, m%8             ; o7|o5
    paddw       m%4, m%2, m%6         ; o3|o1
    psubw       m%2, m%6              ; o4|o6
%endmacro

; negate the y half of m%1 in pass %2: k1/k2 (avx512, m15 = 0) or the
; signs of the pass in m14 (avx2)
%macro LSIGN 2
%if cpuflag(avx512)
    vpsubw      m%1 {k%2}, m15, m%1
%else
    psignw      m%1, m%1, m14
%endif
%endmacro

; m%1 = dst rows %2, %3 as words in the residual's order
%macro IDCT8_DSTW 3
    vpbroadcastq m%1, [r0+%2*FDEC_STRIDE]
    vpbroadcastq m12, [r0+%3*FDEC_STRIDE]
%if cpuflag(avx512)
    punpcklqdq  m%1, m12
%else
    vpblendd    m%1, m%1, m12, 0xcc
%endif
    pshufb      m%1, m13
%endmacro

%macro ADD8x8_IDCT8_PAIRS 0
cglobal add8x8_idct8, 2,3,16
%if cpuflag(avx512)
    mov         r2d, 0xff00
    kmovw       k1, r2d
    mov         r2d, 0xf0f0
    kmovw       k2, r2d
    pxor        m15, m15
%else
    movu        m14, [idct8_lsign]
%endif
    vbroadcasti128 m0, [r1+0x00]      ; s0|s0
    vbroadcasti128 m1, [r1+0x40]      ; s4|s4
    movu        xm2, [r1+0x20]
    vinserti128 m2, m2, [r1+0x60], 1  ; s2|s6
    movu        xm3, [r1+0x60]
    vinserti128 m3, m3, [r1+0x20], 1  ; s6|s2
    movu        xm4, [r1+0x10]
    vinserti128 m4, m4, [r1+0x30], 1  ; s1|s3
    movu        xm5, [r1+0x30]
    vinserti128 m5, m5, [r1+0x10], 1  ; s3|s1
    movu        xm6, [r1+0x50]
    vinserti128 m6, m6, [r1+0x70], 1  ; s5|s7
    movu        xm7, [r1+0x70]
    vinserti128 m7, m7, [r1+0x50], 1  ; s7|s5
    IDCT8_PAIRS 1, 0,1,2,3,4,5,6,7,8,9
    ; rows o0|o2 m1, o7|o5 m8, o3|o1 m2, o4|o6 m0: lane 0 rows 0,7,3,4
    punpckhwd   m3, m1, m8
    punpcklwd   m1, m8
    punpckhwd   m4, m2, m0
    punpcklwd   m2, m0
    punpckhdq   m5, m1, m2            ; columns 2, 3
    punpckldq   m1, m2                ; 0, 1
    punpckhdq   m6, m3, m4            ; 6, 7
    punpckldq   m3, m4                ; 4, 5
    punpckhqdq  m7, m1, m5            ; t1|t3
    punpckhqdq  m8, m5, m1            ; t3|t1
    punpckhqdq  m9, m3, m6            ; t5|t7
    punpckhqdq  m10, m6, m3           ; t7|t5
    punpcklqdq  m0, m3, m1            ; t4|t0
    punpcklqdq  m1, m3                ; t0|t4
    punpcklqdq  m2, m5, m6            ; t2|t6
    punpcklqdq  m4, m6, m5            ; t6|t2
    paddw       m0, [pw_32]           ; rounding for the >>6 at the end
%if cpuflag(avx512) == 0
    movu        m14, [idct8_qsign]
%endif
    IDCT8_PAIRS 2, 0,1,2,4,7,8,9,10,3,5
    ; pixel rows 0|2 m1, 7|5 m3, 3|1 m2, 4|6 m0
    movu        m13, [idct8_dstw]
    psraw       m1, 6
    psraw       m3, 6
    psraw       m2, 6
    psraw       m0, 6
    IDCT8_DSTW  4, 0, 2
    paddsw      m1, m4
    IDCT8_DSTW  4, 7, 5
    paddsw      m3, m4
    IDCT8_DSTW  4, 3, 1
    paddsw      m2, m4
    IDCT8_DSTW  4, 4, 6
    paddsw      m0, m4
    packuswb    m1, m3                ; X | Y halves of rows 0 2 7 5
    packuswb    m2, m0                ; 3 1 4 6
    ; two rows to each low lane, so every row store is from an xmm (no extract)
%if cpuflag(avx512)
    movu        m4, [idct8_rowp]
    movu        m5, [idct8_rowp+16]
    vpermb      m6, m5, m1            ; 7 5
    vpermb      m1, m4, m1            ; 0 2
    vpermb      m7, m5, m2            ; 4 6
    vpermb      m2, m4, m2            ; 3 1
%else
    movu        m4, [idct8_rowd]
    movu        m5, [idct8_rowd+16]
    vpermd      m6, m5, m1
    vpermd      m1, m4, m1
    vpermd      m7, m5, m2
    vpermd      m2, m4, m2
    movu        xm4, [idct8_rowb]
    pshufb      xm1, xm4
    pshufb      xm6, xm4
    pshufb      xm2, xm4
    pshufb      xm7, xm4
%endif
    movq        [r0+0*FDEC_STRIDE], xm1
    movhps      [r0+2*FDEC_STRIDE], xm1
    movq        [r0+3*FDEC_STRIDE], xm2
    movhps      [r0+1*FDEC_STRIDE], xm2
    movq        [r0+7*FDEC_STRIDE], xm6
    movhps      [r0+5*FDEC_STRIDE], xm6
    movq        [r0+4*FDEC_STRIDE], xm7
    movhps      [r0+6*FDEC_STRIDE], xm7
    RET
%endmacro

INIT_YMM avx2
ADD8x8_IDCT8_PAIRS

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

%endif ; !HIGH_BIT_DEPTH
