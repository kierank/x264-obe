;*****************************************************************************
;* dct-a.asm: x86 transform and zigzag
;*****************************************************************************
;* Copyright (C) 2003-2014 x264 project
;*
;* Authors: Holger Lubitz <holger@lubitz.org>
;*          Loren Merritt <lorenm@u.washington.edu>
;*          Laurent Aimar <fenrir@via.ecp.fr>
;*          Min Chen <chenm001.163.com>
;*          Jason Garrett-Glaser <darkshikari@gmail.com>
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
; AVX-512 permutation indices are bit-packed to save cache
%if HIGH_BIT_DEPTH
scan_frame_avx512: dd 0x00bf0200, 0x00fd7484, 0x0033a611, 0x0069d822 ; bits 0-3:   4x4_frame
                   dd 0x00a3ca95, 0x00dd8d08, 0x00e75b8c, 0x00a92919 ; bits 4-8:   8x8_frame1
                   dd 0x0072f6a6, 0x003c8433, 0x007e5247, 0x00b6a0ba ; bits 9-13:  8x8_frame2
                   dd 0x00ecf12d, 0x00f3239e, 0x00b9540b, 0x00ff868f ; bits 14-18: 8x8_frame3
                                                                     ; bits 19-23: 8x8_frame4
scan_field_avx512: dd 0x0006b240, 0x000735a1, 0x0007b9c2, 0x0009bde8 ; bits 0-4:   8x8_field1
                   dd 0x000c4e69, 0x000ce723, 0x000a0004, 0x000aeb4a ; bits 5-9:   8x8_field2
                   dd 0x000b5290, 0x000bd6ab, 0x000d5ac5, 0x000ddee6 ; bits 10-14: 8x8_field3
                   dd 0x000e6f67, 0x000e842c, 0x000f0911, 0x000ff058 ; bits 15-19: 8x8_field4
cavlc_shuf_avx512: dd 0x00018820, 0x000398a4, 0x0005a928, 0x0007b9ac ; bits 0-4:   interleave1
                   dd 0x0009ca30, 0x000bdab4, 0x000deb38, 0x000ffbbc ; bits 5-9:   interleave2
                   dd 0x00010c01, 0x00031c85, 0x00052d09, 0x00073d8d ; bits 10-14: interleave3
                   dd 0x00094e11, 0x000b5e95, 0x000d6f19, 0x000f7f9d ; bits 15-19: interleave4
sub4x4_hbd_shift:  dd 0, 0, 0, 0, 1, 1, 1, 1
; zigzag_scan_4x4_frame avx2: out0 = I(in0-7) | J(in8-15), out1 = J(in0-7) | I(in8-15)
scan4x4_frame_avx2: dd 0, 4, 1, 2, 5, 6, 3, 7 ; I
                    dd 6, 3, 7, 0, 0, 0, 4, 1 ; J
%else
dct_avx512:        dd 0x10000000, 0x00021104, 0x3206314c, 0x60042048 ; bits    0-4:   dct8x8_fenc    bits    5-9:   dct8x8_fdec
                   dd 0x98008a10, 0x20029b14, 0xba06bb5c, 0x4004aa58 ; bits    10-13: dct16x16_fenc  bits    14-18: dct16x16_fdec
                   dd 0x54004421, 0x80025525, 0x7606756d, 0xe0046469 ; bits(e) 24-27: idct8x8_idct1  bits(e) 28-31: idct8x8_idct2
                   dd 0xdc00ce31, 0xa002df35, 0xfe06ff7d, 0xc004ee79 ; bits(o) 24-31: idct8x8_gather
scan_frame_avx512: dw 0x7000, 0x5484, 0x3811, 0x1c22, 0x3c95, 0x5908, 0x758c, 0x9119 ; bits 0-3:   4x4_frame
                   dw 0xaca6, 0xc833, 0xe447, 0xe8ba, 0xcd2d, 0xb19e, 0x960b, 0x7a8f ; bits 4-9:   8x8_frame1
                   dw 0x5e10, 0x7da0, 0x9930, 0xb4c0, 0xd050, 0xec60, 0xf0d0, 0xd540 ; bits 10-15: 8x8_frame2
                   dw 0xb9b0, 0x9e20, 0xbe90, 0xdb00, 0xf780, 0xfb10, 0xdea0, 0xfe30
scan_field_avx512: dw 0x0700, 0x0741, 0x0782, 0x07c8, 0x08c9, 0x0a43, 0x0c04, 0x0a8a ; bits 0-5:   8x8_field1
                   dw 0x0910, 0x094b, 0x0985, 0x09c6, 0x0ac7, 0x0c4c, 0x0c91, 0x0b18 ; bits 6-11:  8x8_field2
                   dw 0x0b52, 0x0b8d, 0x0bce, 0x0ccf, 0x0e13, 0x0e59, 0x0d20, 0x0d5a
                   dw 0x0d94, 0x0dd5, 0x0e96, 0x0ed7, 0x0f1b, 0x0f61, 0x0fa8, 0x0fe2
cavlc_shuf_avx512: dw 0x0080, 0x0184, 0x0288, 0x038c, 0x0490, 0x0594, 0x0698, 0x079c ; bits 0-5:   interleave1
                   dw 0x08a0, 0x09a4, 0x0aa8, 0x0bac, 0x0cb0, 0x0db4, 0x0eb8, 0x0fbc ; bits 6-11:  interleave2
                   dw 0x00c1, 0x01c5, 0x02c9, 0x03cd, 0x04d1, 0x05d5, 0x06d9, 0x07dd
                   dw 0x08e1, 0x09e5, 0x0ae9, 0x0bed, 0x0cf1, 0x0df5, 0x0ef9, 0x0ffd
%endif

pw_ppmmmmpp:    dw 1,1,-1,-1,-1,-1,1,1
; dct4x4dc/idct4x4dc avx512icl: output order, butterfly masks
dc4x4_perm:     db 0,8,12,4,2,10,14,6,3,11,15,7,1,9,13,5
dc4x4_masks:    dw 0xaaaa,0xcccc,0xf0f0,0xff00
; add8x8_idct high bit depth avx512icl: packed row pairs to 8-pixel rows
add8x8_hbd_zmm_rows: db 0,2,1,3,4,6,5,7
; zigzag_scan_4x4_field avx512icl
scan4field_perm: db 0,1,4,2,3,5,6,7,8,9,10,11,12,13,14,15
pb_sub4frame:   db 0,1,4,8,5,2,3,6,9,12,13,10,7,11,14,15
pb_sub4field:   db 0,4,1,8,12,5,9,13,2,6,10,14,3,7,11,15
pb_subacmask:   dw 0,-1,-1,-1,-1,-1,-1,-1
pb_scan4framea: SHUFFLE_MASK_W 6,3,7,0,4,1,2,5
pb_scan4frameb: SHUFFLE_MASK_W 0,4,1,2,5,6,3,7
pb_scan4frame2a: SHUFFLE_MASK_W 0,4,1,2,5,8,12,9
pb_scan4frame2b: SHUFFLE_MASK_W 6,3,7,10,13,14,11,15

pb_scan8framet1: SHUFFLE_MASK_W 0,  1,  6,  7,  8,  9, 13, 14
pb_scan8framet2: SHUFFLE_MASK_W 2 , 3,  4,  7,  9, 15, 10, 14
pb_scan8framet3: SHUFFLE_MASK_W 0,  1,  5,  6,  8, 11, 12, 13
pb_scan8framet4: SHUFFLE_MASK_W 0,  3,  4,  5,  8, 11, 12, 15
pb_scan8framet5: SHUFFLE_MASK_W 1,  2,  6,  7,  9, 10, 13, 14
pb_scan8framet6: SHUFFLE_MASK_W 0,  3,  4,  5, 10, 11, 12, 15
pb_scan8framet7: SHUFFLE_MASK_W 1,  2,  6,  7,  8,  9, 14, 15
pb_scan8framet8: SHUFFLE_MASK_W 0,  1,  2,  7,  8, 10, 11, 14
pb_scan8framet9: SHUFFLE_MASK_W 1,  4,  5,  7,  8, 13, 14, 15

pb_scan8frame1: SHUFFLE_MASK_W  0,  8,  1,  2,  9, 12,  4, 13
pb_scan8frame2: SHUFFLE_MASK_W  4,  0,  1,  5,  8, 10, 12, 14
pb_scan8frame3: SHUFFLE_MASK_W 12, 10,  8,  6,  2,  3,  7,  9
pb_scan8frame4: SHUFFLE_MASK_W  0,  1,  8, 12,  4, 13,  9,  2
pb_scan8frame5: SHUFFLE_MASK_W  5, 14, 10,  3, 11, 15,  6,  7
pb_scan8frame6: SHUFFLE_MASK_W  6,  8, 12, 13,  9,  7,  5,  3
pb_scan8frame7: SHUFFLE_MASK_W  1,  3,  5,  7, 10, 14, 15, 11
pb_scan8frame8: SHUFFLE_MASK_W  10, 3, 11, 14,  5,  6, 15,  7

pb_scan8field1 : SHUFFLE_MASK_W    0,   1,   2,   8,   9,   3,   4,  10
pb_scan8field2a: SHUFFLE_MASK_W 0x80,  11,   5,   6,   7,  12,0x80,0x80
pb_scan8field2b: SHUFFLE_MASK_W    0,0x80,0x80,0x80,0x80,0x80,   1,   8
pb_scan8field3a: SHUFFLE_MASK_W   10,   5,   6,   7,  11,0x80,0x80,0x80
pb_scan8field3b: SHUFFLE_MASK_W 0x80,0x80,0x80,0x80,0x80,   1,   8,   2
pb_scan8field4a: SHUFFLE_MASK_W    4,   5,   6,   7,  11,0x80,0x80,0x80
pb_scan8field6 : SHUFFLE_MASK_W    4,   5,   6,   7,  11,0x80,0x80,  12
pb_scan8field7 : SHUFFLE_MASK_W    5,   6,   7,  11,0x80,0x80,  12,  13

%if HIGH_BIT_DEPTH == 0
; zigzag_scan_8x8_field rows 1-6 then row 0; ymm loads take rows r and r+1
align 32
pb_scan8field_u: SHUFFLE_MASK_W 0x80,   6,   0,   1,   2,   7,0x80,0x80
                 SHUFFLE_MASK_W    5,   0,   1,   2,   6,0x80,0x80,0x80
                 SHUFFLE_MASK_W    0,   1,   2,   3,   7,0x80,0x80,0x80
                 SHUFFLE_MASK_W    0,   1,   2,   3,   7,0x80,0x80,0x80
                 SHUFFLE_MASK_W    0,   1,   2,   3,   7,0x80,0x80,0x80
                 SHUFFLE_MASK_W    1,   2,   3,   7,0x80,0x80,0x80,0x80
pb_scan8field_v: SHUFFLE_MASK_W 0x80,0x80,0x80,0x80,0x80,0x80,   0,   7
                 SHUFFLE_MASK_W 0x80,0x80,0x80,0x80,0x80,   0,   7,   1
                 SHUFFLE_MASK_W 0x80,0x80,0x80,0x80,0x80,   0,   7,   1
                 SHUFFLE_MASK_W 0x80,0x80,0x80,0x80,0x80,   0,   7,   1
                 SHUFFLE_MASK_W 0x80,0x80,0x80,0x80,0x80,   5,   6,   0
                 SHUFFLE_MASK_W 0x80,0x80,0x80,0x80,   4,   5,   0,   1
pb_scan8field_u0: SHUFFLE_MASK_W    0,   1,   2,0x80,0x80,0x80,0x80,0x80
pb_scan8field_v0: SHUFFLE_MASK_W 0x80,0x80,0x80,   5,   6,   0,   1,   7
align 32
; zigzag_scan_4x4_field avx2: words 2-5 of lane 0 permuted, lane 1 copied
pb_scan4field_avx2: db 0,1,2,3,8,9,4,5,6,7,10,11,12,13,14,15
                    db 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
; zigzag_scan_8x8_frame avx2: one pshufb mask per source ymm, 4 outputs
const pb_scan8frame_avx2, db 0,1,-1,-1,2,3,4,5,-1,-1,-1,-1,-1,-1,-1,-1,4,5,-1,-1,-1,-1,6,7,-1,-1,-1,-1,-1,-1,-1,-1
                       db -1,-1,0,1,-1,-1,-1,-1,2,3,-1,-1,-1,-1,-1,-1,-1,-1,6,7,8,9,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1
                       db -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,0,1,-1,-1,2,3,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,2,3,-1,-1,-1,-1
                       db -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,0,1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,4,5,-1,-1,-1,-1,-1,-1
                       db -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,0,1
                       db -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,0,1,-1,-1
                       db -1,-1,-1,-1,-1,-1,-1,-1,10,11,12,13,-1,-1,-1,-1,6,7,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1
                       db -1,-1,-1,-1,-1,-1,8,9,-1,-1,-1,-1,10,11,-1,-1,-1,-1,4,5,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,6,7
                       db -1,-1,-1,-1,6,7,-1,-1,-1,-1,-1,-1,-1,-1,8,9,-1,-1,-1,-1,2,3,-1,-1,-1,-1,-1,-1,4,5,-1,-1
                       db -1,-1,4,5,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,0,1,-1,-1,2,3,-1,-1,-1,-1
                       db 2,3,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,0,1,-1,-1,-1,-1,-1,-1
                       db -1,-1,-1,-1,-1,-1,14,15,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,12,13
                       db -1,-1,-1,-1,12,13,-1,-1,14,15,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,10,11,-1,-1
                       db -1,-1,10,11,-1,-1,-1,-1,-1,-1,12,13,-1,-1,-1,-1,6,7,-1,-1,-1,-1,-1,-1,-1,-1,8,9,-1,-1,-1,-1
                       db 8,9,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,10,11,-1,-1,-1,-1,4,5,-1,-1,-1,-1,6,7,-1,-1,-1,-1,-1,-1
                       db -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,8,9,-1,-1,-1,-1,2,3,4,5,-1,-1,-1,-1,-1,-1,-1,-1
                       db 14,15,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1
                       db -1,-1,14,15,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1
                       db -1,-1,-1,-1,12,13,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,12,13,-1,-1,14,15,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1
                       db -1,-1,-1,-1,-1,-1,10,11,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,14,15,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1
                       db -1,-1,-1,-1,-1,-1,-1,-1,8,9,-1,-1,-1,-1,10,11,-1,-1,-1,-1,-1,-1,-1,-1,10,11,12,13,-1,-1,14,15
                       db -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,6,7,8,9,-1,-1,-1,-1,-1,-1,-1,-1,12,13,-1,-1,-1,-1,14,15,-1,-1
align 64
; zigzag_sub_8x8 avx512icl: vpermb indices into the 8x8 block packed as 8 bytes
; per row; even bytes give coefs 0-31, odd bytes coefs 32-63
zsub8_frame8:  db  0,35, 1,42, 8,49,16,56, 9,57, 2,50, 3,43,10,36
               db 17,29,24,22,32,15,25,23,18,30,11,37, 4,44, 5,51
               db 12,58,19,59,26,52,33,45,40,38,48,31,41,39,34,46
               db 27,53,20,60,13,61, 6,54, 7,47,14,55,21,62,28,63
zsub8_field8:  db  0,35, 8,43,16,51, 1,59, 9,28,24,13,32, 6,17,21
               db  2,36,25,44,40,52,48,60,56,29,33,14,10,22, 3,37
               db 18,45,41,53,49,61,57,30,26,7,11,15, 4,38,19,46
               db 34,54,42,62,50,23,58,31,27,39,12,47, 5,55,20,63
; vpermt2b indices packing the 8 src rows to 8 bytes each
zsub8_pack:    db   0,  1,  2,  3,  4,  5,  6,  7, 16, 17, 18, 19, 20, 21, 22, 23
               db  32, 33, 34, 35, 36, 37, 38, 39, 48, 49, 50, 51, 52, 53, 54, 55
               db  64, 65, 66, 67, 68, 69, 70, 71, 80, 81, 82, 83, 84, 85, 86, 87
               db  96, 97, 98, 99,100,101,102,103,112,113,114,115,116,117,118,119
; zigzag_sub_4x4 avx512icl: even bytes index FENC_STRIDE rows, odd bytes the packed dst rows
zsub4_frame:   db  0, 0, 1, 1,16, 4,32, 8,17, 5, 2, 2, 3, 3,18, 6
               db 33, 9,48,12,49,13,34,10,19, 7,35,11,50,14,51,15
zsub4_field:   db  0, 0,16, 4, 1, 1,32, 8,48,12,17, 5,33, 9,49,13
               db  2, 2,18, 6,34,10,50,14, 3, 3,19, 7,35,11,51,15
%endif
ALIGN 32
; inter_resid_4x4: the block of each nnz byte, rows 0-1 | rows 2-3
ir_nnz_bits:    dw 1<<0, 1<<1, 1<<4, 1<<5, 1<<2, 1<<3, 1<<6, 1<<7
                dw 1<<8, 1<<9, 1<<12, 1<<13, 1<<10, 1<<11, 1<<14, 1<<15
%if HIGH_BIT_DEPTH
ALIGN 32
; add16x16_idct_dc avx2: dc0 x4 dc1 x4 | dc2 x4 dc3 x4 from packssdw'd dc0-3 in both lanes
idct_dc16_shuf: db 0,1,0,1,0,1,0,1,2,3,2,3,2,3,2,3, 4,5,4,5,4,5,4,5,6,7,6,7,6,7,6,7
%endif
%if HIGH_BIT_DEPTH == 0
ALIGN 32
; zigzag_scan_4x4_frame avx2: words of coefs 0-7 | 8-15 (a), of 8-15 | 0-7 (b)
scan4frame_ymm_a: SHUFFLE_MASK_W 0, 4, 1, 2, 5, 0x80, 0x80, 0x80
                  SHUFFLE_MASK_W 0x80, 0x80, 0x80, 2, 5, 6, 3, 7
scan4frame_ymm_b: SHUFFLE_MASK_W 0x80, 0x80, 0x80, 0x80, 0x80, 0, 4, 1
                  SHUFFLE_MASK_W 6, 3, 7, 0x80, 0x80, 0x80, 0x80, 0x80
%endif
%if HIGH_BIT_DEPTH == 0
; dct2x4dc avx512icl: the dc of each 16-coef block
dct2x4_dc_idxw: dw 0, 16, 32, 48
                times 28 dw 0
%endif
%if HIGH_BIT_DEPTH
; zigzag_sub avx512icl (high bit depth): raster index of each scan position
align 32
zsub4_frame_hbd: dw  0, 1, 4, 8, 5, 2, 3, 6, 9,12,13,10, 7,11,14,15
zsub4_field_hbd: dw  0, 4, 1, 8,12, 5, 9,13, 2, 6,10,14, 3, 7,11,15
align 64
zsub8_frame_hbd: dw  0, 1, 8,16, 9, 2, 3,10,17,24,32,25,18,11, 4, 5
                 dw 12,19,26,33,40,48,41,34,27,20,13, 6, 7,14,21,28
                 dw 35,42,49,56,57,50,43,36,29,22,15,23,30,37,44,51
                 dw 58,59,52,45,38,31,39,46,53,60,61,54,47,55,62,63
zsub8_field_hbd: dw  0, 8,16, 1, 9,24,32,17, 2,25,40,48,56,33,10, 3
                 dw 18,41,49,57,26,11, 4,19,34,42,50,58,27,12, 5,20
                 dw 35,43,51,59,28,13, 6,21,36,44,52,60,29,14,22,37
                 dw 45,53,61,30, 7,15,38,46,54,62,23,31,39,47,55,63
%endif

SECTION .text

cextern pw_32_0
cextern pw_32
cextern pw_512
cextern pw_8000
cextern pw_pixel_max
cextern hsub_mul
cextern pb_1
cextern pw_1
cextern pd_1
cextern pd_32
cextern pw_ppppmmmm
cextern pw_pmpmpmpm
cextern deinterleave_shufd
cextern pb_unpackbd1
cextern pb_unpackbd2
%if HIGH_BIT_DEPTH
cextern qscan4_frame_i
cextern qscan4_frame_j
cextern qscan4_field
cextern qscan4_bytes
%else
cextern qscan4_frame_a
cextern qscan4_frame_b
cextern qscan4_field
%endif

; inter_resid zero screen. m0-m3: rows 0|4, 1|5, 2|6, 3|7 of an 8x8 residual (words). %2 = 0x33 if every
; 4x4 has 16*sum(r^2) - sum(r)^2 <= [rsp+%1] (unsigned) and |sum(r)| < [rsp+%1+32]; m4-m6 clobbered
%macro IR_ZSCREEN4 2 ; thresholds (broadcast), gpr
    pmaddwd   m4, m0, m0
    pmaddwd   m5, m1, m1
    paddd     m4, m5
    pmaddwd   m5, m2, m2
    paddd     m4, m5
    pmaddwd   m5, m3, m3
    paddd     m4, m5
    paddw     m5, m0, m1
    paddw     m6, m2, m3
    paddw     m5, m6
    pmaddwd   m5, [pw_1]
    phaddd    m4, m5            ; E of 4x4 0, 1, S of 0, 1 | of 2, 3
    pshufd    m5, m4, q1032
    pabsd     m5, m5
    pmaddwd   m6, m5, m5        ; S^2, |S| < 2^15
    pslld     m4, 4
    psubd     m4, m6
    pminud    m6, m4, [rsp+%1]
    pcmpeqd   m4, m6
    mova      m6, [rsp+%1+32]
    pcmpgtd   m6, m5
    pand      m4, m6
    movmskps  %2, m4
    and       %2, 0x33
%endmacro

; zthr (r9m) to the broadcast thresholds at rsp+%1, before r9 and rstk are used
%macro IR_ZSCREEN_INIT 1
    mov       r9, r9m
    vpbroadcastd m0, [r9]
    vpbroadcastd m1, [r9+4]
    mova [rsp+%1], m0
    mova [rsp+%1+32], m1
%endmacro

%macro WALSH4_1D 6
    SUMSUB_BADC %1, %5, %4, %3, %2, %6
    SUMSUB_BADC %1, %5, %3, %4, %2, %6
    SWAP %2, %5, %4
%endmacro

%macro SUMSUB_17BIT 4 ; a, b, tmp, 0x8000
    movq  m%3, m%4
    pxor  m%1, m%4
    psubw m%3, m%2
    pxor  m%2, m%4
    pavgw m%3, m%1
    pavgw m%2, m%1
    pxor  m%3, m%4
    pxor  m%2, m%4
    SWAP %1, %2, %3
%endmacro

%macro DCT_UNPACK 3
    punpcklwd %3, %1
    punpckhwd %2, %1
    psrad     %3, 16
    psrad     %2, 16
    SWAP      %1, %3
%endmacro

%if HIGH_BIT_DEPTH
;-----------------------------------------------------------------------------
; void dct4x4dc( dctcoef d[4][4] )
;-----------------------------------------------------------------------------
%macro DCT4x4_DC 0
cglobal dct4x4dc, 1,1,5
    mova   m0, [r0+ 0]
    mova   m1, [r0+16]
    mova   m2, [r0+32]
    mova   m3, [r0+48]
    WALSH4_1D  d, 0,1,2,3,4
    TRANSPOSE4x4D 0,1,2,3,4
    paddd  m0, [pd_1]
    WALSH4_1D  d, 0,1,2,3,4
    psrad  m0, 1
    psrad  m1, 1
    psrad  m2, 1
    psrad  m3, 1
    mova [r0+ 0], m0
    mova [r0+16], m1
    mova [r0+32], m2
    mova [r0+48], m3
    RET
%endmacro ; DCT4x4_DC

INIT_XMM sse2
DCT4x4_DC
INIT_XMM avx
DCT4x4_DC
%else

