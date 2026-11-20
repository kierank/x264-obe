;*****************************************************************************
;* mbcache-a.asm: x86 macroblock cache load helpers
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

; x264_fref_base_t: p_fref[2][X264_REF_MAX*2][12], then p_fref_w[X264_REF_MAX*2]
%define FREF_ROW  (12*8)
%define FREF_LIST (32*FREF_ROW)
%define FREF_W    (2*FREF_LIST)

SECTION_RODATA 32

mbaff_deint_shuf: db 0,2,4,6,8,10,12,14,1,3,5,7,9,11,13,15

SECTION .text

;-----------------------------------------------------------------------------
; void mb_fref_load( pixel **dst, pixel **src, intptr_t off_y, intptr_t off_c, int n0, int n1 )
; 4:2:0 / 4:2:2. Rows j < n of list l: slots 0-3 += off_y, 4-5 += off_c;
; p_fref_w[j < n0] += off_y. Nothing else is written.
;-----------------------------------------------------------------------------
INIT_YMM avx2
cglobal mb_fref_load, 6,7,4
%if HIGH_BIT_DEPTH
    add        r2, r2
    add        r3, r3
%endif
    movq      xm0, r2q
    movq      xm1, r3q
    vpbroadcastq m0, xm0
    vpbroadcastq xm1, xm1
    lea        r2, [r0+FREF_W]
    lea        r3, [r1+FREF_W]
    lea       r6d, [r4-4]
    test      r6d, r6d
    jl .w_tail
.w4:
    paddq      m2, m0, [r3]
    movu     [r2], m2
    add        r2, 32
    add        r3, 32
    sub       r6d, 4
    jge .w4
.w_tail:                   ; r6d = rem-4, rem = n0&3
    test      r6b, 2
    jz .w1
    paddq     xm2, xm0, [r3]
    movu     [r2], xm2
    add        r2, 16
    add        r3, 16
.w1:
    test      r6b, 1
    jz .l0
    movq      xm2, [r3]
    paddq     xm2, xm0
    movq     [r2], xm2
.l0:
    lea        r2, [r0+FREF_LIST]
    lea        r3, [r1+FREF_LIST]
    test      r4d, r4d
    jz .l1
.loop0:
    paddq      m2, m0, [r1]
    paddq     xm3, xm1, [r1+32]
    movu     [r0], m2
    movu  [r0+32], xm3
    add        r0, FREF_ROW
    add        r1, FREF_ROW
    dec       r4d
    jg .loop0
.l1:
    test      r5d, r5d
    jz .end
.loop1:
    paddq      m2, m0, [r3]
    paddq     xm3, xm1, [r3+32]
    movu     [r2], m2
    movu  [r2+32], xm3
    add        r2, FREF_ROW
    add        r3, FREF_ROW
    dec       r5d
    jg .loop1
.end:
    RET

; Rows as one run of zmm stores, 8 pointers each, from slot 4 of row 0. Row j
; of mb.pic.p_fref (and of the table, see its pad) starts at 32 + 96*j mod 64,
; so after the ymm of row 0's luma every store is a whole 64-byte line.
; The run also writes slots 6-11 of rows < n with src's (0 in both, 4:2:0/4:2:2).
; m0: off_y x4, m1: [y y y y c c 0 0], m4: [c c 0 0 0 0 0 0], m5: [0 0 0 0 y y y y]
%macro FREF_ROWS 3 ; dst, src, n
    test      %3d, %3d
    jz %%end
    paddq     ym3, ym0, [%2]
    paddq      m2, m4, [%2+32]
    movu     [%1], ym3
    movu  [%1+32], m2
    dec       %3d
    jz %%end
%%loop:
    paddq      m2, m1, [%2+96]          ; row r 0-7
    movu  [%1+96], m2
    dec       %3d
    jz %%end
    paddq      m2, m5, [%2+160]         ; row r 8-11, row r+1 0-3
    paddq      m3, m4, [%2+224]         ; row r+1 4-11
    movu [%1+160], m2
    movu [%1+224], m3
    add        %1, 2*FREF_ROW
    add        %2, 2*FREF_ROW
    dec       %3d
    jg %%loop
%%end:
%endmacro

INIT_ZMM avx512
cglobal mb_fref_load, 6,7,6
%if HIGH_BIT_DEPTH
    add        r2, r2
    add        r3, r3
%endif
    mov       r6d, 0x0f
    kmovw      k1, r6d
    mov       r6d, 0x30
    kmovw      k2, r6d
    mov       r6d, 0x03
    kmovw      k3, r6d
    mov       r6d, 0xf0
    kmovw      k4, r6d
    vpbroadcastq m0, r2q
    vpbroadcastq m1 {k1}{z}, r2q
    vpbroadcastq m1 {k2}, r3q
    vpbroadcastq m4 {k3}{z}, r3q
    vpbroadcastq m5 {k4}{z}, r2q
    ; weighted: whole ymm/xmm/qword stores of exactly n0 pointers
    lea        r2, [r0+FREF_W]
    lea        r3, [r1+FREF_W]
    lea       r6d, [r4-4]
    test      r6d, r6d
    jl .w_tail
.w4:
    paddq     ym2, ym0, [r3]
    movu     [r2], ym2
    add        r2, 32
    add        r3, 32
    sub       r6d, 4
    jge .w4
