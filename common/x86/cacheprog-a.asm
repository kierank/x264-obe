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