INIT_MMX mmx2
cglobal dct4x4dc, 1,1
    movq   m3, [r0+24]
    movq   m2, [r0+16]
    movq   m1, [r0+ 8]
    movq   m0, [r0+ 0]
    movq   m7, [pw_8000] ; convert to unsigned and back, so that pavgw works
    WALSH4_1D  w, 0,1,2,3,4
    TRANSPOSE4x4W 0,1,2,3,4
    SUMSUB_BADC w, 1, 0, 3, 2, 4
    SWAP 0, 1
    SWAP 2, 3
    SUMSUB_17BIT 0,2,4,7
    SUMSUB_17BIT 1,3,5,7
    movq  [r0+0], m0
    movq  [r0+8], m2
    movq [r0+16], m3
    movq [r0+24], m1
    RET
%endif ; HIGH_BIT_DEPTH

%if HIGH_BIT_DEPTH
;-----------------------------------------------------------------------------
; void idct4x4dc( int32_t d[4][4] )
;-----------------------------------------------------------------------------
%macro IDCT4x4DC 0
cglobal idct4x4dc, 1,1
    mova   m3, [r0+48]
    mova   m2, [r0+32]
    mova   m1, [r0+16]
    mova   m0, [r0+ 0]
    WALSH4_1D  d,0,1,2,3,4
    TRANSPOSE4x4D 0,1,2,3,4
    WALSH4_1D  d,0,1,2,3,4
    mova  [r0+ 0], m0
    mova  [r0+16], m1
    mova  [r0+32], m2
    mova  [r0+48], m3
    RET
%endmacro ; IDCT4x4DC

INIT_XMM sse2
IDCT4x4DC
INIT_XMM avx
IDCT4x4DC
%else

;-----------------------------------------------------------------------------
; void idct4x4dc( int16_t d[4][4] )
;-----------------------------------------------------------------------------
INIT_MMX mmx
cglobal idct4x4dc, 1,1
    movq   m3, [r0+24]
    movq   m2, [r0+16]
    movq   m1, [r0+ 8]
    movq   m0, [r0+ 0]
    WALSH4_1D  w,0,1,2,3,4
    TRANSPOSE4x4W 0,1,2,3,4
    WALSH4_1D  w,0,1,2,3,4
    movq  [r0+ 0], m0
    movq  [r0+ 8], m1
    movq  [r0+16], m2
    movq  [r0+24], m3
    RET
%endif ; HIGH_BIT_DEPTH

;-----------------------------------------------------------------------------
; dct4x4dc/idct4x4dc avx512icl: the block in one register, rows in 4-coef
; lanes. A butterfly is a shuffle, an add and a masked subtract; it leaves the
; frequencies in order 0 3 1 2 on both axes, and one permute gives the
; transposed order of the C. 8-bit dct4x4dc does the rows in words (the C
; truncates there) and the columns in dwords (17 bits before the >>1).
;-----------------------------------------------------------------------------
%macro WALSH4_ICL 6 ; size, dst, src, tmp, shuffle, mask
    %5
    padd%1     %2, %3, %4
    vpsub%1    %2 {%6}, %4, %3
%endmacro

%macro DC4x4_ICL_MASKS 0
    kmovw      k1, [dc4x4_masks+0]
    kmovw      k2, [dc4x4_masks+2]
    kmovw      k3, [dc4x4_masks+4]
    kmovw      k4, [dc4x4_masks+6]
%endmacro

; columns, dwords, from m0
%macro DC4x4_ICL_COLS 0
    WALSH4_ICL  d, m2, m0, m1, {vshufi32x4 m1, m0, m0, q2301}, k3
    WALSH4_ICL  d, m0, m2, m1, {vshufi32x4 m1, m2, m2, q1032}, k4
%endmacro

INIT_ZMM avx512icl
%if HIGH_BIT_DEPTH
cglobal dct4x4dc, 1,1
    DC4x4_ICL_MASKS
    mova        m0, [r0]
    WALSH4_ICL  d, m2, m0, m1, {pshufd m1, m0, q2301}, k1
    WALSH4_ICL  d, m0, m2, m1, {pshufd m1, m2, q1032}, k2
    DC4x4_ICL_COLS
    vpmovzxbd   m1, [dc4x4_perm]
    vpaddd      m0, m0, [pd_1] {1to16}
    psrad       m0, 1
    vpermd      m0, m1, m0
    mova      [r0], m0
    RET

cglobal idct4x4dc, 1,1
    DC4x4_ICL_MASKS
    mova        m0, [r0]
    WALSH4_ICL  d, m2, m0, m1, {pshufd m1, m0, q2301}, k1
    WALSH4_ICL  d, m0, m2, m1, {pshufd m1, m2, q1032}, k2
    DC4x4_ICL_COLS
    vpmovzxbd   m1, [dc4x4_perm]
    vpermd      m0, m1, m0
    mova      [r0], m0
    RET
%else
cglobal dct4x4dc, 1,1
    DC4x4_ICL_MASKS
    mova       ym0, [r0]
    WALSH4_ICL  w, ym2, ym0, ym1, {vprold ym1, ym0, 16}, k1
    WALSH4_ICL  w, ym0, ym2, ym1, {pshufd ym1, ym2, q2301}, k2
    vpmovsxwd   m0, ym0
    DC4x4_ICL_COLS
    vpmovzxbd   m1, [dc4x4_perm]
    vpaddd      m0, m0, [pd_1] {1to16}
    psrad       m0, 1
    vpermd      m0, m1, m0
    vpmovdw    ym1, m0
    mova      [r0], ym1
    RET

cglobal idct4x4dc, 1,1
    DC4x4_ICL_MASKS
    mova       ym0, [r0]
    WALSH4_ICL  w, ym2, ym0, ym1, {vprold ym1, ym0, 16}, k1
    WALSH4_ICL  w, ym0, ym2, ym1, {pshufd ym1, ym2, q2301}, k2
    WALSH4_ICL  w, ym2, ym0, ym1, {pshufd ym1, ym0, q1032}, k3
    WALSH4_ICL  w, ym0, ym2, ym1, {vpermq ym1, ym2, q1032}, k4
    vpmovzxbw  ym1, [dc4x4_perm]
    vpermw     ym0, ym1, ym0
    mova      [r0], ym0
    RET
%endif

;-----------------------------------------------------------------------------
; void dct2x4dc( dctcoef dct[8], dctcoef dct4x4[8][16] )
;-----------------------------------------------------------------------------
%if WIN64
    DECLARE_REG_TMP 6 ; Avoid some REX prefixes to reduce code size
%else
    DECLARE_REG_TMP 2
%endif

%macro INSERT_COEFF 3 ; dst, src, imm
    %if %3
        %if HIGH_BIT_DEPTH
            %if cpuflag(sse4)
                pinsrd %1, %2, %3
            %elif %3 == 2
                movd       m2, %2
            %elif %3 == 1
                punpckldq  %1, %2
            %else
                punpckldq  m2, %2
                punpcklqdq %1, m2
            %endif
        %else
            %if %3 == 2
                punpckldq  %1, %2
            %else
                pinsrw %1, %2, %3
            %endif
        %endif
    %else
        movd %1, %2
    %endif
    %if HIGH_BIT_DEPTH
        mov %2, t0d
    %else
        mov %2, t0w
    %endif
%endmacro

%macro DCT2x4DC 2
cglobal dct2x4dc, 2,3
    xor          t0d, t0d
    INSERT_COEFF  m0, [r1+0*16*SIZEOF_DCTCOEF], 0
    INSERT_COEFF  m0, [r1+1*16*SIZEOF_DCTCOEF], 2
    add           r1, 4*16*SIZEOF_DCTCOEF
    INSERT_COEFF  m0, [r1-2*16*SIZEOF_DCTCOEF], 1
    INSERT_COEFF  m0, [r1-1*16*SIZEOF_DCTCOEF], 3
    INSERT_COEFF  m1, [r1+0*16*SIZEOF_DCTCOEF], 0
    INSERT_COEFF  m1, [r1+1*16*SIZEOF_DCTCOEF], 2
    INSERT_COEFF  m1, [r1+2*16*SIZEOF_DCTCOEF], 1
    INSERT_COEFF  m1, [r1+3*16*SIZEOF_DCTCOEF], 3
    SUMSUB_BA     %1, 1, 0, 2
    SBUTTERFLY    %2, 1, 0, 2
    SUMSUB_BA     %1, 0, 1, 2
    SBUTTERFLY    %2, 0, 1, 2
    SUMSUB_BA     %1, 1, 0, 2
    pshuf%1       m0, m0, q1032
    mova        [r0], m1
    mova [r0+mmsize], m0
    RET
%endmacro

%if HIGH_BIT_DEPTH
INIT_XMM sse2
DCT2x4DC d, dq
INIT_XMM avx
DCT2x4DC d, dq
%else
INIT_MMX mmx2
DCT2x4DC w, wd

; avx512icl: the 8 blocks in 4 zmm, the dcs picked with vpermi2w, the blocks
; stored back with the dcs cleared by a zero-masking move. The 2x4 transform
; in dwords with merge-masked vpsubd.
INIT_ZMM avx512icl
cglobal dct2x4dc, 2,3
    mov          r2d, 0xfffefffe
    kmovd         k2, r2d
    movu         m0, [r1+0*64]
    movu         m1, [r1+1*64]
    movu         m2, [r1+2*64]
    movu         m3, [r1+3*64]
    movu         m4, [dct2x4_dc_idxw]
    vpermi2w     m4, m0, m1              ; dc of blocks 0-3
    vmovdqu16    m0 {k2}{z}, m0
    vmovdqu16    m1 {k2}{z}, m1
    movu  [r1+0*64], m0
    movu  [r1+1*64], m1
    movu         m5, [dct2x4_dc_idxw]
    vpermi2w     m5, m2, m3              ; dc of blocks 4-7
    vmovdqu16    m2 {k2}{z}, m2
    vmovdqu16    m3 {k2}{z}, m3
    movu  [r1+2*64], m2
    movu  [r1+3*64], m3
    punpcklqdq   xm4, xm5
    pmovsxwd     ym0, xm4                   ; dc0-7
    mov          r2d, 0xaa
    kmovb         k1, r2d
    pshufd        ym1, ym0, q2301
    paddd         ym2, ym0, ym1
    vpsubd        ym2 {k1}, ym1, ym0           ; a0 a4 a1 a5 | a2 a6 a3 a7
    mov          r2d, 0xcc
    kmovb         k1, r2d
    pshufd        ym1, ym2, q1032
    paddd         ym0, ym2, ym1
    vpsubd        ym0 {k1}, ym1, ym2           ; b0 b2 b4 b6 | b1 b3 b5 b7
    vextracti32x4 xm1, ym0, 1
    paddd         xm2, xm0, xm1             ; dct 0 1 6 7
    psubd         xm0, xm1                  ; dct 2 3 4 5
    punpcklqdq    xm1, xm2, xm0
    punpckhqdq    xm0, xm2
    packssdw      xm1, xm0
    movu      [r0], xm1
    RET
%endif

%if HIGH_BIT_DEPTH
;-----------------------------------------------------------------------------
; void sub4x4_dct( dctcoef dct[4][4], pixel *pix1, pixel *pix2 )
;-----------------------------------------------------------------------------
INIT_MMX mmx
cglobal sub4x4_dct, 3,3
.skip_prologue:
    LOAD_DIFF  m0, m4, none, [r1+0*FENC_STRIDE], [r2+0*FDEC_STRIDE]
    LOAD_DIFF  m3, m4, none, [r1+6*FENC_STRIDE], [r2+6*FDEC_STRIDE]
    LOAD_DIFF  m1, m4, none, [r1+2*FENC_STRIDE], [r2+2*FDEC_STRIDE]
    LOAD_DIFF  m2, m4, none, [r1+4*FENC_STRIDE], [r2+4*FDEC_STRIDE]
    DCT4_1D 0,1,2,3,4
    TRANSPOSE4x4W 0,1,2,3,4

    SUMSUB_BADC w, 3, 0, 2, 1
    SUMSUB_BA   w, 2, 3, 4
    DCT_UNPACK m2, m4, m5
    DCT_UNPACK m3, m6, m7
    mova  [r0+ 0], m2 ; s03 + s12
    mova  [r0+ 8], m4
    mova  [r0+32], m3 ; s03 - s12
    mova  [r0+40], m6

    DCT_UNPACK m0, m2, m4
    DCT_UNPACK m1, m3, m5
    SUMSUB2_AB  d, 0, 1, 4
    SUMSUB2_AB  d, 2, 3, 5
    mova  [r0+16], m0 ; d03*2 + d12
    mova  [r0+24], m2
    mova  [r0+48], m4 ; d03 - 2*d12
    mova  [r0+56], m5
    RET

;-----------------------------------------------------------------------------
; void sub4x4_dct( dctcoef dct[16], pixel *pix1, pixel *pix2 ), AVX2
; Vertical pass in words, then the columns are paired as [s03|d03] and [s12|d12]
; so that the horizontal pass writes two output rows per ymm, in dwords.
; Two 32 byte stores, so quant's 32 byte loads can forward from them.
;-----------------------------------------------------------------------------
INIT_YMM avx2
cglobal sub4x4_dct, 3,3,6
    movq       xm0, [r1+0*FENC_STRIDEB]
    movq       xm4, [r2+0*FDEC_STRIDEB]
    movq       xm1, [r1+1*FENC_STRIDEB]
    movq       xm5, [r2+1*FDEC_STRIDEB]
    psubw      xm0, xm4
    movq       xm2, [r1+2*FENC_STRIDEB]
    movq       xm4, [r2+2*FDEC_STRIDEB]
    psubw      xm1, xm5
    movq       xm3, [r1+3*FENC_STRIDEB]
    movq       xm5, [r2+3*FDEC_STRIDEB]
    psubw      xm2, xm4
    psubw      xm3, xm5
    paddw      xm4, xm0, xm3      ; s03
    psubw      xm0, xm3           ; d03
    paddw      xm5, xm1, xm2      ; s12
    psubw      xm1, xm2           ; d12
    paddw      xm2, xm4, xm5      ; f0 = s03 + s12
    psubw      xm4, xm5           ; f2 = s03 - s12
    paddw      xm3, xm0, xm0
    paddw      xm3, xm1           ; f1 = 2*d03 + d12
    psubw      xm0, xm1
    psubw      xm0, xm1           ; f3 = d03 - 2*d12
    punpcklwd  xm2, xm3
    punpcklwd  xm4, xm0
    punpckhdq  xm1, xm2, xm4      ; c2 | c3
    punpckldq  xm2, xm4           ; c0 | c1
    pshufd     xm1, xm1, q1032    ; c3 | c2
    paddw      xm0, xm2, xm1      ; s03 | s12
    psubw      xm2, xm1           ; d03 | d12
    punpcklqdq xm1, xm0, xm2      ; s03 | d03
    punpckhqdq xm0, xm2           ; s12 | d12
    pmovsxwd    m1, xm1
    pmovsxwd    m0, xm0
    vpsllvd     m2, m1, [sub4x4_hbd_shift]
    vpsllvd     m3, m0, [sub4x4_hbd_shift]
    paddd       m2, m0            ; s03 + s12   | 2*d03 + d12
    psubd       m1, m3            ; s03 - s12   | d03 - 2*d12
    movu   [r0+ 0], m2
    movu   [r0+32], m1
    RET

;-----------------------------------------------------------------------------
; void sub8x8_dct( dctcoef dct[4][16], pixel *pix1, pixel *pix2 ), AVX2
; Each lane holds one row of two 4x4 blocks (rows i and i+4 of the 8x8), so a
; pass transforms all four blocks. The first pass and the s03 +- s12 rows of
; the second fit words (at most 24552); 2*d03 + d12 and d03 - 2*d12 can reach
; 36828 and are done in dwords.
;-----------------------------------------------------------------------------
%macro SUB8x8_DCT_HBD_LOAD 0
%assign subdct_hbd_i 0
%rep 4
    movu         xm %+ subdct_hbd_i, [r1+subdct_hbd_i*FENC_STRIDEB]
    vinserti128   m %+ subdct_hbd_i, m %+ subdct_hbd_i, [r1+(subdct_hbd_i+4)*FENC_STRIDEB], 1
    movu         xm4, [r2+subdct_hbd_i*FDEC_STRIDEB]
    vinserti128   m4, m4, [r2+(subdct_hbd_i+4)*FDEC_STRIDEB], 1
    psubw         m %+ subdct_hbd_i, m4
%assign subdct_hbd_i subdct_hbd_i+1
%endrep
%endmacro

; %1, %2: dwords of output rows i and i+1, lane 0 = block 0 or 1, lane 1 = block 2 or 3
; One 32 byte store per row pair, so quant's 32 byte loads can forward from it.
%macro SUB8x8_DCT_HBD_STORE 4 ; row i, row i+1, tmp, offset
    vperm2i128   m%3, m%1, m%2, 0x20
    vperm2i128   m%1, m%1, m%2, 0x31
    mova  [r0+%4    ], m%3
    mova  [r0+%4+128], m%1
%endmacro

; %1: l = blocks 0 and 2, h = blocks 1 and 3
%macro SUB8x8_DCT_HBD_HALF 2 ; punpck suffix, offset
    punpck%1wd    m4, m2, m2    ; s03 + s12
    punpck%1wd    m5, m0, m0    ; d03
    punpck%1wd    m6, m1, m1    ; d12
    psrad         m4, 16
    psrad         m5, 16
    psrad         m6, 16
    SUMSUB2_AB    d, 5, 6, 7    ; 2*d03 + d12, d03 - 2*d12
    SUB8x8_DCT_HBD_STORE 4, 5, 6, %2
    punpck%1wd    m4, m3, m3    ; s03 - s12
    psrad         m4, 16
    SUB8x8_DCT_HBD_STORE 4, 7, 6, %2+32
%endmacro

; the dct of the residual SUB8x8_DCT_HBD_LOAD left in m0-m3
%macro SUB8x8_DCT_HBD_TX 0
    DCT4_1D 0, 1, 2, 3, 4
    TRANSPOSE2x4x4W 0, 1, 2, 3, 4
    SUMSUB_BADC w, 3, 0, 2, 1   ; s03, d03, s12, d12
    SUMSUB_BA   w, 2, 3, 4      ; s03 + s12, s03 - s12
    SUB8x8_DCT_HBD_HALF l, 0
    SUB8x8_DCT_HBD_HALF h, 64
%endmacro

%macro SUB8x8_DCT_HBD 0
    SUB8x8_DCT_HBD_LOAD
    SUB8x8_DCT_HBD_TX
%endmacro

INIT_YMM avx2
cglobal sub8x8_dct, 3,3,8
    SUB8x8_DCT_HBD
    RET

cglobal sub16x16_dct, 3,3,8
    call .sub8x8
    add  r0, 256
    add  r1, 8*SIZEOF_PIXEL
    add  r2, 8*SIZEOF_PIXEL
    call .sub8x8
    add  r0, 256
    add  r1, 8*FENC_STRIDEB-8*SIZEOF_PIXEL
    add  r2, 8*FDEC_STRIDEB-8*SIZEOF_PIXEL
    call .sub8x8
    add  r0, 256
    add  r1, 8*SIZEOF_PIXEL
    add  r2, 8*SIZEOF_PIXEL
    call .sub8x8
    RET
.sub8x8:
    SUB8x8_DCT_HBD
    ret
%else

%macro SUB_DCT4 0
cglobal sub4x4_dct, 3,3
.skip_prologue:
%if cpuflag(ssse3)
    mova m5, [hsub_mul]
%endif
    LOAD_DIFF8x4 0, 3, 1, 2, 4, 5, r1, r2
    DCT4_1D 0,1,2,3,4
    TRANSPOSE4x4W 0,1,2,3,4
    DCT4_1D 0,1,2,3,4
    movq  [r0+ 0], m0
    movq  [r0+ 8], m1
    movq  [r0+16], m2
    movq  [r0+24], m3
    RET
%endmacro

INIT_MMX mmx
SUB_DCT4
INIT_MMX ssse3
SUB_DCT4
%endif ; HIGH_BIT_DEPTH

%if HIGH_BIT_DEPTH
;-----------------------------------------------------------------------------
; void add4x4_idct( pixel *p_dst, dctcoef dct[4][4] )
;-----------------------------------------------------------------------------
%macro STORE_DIFFx2 6
    psrad     %1, 6
    psrad     %2, 6
    packssdw  %1, %2
    movq      %3, %5
    movhps    %3, %6
    paddsw    %1, %3
    CLIPW     %1, %4, [pw_pixel_max]
    movq      %5, %1
    movhps    %6, %1
%endmacro

%macro ADD4x4_IDCT 0
cglobal add4x4_idct, 2,2,6
    add   r0, 2*FDEC_STRIDEB
.skip_prologue:
    mova  m1, [r1+16]
    mova  m3, [r1+48]
    mova  m2, [r1+32]
    mova  m0, [r1+ 0]
    IDCT4_1D d,0,1,2,3,4,5
    TRANSPOSE4x4D 0,1,2,3,4
    paddd m0, [pd_32]
    IDCT4_1D d,0,1,2,3,4,5
    pxor  m5, m5
    STORE_DIFFx2 m0, m1, m4, m5, [r0-2*FDEC_STRIDEB], [r0-1*FDEC_STRIDEB]
    STORE_DIFFx2 m2, m3, m4, m5, [r0+0*FDEC_STRIDEB], [r0+1*FDEC_STRIDEB]
    RET
%endmacro

INIT_XMM sse2
ADD4x4_IDCT
INIT_XMM avx
ADD4x4_IDCT

;-----------------------------------------------------------------------------
; void add8x8_idct( pixel *p_dst, dctcoef dct[4][16] ), AVX2
; Lane 0 holds block 0 or 1 and lane 1 the block below it (2 or 3), so each
; instruction transforms two blocks. Packed rows of the left and right blocks
; then interleave in-lane into [row r | row r+4], 8 contiguous pixels each.
;-----------------------------------------------------------------------------
%macro ADD8x8_IDCT_HBD_LOAD 2 ; reg, dct offset
    mova         xm%1, [r1+%2]
    vinserti128   m%1, m%1, [r1+%2+128], 1
%endmacro

; %1: dct offset of the upper block, %2-%5: rows, %6-%7: tmp
; out: m%2 = rows 0,1 and m%4 = rows 2,3 as words, lane 1 = lower block
%macro ADD8x8_IDCT_HBD_PASS 7
    ADD8x8_IDCT_HBD_LOAD %2, %1+ 0
    ADD8x8_IDCT_HBD_LOAD %3, %1+16
    ADD8x8_IDCT_HBD_LOAD %4, %1+32
    ADD8x8_IDCT_HBD_LOAD %5, %1+48
    IDCT4_1D d,%2,%3,%4,%5,%6,%7
    TRANSPOSE4x4D %2,%3,%4,%5,%6
    vpbroadcastd  m%6, [pd_32]
    paddd         m%2, m%6
    IDCT4_1D d,%2,%3,%4,%5,%6,%7
    psrad         m%2, 6
    psrad         m%3, 6
    psrad         m%4, 6
    psrad         m%5, 6
    packssdw      m%2, m%3
    packssdw      m%4, m%5
%endmacro

; %1: words of rows %3 | %3+4, %2: tmp, m5: 0, m7: pw_pixel_max
%macro ADD8x8_IDCT_HBD_STORE 3
    mova         xm%2, [r0+%3*FDEC_STRIDEB]
    vinserti128   m%2, m%2, [r0+(%3+4)*FDEC_STRIDEB], 1
    paddsw        m%1, m%2
    CLIPW         m%1, m5, m7
    mova         [r0+%3*FDEC_STRIDEB], xm%1
    vextracti128 [r0+(%3+4)*FDEC_STRIDEB], m%1, 1
%endmacro