.w_tail:
    test      r6b, 2
    jz .w1
    paddq     xm2, xm0, [r3]
    movu     [r2], xm2
    add        r2, 16
    add        r3, 16
.w1:
    test      r6b, 1
    jz .l0
    movq      xm2, [r3]
    paddq     xm2, xm0
    movq     [r2], xm2
.l0:
    lea        r2, [r0+FREF_LIST]
    lea        r3, [r1+FREF_LIST]
    FREF_ROWS  r0, r1, r4
    FREF_ROWS  r2, r3, r5
    RET

%if ARCH_X86_64 && HIGH_BIT_DEPTH == 0
;-----------------------------------------------------------------------------
; void mbaff_load_luma( pixel *fenc, pixel *fdec, pixel *src_fenc, pixel *src_fdec,
;                       intptr_t stride, pixel *intra )
; MBAFF cache_load, luma: fenc lines 0-15 = src_fenc lines; fdec line -1,
; x -1..23 = intra[-1..23]; fdec column -1 of lines 0-15 = src_fdec[-1] lines.
;-----------------------------------------------------------------------------
INIT_YMM avx2
cglobal mbaff_load_luma, 6,7,2
    movu      xm0, [r5-1]
    movu      xm1, [r5+8]
    movu [r1-FDEC_STRIDE-1], xm0
    movu [r1-FDEC_STRIDE+8], xm1
    lea        r6, [r4*3]
%assign mbl_i 0
%rep 4
    movu      xm0, [r2]
    vinserti128 m0, m0, [r2+r4], 1
    movu      xm1, [r2+r4*2]
    vinserti128 m1, m1, [r2+r6], 1
    mova [r0+mbl_i*64], m0
    mova [r0+mbl_i*64+32], m1
%if mbl_i < 3
    lea        r2, [r2+r4*4]
%endif
%assign mbl_i mbl_i+1
%endrep
%assign mbl_i 0
%rep 4
    movzx     r2d, byte [r3-1]
    mov [r1-1+(4*mbl_i+0)*FDEC_STRIDE], r2b
    movzx     r2d, byte [r3+r4-1]
    mov [r1-1+(4*mbl_i+1)*FDEC_STRIDE], r2b
    movzx     r2d, byte [r3+r4*2-1]
    mov [r1-1+(4*mbl_i+2)*FDEC_STRIDE], r2b
    movzx     r2d, byte [r3+r6-1]
    mov [r1-1+(4*mbl_i+3)*FDEC_STRIDE], r2b
%if mbl_i < 3
    lea        r3, [r3+r4*4]
%endif
%assign mbl_i mbl_i+1
%endrep
    RET
%undef mbl_i

;-----------------------------------------------------------------------------
; void mbaff_load_chroma_420/422( pixel *fenc, pixel *fdec, pixel *src_fenc, pixel *src_fdec,
;                                 intptr_t stride, pixel *intra )
; MBAFF cache_load, nv12 chroma of 8 or 16 lines: fenc line j = u (8) then v (8) of
; src_fenc line j; fdec u at fdec, v at fdec+16: line -1 u = intra[0..7], v =
; intra[8..15], x -1 = intra[-9] and intra[-1]; column -1 of line j = src_fdec
; line j [-2] and [-1].
;-----------------------------------------------------------------------------
%macro MBAFF_LOAD_CHROMA 1 ; lines
cglobal mbaff_load_chroma_%1, 6,7,3
    movq      xm0, [r5]
    movq      xm1, [r5+8]
    movq [r1-FDEC_STRIDE], xm0
    movq [r1-FDEC_STRIDE+16], xm1
    movzx     r6d, byte [r5-9]
    mov [r1-FDEC_STRIDE-1], r6b
    movzx     r6d, byte [r5-1]
    mov [r1-FDEC_STRIDE+15], r6b
    vbroadcasti128 m2, [mbaff_deint_shuf]
    lea        r6, [r4*3]
%assign %%i 0
%rep %1/4
    movu      xm0, [r2]
    vinserti128 m0, m0, [r2+r4], 1
    movu      xm1, [r2+r4*2]
    vinserti128 m1, m1, [r2+r6], 1
    pshufb     m0, m2
    pshufb     m1, m2
    mova [r0+%%i*64], m0
    mova [r0+%%i*64+32], m1
%if %%i < %1/4-1
    lea        r2, [r2+r4*4]
%endif
%assign %%i %%i+1
%endrep
    ; u and v of a line in one word load; r6 is rax in both x86-64 ABIs, so ah is its byte 1
    lea        r2, [r4*3]
%assign %%i 0
%rep %1/4
%assign %%j 0
%rep 4
%if %%j == 0
    movzx     r6d, word [r3-2]
%elif %%j == 3
    movzx     r6d, word [r3+r2-2]
%else
    movzx     r6d, word [r3+r4*%%j-2]
%endif
    mov [r1-1+(4*%%i+%%j)*FDEC_STRIDE], r6b
    mov [r1+15+(4*%%i+%%j)*FDEC_STRIDE], ah
%assign %%j %%j+1
%endrep
%if %%i < %1/4-1
    lea        r3, [r3+r4*4]
%endif
%assign %%i %%i+1
%endrep
    RET
%endmacro

MBAFF_LOAD_CHROMA 8
MBAFF_LOAD_CHROMA 16
%endif
