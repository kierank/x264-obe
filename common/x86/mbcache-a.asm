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