%macro ADD8x8_IDCT_HBD 0
    ADD8x8_IDCT_HBD_PASS  0, 0, 1, 2, 3, 4, 5 ; blocks 0, 2
    ADD8x8_IDCT_HBD_PASS 64, 4, 5, 6, 7, 1, 3 ; blocks 1, 3
    punpcklqdq    m1, m0, m4 ; rows 0 | 4
    punpckhqdq    m0, m4     ; rows 1 | 5
    punpcklqdq    m3, m2, m6 ; rows 2 | 6
    punpckhqdq    m2, m6     ; rows 3 | 7
    pxor          m5, m5
    mova          m7, [pw_pixel_max]
    ADD8x8_IDCT_HBD_STORE 1, 4, 0
    ADD8x8_IDCT_HBD_STORE 0, 6, 1
    ADD8x8_IDCT_HBD_STORE 3, 4, 2
    ADD8x8_IDCT_HBD_STORE 2, 6, 3
%endmacro

INIT_YMM avx2
cglobal add8x8_idct, 2,2,8
    ADD8x8_IDCT_HBD
    RET

cglobal add16x16_idct, 2,2,8
    call .add8x8
    add  r0, 8*SIZEOF_PIXEL
    add  r1, 256
    call .add8x8
    add  r0, 8*FDEC_STRIDEB-8*SIZEOF_PIXEL
    add  r1, 256
    call .add8x8
    add  r0, 8*SIZEOF_PIXEL
    add  r1, 256
    call .add8x8
    RET
.add8x8:
    ADD8x8_IDCT_HBD
    ret

;-----------------------------------------------------------------------------
; void add8x8_idct( pixel *p_dst, dctcoef dct[4][16] ), AVX-512
; One pass for the four blocks: lane b holds block b, a register one row.
; The rows come from a 4x4 transpose of the 128-bit lanes of the four
; blocks; after the pack a vpermq gives four 8-pixel rows per register.
;-----------------------------------------------------------------------------
%macro ADD8x8_IDCT_HBD_ZMM_ROWS 5 ; reg, 4 pixel rows
    movu         xm2, [r0+%2*FDEC_STRIDEB]
    vinserti32x4  m2, m2, [r0+%3*FDEC_STRIDEB], 1
    vinserti32x4  m2, m2, [r0+%4*FDEC_STRIDEB], 2
    vinserti32x4  m2, m2, [r0+%5*FDEC_STRIDEB], 3
    paddsw       m%1, m2
    CLIPW        m%1, m7, m8
    movu  [r0+%2*FDEC_STRIDEB], xm%1
    vextracti32x4 [r0+%3*FDEC_STRIDEB], m%1, 1
    vextracti32x4 [r0+%4*FDEC_STRIDEB], m%1, 2
    vextracti32x4 [r0+%5*FDEC_STRIDEB], m%1, 3
%endmacro

%macro ADD8x8_IDCT_HBD_ZMM 0
    mova          m0, [r1+  0]
    mova          m1, [r1+ 64]
    mova          m2, [r1+128]
    mova          m3, [r1+192]
    vshufi32x4    m4, m0, m1, q1010 ; b0r0 b0r1 b1r0 b1r1
    vshufi32x4    m0, m0, m1, q3232 ; b0r2 b0r3 b1r2 b1r3
    vshufi32x4    m1, m2, m3, q1010 ; b2r0 b2r1 b3r0 b3r1
    vshufi32x4    m2, m2, m3, q3232 ; b2r2 b2r3 b3r2 b3r3
    vshufi32x4    m3, m4, m1, q2020 ; row 0
    vshufi32x4    m4, m4, m1, q3131 ; row 1
    vshufi32x4    m1, m0, m2, q2020 ; row 2
    vshufi32x4    m0, m0, m2, q3131 ; row 3
    IDCT4_1D d, 3, 4, 1, 0, 2, 5
    TRANSPOSE4x4D 3, 4, 1, 0, 2
    paddd         m3, m6
    IDCT4_1D d, 3, 4, 1, 0, 2, 5
    psrad         m3, 6
    psrad         m4, 6
    psrad         m1, 6
    psrad         m0, 6
    packssdw      m3, m4            ; rows 0, 1 of each block
    packssdw      m1, m0            ; rows 2, 3
    vpermq        m3, m9, m3        ; pixel rows 0 1 4 5
    vpermq        m1, m9, m1        ; pixel rows 2 3 6 7
    ADD8x8_IDCT_HBD_ZMM_ROWS 3, 0, 1, 4, 5
    ADD8x8_IDCT_HBD_ZMM_ROWS 1, 2, 3, 6, 7
%endmacro

%macro ADD8x8_IDCT_HBD_ZMM_INIT 0
    vpbroadcastd  m6, [pd_32]
    pxor         xm7, xm7
    vpbroadcastw  m8, [pw_pixel_max]
    vpmovzxbq     m9, [add8x8_hbd_zmm_rows]
%endmacro

%if ARCH_X86_64
INIT_ZMM avx512icl
cglobal add8x8_idct, 2,2,10
    ADD8x8_IDCT_HBD_ZMM_INIT
    ADD8x8_IDCT_HBD_ZMM
    RET

cglobal add16x16_idct, 2,2,10
    ADD8x8_IDCT_HBD_ZMM_INIT
    call .add8x8
    add  r0, 8*SIZEOF_PIXEL
    add  r1, 256
    call .add8x8
    add  r0, 8*FDEC_STRIDEB-8*SIZEOF_PIXEL
    add  r1, 256
    call .add8x8
    add  r0, 8*SIZEOF_PIXEL
    add  r1, 256
    call .add8x8
    RET
.add8x8:
    ADD8x8_IDCT_HBD_ZMM
    ret
%endif ; ARCH_X86_64


%if ARCH_X86_64
;-----------------------------------------------------------------------------
; int inter_resid_4x4( dctcoef level[16][16], pixel *p_src, pixel *p_dst, uint8_t *nnz, udctcoef mf[16],
;                      udctcoef bias[16], int dequant_mf[6][16], int i_qp, int i_decimate_mb,
;                      const uint32_t zthr[4] )
;-----------------------------------------------------------------------------
; sub8x8_dct, quant_4x4x4_scan and dequant per 8x8, then the decimation, nnz and the idct of the coded 8x8s
; (dc-only 8x8s by add8x8_idct_dc). Returns the coded 8x8s | the summed score << 4 (0 without decimation).
%define IRH_DQ    0         ; dequantised coefs, 256 bytes per 8x8
%define IRH_T     1024      ; dct of an 8x8, then the levels of its zero blocks
%define IRH_DMF   1280      ; dmf[i_qp%6]
%define IRH_RND   1344      ; rounding if i_qp/6 < 4
%define IRH_SHF   1376      ; shift
%define IRH_MODE  1392
%define IRH_OFF   1396      ; 4 without decimation
%define IRH_NNZ   1400
%define IRH_ZT    1408      ; zero screen thresholds, broadcast
%define IRH_SIZE  1472

; dst, offset: quant the coefs at r0+offset
%macro IRH_QUANT 2
    pabsd     m8, [r0+%2]
    paddd     m8, [r5+(%2&32)]
    pmulld    m8, [r4+(%2&32)]
    psrad     m8, 16
    psignd    %1, m8, [r0+%2]
%endmacro

; block, 2x src: to level if the block is nonzero (r10), else to the dct buffer
%macro IRH_STORE_LEVEL 3
    bt        r10d, %1
    sbb       r11, r11
    and       r11, r9
    mova [r0+r11+64*%1   ], %2
    mova [r0+r11+64*%1+32], %3
%endmacro

; field, block, A, B, packed dst (as QUANT_SCAN_BLOCK)
%macro IRH_SCAN_BLOCK 5
%if %1
    vpermd    m8, m10, %3
    IRH_STORE_LEVEL %2, m8, %4
    packssdw  %5, m8, %4
%else
    vpermd    m8, m10, %3
    vpermd    m9, m11, %4
    vpblendd  m8, m8, m9, 0xe0
    vpermd    m9, m11, %3
    vpermd    m12, m10, %4
    vpblendd  m9, m9, m12, 0xf8
    IRH_STORE_LEVEL %2, m8, m9
    packssdw  %5, m8, m9
%endif
%endmacro

%macro INTER_RESID_4x4_HBD 3 ; name, field, zero screen (else A6)
cglobal inter_resid_4x4_%1, 9,15,16,-IRH_SIZE
%if %3
    IR_ZSCREEN_INIT IRH_ZT
%endif
    mov [rsp+IRH_NNZ], r3
    imul      r9d, r7d, 0x2b
    shr       r9d, 8            ; i_qp / 6
    lea       r10d, [r9*3]
    add       r10d, r10d
    sub       r7d, r10d         ; i_qp % 6
    shl       r7d, 6
    add       r6, r7
    mova      m0, [r6]
    mova      m1, [r6+32]
    mova [rsp+IRH_DMF   ], m0
    mova [rsp+IRH_DMF+32], m1
    xor       r7d, r7d
    sub       r9d, 4
    jge .shl
    neg       r9d
    inc       r7d
    vpbroadcastd m1, [pd_1]
    movd      xm0, r9d
    pslld     m1, xm0
    psrld     m1, 1
    mova [rsp+IRH_RND], m1
    jmp .init
.shl:
    movd      xm0, r9d
.init:
    mova [rsp+IRH_SHF], xm0
    mov [rsp+IRH_MODE], r7d
    ; r8: score, IRH_OFF: 4 without decimation (every nonzero 8x8 coded, no MB threshold)
    xor       r10d, r10d
    mov       r7d, 6
    test      r8d, r8d
    sets      r10b
    cmovs     r8d, r7d
    shl       r10d, 2
    mov [rsp+IRH_OFF], r10d
    mov       r9, r0
    lea       r0, [rsp+IRH_T]
    sub       r9, r0            ; level - dct buffer
    xor       r12d, r12d        ; nz of the coded 8x8s
    xor       r13d, r13d        ; 256 * 8x8
    xor       r14d, r14d        ; coded 8x8s | ac << 8
.loop:
    SUB8x8_DCT_HBD_LOAD
%if %3
    IR_ZSCREEN4 IRH_ZT, r10d
    cmp       r10d, 0x33
    je .zero
%else
    por       m5, m0, m1
    por       m6, m2, m3
    por       m5, m6
    ptest     m5, m5            ; no residual
    jz .zero
%endif
    SUB8x8_DCT_HBD_TX
    IRH_QUANT m0,   0
    IRH_QUANT m1,  32
    IRH_QUANT m2,  64
    IRH_QUANT m3,  96
    IRH_QUANT m4, 128
    IRH_QUANT m5, 160
    IRH_QUANT m6, 192
    IRH_QUANT m7, 224
    por       m8, m0, m1
    por       m9, m2, m3
    packssdw  m8, m9
    por       m9, m4, m5
    por       m10, m6, m7
    packssdw  m9, m10
    packssdw  m8, m9
    pxor      m15, m15
    pcmpeqd   m8, m15
    movmskps  r10d, m8
    mov       r11d, r10d
    shr       r10d, 4
    and       r10d, r11d
    xor       r10d, 0xf         ; nonzero blocks
    jz .zero
%if %2
    mova      m10, [qscan4_field]
%else
    mova      m10, [qscan4_frame_i]
    mova      m11, [qscan4_frame_j]
%endif
    IRH_SCAN_BLOCK %2, 0, m0, m1, m13
    IRH_SCAN_BLOCK %2, 1, m2, m3, m14
    packsswb  m13, m14
    IRH_SCAN_BLOCK %2, 2, m4, m5, m14
    IRH_SCAN_BLOCK %2, 3, m6, m7, m8
    packsswb  m14, m8
    mova      m8, [qscan4_bytes]
    vpermd    m13, m8, m13
    vpermd    m14, m8, m14
    ; score = sum over nonzero levels of [run<1] + [run<3] + [run<6], run = zeros below; 9 if a |level| > 1
    pabsb     m10, m13
    pabsb     m11, m14
    por       m10, m11
    psubusb   m10, [pb_1]
    pcmpeqb   m13, m15
    pcmpeqb   m14, m15
    pmovmskb  r3d, m13
    pmovmskb  r6d, m14
    shl       r6, 32
    or        r3, r6
    not       r3                ; nonzero levels in scan order, 16 bits per block
    lea       r6, [r3+r3]
    lea       r7, [r3*4]
    lea       r11, [r3*8]
    or        r7, r6
    or        r7, r11
    lea       r11, [r7*8]
    or        r11, r7
    mov       r10, 0x0001000100010001
    or        r6, r10
    mov       r10, 0x0007000700070007
    or        r7, r10
    mov       r10, 0x003f003f003f003f
    or        r11, r10
    and       r6, r3
    and       r7, r3
    and       r11, r3
    popcnt    r6, r6
    popcnt    r7, r7
    popcnt    r11, r11
    add       r6d, r7d
    add       r6d, r11d
    mov       r7d, 9
    cmp       r6d, r7d
    cmova     r6d, r7d
    ptest     m10, m10
    cmovnz    r6d, r7d          ; score
    mov       r10, 0xfffefffefffefffe
    xor       r7d, r7d
    test      r3, r10
    setnz     r7b               ; a nonzero ac level
    ; dequant
    pmaddwd   m0, [rsp+IRH_DMF   ]
    pmaddwd   m1, [rsp+IRH_DMF+32]
    pmaddwd   m2, [rsp+IRH_DMF   ]
    pmaddwd   m3, [rsp+IRH_DMF+32]
    pmaddwd   m4, [rsp+IRH_DMF   ]
    pmaddwd   m5, [rsp+IRH_DMF+32]
    pmaddwd   m6, [rsp+IRH_DMF   ]
    pmaddwd   m7, [rsp+IRH_DMF+32]
    cmp dword [rsp+IRH_MODE], 0
    jz .dq_shl
    mova      m8, [rsp+IRH_RND]
    paddd     m0, m8
    paddd     m1, m8
    paddd     m2, m8
    paddd     m3, m8
    paddd     m4, m8
    paddd     m5, m8
    paddd     m6, m8
    paddd     m7, m8
    mova      xm8, [rsp+IRH_SHF]
    psrad     m0, xm8
    psrad     m1, xm8
    psrad     m2, xm8
    psrad     m3, xm8
    psrad     m4, xm8
    psrad     m5, xm8
    psrad     m6, xm8
    psrad     m7, xm8
    jmp .dq_store
.dq_shl:
    mova      xm8, [rsp+IRH_SHF]
    pslld     m0, xm8
    pslld     m1, xm8
    pslld     m2, xm8
    pslld     m3, xm8
    pslld     m4, xm8
    pslld     m5, xm8
    pslld     m6, xm8
    pslld     m7, xm8
.dq_store:
    mova [rsp+r13+IRH_DQ+  0], m0
    mova [rsp+r13+IRH_DQ+ 32], m1
    mova [rsp+r13+IRH_DQ+ 64], m2
    mova [rsp+r13+IRH_DQ+ 96], m3
    mova [rsp+r13+IRH_DQ+128], m4
    mova [rsp+r13+IRH_DQ+160], m5
    mova [rsp+r13+IRH_DQ+192], m6
    mova [rsp+r13+IRH_DQ+224], m7
    ; nonzero blocks again, from the 16 bits per block
    mov       r10, 0x7fff7fff7fff7fff
    mov       r11, r3
    and       r11, r10
    add       r11, r10
    or        r11, r3
    mov       r10, 0x8000800080008000
    and       r11, r10
    mov       r10, 0x0000200040008001
    imul      r11, r10
    shr       r11, 60
    mov       r10d, r11d
    add       r8d, r6d
    add       r6d, [rsp+IRH_OFF]
    xor       r3d, r3d
    xor       r11d, r11d
    cmp       r6d, 4
    cmovae    r3d, r10d         ; nz of a coded 8x8
    setae     r11b
    shl       r7d, 11
    shl       r11d, 3
    or        r7d, r11d
    shl       r3d, 12
    shr       r12d, 4
    shr       r14d, 1
    or        r12d, r3d
    or        r14d, r7d
    jmp .next
.zero:
    shr       r12d, 4
    shr       r14d, 1
.next:
    add       r1, 8*SIZEOF_PIXEL
    add       r2, 8*SIZEOF_PIXEL
    add       r9, 256
    add       r13d, 256
    cmp       r13d, 512
    jne .next2
    add       r1, 8*FENC_STRIDEB-16*SIZEOF_PIXEL
    add       r2, 8*FDEC_STRIDEB-16*SIZEOF_PIXEL
.next2:
    cmp       r13d, 1024
    jl .loop

    ; MB decimation
    xor       r4d, r4d
    cmp       r8d, 6
    cmovl     r12d, r4d
    cmovl     r14d, r4d
    cmp dword [rsp+IRH_OFF], 0
    cmovnz    r8d, r4d
    shl       r8d, 4
    mov       r4d, r14d
    and       r4d, 0xf
    or        r8d, r4d          ; return value
    mov       r3, [rsp+IRH_NNZ]
    movd      xm0, r12d
    vpbroadcastw m0, xm0
    mova      m1, [ir_nnz_bits]
    pand      m0, m1
    pcmpeqw   m0, m1
    psrlw     m0, 15
    packuswb  m0, m0
    vextracti128 xm1, m0, 1
    movd [r3+0*8], xm0
    pextrd [r3+1*8], xm0, 1
    movd [r3+2*8], xm1
    pextrd [r3+3*8], xm1, 1
    test      r4d, r4d
    jz .end
    sub       r2, 8*FDEC_STRIDEB+16*SIZEOF_PIXEL ; p_dst
    mov       r9, r2
.recon:
    tzcnt     r5d, r4d
    mov       r6d, r5d
    and       r6d, 1
    mov       r7d, r5d
    shr       r7d, 1
    imul      r7d, 8*FDEC_STRIDEB
    lea       r0, [r9+r7]
    shl       r6d, 4
    add       r0, r6            ; dst of the 8x8
    mov       r6d, r5d
    shl       r6d, 8
    lea       r1, [rsp+r6+IRH_DQ]
    lea       r6d, [r5+8]
    bt        r14d, r6d
    jnc .dc
    ADD8x8_IDCT_HBD
    jmp .recon_next
.dc:
    movd      xm0, [r1+  0]
    pinsrd    xm0, [r1+ 64], 1
    pinsrd    xm0, [r1+128], 2
    pinsrd    xm0, [r1+192], 3
    paddd     xm0, [pd_32]
    psrad     xm0, 6            ; (dc+32)>>6
    packssdw  xm0, xm0
    punpcklwd xm0, xm0
    pshufd    xm1, xm0, q1100   ; rows 0-3
    pshufd    xm0, xm0, q3322   ; rows 4-7
    vinserti128 m1, m1, xm1, 1
    vinserti128 m0, m0, xm0, 1
    pxor      m5, m5
    mova      m7, [pw_pixel_max]
%assign irh_i 0
%rep 4
    movu         xm2, [r0+irh_i*FDEC_STRIDEB]
    vinserti128   m2, m2, [r0+(irh_i+1)*FDEC_STRIDEB], 1
%if irh_i < 4
    paddsw        m2, m1
%else
    paddsw        m2, m0
%endif
    CLIPW         m2, m5, m7
    movu [r0+irh_i*FDEC_STRIDEB], xm2
    vextracti128 [r0+(irh_i+1)*FDEC_STRIDEB], m2, 1
%assign irh_i irh_i+2
%endrep
.recon_next:
    blsr      r4d, r4d
    jnz .recon
.end:
    mov       eax, r8d
    RET
%endmacro

INIT_YMM avx2
INTER_RESID_4x4_HBD frame, 0, 1
INTER_RESID_4x4_HBD field, 1, 1
INTER_RESID_4x4_HBD a6_frame, 0, 0
INTER_RESID_4x4_HBD a6_field, 1, 0
%undef irh_i
%endif ; ARCH_X86_64

%else ; !HIGH_BIT_DEPTH

INIT_MMX mmx
cglobal add4x4_idct, 2,2
    pxor m7, m7
.skip_prologue:
    movq  m1, [r1+ 8]
    movq  m3, [r1+24]
    movq  m2, [r1+16]
    movq  m0, [r1+ 0]
    IDCT4_1D w,0,1,2,3,4,5
    TRANSPOSE4x4W 0,1,2,3,4
    paddw m0, [pw_32]
    IDCT4_1D w,0,1,2,3,4,5
    STORE_DIFF  m0, m4, m7, [r0+0*FDEC_STRIDE]
    STORE_DIFF  m1, m4, m7, [r0+1*FDEC_STRIDE]
    STORE_DIFF  m2, m4, m7, [r0+2*FDEC_STRIDE]
    STORE_DIFF  m3, m4, m7, [r0+3*FDEC_STRIDE]
    RET

%macro ADD4x4 0
cglobal add4x4_idct, 2,2,6
    mova      m1, [r1+0x00]     ; row1/row0
    mova      m3, [r1+0x10]     ; row3/row2
    psraw     m0, m1, 1         ; row1>>1/...
    psraw     m2, m3, 1         ; row3>>1/...
    movsd     m0, m1            ; row1>>1/row0
    movsd     m2, m3            ; row3>>1/row2
    psubw     m0, m3            ; row1>>1-row3/row0-2
    paddw     m2, m1            ; row3>>1+row1/row0+2
    SBUTTERFLY2 wd, 0, 2, 1
    SUMSUB_BA w, 2, 0, 1
    pshuflw   m1, m2, q2301
    pshufhw   m2, m2, q2301
    punpckldq m1, m0
    punpckhdq m2, m0
    SWAP       0, 1

    mova      m1, [pw_32_0]
    paddw     m1, m0            ; row1/row0 corrected
    psraw     m0, 1             ; row1>>1/...
    psraw     m3, m2, 1         ; row3>>1/...
    movsd     m0, m1            ; row1>>1/row0
    movsd     m3, m2            ; row3>>1/row2
    psubw     m0, m2            ; row1>>1-row3/row0-2
    paddw     m3, m1            ; row3>>1+row1/row0+2
    SBUTTERFLY2 qdq, 0, 3, 1
    SUMSUB_BA w, 3, 0, 1

    movd      m4, [r0+FDEC_STRIDE*0]
    movd      m1, [r0+FDEC_STRIDE*1]
    movd      m2, [r0+FDEC_STRIDE*2]
    movd      m5, [r0+FDEC_STRIDE*3]
    punpckldq m1, m4            ; row0/row1
    pxor      m4, m4
    punpckldq m2, m5            ; row3/row2
    punpcklbw m1, m4
    psraw     m3, 6
    punpcklbw m2, m4
    psraw     m0, 6
    paddsw    m3, m1
    paddsw    m0, m2
    packuswb  m0, m3            ; row0/row1/row3/row2
    pextrd   [r0+FDEC_STRIDE*0], m0, 3
    pextrd   [r0+FDEC_STRIDE*1], m0, 2
    movd     [r0+FDEC_STRIDE*2], m0
    pextrd   [r0+FDEC_STRIDE*3], m0, 1
    RET
%endmacro ; ADD4x4

INIT_XMM sse4
ADD4x4
INIT_XMM avx
ADD4x4

%macro STOREx2_AVX2 9
    movq      xm%3, [r0+%5*FDEC_STRIDE]
    vinserti128 m%3, m%3, [r0+%6*FDEC_STRIDE], 1
    movq      xm%4, [r0+%7*FDEC_STRIDE]
    vinserti128 m%4, m%4, [r0+%8*FDEC_STRIDE], 1
    punpcklbw  m%3, m%9
    punpcklbw  m%4, m%9
    psraw      m%1, 6
    psraw      m%2, 6
    paddsw     m%1, m%3
    paddsw     m%2, m%4
    packuswb   m%1, m%2
    vextracti128 xm%2, m%1, 1
    movq   [r0+%5*FDEC_STRIDE], xm%1
    movq   [r0+%6*FDEC_STRIDE], xm%2
    movhps [r0+%7*FDEC_STRIDE], xm%1
    movhps [r0+%8*FDEC_STRIDE], xm%2
%endmacro

INIT_YMM avx2
cglobal add8x8_idct, 2,3,8
    add    r0, 4*FDEC_STRIDE
    pxor   m7, m7
    TAIL_CALL .skip_prologue, 0
