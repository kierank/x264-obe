;*****************************************************************************
;* cacheprog-a.asm: x86 progressive macroblock cache load/save
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

%include "x86inc.asm"
%include "x86util.asm"

SECTION_RODATA 64

; save_nnz: the nnz rows are cache dwords 3,5,7,9 / 13,15,17,19 / 23,25,27,29;
; avx512 indexes [cache dwords 0..15 | 14..29]
save_nnz_idx:  dd 3,5,7,9,13,15,19,21,25,27,29,31,0,0,0,0
save_nnz_perm: dd 0,2,4,6,1,3,5,7
save_nnz_k420: dw 0x033f
save_nnz_k422: dw 0x0fff

; load_nnz: vpermi2b indices over [nnz_top | nnz_left] for cache bytes 0..55 (store at +0)
; and 56..119 (store at +56), store masks; intra4x4 over [i4x4_top | i4x4_left] to cache bytes 4..35
ALIGN 64
load_nnz_idx0_420:
    db 0,0,0,0,12,13,14,15,0,0,0,67,0,0,0,0,0,0,0,71,0,0,0,0,0,0,0,75,0,0,0,0
    db 0,0,0,79,0,0,0,0,0,0,0,0,20,21,22,23,0,0,0,81,0,0,0,0,0,0,0,0,0,0,0,0
load_nnz_idx1_420:
    db 0,0,0,85,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,36,37,38,39
    db 0,0,0,97,0,0,0,0,0,0,0,101,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
load_nnz_idx0_422:
    db 0,0,0,0,12,13,14,15,0,0,0,67,0,0,0,0,0,0,0,71,0,0,0,0,0,0,0,75,0,0,0,0
    db 0,0,0,79,0,0,0,0,0,0,0,0,28,29,30,31,0,0,0,81,0,0,0,0,0,0,0,0,0,0,0,0
load_nnz_idx1_422:
    db 0,0,0,85,0,0,0,0,0,0,0,89,0,0,0,0,0,0,0,93,0,0,0,0,0,0,0,0,44,45,46,47
    db 0,0,0,97,0,0,0,0,0,0,0,101,0,0,0,0,0,0,0,105,0,0,0,0,0,0,0,109,0,0,0,0

load_nnz_i4_idx: db 0,1,2,3,0,0,0,12,0,0,0,0,0,0,0,13,0,0,0,0,0,0,0,14,0,0,0,0,0,0,0,11
load_nnz_k0_420: dq 0x0008f008080808f0
load_nnz_k1_420: dq 0x00000808f0000008
load_nnz_k0_422: dq 0x0008f008080808f0
load_nnz_k1_422: dq 0x08080808f0080808
load_nnz_i4_k:   dd 0x8080808f

SECTION .text

;-----------------------------------------------------------------------------
; void cacheprog_save_nnz( uint8_t nnz[48], uint8_t nnz_cache[120] )
;-----------------------------------------------------------------------------
INIT_YMM avx2
cglobal cacheprog_save_nnz_420, 2,2,3
    mova           m2, [save_nnz_perm]
    movu           m0, [r1+12]
    vpermd         m0, m2, m0
    movu         [r0], xm0
    movu           m1, [r1+52]
    vpermd         m1, m2, m1
    movq      [r0+16], xm1
    movu          xm0, [r1+92]
    pshufd        xm0, xm0, q2020
    movq      [r0+32], xm0
    RET

cglobal cacheprog_save_nnz_422, 2,2,3
    mova           m2, [save_nnz_perm]
    movu           m0, [r1+12]
    vpermd         m0, m2, m0
    movu         [r0], xm0
    movu           m1, [r1+52]
    vpermd         m1, m2, m1
    movu      [r0+16], xm1
    movu           m0, [r1+88]
    vpermd         m0, m2, m0
    vextracti128 [r0+32], m0, 1
    RET

%macro SAVE_NNZ_AVX512 1 ; chroma format
cglobal cacheprog_save_nnz_%1, 2,2,2
    kmovw          k1, [save_nnz_k%1]
    mova           m0, [save_nnz_idx]
    movu           m1, [r1]
    vpermi2d       m0, m1, [r1+56]
    vmovdqu32 [r0]{k1}, m0
    RET
%endmacro

INIT_ZMM avx512
SAVE_NNZ_AVX512 420
SAVE_NNZ_AVX512 422

;-----------------------------------------------------------------------------
; void cacheprog_load_nnz( uint8_t nnz_cache[120], int8_t i4x4_cache[40], uint8_t *nnz_top,
;                          uint8_t *nnz_left, int8_t *i4x4_top, int8_t *i4x4_left )
; reads 64 bytes at nnz_top/nnz_left, 8 at i4x4_top/i4x4_left
;-----------------------------------------------------------------------------
%macro LOAD_NNZ 1 ; chroma format
cglobal cacheprog_load_nnz_%1, 6,6,6
    movu            m0, [r2]
    movu            m1, [r3]
    mova            m2, [load_nnz_idx0_%1]
    mova            m3, [load_nnz_idx1_%1]
    vpermi2b        m2, m0, m1
    vpermi2b        m3, m0, m1
    kmovq           k1, [load_nnz_k0_%1]
    kmovq           k2, [load_nnz_k1_%1]
    vmovdqu8   [r0]{k1}, m2
    vmovdqu8 [r0+56]{k2}, m3
    movq           xm4, [r4]
    movhps         xm4, [r5]
    mova           ym5, [load_nnz_i4_idx]
    vpermb         ym5, ym5, ym4
    kmovd           k3, [load_nnz_i4_k]
    vmovdqu8 [r1+4]{k3}, ym5
    RET
%endmacro

INIT_ZMM avx512icl
LOAD_NNZ 420
LOAD_NNZ 422