global current_function %+ .skip_prologue
.skip_prologue:
    ; TRANSPOSE4x4Q
    mova       xm0, [r1+ 0]
    mova       xm1, [r1+32]
    mova       xm2, [r1+16]
    mova       xm3, [r1+48]
    vinserti128 m0, m0, [r1+ 64], 1
    vinserti128 m1, m1, [r1+ 96], 1
    vinserti128 m2, m2, [r1+ 80], 1
    vinserti128 m3, m3, [r1+112], 1
    SBUTTERFLY qdq, 0, 1, 4
    SBUTTERFLY qdq, 2, 3, 4
    IDCT4_1D w,0,1,2,3,4,5
    TRANSPOSE2x4x4W 0,1,2,3,4
    paddw m0, [pw_32]
    IDCT4_1D w,0,1,2,3,4,5
    STOREx2_AVX2 0, 1, 4, 5, -4, 0, -3, 1, 7
    STOREx2_AVX2 2, 3, 4, 5, -2, 2, -1, 3, 7
    ret

; 2xdst, 2xtmp, 4xsrcrow, 1xhsub_mul: fenc, fdec byte pairs by pmaddubsw (1, -1)
%macro LOAD_DIFF8x2_AVX2 9
    movq    xm%1, [r1+%5*FENC_STRIDE]
    movq    xm%2, [r1+%6*FENC_STRIDE]
    vinserti128 m%1, m%1, [r1+%7*FENC_STRIDE], 1
    vinserti128 m%2, m%2, [r1+%8*FENC_STRIDE], 1
    movq    xm%3, [r2+(%5-4)*FDEC_STRIDE]
    movq    xm%4, [r2+(%6-4)*FDEC_STRIDE]
    vinserti128 m%3, m%3, [r2+(%7-4)*FDEC_STRIDE], 1
    vinserti128 m%4, m%4, [r2+(%8-4)*FDEC_STRIDE], 1
    punpcklbw m%1, m%3
    punpcklbw m%2, m%4
    pmaddubsw m%1, m%9
    pmaddubsw m%2, m%9
%endmacro

; 4x src row, 2x tmp, 2x offset
; In: row i of blocks A|B in lane 0 and of C|D in lane 1.
; Out: one 32 byte store per 4x4 block, so quant's 32 byte loads can forward from it.
%macro STORE_DCT_AVX2 8
    vperm2i128  m%5, m%1, m%3, 0x20 ; A0 B0 A2 B2
    vperm2i128  m%6, m%2, m%4, 0x20 ; A1 B1 A3 B3
    vperm2i128  m%1, m%1, m%3, 0x31 ; C0 D0 C2 D2
    vperm2i128  m%2, m%2, m%4, 0x31 ; C1 D1 C3 D3
    punpcklqdq  m%3, m%5, m%6       ; A
    punpckhqdq  m%5, m%6            ; B
    punpcklqdq  m%4, m%1, m%2       ; C
    punpckhqdq  m%1, m%2            ; D
    mova [r0+%7+ 0], m%3
    mova [r0+%7+32], m%5
    mova [r0+%8+ 0], m%4
    mova [r0+%8+32], m%1
%endmacro

INIT_YMM avx2
cglobal sub8x8_dct, 3,3,7
    mova m6, [hsub_mul]
    add r2, 4*FDEC_STRIDE
    LOAD_DIFF8x2_AVX2 0, 1, 4, 5, 0, 1, 4, 5, 6
    LOAD_DIFF8x2_AVX2 2, 3, 4, 5, 2, 3, 6, 7, 6
    DCT4_1D 0, 1, 2, 3, 4
    TRANSPOSE2x4x4W 0, 1, 2, 3, 4
    DCT4_1D 0, 1, 2, 3, 4
    STORE_DCT_AVX2 0, 1, 2, 3, 4, 5, 0, 64
    RET

INIT_YMM avx2
cglobal sub16x16_dct, 3,3,6
    add r0, 128
    add r2, 4*FDEC_STRIDE
    call .sub16x4_dct
    add r0, 64
    add r1, 4*FENC_STRIDE
    add r2, 4*FDEC_STRIDE
    call .sub16x4_dct
    add r0, 256-64
    add r1, 4*FENC_STRIDE
    add r2, 4*FDEC_STRIDE
    call .sub16x4_dct
    add r0, 64
    add r1, 4*FENC_STRIDE
    add r2, 4*FDEC_STRIDE
    call .sub16x4_dct
    RET
.sub16x4_dct:
    LOAD_DIFF16x2_AVX2 0, 1, 4, 5, 0, 1
    LOAD_DIFF16x2_AVX2 2, 3, 4, 5, 2, 3
    DCT4_1D 0, 1, 2, 3, 4
    TRANSPOSE2x4x4W 0, 1, 2, 3, 4
    DCT4_1D 0, 1, 2, 3, 4
    STORE_DCT_AVX2 0, 1, 2, 3, 4, 5, -128, 0
    ret

%macro DCT4x4_AVX512 0
    psubw      m0, m2            ; 0 1
    psubw      m1, m3            ; 3 2
    SUMSUB_BA   w, 1, 0, 2
    SBUTTERFLY wd, 1, 0, 2
    paddw      m2, m1, m0
    psubw      m3, m1, m0
    vpaddw     m2 {k1}, m1       ; 0+1+2+3 0<<1+1-2-3<<1
    vpsubw     m3 {k1}, m0       ; 0-1-2+3 0-1<<1+2<<1-3
    shufps     m1, m2, m3, q2323 ; a3 b3 a2 b2 c3 d3 c2 d2
    punpcklqdq m2, m3            ; a0 b0 a1 b1 c0 d0 c1 d1
    SUMSUB_BA   w, 1, 2, 3
    shufps     m3, m1, m2, q3131 ; a1+a2 b1+b2 c1+c2 d1+d2 a1-a2 b1-b2 b1-b2 d1-d2
    shufps     m1, m2, q2020     ; a0+a3 b0+b3 c0+c3 d0+d3 a0-a3 b0-b3 c0-c3 d0-d3
    paddw      m2, m1, m3
    psubw      m0, m1, m3
    vpaddw     m2 {k2}, m1       ; 0'+1'+2'+3' 0'<<1+1'-2'-3'<<1
    vpsubw     m0 {k2}, m3       ; 0'-1'-2'+3' 0'-1'<<1+2'<<1-3'
%endmacro

INIT_XMM avx512
cglobal sub4x4_dct
    mov         eax, 0xf0aa
    kmovw        k1, eax
    PROLOGUE 3,3
    movd         m0,      [r1+0*FENC_STRIDE]
    movd         m2,      [r2+0*FDEC_STRIDE]
    vpbroadcastd m0 {k1}, [r1+1*FENC_STRIDE]
    vpbroadcastd m2 {k1}, [r2+1*FDEC_STRIDE]
    movd         m1,      [r1+3*FENC_STRIDE]
    movd         m3,      [r2+3*FDEC_STRIDE]
    vpbroadcastd m1 {k1}, [r1+2*FENC_STRIDE]
    vpbroadcastd m3 {k1}, [r2+2*FDEC_STRIDE]
    kshiftrw     k2, k1, 8
    pxor         m4, m4
    punpcklbw    m0, m4
    punpcklbw    m2, m4
    punpcklbw    m1, m4
    punpcklbw    m3, m4
    DCT4x4_AVX512
    mova       [r0], m2
    mova    [r0+16], m0
    RET

INIT_ZMM avx512
cglobal dct4x4x4_internal
    punpcklbw  m0, m1, m4
    punpcklbw  m2, m3, m4
    punpckhbw  m1, m4
    punpckhbw  m3, m4
    DCT4x4_AVX512
    mova       m1, m2
    vshufi32x4 m2 {k2}, m0, m0, q2200 ; m0
    vshufi32x4 m0 {k3}, m1, m1, q3311 ; m1
    ret

%macro DCT8x8_LOAD_FENC_AVX512 4 ; dst, perm, row1, row2
    movu     %1,     [r1+%3*FENC_STRIDE]
    vpermt2d %1, %2, [r1+%4*FENC_STRIDE]
%endmacro

%macro DCT8x8_LOAD_FDEC_AVX512 5 ; dst, perm, tmp, row1, row2
    movu     %1,      [r2+(%4  )*FDEC_STRIDE]
    vmovddup %1 {k1}, [r2+(%4+2)*FDEC_STRIDE]
    movu     %3,      [r2+(%5  )*FDEC_STRIDE]
    vmovddup %3 {k1}, [r2+(%5+2)*FDEC_STRIDE]
    vpermt2d %1, %2, %3
%endmacro

cglobal sub8x8_dct, 3,3
    mova       m0, [dct_avx512]
    DCT8x8_LOAD_FENC_AVX512 m1, m0, 0, 4 ; 0 2 1 3
    mov       r1d, 0xaaaaaaaa
    kmovd      k1, r1d
    psrld      m0, 5
    DCT8x8_LOAD_FDEC_AVX512 m3, m0, m2, 0, 4
    mov       r1d, 0xf0f0f0f0
    kmovd      k2, r1d
    pxor      xm4, xm4
    knotw      k3, k2
    call dct4x4x4_internal_avx512
    mova     [r0], m0
    mova  [r0+64], m1
    RET

%macro SUB4x16_DCT_AVX512 2 ; dst, src
    vpermd   m1, m5, [r1+1*%2*64]
    mova     m3,     [r2+2*%2*64]
    vpermt2d m3, m6, [r2+2*%2*64+64]
    call dct4x4x4_internal_avx512
    mova [r0+%1*64    ], m0
    mova [r0+%1*64+128], m1
%endmacro

cglobal sub16x16_dct
    psrld    m5, [dct_avx512], 10
    mov     eax, 0xaaaaaaaa
    kmovd    k1, eax
    mov     eax, 0xf0f0f0f0
    kmovd    k2, eax
    PROLOGUE 3,3
    pxor    xm4, xm4
    knotw    k3, k2
    psrld    m6, m5, 4
    SUB4x16_DCT_AVX512 0, 0
    SUB4x16_DCT_AVX512 1, 1
    SUB4x16_DCT_AVX512 4, 2
    SUB4x16_DCT_AVX512 5, 3
    RET

cglobal sub8x8_dct_dc, 3,3
    mova         m3, [dct_avx512]
    DCT8x8_LOAD_FENC_AVX512 m0, m3, 0, 4 ; 0 2 1 3
    mov         r1d, 0xaa
    kmovb        k1, r1d
    psrld        m3, 5
    DCT8x8_LOAD_FDEC_AVX512 m1, m3, m2, 0, 4
    pxor        xm3, xm3
    psadbw       m0, m3
    psadbw       m1, m3
    psubw        m0, m1
    vpmovqw    xmm0, m0
    vprold     xmm1, xmm0, 16
    paddw      xmm0, xmm1       ; 0 0 2 2 1 1 3 3
    punpckhqdq xmm2, xmm0, xmm0
    psubw      xmm1, xmm0, xmm2 ; 0-1 0-1 2-3 2-3
    paddw      xmm0, xmm2       ; 0+1 0+1 2+3 2+3
    punpckldq  xmm0, xmm1       ; 0+1 0+1 0-1 0-1 2+3 2+3 2-3 2-3
    punpcklqdq xmm1, xmm0, xmm0
    vpsubw     xmm0 {k1}, xm3, xmm0
    paddw      xmm0, xmm1       ; 0+1+2+3 0+1-2-3 0-1+2-3 0-1-2+3
    movhps     [r0], xmm0
    RET

cglobal sub8x16_dct_dc, 3,3
    mova         m5, [dct_avx512]
    DCT8x8_LOAD_FENC_AVX512 m0, m5, 0, 8  ; 0 4 1 5
    DCT8x8_LOAD_FENC_AVX512 m1, m5, 4, 12 ; 2 6 3 7
    mov         r1d, 0xaa
    kmovb        k1, r1d
    psrld        m5, 5
    DCT8x8_LOAD_FDEC_AVX512 m2, m5, m4, 0, 8
    DCT8x8_LOAD_FDEC_AVX512 m3, m5, m4, 4, 12
    pxor        xm4, xm4
    psadbw       m0, m4
    psadbw       m1, m4
    psadbw       m2, m4
    psadbw       m3, m4
    psubw        m0, m2
    psubw        m1, m3
    SBUTTERFLY  qdq, 0, 1, 2
    paddw        m0, m1
    vpmovqw    xmm0, m0         ; 0 2 4 6 1 3 5 7
    psrlq      xmm2, xmm0, 32
    psubw      xmm1, xmm0, xmm2 ; 0-4 2-6 1-5 3-7
    paddw      xmm0, xmm2       ; 0+4 2+6 1+5 3+7
    punpckhdq  xmm2, xmm0, xmm1
    punpckldq  xmm0, xmm1
    psubw      xmm1, xmm0, xmm2 ; 0-1+4-5 2-3+6-7 0-1-4+5 2-3-6+7
    paddw      xmm0, xmm2       ; 0+1+4+5 2+3+6+7 0+1-4-5 2+3-6-7
    punpcklwd  xmm0, xmm1
    psrlq      xmm2, xmm0, 32
    psubw      xmm1, xmm0, xmm2 ; 0+1-2-3+4+5-6-7 0-1-2+3+4-5-6+7 0+1-2-3-4-5+6+7 0-1-2+3-4+5+6-7
    paddw      xmm0, xmm2       ; 0+1+2+3+4+5+6+7 0-1+2-3+4-5+6-7 0+1+2+3-4-5-6-7 0-1+2-3-4+5-6+7
    shufps     xmm0, xmm1, q0220
    mova       [r0], xmm0
    RET

%macro SARSUMSUB 3 ; a, b, tmp
    mova    m%3, m%1
    vpsraw  m%1 {k1}, 1
    psubw   m%1, m%2    ; 0-2 1>>1-3
    vpsraw  m%2 {k1}, 1
    paddw   m%2, m%3    ; 0+2 1+3>>1
%endmacro

cglobal add8x8_idct, 2,2
    mova            m1, [r1]
    mova            m2, [r1+64]
    mova            m3, [dct_avx512]
    vbroadcasti32x4 m4, [pw_32]
    mov            r1d, 0xf0f0f0f0
    kxnorb          k2, k2, k2
    kmovd           k1, r1d
    kmovb           k3, k2
    vshufi32x4      m0, m1, m2, q2020 ; 0 1   4 5   8 9   c d
    vshufi32x4      m1, m2, q3131     ; 2 3   6 7   a b   e f
    psrlq           m5, m3, 56        ; {0, 3, 1, 2, 4, 7, 5, 6} * FDEC_STRIDE
    vpgatherqq      m6 {k2}, [r0+m5]
    SARSUMSUB        0, 1, 2
    SBUTTERFLY      wd, 1, 0, 2
    psrlq           m7, m3, 28
    SUMSUB_BA        w, 0, 1, 2       ; 0+1+2+3>>1 0+1>>1-2-3
    vprold          m1, 16            ; 0-1>>1-2+3 0-1+2-3>>1
    SBUTTERFLY      dq, 0, 1, 2
    psrlq           m3, 24
    SARSUMSUB        0, 1, 2
    vpermi2q        m3, m1, m0
    vpermt2q        m1, m7, m0
    paddw           m3, m4            ; += 32
    SUMSUB_BA        w, 1, 3, 0
    psraw           m1, 6             ; 0'+1'+2'+3'>>1 0'+1'>>1-2'-3'
    psraw           m3, 6             ; 0'-1'+2'-3'>>1 0'-1'>>1-2'+3'
    pxor           xm0, xm0
    SBUTTERFLY      bw, 6, 0, 2
    paddsw          m1, m6
    paddsw          m3, m0
    packuswb        m1, m3
    vpscatterqq [r0+m5] {k3}, m1
    RET

; fdec rows as qwords {0 3 1 2 4 7 5 6}, the order the packuswb output comes in
%macro ADD8x8_IDCT_ZMM_INIT 0
    mova            m8, [dct_avx512]
    vbroadcasti32x4 m9, [pw_32]
    psrlq          m13, m8, 28
    psrlq          m14, m8, 24
    mov            r2d, 0xf0f0f0f0
    kmovd           k1, r2d
%endmacro

%macro ADD8x8_IDCT_ZMM 0
    movq           xm6, [r0+0*FDEC_STRIDE]
    movhps         xm6, [r0+3*FDEC_STRIDE]
    movq           xm7, [r0+1*FDEC_STRIDE]
    movhps         xm7, [r0+2*FDEC_STRIDE]
    movq           xm4, [r0+4*FDEC_STRIDE]
    movhps         xm4, [r0+7*FDEC_STRIDE]
    movq           xm5, [r0+5*FDEC_STRIDE]
    movhps         xm5, [r0+6*FDEC_STRIDE]
    vinserti32x4   ym6, ym6, xm7, 1
    vinserti32x4   ym4, ym4, xm5, 1
    vinserti64x4    m6, m6, ym4, 1
    mova            m1, [r1]
    mova            m2, [r1+64]
    vshufi32x4      m0, m1, m2, q2020 ; 0 1   4 5   8 9   c d
    vshufi32x4      m1, m2, q3131     ; 2 3   6 7   a b   e f
    SARSUMSUB        0, 1, 2
    SBUTTERFLY      wd, 1, 0, 2
    SUMSUB_BA        w, 0, 1, 2       ; 0+1+2+3>>1 0+1>>1-2-3
    vprold          m1, 16            ; 0-1>>1-2+3 0-1+2-3>>1
    SBUTTERFLY      dq, 0, 1, 2
    mova            m3, m14
    SARSUMSUB        0, 1, 2
    vpermi2q        m3, m1, m0
    vpermt2q        m1, m13, m0
    paddw           m3, m9            ; += 32
    SUMSUB_BA        w, 1, 3, 0
    psraw           m1, 6             ; 0'+1'+2'+3'>>1 0'+1'>>1-2'-3'
    psraw           m3, 6             ; 0'-1'+2'-3'>>1 0'-1'>>1-2'+3'
    pxor           xm0, xm0
    SBUTTERFLY      bw, 6, 0, 2
    paddsw          m1, m6
    paddsw          m3, m0
    packuswb        m1, m3
    vextracti32x4  xm0, m1, 1
    vextracti32x4  xm2, m1, 2
    vextracti32x4  xm3, m1, 3
    movq   [r0+0*FDEC_STRIDE], xm1
    movhps [r0+3*FDEC_STRIDE], xm1
    movq   [r0+1*FDEC_STRIDE], xm0
    movhps [r0+2*FDEC_STRIDE], xm0
    movq   [r0+4*FDEC_STRIDE], xm2
    movhps [r0+7*FDEC_STRIDE], xm2
    movq   [r0+5*FDEC_STRIDE], xm3
    movhps [r0+6*FDEC_STRIDE], xm3
%endmacro

; the avx512 versions above without vpgatherqq/vpscatterqq
%if ARCH_X86_64
INIT_ZMM avx512icl
cglobal add8x8_idct, 2,3,15
    ADD8x8_IDCT_ZMM_INIT
    ADD8x8_IDCT_ZMM
    RET

cglobal add16x16_idct, 2,3,15
    ADD8x8_IDCT_ZMM_INIT
    call .add8x8
    add             r0, 8
    add             r1, 128
    call .add8x8
    add             r0, 8*FDEC_STRIDE-8
    add             r1, 128
    call .add8x8
    add             r0, 8
    add             r1, 128
    call .add8x8
    RET
.add8x8:
    ADD8x8_IDCT_ZMM
    ret
%endif ; ARCH_X86_64

%if ARCH_X86_64
;-----------------------------------------------------------------------------
; int inter_resid_4x4( dctcoef level[16][16], pixel *p_src, pixel *p_dst, uint8_t *nnz, udctcoef mf[16],
;                      udctcoef bias[16], int dequant_mf[6][16], int i_qp, int i_decimate_mb,
;                      const uint32_t zthr[4] )
;-----------------------------------------------------------------------------
; sub8x8_dct, quant_4x4x4_scan and dequant per 8x8, then the decimation, nnz and the idct of the coded 8x8s
; (dc-only 8x8s by add8x8_idct_dc). Returns the coded 8x8s | the summed score << 4 (0 without decimation).
%define IR_DQ   0          ; dequantised coefs, 128 bytes per 8x8
%define IR_DUMP  512        ; levels of zero blocks
%define IR_RND   640        ; dequant rounding and shift if not exact
%define IR_SHF   672
%define IR_MODE  688
%define IR_ZT    704        ; zero screen thresholds, broadcast
%define IR_SIZE  768

; dst1, dst2, row a, row b: fenc - fdec of rows a, b | a+4, b+4; m4, m5 tmp
%macro IR_LOAD_DIFF8x2 4
    movq        xm%1, [r1+%3*FENC_STRIDE]
    movq        xm%2, [r1+%4*FENC_STRIDE]
    vinserti128  m%1, m%1, [r1+(%3+4)*FENC_STRIDE], 1
    vinserti128  m%2, m%2, [r1+(%4+4)*FENC_STRIDE], 1
    movq         xm4, [r2+%3*FDEC_STRIDE]
    movq         xm5, [r2+%4*FDEC_STRIDE]
    vinserti128   m4, m4, [r2+(%3+4)*FDEC_STRIDE], 1
    vinserti128   m5, m5, [r2+(%4+4)*FDEC_STRIDE], 1
    punpcklbw    m%1, m4
    punpcklbw    m%2, m5
    pmaddubsw    m%1, [hsub_mul]
    pmaddubsw    m%2, [hsub_mul]
%endmacro

; block, src: to level if the block is nonzero (r9), else to the dump
%macro IR_STORE_LEVEL 2
    bt        r9d, %1
    sbb       r4, r4
    and       r4, r0
    mova [rsp+r4+IR_DUMP+32*%1], %2
%endmacro

; as STOREx2_AVX2, dst r7
%macro IR_STOREx2 8 ; 2x src, 2x tmp, 4x row
    movq        xm%3, [r7+%5*FDEC_STRIDE]
    vinserti128  m%3, m%3, [r7+%6*FDEC_STRIDE], 1
    movq        xm%4, [r7+%7*FDEC_STRIDE]
    vinserti128  m%4, m%4, [r7+%8*FDEC_STRIDE], 1
    punpcklbw    m%3, m12
    punpcklbw    m%4, m12
    psraw        m%1, 6
    psraw        m%2, 6
    paddsw       m%1, m%3
    paddsw       m%2, m%4
    packuswb     m%1, m%2
    vextracti128 xm%2, m%1, 1
    movq   [r7+%5*FDEC_STRIDE], xm%1
    movq   [r7+%6*FDEC_STRIDE], xm%2
    movhps [r7+%7*FDEC_STRIDE], xm%1
    movhps [r7+%8*FDEC_STRIDE], xm%2
%endmacro

; dst, tmp; m13: dmf, m10: rounding, xm11: shift
%macro IR_DEQUANT_ROUND 2
    pmullw    %2, %1, m13
    pmulhw    %1, m13
    punpckhwd m9, %2, %1
    punpcklwd %1, %2, %1
    paddd     %1, m10
    paddd     m9, m10
    psrad     %1, xm11
    psrad     m9, xm11
    packssdw  %1, m9
%endmacro

%macro INTER_RESID_4x4 3 ; name, field, zero screen (else A6)
cglobal inter_resid_4x4_%1, 9,15,16,-IR_SIZE
%if %3
    IR_ZSCREEN_INIT IR_ZT
%endif
    mova      m15, [r4]
    mova      m14, [r5]
    imul      r4d, r7d, 0x2b
    shr       r4d, 8            ; i_qp / 6
    lea       r5d, [r4*3]
    add       r5d, r5d
    sub       r7d, r5d          ; i_qp % 6
    shl       r7d, 6
    add       r6, r7
    mova      m13, [r6]
    packssdw  m13, [r6+32]
    vpermq    m13, m13, q3120   ; dmf as words
    xor       r7d, r7d
    sub       r4d, 4
    jl .rshift
    movd      xm0, r4d
    psllw     m13, xm0
    jmp .init
.rshift:
    ; exact if dmf is divisible by 1<<shift (flat): multiply by dmf>>shift like dequant_4x4_flat16
    neg       r4d
    movd      xm0, r4d
    pcmpeqw   m1, m1
    mov       r5d, 16
    sub       r5d, r4d
    movd      xm2, r5d
    psrlw     m1, xm2
    ptest     m13, m1
    jnz .rshift_round
    psrlw     m13, xm0
    jmp .init
.rshift_round:
    inc       r7d
    mova [rsp+IR_SHF], xm0
    mova      m1, [pd_1]
    pslld     m1, xm0
    psrld     m1, 1
    mova [rsp+IR_RND], m1
.init:
    mov  [rsp+IR_MODE], r7d
    pxor      m12, m12
    ; r8: score, r10: 4 without decimation (every nonzero 8x8 coded, no MB threshold)
    xor       r10d, r10d
    mov       r4d, 6
    test      r8d, r8d
    sets      r10b
    cmovs     r8d, r4d
    shl       r10d, 2
    lea       r4, [rsp+IR_DUMP]
    sub       r0, r4            ; level - dump
    xor       r12d, r12d        ; nz of the coded 8x8s
    xor       r13d, r13d        ; 128 * 8x8
    xor       r14d, r14d        ; coded 8x8s | ac << 8
.loop:
    IR_LOAD_DIFF8x2 0, 1, 0, 1
    IR_LOAD_DIFF8x2 2, 3, 2, 3
%if %3
    IR_ZSCREEN4 IR_ZT, r4d
    cmp       r4d, 0x33
    je .zero
%else
    por       m4, m0, m1
    por       m5, m2, m3
    por       m4, m5
    ptest     m4, m4            ; no residual
    jz .zero
%endif
    DCT4_1D 0, 1, 2, 3, 4
    TRANSPOSE2x4x4W 0, 1, 2, 3, 4
    DCT4_1D 0, 1, 2, 3, 4
    vperm2i128 m4, m0, m2, 0x20 ; A0 B0 A2 B2
    vperm2i128 m5, m1, m3, 0x20 ; A1 B1 A3 B3
    vperm2i128 m6, m0, m2, 0x31 ; C0 D0 C2 D2
    vperm2i128 m7, m1, m3, 0x31 ; C1 D1 C3 D3
    punpcklqdq m0, m4, m5
    punpckhqdq m1, m4, m5
    punpcklqdq m2, m6, m7
    punpckhqdq m3, m6, m7
    pabsw     m4, m0
    pabsw     m5, m1
    pabsw     m6, m2
    pabsw     m7, m3
    paddusw   m4, m14
    paddusw   m5, m14
    paddusw   m6, m14
    paddusw   m7, m14
    pmulhuw   m4, m15
    pmulhuw   m5, m15
    pmulhuw   m6, m15
    pmulhuw   m7, m15
    psignw    m0, m4, m0
    psignw    m1, m5, m1
    psignw    m2, m6, m2
    psignw    m3, m7, m3
    packssdw  m4, m0, m1
    packssdw  m5, m2, m3
    packssdw  m4, m5
    pcmpeqd   m4, m12
    movmskps  r9d, m4
    mov       r4d, r9d
    shr       r9d, 4
    and       r9d, r4d
    xor       r9d, 0xf          ; nonzero blocks
    jz .zero
%if %2
    mova      m8, [qscan4_field]
    pshufb    m4, m0, m8
    pshufb    m5, m1, m8
    pshufb    m6, m2, m8
    pshufb    m7, m3, m8
%else
    mova      m10, [qscan4_frame_a]
    mova      m11, [qscan4_frame_b]
    vperm2i128 m8, m0, m0, 0x01
    vperm2i128 m9, m1, m1, 0x01
    pshufb    m4, m0, m10
    pshufb    m5, m1, m10
    pshufb    m8, m11
    pshufb    m9, m11
    por       m4, m8
    por       m5, m9
    vperm2i128 m8, m2, m2, 0x01
    vperm2i128 m9, m3, m3, 0x01
    pshufb    m6, m2, m10
    pshufb    m7, m3, m10
    pshufb    m8, m11
    pshufb    m9, m11
    por       m6, m8
    por       m7, m9
%endif
    IR_STORE_LEVEL 0, m4
    IR_STORE_LEVEL 1, m5
    IR_STORE_LEVEL 2, m6
    IR_STORE_LEVEL 3, m7
    ; score = sum over nonzero levels of [run<1] + [run<3] + [run<6], run = zeros below; 9 if a |level| > 1
    packsswb  m8, m4, m5
    packsswb  m9, m6, m7
    vpermq    m8, m8, q3120
    vpermq    m9, m9, q3120
    pabsb     m10, m8
    pabsb     m11, m9
    por       m10, m11
    psubusb   m10, [pb_1]
    pcmpeqb   m8, m12
    pcmpeqb   m9, m12
    pmovmskb  r4d, m8
    pmovmskb  r5d, m9
    shl       r5, 32
    or        r4, r5
    not       r4                ; nonzero levels in scan order, 16 bits per block
    lea       r5, [r4+r4]
    lea       r6, [r4*4]
    lea       r7, [r4*8]
    or        r6, r5
    or        r6, r7
    lea       r7, [r6*8]
    or        r7, r6
    mov       r11, 0x0001000100010001
    or        r5, r11
    mov       r11, 0x0007000700070007
    or        r6, r11
    mov       r11, 0x003f003f003f003f
    or        r7, r11
    and       r5, r4
    and       r6, r4
    and       r7, r4
    popcnt    r5, r5
    popcnt    r6, r6
    popcnt    r7, r7
    add       r5d, r6d
    add       r5d, r7d
    mov       r6d, 9
    cmp       r5d, r6d
    cmova     r5d, r6d
    ptest     m10, m10
    cmovnz    r5d, r6d
    mov       r11, 0xfffefffefffefffe
    xor       r6d, r6d
    test      r4, r11
    setnz     r6b               ; a nonzero ac level
    ; dequant
    cmp dword [rsp+IR_MODE], 0
    jz .dq_flat
    mova      m10, [rsp+IR_RND]
    mova     xm11, [rsp+IR_SHF]
    IR_DEQUANT_ROUND m0, m4
    IR_DEQUANT_ROUND m1, m4
    IR_DEQUANT_ROUND m2, m4
    IR_DEQUANT_ROUND m3, m4
    jmp .dq_store
.dq_flat:
    pmullw    m0, m13
    pmullw    m1, m13
    pmullw    m2, m13
    pmullw    m3, m13
.dq_store:
    mova [rsp+r13+IR_DQ+ 0], m0
    mova [rsp+r13+IR_DQ+32], m1
    mova [rsp+r13+IR_DQ+64], m2
    mova [rsp+r13+IR_DQ+96], m3
    add       r8d, r5d
    add       r5d, r10d
    xor       r4d, r4d
    xor       r7d, r7d
    cmp       r5d, 4
    cmovae    r4d, r9d          ; nz of a coded 8x8
    setae     r7b
    shl       r6d, 11
    shl       r7d, 3
    or        r6d, r7d
    shl       r4d, 12
    shr       r12d, 4
    shr       r14d, 1
    or        r12d, r4d
    or        r14d, r6d
    jmp .next
.zero:
    shr       r12d, 4
    shr       r14d, 1
.next:
    add       r1, 8
    add       r2, 8
    sub       r0, -128
    add       r13d, 128
    cmp       r13d, 256
    jne .next2
    add       r1, 8*FENC_STRIDE-16
    add       r2, 8*FDEC_STRIDE-16
.next2:
    cmp       r13d, 512
    jl .loop

    ; MB decimation
    xor       r4d, r4d
    cmp       r8d, 6
    cmovl     r12d, r4d
    cmovl     r14d, r4d
    test      r10d, r10d
    cmovnz    r8d, r4d
    shl       r8d, 4
    mov       r4d, r14d
    and       r4d, 0xf
    or        r8d, r4d          ; return value
    movd      xm0, r12d
    vpbroadcastw m0, xm0
    mova      m1, [ir_nnz_bits]
    pand      m0, m1
    pcmpeqw   m0, m1
    psrlw     m0, 15
    packuswb  m0, m0
    vextracti128 xm1, m0, 1
    movd [r3+0*8], xm0
    pextrd [r3+1*8], xm0, 1
    movd [r3+2*8], xm1
    pextrd [r3+3*8], xm1, 1
    test      r4d, r4d
    jz .end
    sub       r2, 4*FDEC_STRIDE+16 ; p_dst + 4*FDEC_STRIDE
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
    lea       r6, [rsp+r6+IR_DQ]
    lea       r9d, [r5+8]
    bt        r14d, r9d
    jnc .dc
    mova      xm0, [r6+ 0]
    mova      xm1, [r6+32]
    mova      xm2, [r6+16]
    mova      xm3, [r6+48]
    vinserti128 m0, m0, [r6+ 64], 1
    vinserti128 m1, m1, [r6+ 96], 1
    vinserti128 m2, m2, [r6+ 80], 1
    vinserti128 m3, m3, [r6+112], 1
    SBUTTERFLY qdq, 0, 1, 4
    SBUTTERFLY qdq, 2, 3, 4
    IDCT4_1D w,0,1,2,3,4,5
    TRANSPOSE2x4x4W 0,1,2,3,4
    paddw     m0, [pw_32]
    IDCT4_1D w,0,1,2,3,4,5
    IR_STOREx2 0, 1, 4, 5, -4, 0, -3, 1
    IR_STOREx2 2, 3, 4, 5, -2, 2, -1, 3
    jmp .recon_next
.dc:
    movd      xm0, [r6+ 0]
    pinsrw    xm0, [r6+32], 1
    pinsrw    xm0, [r6+64], 2
    pinsrw    xm0, [r6+96], 3
    pmulhrsw  xm0, [pw_512]     ; (dc+32)>>6
    psubw     xm1, xm12, xm0
    packuswb  xm0, xm0
    packuswb  xm1, xm1
    pshufb    xm0, [pb_unpackbd1]
    pshufb    xm1, [pb_unpackbd1]
    punpcklqdq xm2, xm0, xm0
    punpckhqdq xm0, xm0
    punpcklqdq xm3, xm1, xm1
    punpckhqdq xm1, xm1
%assign ir_i -4
%rep 4
    movq      xm4, [r7+(ir_i+0)*FDEC_STRIDE]
    movhps    xm4, [r7+(ir_i+1)*FDEC_STRIDE]
%if ir_i < 0
    paddusb   xm4, xm2
    psubusb   xm4, xm3
%else
    paddusb   xm4, xm0
    psubusb   xm4, xm1
%endif
    movq   [r7+(ir_i+0)*FDEC_STRIDE], xm4
    movhps [r7+(ir_i+1)*FDEC_STRIDE], xm4
%assign ir_i ir_i+2
%endrep
.recon_next:
    blsr      r4d, r4d
    jnz .recon
.end:
    mov       eax, r8d
    RET
%endmacro

INIT_YMM avx2
INTER_RESID_4x4 frame, 0, 1
INTER_RESID_4x4 field, 1, 1
INTER_RESID_4x4 a6_frame, 0, 0
INTER_RESID_4x4 a6_field, 1, 0
%endif ; ARCH_X86_64
%endif ; HIGH_BIT_DEPTH

INIT_MMX
;-----------------------------------------------------------------------------
; void sub8x8_dct( int16_t dct[4][4][4], uint8_t *pix1, uint8_t *pix2 )
;-----------------------------------------------------------------------------
%macro SUB_NxN_DCT 7
cglobal %1, 3,3,%7
%if HIGH_BIT_DEPTH == 0
%if mmsize == 8
    pxor m7, m7
%else
    add r2, 4*FDEC_STRIDE
    mova m7, [hsub_mul]
%endif
%endif ; !HIGH_BIT_DEPTH
.skip_prologue:
    call %2.skip_prologue
    add  r0, %3
    add  r1, %4-%5-%6*FENC_STRIDE
    add  r2, %4-%5-%6*FDEC_STRIDE
    call %2.skip_prologue
    add  r0, %3
    add  r1, (%4-%6)*FENC_STRIDE-%5-%4
    add  r2, (%4-%6)*FDEC_STRIDE-%5-%4
    call %2.skip_prologue
    add  r0, %3
    add  r1, %4-%5-%6*FENC_STRIDE
    add  r2, %4-%5-%6*FDEC_STRIDE
    TAIL_CALL %2.skip_prologue, 1
%endmacro

;-----------------------------------------------------------------------------
; void add8x8_idct( uint8_t *pix, int16_t dct[4][4][4] )
;-----------------------------------------------------------------------------
%macro ADD_NxN_IDCT 6-7
%if HIGH_BIT_DEPTH
cglobal %1, 2,2,%7
%if %3==256
    add r1, 128
%endif
%else
cglobal %1, 2,2,11
    pxor m7, m7
%endif
%if mmsize>=16 && %3!=256
    add  r0, 4*FDEC_STRIDE
%endif
.skip_prologue:
    call %2.skip_prologue
    add  r0, %4-%5-%6*FDEC_STRIDE
    add  r1, %3
    call %2.skip_prologue
    add  r0, (%4-%6)*FDEC_STRIDE-%5-%4
    add  r1, %3
    call %2.skip_prologue
    add  r0, %4-%5-%6*FDEC_STRIDE
    add  r1, %3
    TAIL_CALL %2.skip_prologue, 1
%endmacro

%if HIGH_BIT_DEPTH
INIT_MMX
SUB_NxN_DCT  sub8x8_dct_mmx,     sub4x4_dct_mmx,   64,  8, 0, 0, 0
SUB_NxN_DCT  sub16x16_dct_mmx,   sub8x8_dct_mmx,   64, 16, 8, 8, 0
INIT_XMM
ADD_NxN_IDCT add8x8_idct_sse2,   add4x4_idct_sse2, 64,  8, 0, 0, 6
ADD_NxN_IDCT add16x16_idct_sse2, add8x8_idct_sse2, 64, 16, 8, 8, 6
ADD_NxN_IDCT add8x8_idct_avx,    add4x4_idct_avx,  64,  8, 0, 0, 6
ADD_NxN_IDCT add16x16_idct_avx,  add8x8_idct_avx,  64, 16, 8, 8, 6
cextern add8x8_idct8_sse2.skip_prologue
cextern add8x8_idct8_avx.skip_prologue
ADD_NxN_IDCT add16x16_idct8_sse2, add8x8_idct8_sse2, 256, 16, 0, 0, 16
ADD_NxN_IDCT add16x16_idct8_avx,  add8x8_idct8_avx,  256, 16, 0, 0, 16
cextern sub8x8_dct8_sse2.skip_prologue
cextern sub8x8_dct8_sse4.skip_prologue
cextern sub8x8_dct8_avx.skip_prologue
SUB_NxN_DCT  sub16x16_dct8_sse2, sub8x8_dct8_sse2, 256, 16, 0, 0, 14
SUB_NxN_DCT  sub16x16_dct8_sse4, sub8x8_dct8_sse4, 256, 16, 0, 0, 14
SUB_NxN_DCT  sub16x16_dct8_avx,  sub8x8_dct8_avx,  256, 16, 0, 0, 14
%if ARCH_X86_64
INIT_YMM
cextern add8x8_idct8_avx2.skip_prologue
ADD_NxN_IDCT add16x16_idct8_avx2, add8x8_idct8_avx2, 256, 16, 0, 0, 11
cextern sub8x8_dct8_avx2.skip_prologue
SUB_NxN_DCT  sub16x16_dct8_avx2, sub8x8_dct8_avx2, 256, 16, 0, 0, 10
%endif
%else ; !HIGH_BIT_DEPTH
%if ARCH_X86_64 == 0
INIT_MMX
SUB_NxN_DCT  sub8x8_dct_mmx,     sub4x4_dct_mmx,   32, 4, 0, 0, 0
ADD_NxN_IDCT add8x8_idct_mmx,    add4x4_idct_mmx,  32, 4, 0, 0
SUB_NxN_DCT  sub16x16_dct_mmx,   sub8x8_dct_mmx,   32, 8, 4, 4, 0
ADD_NxN_IDCT add16x16_idct_mmx,  add8x8_idct_mmx,  32, 8, 4, 4

cextern sub8x8_dct8_mmx.skip_prologue
cextern add8x8_idct8_mmx.skip_prologue
SUB_NxN_DCT  sub16x16_dct8_mmx,  sub8x8_dct8_mmx,  128, 8, 0, 0, 0
ADD_NxN_IDCT add16x16_idct8_mmx, add8x8_idct8_mmx, 128, 8, 0, 0
%endif

INIT_XMM
cextern sub8x8_dct_sse2.skip_prologue
cextern sub8x8_dct_ssse3.skip_prologue
cextern sub8x8_dct_avx.skip_prologue
cextern sub8x8_dct_xop.skip_prologue
SUB_NxN_DCT  sub16x16_dct_sse2,  sub8x8_dct_sse2,  128, 8, 0, 0, 10
SUB_NxN_DCT  sub16x16_dct_ssse3, sub8x8_dct_ssse3, 128, 8, 0, 0, 10
SUB_NxN_DCT  sub16x16_dct_avx,   sub8x8_dct_avx,   128, 8, 0, 0, 10
SUB_NxN_DCT  sub16x16_dct_xop,   sub8x8_dct_xop,   128, 8, 0, 0, 10

cextern add8x8_idct_sse2.skip_prologue
cextern add8x8_idct_avx.skip_prologue
ADD_NxN_IDCT add16x16_idct_sse2, add8x8_idct_sse2, 128, 8, 0, 0
ADD_NxN_IDCT add16x16_idct_avx,  add8x8_idct_avx,  128, 8, 0, 0

cextern add8x8_idct8_sse2.skip_prologue
cextern add8x8_idct8_avx.skip_prologue
ADD_NxN_IDCT add16x16_idct8_sse2, add8x8_idct8_sse2, 128, 8, 0, 0
ADD_NxN_IDCT add16x16_idct8_avx,  add8x8_idct8_avx,  128, 8, 0, 0

cextern sub8x8_dct8_sse2.skip_prologue
cextern sub8x8_dct8_ssse3.skip_prologue
cextern sub8x8_dct8_avx.skip_prologue
SUB_NxN_DCT  sub16x16_dct8_sse2,  sub8x8_dct8_sse2,  128, 8, 0, 0, 11
SUB_NxN_DCT  sub16x16_dct8_ssse3, sub8x8_dct8_ssse3, 128, 8, 0, 0, 11
SUB_NxN_DCT  sub16x16_dct8_avx,   sub8x8_dct8_avx,   128, 8, 0, 0, 11

INIT_YMM
ADD_NxN_IDCT add16x16_idct_avx2, add8x8_idct_avx2, 128, 8, 0, 0
%endif ; HIGH_BIT_DEPTH

%if HIGH_BIT_DEPTH
;-----------------------------------------------------------------------------
; void add8x8_idct_dc( pixel *p_dst, dctcoef *dct2x2 )
;-----------------------------------------------------------------------------
%macro ADD_DC 2
    mova    m0, [%1+FDEC_STRIDEB*0] ; 8pixels
    mova    m1, [%1+FDEC_STRIDEB*1]
    mova    m2, [%1+FDEC_STRIDEB*2]
    paddsw  m0, %2
    paddsw  m1, %2
    paddsw  m2, %2
    paddsw  %2, [%1+FDEC_STRIDEB*3]
    CLIPW   m0, m5, m6
    CLIPW   m1, m5, m6
    CLIPW   m2, m5, m6
    CLIPW   %2, m5, m6
    mova    [%1+FDEC_STRIDEB*0], m0
    mova    [%1+FDEC_STRIDEB*1], m1
    mova    [%1+FDEC_STRIDEB*2], m2
    mova    [%1+FDEC_STRIDEB*3], %2
%endmacro

%macro ADD_IDCT_DC 0
cglobal add8x8_idct_dc, 2,2,7
    mova        m6, [pw_pixel_max]
    pxor        m5, m5
    mova        m3, [r1]
    paddd       m3, [pd_32]
    psrad       m3, 6         ; dc0   0 dc1   0 dc2   0 dc3   0
    pshuflw     m4, m3, q2200 ; dc0 dc0 dc1 dc1   _   _   _   _
    pshufhw     m3, m3, q2200 ;   _   _   _   _ dc2 dc2 dc3 dc3
    pshufd      m4, m4, q1100 ; dc0 dc0 dc0 dc0 dc1 dc1 dc1 dc1
    pshufd      m3, m3, q3322 ; dc2 dc2 dc2 dc2 dc3 dc3 dc3 dc3
    ADD_DC r0+FDEC_STRIDEB*0, m4
    ADD_DC r0+FDEC_STRIDEB*4, m3
    RET

cglobal add16x16_idct_dc, 2,3,8
    mov         r2, 4
    mova        m6, [pw_pixel_max]
    mova        m7, [pd_32]
    pxor        m5, m5
.loop:
    mova        m3, [r1]
    paddd       m3, m7
    psrad       m3, 6         ; dc0   0 dc1   0 dc2   0 dc3   0
    pshuflw     m4, m3, q2200 ; dc0 dc0 dc1 dc1   _   _   _   _
    pshufhw     m3, m3, q2200 ;   _   _   _   _ dc2 dc2 dc3 dc3
    pshufd      m4, m4, q1100 ; dc0 dc0 dc0 dc0 dc1 dc1 dc1 dc1
    pshufd      m3, m3, q3322 ; dc2 dc2 dc2 dc2 dc3 dc3 dc3 dc3
    ADD_DC r0+FDEC_STRIDEB*0, m4
    ADD_DC r0+SIZEOF_PIXEL*8, m3
    add         r1, 16
    add         r0, 4*FDEC_STRIDEB
    dec         r2
    jg .loop
    RET
%endmacro ; ADD_IDCT_DC

INIT_XMM sse2
ADD_IDCT_DC
INIT_XMM avx
ADD_IDCT_DC

; One ymm per row: [dc0 x4, dc1 x4 | dc2 x4, dc3 x4]
INIT_YMM avx2
cglobal add16x16_idct_dc, 2,3,8
    mov         r2d, 4
    mova         m5, [pw_pixel_max]
    pxor         m4, m4
    vpbroadcastd m6, [pd_32]
    mova         m7, [idct_dc16_shuf]
.loop:
    vbroadcasti128 m3, [r1]
    paddd        m3, m6
    psrad        m3, 6
    packssdw     m3, m3        ; dc0 dc1 dc2 dc3 dc0 dc1 dc2 dc3 in both lanes
    pshufb       m3, m7        ; dc0 x4 dc1 x4 | dc2 x4 dc3 x4
    paddsw       m0, m3, [r0+FDEC_STRIDEB*0]
    paddsw       m1, m3, [r0+FDEC_STRIDEB*1]
    paddsw       m2, m3, [r0+FDEC_STRIDEB*2]
    paddsw       m3, [r0+FDEC_STRIDEB*3]
    CLIPW        m0, m4, m5
    CLIPW        m1, m4, m5
    CLIPW        m2, m4, m5
    CLIPW        m3, m4, m5
    mova [r0+FDEC_STRIDEB*0], m0
    mova [r0+FDEC_STRIDEB*1], m1
    mova [r0+FDEC_STRIDEB*2], m2
    mova [r0+FDEC_STRIDEB*3], m3
    add          r1, 16
    add          r0, 4*FDEC_STRIDEB
    dec         r2d
    jg .loop
    RET

%else ;!HIGH_BIT_DEPTH
%macro ADD_DC 3
    mova    m4, [%3+FDEC_STRIDE*0]
    mova    m5, [%3+FDEC_STRIDE*1]
    mova    m6, [%3+FDEC_STRIDE*2]
    paddusb m4, %1
    paddusb m5, %1
    paddusb m6, %1
    paddusb %1, [%3+FDEC_STRIDE*3]
    psubusb m4, %2
    psubusb m5, %2
    psubusb m6, %2
    psubusb %1, %2
    mova [%3+FDEC_STRIDE*0], m4
    mova [%3+FDEC_STRIDE*1], m5
    mova [%3+FDEC_STRIDE*2], m6
    mova [%3+FDEC_STRIDE*3], %1
%endmacro

INIT_MMX mmx2
cglobal add8x8_idct_dc, 2,2
    mova      m0, [r1]
    pxor      m1, m1
    add       r0, FDEC_STRIDE*4
    paddw     m0, [pw_32]
    psraw     m0, 6
    psubw     m1, m0
    packuswb  m0, m0
    packuswb  m1, m1
    punpcklbw m0, m0
    punpcklbw m1, m1
    pshufw    m2, m0, q3322
    pshufw    m3, m1, q3322
    punpcklbw m0, m0
    punpcklbw m1, m1
    ADD_DC    m0, m1, r0-FDEC_STRIDE*4
    ADD_DC    m2, m3, r0
    RET

INIT_XMM ssse3
cglobal add8x8_idct_dc, 2,2
    movh     m0, [r1]
    pxor     m1, m1
    add      r0, FDEC_STRIDE*4
    pmulhrsw m0, [pw_512]
    psubw    m1, m0
    mova     m5, [pb_unpackbd1]
    packuswb m0, m0
    packuswb m1, m1
    pshufb   m0, m5
    pshufb   m1, m5
    movh     m2, [r0+FDEC_STRIDE*-4]
    movh     m3, [r0+FDEC_STRIDE*-3]
    movh     m4, [r0+FDEC_STRIDE*-2]
    movh     m5, [r0+FDEC_STRIDE*-1]
    movhps   m2, [r0+FDEC_STRIDE* 0]
    movhps   m3, [r0+FDEC_STRIDE* 1]
    movhps   m4, [r0+FDEC_STRIDE* 2]
    movhps   m5, [r0+FDEC_STRIDE* 3]
    paddusb  m2, m0
    paddusb  m3, m0
    paddusb  m4, m0
    paddusb  m5, m0
    psubusb  m2, m1
    psubusb  m3, m1
    psubusb  m4, m1
    psubusb  m5, m1
    movh   [r0+FDEC_STRIDE*-4], m2
    movh   [r0+FDEC_STRIDE*-3], m3
    movh   [r0+FDEC_STRIDE*-2], m4
    movh   [r0+FDEC_STRIDE*-1], m5
    movhps [r0+FDEC_STRIDE* 0], m2
    movhps [r0+FDEC_STRIDE* 1], m3
    movhps [r0+FDEC_STRIDE* 2], m4
    movhps [r0+FDEC_STRIDE* 3], m5
    RET

INIT_MMX mmx2
cglobal add16x16_idct_dc, 2,3
    mov       r2, 4
.loop:
    mova      m0, [r1]
    pxor      m1, m1
    paddw     m0, [pw_32]
    psraw     m0, 6
    psubw     m1, m0
    packuswb  m0, m0
    packuswb  m1, m1
    punpcklbw m0, m0
    punpcklbw m1, m1
    pshufw    m2, m0, q3322
    pshufw    m3, m1, q3322
    punpcklbw m0, m0
    punpcklbw m1, m1
    ADD_DC    m0, m1, r0
    ADD_DC    m2, m3, r0+8
    add       r1, 8
    add       r0, FDEC_STRIDE*4
    dec       r2
    jg .loop
    RET

INIT_XMM sse2
cglobal add16x16_idct_dc, 2,2,8
    call .loop
    add       r0, FDEC_STRIDE*4
    TAIL_CALL .loop, 0
.loop:
    add       r0, FDEC_STRIDE*4
    movq      m0, [r1+0]
    movq      m2, [r1+8]
    add       r1, 16
    punpcklwd m0, m0
    punpcklwd m2, m2
    pxor      m3, m3
    paddw     m0, [pw_32]
    paddw     m2, [pw_32]
    psraw     m0, 6
    psraw     m2, 6
    psubw     m1, m3, m0
    packuswb  m0, m1
    psubw     m3, m2
    punpckhbw m1, m0, m0
    packuswb  m2, m3
    punpckhbw m3, m2, m2
    punpcklbw m0, m0
    punpcklbw m2, m2
    ADD_DC    m0, m1, r0+FDEC_STRIDE*-4
    ADD_DC    m2, m3, r0
    ret

%macro ADD16x16 0
cglobal add16x16_idct_dc, 2,2,8
    call .loop
    add      r0, FDEC_STRIDE*4
    TAIL_CALL .loop, 0
.loop:
    add      r0, FDEC_STRIDE*4
    mova     m0, [r1]
    add      r1, 16
    pxor     m1, m1
    pmulhrsw m0, [pw_512]
    psubw    m1, m0
    mova     m5, [pb_unpackbd1]
    mova     m6, [pb_unpackbd2]
    packuswb m0, m0
    packuswb m1, m1
    pshufb   m2, m0, m6
    pshufb   m0, m5
    pshufb   m3, m1, m6
    pshufb   m1, m5
    ADD_DC   m0, m1, r0+FDEC_STRIDE*-4
    ADD_DC   m2, m3, r0
    ret
%endmacro ; ADD16x16

INIT_XMM ssse3
ADD16x16
INIT_XMM avx
ADD16x16

%macro ADD_DC_AVX2 3
    mova   xm4, [r0+FDEC_STRIDE*0+%3]
    mova   xm5, [r0+FDEC_STRIDE*1+%3]
    vinserti128 m4, m4, [r2+FDEC_STRIDE*0+%3], 1
    vinserti128 m5, m5, [r2+FDEC_STRIDE*1+%3], 1
    paddusb m4, %1
    paddusb m5, %1
    psubusb m4, %2
    psubusb m5, %2
    mova [r0+FDEC_STRIDE*0+%3], xm4
    mova [r0+FDEC_STRIDE*1+%3], xm5
    vextracti128 [r2+FDEC_STRIDE*0+%3], m4, 1
    vextracti128 [r2+FDEC_STRIDE*1+%3], m5, 1
%endmacro

INIT_YMM avx2
cglobal add16x16_idct_dc, 2,3,6
    add      r0, FDEC_STRIDE*4
    mova     m0, [r1]
    pxor     m1, m1
    pmulhrsw m0, [pw_512]
    psubw    m1, m0
    mova     m4, [pb_unpackbd1]
    mova     m5, [pb_unpackbd2]
    packuswb m0, m0
    packuswb m1, m1
    pshufb   m2, m0, m4      ; row0, row2
    pshufb   m3, m1, m4      ; row0, row2
    pshufb   m0, m5          ; row1, row3
    pshufb   m1, m5          ; row1, row3
    lea      r2, [r0+FDEC_STRIDE*8]
    ADD_DC_AVX2 m2, m3, FDEC_STRIDE*-4
    ADD_DC_AVX2 m2, m3, FDEC_STRIDE*-2
    ADD_DC_AVX2 m0, m1, FDEC_STRIDE* 0
    ADD_DC_AVX2 m0, m1, FDEC_STRIDE* 2
    RET

%endif ; HIGH_BIT_DEPTH

;-----------------------------------------------------------------------------
; void sub8x8_dct_dc( int16_t dct[2][2], uint8_t *pix1, uint8_t *pix2 )
;-----------------------------------------------------------------------------

%macro DCTDC_2ROW_MMX 4
    mova      %1, [r1+FENC_STRIDE*(0+%3)]
    mova      m1, [r1+FENC_STRIDE*(1+%3)]
    mova      m2, [r2+FDEC_STRIDE*(0+%4)]
    mova      m3, [r2+FDEC_STRIDE*(1+%4)]
    mova      %2, %1
    punpckldq %1, m1
    punpckhdq %2, m1
    mova      m1, m2
    punpckldq m2, m3
    punpckhdq m1, m3
    pxor      m3, m3
    psadbw    %1, m3
    psadbw    %2, m3
    psadbw    m2, m3
    psadbw    m1, m3
    psubw     %1, m2
    psubw     %2, m1
%endmacro

%macro DCT2x2 2 ; reg s1/s0, reg s3/s2 (!=m0/m1)
    PSHUFLW   m1, %1, q2200  ;  s1  s1  s0  s0
    PSHUFLW   m0, %2, q2301  ;  s3  __  s2  __
    paddw     m1, %2         ;  s1 s13  s0 s02
    psubw     m1, m0         ; d13 s13 d02 s02
    PSHUFLW   m0, m1, q1010  ; d02 s02 d02 s02
    psrlq     m1, 32         ;  __  __ d13 s13
    paddw     m0, m1         ; d02 s02 d02+d13 s02+s13
    psllq     m1, 32         ; d13 s13
    psubw     m0, m1         ; d02-d13 s02-s13 d02+d13 s02+s13
%endmacro

%if HIGH_BIT_DEPTH == 0
INIT_MMX mmx2
cglobal sub8x8_dct_dc, 3,3
    DCTDC_2ROW_MMX m0, m4, 0, 0
    DCTDC_2ROW_MMX m5, m6, 2, 2
    paddw     m0, m5
    paddw     m4, m6
    punpckldq m0, m4
    add       r2, FDEC_STRIDE*4
    DCTDC_2ROW_MMX m7, m4, 4, 0
    DCTDC_2ROW_MMX m5, m6, 6, 2
    paddw     m7, m5
    paddw     m4, m6
    punpckldq m7, m4
    DCT2x2    m0, m7
    mova    [r0], m0
    ret

%macro DCTDC_2ROW_SSE2 4
    movh      m1, [r1+FENC_STRIDE*(0+%1)]
    movh      m2, [r1+FENC_STRIDE*(1+%1)]
    punpckldq m1, m2
    movh      m2, [r2+FDEC_STRIDE*(0+%2)]
    punpckldq m2, [r2+FDEC_STRIDE*(1+%2)]
    psadbw    m1, m0
    psadbw    m2, m0
    ACCUM  paddd, %4, 1, %3
    psubd    m%4, m2
%endmacro

INIT_XMM sse2
cglobal sub8x8_dct_dc, 3,3
    pxor     m0, m0
    DCTDC_2ROW_SSE2 0, 0, 0, 3
    DCTDC_2ROW_SSE2 2, 2, 1, 3
    add      r2, FDEC_STRIDE*4
    DCTDC_2ROW_SSE2 4, 0, 0, 4
    DCTDC_2ROW_SSE2 6, 2, 1, 4
    packssdw m3, m3
    packssdw m4, m4
    DCT2x2   m3, m4
    movq   [r0], m0
    RET

%macro SUB8x16_DCT_DC 0
cglobal sub8x16_dct_dc, 3,3
    pxor       m0, m0
    DCTDC_2ROW_SSE2 0, 0, 0, 3
    DCTDC_2ROW_SSE2 2, 2, 1, 3
    add        r1, FENC_STRIDE*8
    add        r2, FDEC_STRIDE*8
    DCTDC_2ROW_SSE2 -4, -4, 0, 4
    DCTDC_2ROW_SSE2 -2, -2, 1, 4
    shufps     m3, m4, q2020
    DCTDC_2ROW_SSE2 0, 0, 0, 5
    DCTDC_2ROW_SSE2 2, 2, 1, 5
    add        r2, FDEC_STRIDE*4
    DCTDC_2ROW_SSE2 4, 0, 0, 4
    DCTDC_2ROW_SSE2 6, 2, 1, 4
    shufps     m5, m4, q2020
%if cpuflag(ssse3)
    %define %%sign psignw
%else
    %define %%sign pmullw
%endif
    SUMSUB_BA d, 5, 3, 0
    packssdw   m5, m3
    pshuflw    m0, m5, q2301
    pshufhw    m0, m0, q2301
    %%sign     m5, [pw_pmpmpmpm]
    paddw      m0, m5
    pshufd     m1, m0, q1320
    pshufd     m0, m0, q0231
    %%sign     m1, [pw_ppppmmmm]
    paddw      m0, m1
    mova     [r0], m0
    RET
%endmacro ; SUB8x16_DCT_DC

INIT_XMM sse2
SUB8x16_DCT_DC
INIT_XMM ssse3
SUB8x16_DCT_DC

%endif ; !HIGH_BIT_DEPTH

%macro DCTDC_4ROW_SSE2 2
    mova       %1, [r1+FENC_STRIDEB*%2]
    mova       m0, [r2+FDEC_STRIDEB*%2]
%assign Y (%2+1)
%rep 3
    paddw      %1, [r1+FENC_STRIDEB*Y]
    paddw      m0, [r2+FDEC_STRIDEB*Y]
%assign Y (Y+1)
%endrep
    psubw      %1, m0
    pshufd     m0, %1, q2301
    paddw      %1, m0
%endmacro

%if HIGH_BIT_DEPTH
%macro SUB8x8_DCT_DC_10 0
cglobal sub8x8_dct_dc, 3,3,3
    DCTDC_4ROW_SSE2 m1, 0
    DCTDC_4ROW_SSE2 m2, 4
    mova       m0, [pw_ppmmmmpp]
    pmaddwd    m1, m0
    pmaddwd    m2, m0
    pshufd     m0, m1, q2200      ; -1 -1 +0 +0
    pshufd     m1, m1, q0033      ; +0 +0 +1 +1
    paddd      m1, m0
    pshufd     m0, m2, q1023      ; -2 +2 -3 +3
    paddd      m1, m2
    paddd      m1, m0
    mova     [r0], m1
    RET
%endmacro
INIT_XMM sse2
SUB8x8_DCT_DC_10

%macro SUB8x16_DCT_DC_10 0
cglobal sub8x16_dct_dc, 3,3,6
    DCTDC_4ROW_SSE2 m1, 0
    DCTDC_4ROW_SSE2 m2, 4
    DCTDC_4ROW_SSE2 m3, 8
    DCTDC_4ROW_SSE2 m4, 12
    mova       m0, [pw_ppmmmmpp]
    pmaddwd    m1, m0
    pmaddwd    m2, m0
    pshufd     m5, m1, q2200      ; -1 -1 +0 +0
    pshufd     m1, m1, q0033      ; +0 +0 +1 +1
    paddd      m1, m5
    pshufd     m5, m2, q1023      ; -2 +2 -3 +3
    paddd      m1, m2
    paddd      m1, m5             ; a6 a2 a4 a0
    pmaddwd    m3, m0
    pmaddwd    m4, m0
    pshufd     m5, m3, q2200
    pshufd     m3, m3, q0033
    paddd      m3, m5
    pshufd     m5, m4, q1023
    paddd      m3, m4
    paddd      m3, m5             ; a7 a3 a5 a1
    paddd      m0, m1, m3
    psubd      m1, m3
    pshufd     m0, m0, q3120
    pshufd     m1, m1, q3120
    punpcklqdq m2, m0, m1
    punpckhqdq m1, m0
    mova  [r0+ 0], m2
    mova  [r0+16], m1
    RET
%endmacro
INIT_XMM sse2
SUB8x16_DCT_DC_10
INIT_XMM avx
SUB8x16_DCT_DC_10
%endif

;-----------------------------------------------------------------------------
; void zigzag_scan_8x8_frame( int16_t level[64], int16_t dct[8][8] )
;-----------------------------------------------------------------------------
%macro SCAN_8x8 0
cglobal zigzag_scan_8x8_frame, 2,2,8
    movdqa    xmm0, [r1]
    movdqa    xmm1, [r1+16]
    movdq2q    mm0, xmm0
    PALIGNR   xmm1, xmm1, 14, xmm2
    movdq2q    mm1, xmm1

    movdqa    xmm2, [r1+32]
    movdqa    xmm3, [r1+48]
    PALIGNR   xmm2, xmm2, 12, xmm4
    movdq2q    mm2, xmm2
    PALIGNR   xmm3, xmm3, 10, xmm4
    movdq2q    mm3, xmm3

    punpckhwd xmm0, xmm1
    punpckhwd xmm2, xmm3

    movq       mm4, mm1
    movq       mm5, mm1
    movq       mm6, mm2
    movq       mm7, mm3
    punpckhwd  mm1, mm0
    psllq      mm0, 16
    psrlq      mm3, 16
    punpckhdq  mm1, mm1
    punpckhdq  mm2, mm0
    punpcklwd  mm0, mm4
    punpckhwd  mm4, mm3
    punpcklwd  mm4, mm2
    punpckhdq  mm0, mm2
    punpcklwd  mm6, mm3
    punpcklwd  mm5, mm7
    punpcklwd  mm5, mm6

    movdqa    xmm4, [r1+64]
    movdqa    xmm5, [r1+80]
    movdqa    xmm6, [r1+96]
    movdqa    xmm7, [r1+112]

    movq [r0+2*00], mm0
    movq [r0+2*04], mm4
    movd [r0+2*08], mm1
    movq [r0+2*36], mm5
    movq [r0+2*46], mm6

    PALIGNR   xmm4, xmm4, 14, xmm3
    movdq2q    mm4, xmm4
    PALIGNR   xmm5, xmm5, 12, xmm3
    movdq2q    mm5, xmm5
    PALIGNR   xmm6, xmm6, 10, xmm3
    movdq2q    mm6, xmm6
%if cpuflag(ssse3)
    PALIGNR   xmm7, xmm7, 8, xmm3
    movdq2q    mm7, xmm7
%else
    movhlps   xmm3, xmm7
    punpcklqdq xmm7, xmm7
    movdq2q    mm7, xmm3
%endif

    punpckhwd xmm4, xmm5
    punpckhwd xmm6, xmm7

    movq       mm0, mm4
    movq       mm1, mm5
    movq       mm3, mm7
    punpcklwd  mm7, mm6
    psrlq      mm6, 16
    punpcklwd  mm4, mm6
    punpcklwd  mm5, mm4
    punpckhdq  mm4, mm3
    punpcklwd  mm3, mm6
    punpckhwd  mm3, mm4
    punpckhwd  mm0, mm1
    punpckldq  mm4, mm0
    punpckhdq  mm0, mm6
    pshufw     mm4, mm4, q1230

    movq [r0+2*14], mm4
    movq [r0+2*25], mm0
    movd [r0+2*54], mm7
    movq [r0+2*56], mm5
    movq [r0+2*60], mm3

    punpckhdq xmm3, xmm0, xmm2
    punpckldq xmm0, xmm2
    punpckhdq xmm7, xmm4, xmm6
    punpckldq xmm4, xmm6
    pshufhw   xmm0, xmm0, q0123
    pshuflw   xmm4, xmm4, q0123
    pshufhw   xmm3, xmm3, q0123
    pshuflw   xmm7, xmm7, q0123

    movlps [r0+2*10], xmm0
    movhps [r0+2*17], xmm0
    movlps [r0+2*21], xmm3
    movlps [r0+2*28], xmm4
    movhps [r0+2*32], xmm3
    movhps [r0+2*39], xmm4
    movlps [r0+2*43], xmm7
    movhps [r0+2*50], xmm7

    RET
%endmacro

%if HIGH_BIT_DEPTH == 0
INIT_XMM sse2
SCAN_8x8
INIT_XMM ssse3
SCAN_8x8
%endif

;-----------------------------------------------------------------------------
; void zigzag_scan_8x8_frame( dctcoef level[64], dctcoef dct[8][8] )
;-----------------------------------------------------------------------------
; Output order:
;  0  8  1  2  9 16 24 17
; 10  3  4 11 18 25 32 40
; 33 26 19 12  5  6 13 20
; 27 34 41 48 56 49 42 35
; 28 21 14  7 15 22 29 36
; 43 50 57 58 51 44 37 30
; 23 31 38 45 52 59 60 53
; 46 39 47 54 61 62 55 63
%macro SCAN_8x8_FRAME 5
cglobal zigzag_scan_8x8_frame, 2,2,8
    mova        m0, [r1]
    mova        m1, [r1+ 8*SIZEOF_DCTCOEF]
    movu        m2, [r1+14*SIZEOF_DCTCOEF]
    movu        m3, [r1+21*SIZEOF_DCTCOEF]
    mova        m4, [r1+28*SIZEOF_DCTCOEF]
    punpckl%4   m5, m0, m1
    psrl%2      m0, %1
    punpckh%4   m6, m1, m0
    punpckl%3   m5, m0
    punpckl%3   m1, m1
    punpckh%4   m1, m3
    mova        m7, [r1+52*SIZEOF_DCTCOEF]
    mova        m0, [r1+60*SIZEOF_DCTCOEF]
    punpckh%4   m1, m2
    punpckl%4   m2, m4
    punpckh%4   m4, m3
    punpckl%3   m3, m3
    punpckh%4   m3, m2
    mova      [r0], m5
    mova  [r0+ 4*SIZEOF_DCTCOEF], m1
    mova  [r0+ 8*SIZEOF_DCTCOEF], m6
    punpckl%4   m6, m0
    punpckl%4   m6, m7
    mova        m1, [r1+32*SIZEOF_DCTCOEF]
    movu        m5, [r1+39*SIZEOF_DCTCOEF]
    movu        m2, [r1+46*SIZEOF_DCTCOEF]
    movu [r0+35*SIZEOF_DCTCOEF], m3
    movu [r0+47*SIZEOF_DCTCOEF], m4
    punpckh%4   m7, m0
    psll%2      m0, %1
    punpckh%3   m3, m5, m5
    punpckl%4   m5, m1
    punpckh%4   m1, m2
    mova [r0+52*SIZEOF_DCTCOEF], m6
    movu [r0+13*SIZEOF_DCTCOEF], m5
    movu        m4, [r1+11*SIZEOF_DCTCOEF]
    movu        m6, [r1+25*SIZEOF_DCTCOEF]
    punpckl%4   m5, m7
    punpckl%4   m1, m3
    punpckh%3   m0, m7
    mova        m3, [r1+ 4*SIZEOF_DCTCOEF]
    movu        m7, [r1+18*SIZEOF_DCTCOEF]
    punpckl%4   m2, m5
    movu [r0+25*SIZEOF_DCTCOEF], m1
    mova        m1, m4
    mova        m5, m6
    punpckl%4   m4, m3
    punpckl%4   m6, m7
    punpckh%4   m1, m3
    punpckh%4   m5, m7
    punpckh%3   m3, m6, m4
    punpckh%3   m7, m5, m1
    punpckl%3   m6, m4
    punpckl%3   m5, m1
    movu        m4, [r1+35*SIZEOF_DCTCOEF]
    movu        m1, [r1+49*SIZEOF_DCTCOEF]
    pshuf%5     m6, m6, q0123
    pshuf%5     m5, m5, q0123
    mova [r0+60*SIZEOF_DCTCOEF], m0
    mova [r0+56*SIZEOF_DCTCOEF], m2
    movu        m0, [r1+42*SIZEOF_DCTCOEF]
    mova        m2, [r1+56*SIZEOF_DCTCOEF]
    movu [r0+17*SIZEOF_DCTCOEF], m3
    mova [r0+32*SIZEOF_DCTCOEF], m7
    movu [r0+10*SIZEOF_DCTCOEF], m6
    movu [r0+21*SIZEOF_DCTCOEF], m5
    punpckh%4   m3, m0, m4
    punpckh%4   m7, m2, m1
    punpckl%4   m0, m4
    punpckl%4   m2, m1
    punpckl%3   m4, m2, m0
    punpckl%3   m1, m7, m3
    punpckh%3   m2, m0
    punpckh%3   m7, m3
    pshuf%5     m2, m2, q0123
    pshuf%5     m7, m7, q0123
    mova [r0+28*SIZEOF_DCTCOEF], m4
    movu [r0+43*SIZEOF_DCTCOEF], m1
    movu [r0+39*SIZEOF_DCTCOEF], m2
    movu [r0+50*SIZEOF_DCTCOEF], m7
    RET
%endmacro

%if HIGH_BIT_DEPTH
INIT_XMM sse2
SCAN_8x8_FRAME 4 , dq, qdq, dq, d
INIT_XMM avx
SCAN_8x8_FRAME 4 , dq, qdq, dq, d
%else
INIT_MMX mmx2
SCAN_8x8_FRAME 16, q , dq , wd, w
%endif

;-----------------------------------------------------------------------------
; void zigzag_scan_4x4_frame( dctcoef level[16], dctcoef dct[4][4] )
;-----------------------------------------------------------------------------
%macro SCAN_4x4 4
cglobal zigzag_scan_4x4_frame, 2,2,6
    mova      m0, [r1+ 0*SIZEOF_DCTCOEF]
    mova      m1, [r1+ 4*SIZEOF_DCTCOEF]
    mova      m2, [r1+ 8*SIZEOF_DCTCOEF]
    mova      m3, [r1+12*SIZEOF_DCTCOEF]
    punpckl%4 m4, m0, m1
    psrl%2    m0, %1
    punpckl%3 m4, m0
    mova  [r0+ 0*SIZEOF_DCTCOEF], m4
    punpckh%4 m0, m2
    punpckh%4 m4, m2, m3
    psll%2    m3, %1
    punpckl%3 m2, m2
    punpckl%4 m5, m1, m3
    punpckh%3 m1, m1
    punpckh%4 m5, m2
    punpckl%4 m1, m0
    punpckh%3 m3, m4
    mova [r0+ 4*SIZEOF_DCTCOEF], m5
    mova [r0+ 8*SIZEOF_DCTCOEF], m1
    mova [r0+12*SIZEOF_DCTCOEF], m3
    RET
%endmacro

%if HIGH_BIT_DEPTH
INIT_XMM sse2
SCAN_4x4  4, dq, qdq, dq
INIT_XMM avx
SCAN_4x4  4, dq, qdq, dq

INIT_YMM avx2
cglobal zigzag_scan_4x4_frame, 2,2,4
    mova      m0, [scan4x4_frame_avx2]
    mova      m1, [scan4x4_frame_avx2+32]
    vpermd    m2, m0, [r1]
    vpermd    m3, m1, [r1+32]
    vpblendd  m2, m2, m3, 0xe0      ;  0  4  1  2  5  8 12  9
    vpermd    m1, m1, [r1]
    vpermd    m0, m0, [r1+32]
    vpblendd  m0, m1, m0, 0xf8      ;  6  3  7 10 13 14 11 15
    movu [r0+ 0], m2
    movu [r0+32], m0
    RET
%else
INIT_MMX mmx
SCAN_4x4 16, q , dq , wd

;-----------------------------------------------------------------------------
; void zigzag_scan_4x4_frame( int16_t level[16], int16_t dct[4][4] )
;-----------------------------------------------------------------------------
%macro SCAN_4x4_FRAME 0
cglobal zigzag_scan_4x4_frame, 2,2
    mova    m1, [r1+16]
    mova    m0, [r1+ 0]
    pshufb  m1, [pb_scan4frameb]
    pshufb  m0, [pb_scan4framea]
    psrldq  m2, m1, 6
    palignr m1, m0, 6
    pslldq  m0, 10
    palignr m2, m0, 10
    mova [r0+ 0], m1
    mova [r0+16], m2
    RET
%endmacro

INIT_XMM ssse3
SCAN_4x4_FRAME
INIT_XMM avx
SCAN_4x4_FRAME

; one 32-byte load, one lane swap and two pshufb (the avx version takes 6 shuffles)
INIT_YMM avx2
cglobal zigzag_scan_4x4_frame, 2,2
    movu         m0, [r1]
    vperm2i128   m1, m0, m0, 0x01
    pshufb       m0, [scan4frame_ymm_a]
    pshufb       m1, [scan4frame_ymm_b]
    por          m0, m1
    movu       [r0], m0
    RET

INIT_XMM xop
cglobal zigzag_scan_4x4_frame, 2,2
    mova   m0, [r1+ 0]
    mova   m1, [r1+16]
    vpperm m2, m0, m1, [pb_scan4frame2a]
    vpperm m1, m0, m1, [pb_scan4frame2b]
    mova [r0+ 0], m2
    mova [r0+16], m1
    RET
%endif ; !HIGH_BIT_DEPTH

%if HIGH_BIT_DEPTH
;-----------------------------------------------------------------------------
; void zigzag_scan_4x4_field( int32_t level[16], int32_t dct[4][4] )
;-----------------------------------------------------------------------------
INIT_XMM sse2
cglobal zigzag_scan_4x4_field, 2,3
    movu       m4, [r1+ 8]
    pshufd     m0, m4, q3102
    mova       m1, [r1+32]
    mova       m2, [r1+48]
    movu  [r0+ 8], m0
    mova  [r0+32], m1
    mova  [r0+48], m2
    movq      mm0, [r1]
    movq     [r0], mm0
    movq      mm0, [r1+24]
    movq  [r0+24], mm0
    RET
%else
;-----------------------------------------------------------------------------
; void zigzag_scan_4x4_field( int16_t level[16], int16_t dct[4][4] )
;-----------------------------------------------------------------------------
; sse2 is only 1 cycle faster, and ssse3/pshufb is slower on core2
INIT_MMX mmx2
cglobal zigzag_scan_4x4_field, 2,3
    pshufw      m0, [r1+4], q3102
    mova        m1, [r1+16]
    mova        m2, [r1+24]
    movu    [r0+4], m0
    mova   [r0+16], m1
    mova   [r0+24], m2
    mov        r2d, [r1]
    mov       [r0], r2d
    mov        r2d, [r1+12]
    mov    [r0+12], r2d
    RET
%endif ; HIGH_BIT_DEPTH

;-----------------------------------------------------------------------------
; void zigzag_scan_8x8_field( int16_t level[64], int16_t dct[8][8] )
;-----------------------------------------------------------------------------
; Output order:
;  0  1  2  8  9  3  4 10
; 16 11  5  6  7 12 17 24
; 18 13 14 15 19 25 32 26
; 20 21 22 23 27 33 40 34
; 28 29 30 31 35 41 48 42
; 36 37 38 39 43 49 50 44
; 45 46 47 51 56 57 52 53
; 54 55 58 59 60 61 62 63
%undef SCAN_8x8
%macro SCAN_8x8 5
cglobal zigzag_scan_8x8_field, 2,3,8
    mova       m0, [r1+ 0*SIZEOF_DCTCOEF]       ; 03 02 01 00
    mova       m1, [r1+ 4*SIZEOF_DCTCOEF]       ; 07 06 05 04
    mova       m2, [r1+ 8*SIZEOF_DCTCOEF]       ; 11 10 09 08
    pshuf%1    m3, m0, q3333                    ; 03 03 03 03
    movd      r2d, m2                           ; 09 08
    pshuf%1    m2, m2, q0321                    ; 08 11 10 09
    punpckl%2  m3, m1                           ; 05 03 04 03
    pinsr%1    m0, r2d, 3                       ; 08 02 01 00
    punpckl%2  m4, m2, m3                       ; 04 10 03 09
    pshuf%1    m4, m4, q2310                    ; 10 04 03 09
    mova  [r0+ 0*SIZEOF_DCTCOEF], m0            ; 08 02 01 00
    mova  [r0+ 4*SIZEOF_DCTCOEF], m4            ; 10 04 03 09
    mova       m3, [r1+12*SIZEOF_DCTCOEF]       ; 15 14 13 12
    mova       m5, [r1+16*SIZEOF_DCTCOEF]       ; 19 18 17 16
    punpckl%3  m6, m5                           ; 17 16 XX XX
    psrl%4     m1, %5                           ; XX 07 06 05
    punpckh%2  m6, m2                           ; 08 17 11 16
    punpckl%3  m6, m1                           ; 06 05 11 16
    mova  [r0+ 8*SIZEOF_DCTCOEF], m6            ; 06 05 11 16
    psrl%4     m1, %5                           ; XX XX 07 06
    punpckl%2  m1, m5                           ; 17 07 16 06
    mova       m0, [r1+20*SIZEOF_DCTCOEF]       ; 23 22 21 20
    mova       m2, [r1+24*SIZEOF_DCTCOEF]       ; 27 26 25 24
    punpckh%3  m1, m1                           ; 17 07 17 07
    punpckl%2  m6, m3, m2                       ; 25 13 24 12
    pextr%1    r2d, m5, 2
    mova [r0+24*SIZEOF_DCTCOEF], m0             ; 23 22 21 20
    punpckl%2  m1, m6                           ; 24 17 12 07
    mova [r0+12*SIZEOF_DCTCOEF], m1
    pinsr%1    m3, r2d, 0                       ; 15 14 13 18
    mova [r0+16*SIZEOF_DCTCOEF], m3             ; 15 14 13 18
    mova       m7, [r1+28*SIZEOF_DCTCOEF]
    mova       m0, [r1+32*SIZEOF_DCTCOEF]       ; 35 34 33 32
    psrl%4     m5, %5*3                         ; XX XX XX 19
    pshuf%1    m1, m2, q3321                    ; 27 27 26 25
    punpckl%2  m5, m0                           ; 33 XX 32 19
    psrl%4     m2, %5*3                         ; XX XX XX 27
    punpckl%2  m5, m1                           ; 26 32 25 19
    mova [r0+32*SIZEOF_DCTCOEF], m7
    mova [r0+20*SIZEOF_DCTCOEF], m5             ; 26 32 25 19
    mova       m7, [r1+36*SIZEOF_DCTCOEF]
    mova       m1, [r1+40*SIZEOF_DCTCOEF]       ; 43 42 41 40
    pshuf%1    m3, m0, q3321                    ; 35 35 34 33
    punpckl%2  m2, m1                           ; 41 XX 40 27
    mova [r0+40*SIZEOF_DCTCOEF], m7
    punpckl%2  m2, m3                           ; 34 40 33 27
    mova [r0+28*SIZEOF_DCTCOEF], m2
    mova       m7, [r1+44*SIZEOF_DCTCOEF]       ; 47 46 45 44
    mova       m2, [r1+48*SIZEOF_DCTCOEF]       ; 51 50 49 48
    psrl%4     m0, %5*3                         ; XX XX XX 35
    punpckl%2  m0, m2                           ; 49 XX 48 35
    pshuf%1    m3, m1, q3321                    ; 43 43 42 41
    punpckl%2  m0, m3                           ; 42 48 41 35
    mova [r0+36*SIZEOF_DCTCOEF], m0
    pextr%1     r2d, m2, 3                      ; 51
    psrl%4      m1, %5*3                        ; XX XX XX 43
    punpckl%2   m1, m7                          ; 45 XX 44 43
    psrl%4      m2, %5                          ; XX 51 50 49
    punpckl%2   m1, m2                          ; 50 44 49 43
    pshuf%1     m1, m1, q2310                   ; 44 50 49 43
    mova [r0+44*SIZEOF_DCTCOEF], m1
    psrl%4      m7, %5                          ; XX 47 46 45
    pinsr%1     m7, r2d, 3                      ; 51 47 46 45
    mova [r0+48*SIZEOF_DCTCOEF], m7
    mova        m0, [r1+56*SIZEOF_DCTCOEF]      ; 59 58 57 56
    mova        m1, [r1+52*SIZEOF_DCTCOEF]      ; 55 54 53 52
    mova        m7, [r1+60*SIZEOF_DCTCOEF]
    punpckl%3   m2, m0, m1                      ; 53 52 57 56
    punpckh%3   m1, m0                          ; 59 58 55 54
    mova [r0+52*SIZEOF_DCTCOEF], m2
    mova [r0+56*SIZEOF_DCTCOEF], m1
    mova [r0+60*SIZEOF_DCTCOEF], m7
    RET
%endmacro
%if HIGH_BIT_DEPTH
INIT_XMM sse4
SCAN_8x8 d, dq, qdq, dq, 4
INIT_XMM avx
SCAN_8x8 d, dq, qdq, dq, 4
%else
INIT_MMX mmx2
SCAN_8x8 w, wd, dq , q , 16
%endif

%if HIGH_BIT_DEPTH == 0
; Output rows 1-6 are each a pshufb of two unaligned 8-coef windows of the
; input (u, v); the windows of rows r and r+1 are 8 coefs apart, so a ymm
; does two rows. out[8] (in[16]) is in neither window of row 1.
%macro SCAN_8x8_FIELD_ROWS 3 ; first row, u, v
%assign %%i 0
%rep 32/mmsize
    movu       m0, [r1+(%2+8*%%i)*2]
    movu       m1, [r1+(%3+8*%%i)*2]
    pshufb     m0, [pb_scan8field_u+(%1+%%i-1)*16]
    pshufb     m1, [pb_scan8field_v+(%1+%%i-1)*16]
    por        m0, m1
%if mmsize == 32
    movu [r0+(%1+%%i)*16], m0
%else
    mova [r0+(%1+%%i)*16], m0
%endif
%assign %%i %%i+1
%endrep
%endmacro

%macro SCAN_8x8_FIELD 0
cglobal zigzag_scan_8x8_field, 2,3,2
    mova      xm0, [r1+  0]             ; in 0-7
    movu      xm1, [r1+  6]             ; in 3-10
    pshufb    xm1, [pb_scan8field_v0]
%if cpuflag(avx)
    pblendw   xm0, xm1, 0xf8
%else
    pshufb    xm0, [pb_scan8field_u0]
    por       xm0, xm1
%endif
    mova [r0+  0], xm0
    SCAN_8x8_FIELD_ROWS 1,  5, 17
    SCAN_8x8_FIELD_ROWS 3, 20, 33
    SCAN_8x8_FIELD_ROWS 5, 36, 44
    movzx     r2d, word [r1+32]
    mov  [r0+ 16], r2w
    mova      xm0, [r1+112]
    mov       r2d, [r1+108]
    mova [r0+112], xm0
    mov  [r0+112], r2d
    RET
%endmacro

INIT_XMM ssse3
SCAN_8x8_FIELD
INIT_YMM avx2
SCAN_8x8_FIELD

;-----------------------------------------------------------------------------
; void zigzag_scan_4x4_field( int16_t level[16], int16_t dct[4][4] )
;-----------------------------------------------------------------------------
cglobal zigzag_scan_4x4_field, 2,2
    movu       m0, [r1]
    pshufb     m0, [pb_scan4field_avx2]
    movu     [r0], m0
    RET

%if ARCH_X86_64
;-----------------------------------------------------------------------------
; void zigzag_scan_8x8_frame( int16_t level[64], int16_t dct[8][8] )
; A-D = input ymm 0-3, lanes a0|a1 .. d0|d1 (8 coefs each). Every output
; lane is an OR of pshufbs, one per source lane holding a coef of it:
; out0 from A A' B B' C C', out1 and out2 from X1-X5, out3 from B B' C C' D D'
; (' = lanes swapped, X1 = a0|b1, X2 = a1|c0, X3 = b0|c1, X4 = b1|d0,
; X5 = c0|d1).
;-----------------------------------------------------------------------------
cglobal zigzag_scan_8x8_frame, 2,3,14
    lea          r2, [pb_scan8frame_avx2]
    movu         m0, [r1+ 0]
    movu         m1, [r1+32]
    movu         m2, [r1+64]
    movu         m3, [r1+96]
    vperm2i128   m4, m0, m0, 0x01
    vperm2i128   m5, m1, m1, 0x01
    vperm2i128   m6, m2, m2, 0x01
    vperm2i128   m7, m3, m3, 0x01
    pshufb       m8, m0, [r2+ 0*32]
    pshufb       m9, m4, [r2+ 1*32]
    pshufb      m10, m1, [r2+ 2*32]
    pshufb      m11, m5, [r2+ 3*32]
    pshufb      m12, m2, [r2+ 4*32]
    pshufb      m13, m6, [r2+ 5*32]
    por          m8, m9
    por         m10, m11
    por         m12, m13
    por          m8, m10
    por          m8, m12
    movu    [r0+ 0], m8
    pshufb       m8, m1, [r2+16*32]
    pshufb       m9, m5, [r2+17*32]
    pshufb      m10, m2, [r2+18*32]
    pshufb      m11, m6, [r2+19*32]
    pshufb      m12, m3, [r2+20*32]
    pshufb      m13, m7, [r2+21*32]
    por          m8, m9
    por         m10, m11
    por         m12, m13
    por          m8, m10
    por          m8, m12
    movu    [r0+96], m8
    vpblendd     m4, m0, m1, 0xf0
    vperm2i128   m5, m0, m2, 0x21
    vpblendd     m6, m1, m2, 0xf0
    vperm2i128   m7, m1, m3, 0x21
    vpblendd     m0, m2, m3, 0xf0
    pshufb       m8, m4, [r2+ 6*32]
    pshufb       m9, m5, [r2+ 7*32]
    pshufb      m10, m6, [r2+ 8*32]
    pshufb      m11, m7, [r2+ 9*32]
    pshufb      m12, m0, [r2+10*32]
    por          m8, m9
    por         m10, m11
    por          m8, m12
    por          m8, m10
    movu    [r0+32], m8
    pshufb       m4, [r2+11*32]
    pshufb       m5, [r2+12*32]
    pshufb       m6, [r2+13*32]
    pshufb       m7, [r2+14*32]
    pshufb       m0, [r2+15*32]
    por          m4, m5
    por          m6, m7
    por          m4, m0
    por          m4, m6
    movu    [r0+64], m4
    RET
%endif
%endif ; !HIGH_BIT_DEPTH

;-----------------------------------------------------------------------------
; void zigzag_sub_4x4_frame( int16_t level[16], const uint8_t *src, uint8_t *dst )
;-----------------------------------------------------------------------------
%macro ZIGZAG_SUB_4x4 2
%ifidn %1, ac
cglobal zigzag_sub_4x4%1_%2, 4,4,8
%else
cglobal zigzag_sub_4x4%1_%2, 3,3,8
%endif
    movd      m0, [r1+0*FENC_STRIDE]
    movd      m1, [r1+1*FENC_STRIDE]
    movd      m2, [r1+2*FENC_STRIDE]
    movd      m3, [r1+3*FENC_STRIDE]
    movd      m4, [r2+0*FDEC_STRIDE]
    movd      m5, [r2+1*FDEC_STRIDE]
    movd      m6, [r2+2*FDEC_STRIDE]
    movd      m7, [r2+3*FDEC_STRIDE]
    movd [r2+0*FDEC_STRIDE], m0
    movd [r2+1*FDEC_STRIDE], m1
    movd [r2+2*FDEC_STRIDE], m2
    movd [r2+3*FDEC_STRIDE], m3
    punpckldq  m0, m1
    punpckldq  m2, m3
    punpckldq  m4, m5
    punpckldq  m6, m7
    punpcklqdq m0, m2
    punpcklqdq m4, m6
    mova      m7, [pb_sub4%2]
    pshufb    m0, m7
    pshufb    m4, m7
    mova      m7, [hsub_mul]
    punpckhbw m1, m0, m4
    punpcklbw m0, m4
    pmaddubsw m1, m7
    pmaddubsw m0, m7
%ifidn %1, ac
    movd     r2d, m0
    pand      m0, [pb_subacmask]
%endif
    mova [r0+ 0], m0
    por       m0, m1
    pxor      m2, m2
    mova [r0+16], m1
    pcmpeqb   m0, m2
    pmovmskb eax, m0
%ifidn %1, ac
    mov     [r3], r2w
%endif
    sub      eax, 0xffff
    shr      eax, 31
    RET
%endmacro

%if HIGH_BIT_DEPTH == 0
INIT_XMM ssse3
ZIGZAG_SUB_4x4   , frame
ZIGZAG_SUB_4x4 ac, frame
ZIGZAG_SUB_4x4   , field
ZIGZAG_SUB_4x4 ac, field
INIT_XMM avx
ZIGZAG_SUB_4x4   , frame
ZIGZAG_SUB_4x4 ac, frame
ZIGZAG_SUB_4x4   , field
ZIGZAG_SUB_4x4 ac, field

; vpermb gathers the scan order and zero-extends in one step
%macro ZIGZAG_SUB_4x4_ICL 2
%ifidn %1, ac
cglobal zigzag_sub_4x4%1_%2, 4,5
%else
cglobal zigzag_sub_4x4%1_%2, 3,5
%endif
    mov           r4, 0x000f000f000f000f
    kmovq         k1, r4
    mov          r4d, 0x55555555
    kmovd         k3, r4d
    vmovdqu8      m0 {k1}{z}, [r1]
    movd         xm1, [r2+0*FDEC_STRIDE]
    pinsrd       xm1, [r2+1*FDEC_STRIDE], 1
    pinsrd       xm1, [r2+2*FDEC_STRIDE], 2
    pinsrd       xm1, [r2+3*FDEC_STRIDE], 3
    mova         ym3, [zsub4_%2]
    psrlw        ym4, ym3, 8
    vpermb        m0 {k3}{z}, m3, m0
    vpermb        m1 {k3}{z}, m4, m1
%assign %%i 0
%rep 4
    mov          r4d, [r1+%%i*FENC_STRIDE]
    mov [r2+%%i*FDEC_STRIDE], r4d
%assign %%i %%i+1
%endrep
    psubw        ym0, ym1
%ifidn %1, ac
    movd         r4d, xm0
    mov          [r3], r4w
    mov          r4d, 0xfffe
    kmovw         k1, r4d
    vmovdqu16    ym0 {k1}{z}, ym0
%endif
    mova        [r0], ym0
    vptestmw      k0, ym0, ym0
    xor          eax, eax
    kortestw      k0, k0
    setnz         al
    RET
%endmacro

; 8x8: pack both blocks to 8 bytes per row, then vpermb each half of the scan
%macro ZIGZAG_SUB_8x8_ICL 1
cglobal zigzag_sub_8x8_%1, 3,4
    mov           r3, 0x00ff00ff00ff00ff
    kmovq         k1, r3
    mov           r3, 0x5555555555555555
    kmovq         k3, r3
    vmovdqu8      m0 {k1}{z}, [r1]
    vmovdqu8      m1 {k1}{z}, [r1+4*FENC_STRIDE]
    movq         xm2, [r2+0*FDEC_STRIDE]
    movhps       xm2, [r2+1*FDEC_STRIDE]
    movq         xm3, [r2+2*FDEC_STRIDE]
    movhps       xm3, [r2+3*FDEC_STRIDE]
    movq         xm4, [r2+4*FDEC_STRIDE]
    movhps       xm4, [r2+5*FDEC_STRIDE]
    movq         xm5, [r2+6*FDEC_STRIDE]
    movhps       xm5, [r2+7*FDEC_STRIDE]
    mova          m6, [zsub8_pack]
    vpermt2b      m0, m6, m1            ; src rows 0-7
    vinserti32x4 ym2, ym2, xm3, 1
    vinserti32x4 ym4, ym4, xm5, 1
    vinserti64x4  m2, m2, ym4, 1        ; dst rows 0-7
    mova          m6, [zsub8_%1 %+ 8]
    psrlw         m7, m6, 8
    vpermb        m1 {k3}{z}, m6, m0
    vpermb        m3 {k3}{z}, m7, m0
    vpermb        m4 {k3}{z}, m6, m2
    vpermb        m5 {k3}{z}, m7, m2
    psubw         m1, m4
    psubw         m3, m5
    vextracti32x4 xm4, m0, 1
    vextracti32x4 xm5, m0, 2
    vextracti32x4 xm6, m0, 3
    movq   [r2+0*FDEC_STRIDE], xm0
    movhps [r2+1*FDEC_STRIDE], xm0
    movq   [r2+2*FDEC_STRIDE], xm4
    movhps [r2+3*FDEC_STRIDE], xm4
    movq   [r2+4*FDEC_STRIDE], xm5
    movhps [r2+5*FDEC_STRIDE], xm5
    movq   [r2+6*FDEC_STRIDE], xm6
    movhps [r2+7*FDEC_STRIDE], xm6
    mova      [r0], m1
    mova   [r0+64], m3
    vptestmw      k0, m1, m1
    vptestmw      k1, m3, m3
    xor          eax, eax
    kortestd      k0, k1
    setnz         al
    RET
%endmacro

INIT_ZMM avx512icl
ZIGZAG_SUB_4x4_ICL   , frame
ZIGZAG_SUB_4x4_ICL ac, frame
ZIGZAG_SUB_4x4_ICL   , field
ZIGZAG_SUB_4x4_ICL ac, field
ZIGZAG_SUB_8x8_ICL frame
ZIGZAG_SUB_8x8_ICL field
%endif ; !HIGH_BIT_DEPTH

%if HIGH_BIT_DEPTH
;-----------------------------------------------------------------------------
; int zigzag_sub_4x4[ac]_{frame,field}( int32_t level[16], const uint16_t *src, uint16_t *dst[, int32_t *dc] )
;-----------------------------------------------------------------------------
; avx512icl: the 4 rows as qwords of a ymm (merge-masked broadcasts), the word
; differences put in scan order by vpermw and widened with vpmovsxwd, nz from
; vptestmw
%macro ZIGZAG_SUB_4x4_HBD_ICL 2 ; ac, frame/field
%ifidn %1, ac
cglobal zigzag_sub_4x4%1_%2, 4,5
%else
cglobal zigzag_sub_4x4%1_%2, 3,5
%endif
    mov         r4d, 2
    kmovb        k2, r4d
    mov         r4d, 4
    kmovb        k3, r4d
    mov         r4d, 8
    kmovb        k4, r4d
    movq          xm0, [r1+0*FENC_STRIDEB]
    vpbroadcastq  ym0 {k2}, [r1+1*FENC_STRIDEB]
    vpbroadcastq  ym0 {k3}, [r1+2*FENC_STRIDEB]
    vpbroadcastq  ym0 {k4}, [r1+3*FENC_STRIDEB]
    movq          xm1, [r2+0*FDEC_STRIDEB]
    vpbroadcastq  ym1 {k2}, [r2+1*FDEC_STRIDEB]
    vpbroadcastq  ym1 {k3}, [r2+2*FDEC_STRIDEB]
    vpbroadcastq  ym1 {k4}, [r2+3*FDEC_STRIDEB]
    movq   [r2+0*FDEC_STRIDEB], xm0
    movhps [r2+1*FDEC_STRIDEB], xm0
    vextracti32x4 xm2, ym0, 1
    movq   [r2+2*FDEC_STRIDEB], xm2
    movhps [r2+3*FDEC_STRIDEB], xm2
    psubw         ym1, ym0, ym1
    mova          ym2, [zsub4_%2_hbd]
    vpermw        ym1, ym2, ym1
    vpmovsxwd      m2, ym1
%ifidn %1, ac
    movd         [r3], xm2
    mov          r4d, 0xfffe
    kmovw         k1, r4d
    vmovdqa32      m2 {k1}{z}, m2
    vptestmw      k1 {k1}, ym1, ym1
%else
    vptestmw      k1, ym1, ym1
%endif
    movu         [r0], m2
    xor          eax, eax
    kortestw      k1, k1
    setnz         al
    RET
%endmacro

;-----------------------------------------------------------------------------
; int zigzag_sub_8x8_{frame,field}( int32_t level[64], const uint16_t *src, uint16_t *dst )
;-----------------------------------------------------------------------------
; avx512icl: 4 rows per zmm (merge-masked broadcasts), the word differences
; put in scan order by vpermi2w and widened with vpmovsxwd, nz from vptestmw
%macro ZIGZAG_SUB_8x8_HBD_ICL 1 ; frame/field
cglobal zigzag_sub_8x8_%1, 3,4
    mov         r3d, 0x00f0
    kmovw        k5, r3d
    mov         r3d, 0x0f00
    kmovw        k6, r3d
    mov         r3d, 0xf000
    kmovw        k7, r3d
%assign zsub_r 0
%rep 2
    movu            xm %+ zsub_r, [r1+(4*zsub_r+0)*FENC_STRIDEB]
    vbroadcasti32x4  m %+ zsub_r {k5}, [r1+(4*zsub_r+1)*FENC_STRIDEB]
    vbroadcasti32x4  m %+ zsub_r {k6}, [r1+(4*zsub_r+2)*FENC_STRIDEB]
    vbroadcasti32x4  m %+ zsub_r {k7}, [r1+(4*zsub_r+3)*FENC_STRIDEB]
    movu            xm4, [r2+(4*zsub_r+0)*FDEC_STRIDEB]
    vbroadcasti32x4  m4 {k5}, [r2+(4*zsub_r+1)*FDEC_STRIDEB]
    vbroadcasti32x4  m4 {k6}, [r2+(4*zsub_r+2)*FDEC_STRIDEB]
    vbroadcasti32x4  m4 {k7}, [r2+(4*zsub_r+3)*FDEC_STRIDEB]
    movu   [r2+(4*zsub_r+0)*FDEC_STRIDEB], xm %+ zsub_r
    vextracti32x4 [r2+(4*zsub_r+1)*FDEC_STRIDEB], m %+ zsub_r, 1
    vextracti32x4 [r2+(4*zsub_r+2)*FDEC_STRIDEB], m %+ zsub_r, 2
    vextracti32x4 [r2+(4*zsub_r+3)*FDEC_STRIDEB], m %+ zsub_r, 3
    psubw            m %+ zsub_r, m4
%assign zsub_r zsub_r+1
%endrep
    vptestmw      k1, m0, m0
    vptestmw      k2, m1, m1
    mova          m2, [zsub8_%1_hbd]
    mova          m3, [zsub8_%1_hbd+64]
    vpermi2w      m2, m0, m1                 ; scan 0-31
    vpermi2w      m3, m0, m1                 ; scan 32-63
    vpmovsxwd     m0, ym2
    vextracti64x4 ym2, m2, 1
    vpmovsxwd     m2, ym2
    vpmovsxwd     m1, ym3
    vextracti64x4 ym3, m3, 1
    vpmovsxwd     m3, ym3
    movu  [r0+0*64], m0
    movu  [r0+1*64], m2
    movu  [r0+2*64], m1
    movu  [r0+3*64], m3
    xor          eax, eax
    kortestd      k1, k2
    setnz         al
    RET
%endmacro

INIT_ZMM avx512icl
ZIGZAG_SUB_4x4_HBD_ICL   , frame
ZIGZAG_SUB_4x4_HBD_ICL ac, frame
ZIGZAG_SUB_4x4_HBD_ICL   , field
ZIGZAG_SUB_4x4_HBD_ICL ac, field
ZIGZAG_SUB_8x8_HBD_ICL frame
ZIGZAG_SUB_8x8_HBD_ICL field
%endif ; HIGH_BIT_DEPTH

%if HIGH_BIT_DEPTH == 0
INIT_XMM xop
cglobal zigzag_scan_8x8_field, 2,3,7
    lea        r2, [pb_scan8field1]
    %define off(m) (r2+m-pb_scan8field1)
    mova       m0, [r1+  0]
    mova       m1, [r1+ 16]
    vpperm     m5, m0, m1, [off(pb_scan8field1)]
    mova [r0+  0], m5
    vpperm     m0, m0, m1, [off(pb_scan8field2a)]
    mova       m2, [r1+ 32]
    mova       m3, [r1+ 48]
    vpperm     m5, m2, m3, [off(pb_scan8field2b)]
    por        m5, m0
    mova [r0+ 16], m5
    mova       m4, [off(pb_scan8field3b)]
    vpperm     m1, m1, m2, [off(pb_scan8field3a)]
    mova       m0, [r1+ 64]
    vpperm     m5, m3, m0, m4
    por        m5, m1
    mova [r0+ 32], m5
    ; 4b, 5b are the same as pb_scan8field3b.
    ; 5a is the same as pb_scan8field4a.
    mova       m5, [off(pb_scan8field4a)]
    vpperm     m2, m2, m3, m5
    mova       m1, [r1+ 80]
    vpperm     m6, m0, m1, m4
    por        m6, m2
    mova [r0+ 48], m6
    vpperm     m3, m3, m0, m5
    mova       m2, [r1+ 96]
    vpperm     m5, m1, m2, m4
    por        m5, m3
    mova [r0+ 64], m5
    vpperm     m5, m0, m1, [off(pb_scan8field6)]
    mova [r0+ 80], m5
    vpperm     m5, m1, m2, [off(pb_scan8field7)]
    mov       r2d, [r1+ 98]
    mov  [r0+ 90], r2d
    mova [r0+ 96], m5
    mova       m3, [r1+112]
    movd [r0+104], m3
    mov       r2d, [r1+108]
    mova [r0+112], m3
    mov  [r0+112], r2d
    %undef off
    RET

cglobal zigzag_scan_8x8_frame, 2,3,8
    lea        r2, [pb_scan8frame1]
    %define off(m) (r2+m-pb_scan8frame1)
    mova       m7, [r1+ 16]
    mova       m3, [r1+ 32]
    vpperm     m7, m7, m3, [off(pb_scan8framet1)] ;  8  9 14 15 16 17 21 22
    mova       m2, [r1+ 48]
    vpperm     m0, m3, m2, [off(pb_scan8framet2)] ; 18 19 20 23 25 31 26 30
    mova       m1, [r1+ 80]
    mova       m4, [r1+ 64]
    vpperm     m3, m4, m1, [off(pb_scan8framet3)] ; 32 33 37 38 40 43 44 45
    vpperm     m6, m0, m3, [off(pb_scan8framet4)] ; 18 23 25 31 32 38 40 45
    vpperm     m5, m0, m3, [off(pb_scan8framet5)] ; 19 20 26 30 33 37 43 44
    vpperm     m3, m2, m4, [off(pb_scan8framet6)] ; 24 27 28 29 34 35 36 39
    mova       m4, [r1+ 96]
    vpperm     m4, m1, m4, [off(pb_scan8framet7)] ; 41 42 46 47 48 49 54 55
    mova       m1, [r1+  0]
    vpperm     m2, m1, m3, [off(pb_scan8framet8)] ;  0  1  2  7 24 28 29 36
    vpperm     m1, m2, m7, [off(pb_scan8frame1)]  ;  0  8  1  2  9 16 24 17
    mova [r0+  0], m1
    movh       m0, [r1+  6]
    movhps     m0, [r1+ 20]                       ;  3  4  5  6 10 11 12 13
    vpperm     m1, m0, m6, [off(pb_scan8frame2)]  ; 10  3  4 11 18 25 32 40
    mova [r0+ 16], m1
    vpperm     m1, m0, m5, [off(pb_scan8frame3)]  ; 33 26 19 12  5  6 13 20
    mova [r0+ 32], m1
    vpperm     m1, m2, m7, [off(pb_scan8frame5)]  ; 28 21 14  7 15 22 29 36
    mova [r0+ 64], m1
    movh       m0, [r1+100]
    movhps     m0, [r1+114]                       ; 50 51 52 53 57 58 59 60
    vpperm     m1, m5, m0, [off(pb_scan8frame6)]  ; 43 50 57 58 51 44 37 30
    mova [r0+ 80], m1
    vpperm     m1, m6, m0, [off(pb_scan8frame7)]  ; 23 31 38 45 52 59 60 53
    mova [r0+ 96], m1
    mova       m1, [r1+112]
    vpperm     m0, m3, m1, [off(pb_scan8framet9)] ; 27 34 35 39 56 61 62 63
    vpperm     m1, m0, m4, [off(pb_scan8frame4)]  ; 27 34 41 48 56 49 42 35
    mova [r0+ 48], m1
    vpperm     m1, m0, m4, [off(pb_scan8frame8)]  ; 46 39 47 54 61 62 55 63
    mova [r0+112], m1
    %undef off
    RET
%endif

;-----------------------------------------------------------------------------
; void zigzag_interleave_8x8_cavlc( int16_t *dst, int16_t *src, uint8_t *nnz )
;-----------------------------------------------------------------------------
%macro INTERLEAVE 2
    mova     m0, [r1+(%1*4+ 0)*SIZEOF_PIXEL]
    mova     m1, [r1+(%1*4+ 8)*SIZEOF_PIXEL]
    mova     m2, [r1+(%1*4+16)*SIZEOF_PIXEL]
    mova     m3, [r1+(%1*4+24)*SIZEOF_PIXEL]
    TRANSPOSE4x4%2 0,1,2,3,4
    mova     [r0+(%1+ 0)*SIZEOF_PIXEL], m0
    mova     [r0+(%1+32)*SIZEOF_PIXEL], m1
    mova     [r0+(%1+64)*SIZEOF_PIXEL], m2
    mova     [r0+(%1+96)*SIZEOF_PIXEL], m3
    packsswb m0, m1
    ACCUM   por, 6, 2, %1
    ACCUM   por, 7, 3, %1
    ACCUM   por, 5, 0, %1
%endmacro

%macro ZIGZAG_8x8_CAVLC 1
cglobal zigzag_interleave_8x8_cavlc, 3,3,8
    INTERLEAVE  0, %1
    INTERLEAVE  8, %1
    INTERLEAVE 16, %1
    INTERLEAVE 24, %1
    packsswb   m6, m7
    packsswb   m5, m6
    packsswb   m5, m5
    pxor       m0, m0
%if HIGH_BIT_DEPTH
    packsswb   m5, m5
%endif
    pcmpeqb    m5, m0
    paddb      m5, [pb_1]
    movd      r0d, m5
    mov    [r2+0], r0w
    shr       r0d, 16
    mov    [r2+8], r0w
    RET
%endmacro

%if HIGH_BIT_DEPTH
INIT_XMM sse2
ZIGZAG_8x8_CAVLC D
INIT_XMM avx
ZIGZAG_8x8_CAVLC D
%else
INIT_MMX mmx
ZIGZAG_8x8_CAVLC W
%endif

%macro INTERLEAVE_XMM 1
    mova   m0, [r1+%1*4+ 0]
    mova   m1, [r1+%1*4+16]
    mova   m4, [r1+%1*4+32]
    mova   m5, [r1+%1*4+48]
    SBUTTERFLY wd, 0, 1, 6
    SBUTTERFLY wd, 4, 5, 7
    SBUTTERFLY wd, 0, 1, 6
    SBUTTERFLY wd, 4, 5, 7
    movh   [r0+%1+  0], m0
    movhps [r0+%1+ 32], m0
    movh   [r0+%1+ 64], m1
    movhps [r0+%1+ 96], m1
    movh   [r0+%1+  8], m4
    movhps [r0+%1+ 40], m4
    movh   [r0+%1+ 72], m5
    movhps [r0+%1+104], m5
    ACCUM por, 2, 0, %1
    ACCUM por, 3, 1, %1
    por    m2, m4
    por    m3, m5
%endmacro

%if HIGH_BIT_DEPTH == 0
%macro ZIGZAG_8x8_CAVLC 0
cglobal zigzag_interleave_8x8_cavlc, 3,3,8
    INTERLEAVE_XMM  0
    INTERLEAVE_XMM 16
    packsswb m2, m3
    pxor     m5, m5
    packsswb m2, m2
    packsswb m2, m2
    pcmpeqb  m5, m2
    paddb    m5, [pb_1]
    movd    r0d, m5
    mov  [r2+0], r0w
    shr     r0d, 16
    mov  [r2+8], r0w
    RET
%endmacro

INIT_XMM sse2
ZIGZAG_8x8_CAVLC
INIT_XMM avx
ZIGZAG_8x8_CAVLC

INIT_YMM avx2
cglobal zigzag_interleave_8x8_cavlc, 3,3,6
    mova   m0, [r1+ 0]
    mova   m1, [r1+32]
    mova   m2, [r1+64]
    mova   m3, [r1+96]
    mova   m5, [deinterleave_shufd]
    SBUTTERFLY wd, 0, 1, 4
    SBUTTERFLY wd, 2, 3, 4
    SBUTTERFLY wd, 0, 1, 4
    SBUTTERFLY wd, 2, 3, 4
    vpermd m0, m5, m0
    vpermd m1, m5, m1
    vpermd m2, m5, m2
    vpermd m3, m5, m3
    mova [r0+  0], xm0
    mova [r0+ 16], xm2
    vextracti128 [r0+ 32], m0, 1
    vextracti128 [r0+ 48], m2, 1
    mova [r0+ 64], xm1
    mova [r0+ 80], xm3
    vextracti128 [r0+ 96], m1, 1
    vextracti128 [r0+112], m3, 1

    packsswb m0, m2          ; nnz0, nnz1
    packsswb m1, m3          ; nnz2, nnz3
    packsswb m0, m1          ; {nnz0,nnz2}, {nnz1,nnz3}
    vpermq   m0, m0, q3120   ; {nnz0,nnz1}, {nnz2,nnz3}
    pxor     m5, m5
    pcmpeqq  m0, m5
    pmovmskb r0d, m0
    not     r0d
    and     r0d, 0x01010101
    mov  [r2+0], r0w
    shr     r0d, 16
    mov  [r2+8], r0w
    RET
%endif ; !HIGH_BIT_DEPTH

%if HIGH_BIT_DEPTH
INIT_ZMM avx512
cglobal zigzag_scan_4x4_frame, 2,2
    mova        m0, [scan_frame_avx512]
    vpermd      m0, m0, [r1]
    mova      [r0], m0
    RET

cglobal zigzag_scan_4x4_field, 2,2
    mova        m0, [r1]
    pshufd    xmm1, [r1+8], q3102
    mova      [r0], m0
    movu    [r0+8], xmm1
    RET

INIT_ZMM avx512icl
cglobal zigzag_scan_4x4_field, 2,2
    vpmovzxbd   m0, [scan4field_perm]
    vpermd      m0, m0, [r1]
    mova      [r0], m0
    RET
INIT_ZMM avx512

cglobal zigzag_scan_8x8_frame, 2,2
    psrld       m0, [scan_frame_avx512], 4
    mova        m1, [r1+0*64]
    mova        m2, [r1+1*64]
    mova        m3, [r1+2*64]
    mova        m4, [r1+3*64]
    mov        r1d, 0x01fe7f80
    kmovd       k1, r1d
    kshiftrd    k2, k1, 16
    vpermd      m5, m0, m3  ; __ __ __ __ __ __ __ __ __ __ __ __ __ __ 32 40
    psrld       m6, m0, 5
    vpermi2d    m0, m1, m2  ;  0  8  1  2  9 16 24 17 10  3  4 11 18 25 __ __
    vmovdqa64   m0 {k1}, m5
    mova [r0+0*64], m0
    mova        m5, m1
    vpermt2d    m1, m6, m2  ; __ 26 19 12  5  6 13 20 27 __ __ __ __ __ __ __
    psrld       m0, m6, 5
    vpermi2d    m6, m3, m4  ; 33 __ __ __ __ __ __ __ __ 34 41 48 56 49 42 35
    vmovdqa32   m6 {k2}, m1
    mova [r0+1*64], m6
    vpermt2d    m5, m0, m2  ; 28 21 14  7 15 22 29 __ __ __ __ __ __ __ __ 30
    psrld       m1, m0, 5
    vpermi2d    m0, m3, m4  ; __ __ __ __ __ __ __ 36 43 50 57 58 51 44 37 __
    vmovdqa32   m5 {k1}, m0
    mova [r0+2*64], m5
    vpermt2d    m3, m1, m4  ; __ __ 38 45 52 59 60 53 46 39 47 54 61 62 55 63
    vpermd      m2, m1, m2  ; 23 31 __ __ __ __ __ __ __ __ __ __ __ __ __ __
    vmovdqa64   m2 {k2}, m3
    mova [r0+3*64], m2
    RET

cglobal zigzag_scan_8x8_field, 2,2
    mova        m0, [scan_field_avx512]
    mova        m1, [r1+0*64]
    mova        m2, [r1+1*64]
    mova        m3, [r1+2*64]
    mova        m4, [r1+3*64]
    mov        r1d, 0x3f
    kmovb       k1, r1d
    psrld       m5, m0, 5
    vpermi2d    m0, m1, m2
    vmovdqa64   m1 {k1}, m3 ; 32 33 34 35 36 37 38 39 40 41 42 43 12 13 14 15
    vpermt2d    m1, m5, m2
    psrld       m5, 5
    vmovdqa64   m2 {k1}, m4 ; 48 49 50 51 52 53 54 55 56 57 58 59 28 29 30 31
    vpermt2d    m2, m5, m3
    psrld       m5, 5
    vpermt2d    m3, m5, m4
    mova [r0+0*64], m0
    mova [r0+1*64], m1
    mova [r0+2*64], m2
    mova [r0+3*64], m3
    RET

cglobal zigzag_interleave_8x8_cavlc, 3,3
    mova        m0, [cavlc_shuf_avx512]
    mova        m1, [r1+0*64]
    mova        m2, [r1+1*64]
    mova        m3, [r1+2*64]
    mova        m4, [r1+3*64]
    kxnorb      k1, k1, k1
    por         m7, m1, m2
    psrld       m5, m0, 5
    vpermi2d    m0, m1, m2        ; a0 a1 b0 b1
    vpternlogd  m7, m3, m4, 0xfe  ; m1|m2|m3|m4
    psrld       m6, m5, 5
    vpermi2d    m5, m3, m4        ; b2 b3 a2 a3
    vptestmd    k0, m7, m7
    vpermt2d    m1, m6, m2        ; c0 c1 d0 d1
    psrld       m6, 5
    vpermt2d    m3, m6, m4        ; d2 d3 c2 c3
    vshufi32x4  m2, m0, m5, q1032 ; b0 b1 b2 b3
    vmovdqa32   m5 {k1}, m0       ; a0 a1 a2 a3
    vshufi32x4  m4, m1, m3, q1032 ; d0 d1 d2 d3
    vmovdqa32   m3 {k1}, m1       ; c0 c1 c2 c3
    mova [r0+0*64], m5
    mova [r0+1*64], m2
    mova [r0+2*64], m3
    mova [r0+3*64], m4
    kmovw      r1d, k0
    test       r1d, 0x1111
    setnz     [r2]
    test       r1d, 0x2222
    setnz   [r2+1]
    test       r1d, 0x4444
    setnz   [r2+8]
    test       r1d, 0x8888
    setnz   [r2+9]
    RET

%else ; !HIGH_BIT_DEPTH
INIT_YMM avx512
cglobal zigzag_scan_4x4_frame, 2,2
    mova        m0, [scan_frame_avx512]
    vpermw      m0, m0, [r1]
    mova      [r0], m0
    RET

cglobal zigzag_scan_4x4_field, 2,2
    mova        m0, [r1]
    pshuflw   xmm1, [r1+4], q3102
    mova      [r0], m0
    movq    [r0+4], xmm1
    RET

INIT_YMM avx512icl
cglobal zigzag_scan_4x4_field, 2,2
    vpmovzxbw   m0, [scan4field_perm]
    vpermw      m0, m0, [r1]
    mova      [r0], m0
    RET

INIT_ZMM avx512
cglobal zigzag_scan_8x8_frame, 2,2
    psrlw       m0, [scan_frame_avx512], 4
scan8_avx512:
    mova        m1, [r1]
    mova        m2, [r1+64]
    psrlw       m3, m0, 6
    vpermi2w    m0, m1, m2
    vpermt2w    m1, m3, m2
    mova      [r0], m0
    mova   [r0+64], m1
    RET

cglobal zigzag_scan_8x8_field, 2,2
    mova        m0, [scan_field_avx512]
    jmp scan8_avx512

cglobal zigzag_interleave_8x8_cavlc, 3,3
    mova       m0, [cavlc_shuf_avx512]
    mova       m1, [r1]
    mova       m2, [r1+64]
    psrlw      m3, m0, 6
    vpermi2w   m0, m1, m2
    vpermt2w   m1, m3, m2
    kxnorb     k2, k2, k2
    vptestmd   k0, m0, m0
    vptestmd   k1, m1, m1
    mova     [r0], m0
    mova  [r0+64], m1
    ktestw     k2, k0
    setnz    [r2]
    setnc  [r2+1]
    ktestw     k2, k1
    setnz  [r2+8]
    setnc  [r2+9]
    RET
%endif ; !HIGH_BIT_DEPTH
