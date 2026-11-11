;*****************************************************************************
;* hpelfly-a.asm: hpel_filter's planes of a rect, for common/hpelfly.c
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

%if HIGH_BIT_DEPTH == 0

SECTION_RODATA 16

; 16-byte patterns, broadcast to the vector width
fly_1:     times 16 db 1
fly_m5:    times 16 db -5
fly_20:    times 16 db 20
fly_15:    times 8 db 1, -5
fly_51:    times 8 db -5, 1
fly_shuf:  db 0,8,1,9,2,10,3,11,4,12,5,13,6,14,7,15
fly_1024:  times 8 dw 1024
fly_512:   times 8 dw 512

%define FLY_BR 112 ; at least common/hpelfly.h's: the most rows of a call

%define FLY_STEP mmsize ; the columns of a loop iteration, and its store
%define FLY_ST m0

SECTION .text

;-----------------------------------------------------------------------------
; void hpel_fly_h/v/c( uint8_t *dst, intptr_t i_dst, uint8_t *src, intptr_t i_src,
;                      int width, int height )
; hpel_filter's H, V or C plane of the width x height rect at src, width a
; multiple of 16, height at most FLY_BR; plain stores (the window or band is read
; next). The vector width's columns at a time, then 32 and 16.
;-----------------------------------------------------------------------------

%macro FLY_CONST 2
    vbroadcasti128 %1, [%2]
%endmacro

; the unrounded horizontal 6-tap of mmsize columns at %1 into m0 (even columns) and
; m1 (odd): [-2]*(1,-5) + [0]*20 + [2]*(-5,1), the odd from the same at +1;
; m5 = fly_15, m6 = fly_20, m7 = fly_51
%macro FLY_HRAW 1
    movu      m0, [%1-2]
    movu      m1, [%1-1]
    movu      m2, [%1+2]
    pmaddubsw m0, m5
    pmaddubsw m1, m5
    pmaddubsw m2, m7
    paddw     m0, m2
    movu      m2, [%1]
    movu      m3, [%1+1]
    movu      m4, [%1+3]
    pmaddubsw m2, m6
    pmaddubsw m3, m6
    pmaddubsw m4, m7
    paddw     m0, m2
    paddw     m1, m3
    paddw     m1, m4
%endmacro

; H of mmsize columns at %1 into %2; m8 = fly_1024, m9 = fly_shuf
%macro FLY_H 2
    FLY_HRAW  %1
    pmulhrsw  m0, m8
    pmulhrsw  m1, m8
    packuswb  m0, m1
    pshufb    m0, m9
    movu    [%2], FLY_ST
%endmacro

%macro FLY_H_LOOP 0 ; r6 = the column, r4d the width left
%%loop:
    cmp      r4d, FLY_STEP
    jl %%done
    FLY_H r2+r6, r0+r6
    add       r6, FLY_STEP
    sub      r4d, FLY_STEP
    jmp %%loop
%%done:
%endmacro

%macro HPEL_FLY_H 1 ; cpu
cglobal hpel_fly_h, 6,8,10
    FLY_CONST m5, fly_15
    FLY_CONST m6, fly_20
    FLY_CONST m7, fly_51
    FLY_CONST m8, fly_1024
    FLY_CONST m9, fly_shuf
    mov      r7d, r4d
.row:
    xor      r6d, r6d
    mov      r4d, r7d
    FLY_H_LOOP
%if mmsize == 64
    INIT_YMM %1
    FLY_H_LOOP
%endif
    ; 16 columns: the ymm code, its first half stored
%ifidn %1, avx2
%else
    INIT_YMM %1
%endif
    %define FLY_STEP 16
    %define FLY_ST xm0
    FLY_H_LOOP
    %define FLY_STEP mmsize
    %define FLY_ST m0
%ifidn %1, avx2
    INIT_YMM %1
%else
    INIT_ZMM %1
%endif
    add       r0, r1
    add       r2, r3
    dec      r5d
    jg .row
    RET
%endmacro

; v of mmsize columns of the rows at %1 and %2 = %1 + 3*i_src: words in the lane
; order of punpck, %3 = cols 0-7 of each 16, %4 = 8-15; m6 = fly_20, m10 = fly_1,
; m11 = fly_m5
%macro FLY_V16 4 ; p0, p1, lo, hi
    movu      %4, [%1]
    movu      m3, [%2+r3*2]
    punpcklbw %3, %4, m3
    punpckhbw %4, m3
    pmaddubsw %3, m10
    pmaddubsw %4, m10
    movu      m1, [%1+r3]
    movu      m3, [%2+r3]
    punpcklbw m2, m1, m3
    punpckhbw m1, m3
    pmaddubsw m2, m11
    pmaddubsw m1, m11
    paddw     %3, m2
    paddw     %4, m1
    movu      m1, [%1+r3*2]
    movu      m3, [%2]
    punpcklbw m2, m1, m3
    punpckhbw m1, m3
    pmaddubsw m2, m6
    pmaddubsw m1, m6
    paddw     %3, m2
    paddw     %4, m1
%endmacro

%macro FLY_V_LOOP 0 ; r6 = src - 2*i_src at the column, r7 = r6 + 3*i_src, r9 = dst, r8d the width left
%%loop:
    cmp      r8d, FLY_STEP
    jl %%done
    FLY_V16 r6, r7, m0, m4
    pmulhrsw  m0, m8
    pmulhrsw  m4, m8
    packuswb  m0, m4
    movu    [r9], FLY_ST
    add       r6, FLY_STEP
    add       r7, FLY_STEP
    add       r9, FLY_STEP
    sub      r8d, FLY_STEP
    jmp %%loop
%%done:
%endmacro

%macro HPEL_FLY_V 1 ; cpu
cglobal hpel_fly_v, 6,10,12
    FLY_CONST m6, fly_20
    FLY_CONST m8, fly_1024
    FLY_CONST m10, fly_1
    FLY_CONST m11, fly_m5
    lea       r2, [r2+r3*2]
    neg       r3
    lea       r2, [r2+r3*4]         ; src - 2*i_src
    neg       r3
.row:
    mov       r6, r2
    lea       r7, [r2+r3*2]
    add       r7, r3
    mov       r9, r0
    mov      r8d, r4d
    FLY_V_LOOP
%if mmsize == 64
    INIT_YMM %1
    FLY_V_LOOP
%endif
    ; 16 columns: the ymm code, its first half stored
%ifidn %1, avx2
%else
    INIT_YMM %1
%endif
    %define FLY_STEP 16
    %define FLY_ST xm0
    FLY_V_LOOP
    %define FLY_STEP mmsize
    %define FLY_ST m0
%ifidn %1, avx2
    INIT_YMM %1
%else
    INIT_ZMM %1
%endif
    add       r0, r1
    add       r2, r3
    dec      r5d
    jg .row
    RET
%endmacro

; FILT_H of mc-a2.asm: (a-5*b+20*c)/16, saturating where the output clips either way
%macro FLY_FILT_H 3
    psubw     %1, %2
    psraw     %1, 2
    psubw     %1, %2
    paddsw    %1, %3
    psraw     %1, 2
    paddw     %1, %3
%endmacro

; C of a strip of mmsize columns at r2 into r0: the horizontal 6-tap of rows
; -2..height+2 to the stack (even, odd words per row), then the vertical one over
; those rows; the 2-D tap sum of hpel_filter's C in the other order, so the same.
; m8 = fly_shuf, m9 = fly_512
%macro FLY_CSTRIP 0
    %assign RS 2*mmsize
    mov       r6, r2
    sub       r6, r3
    sub       r6, r3
    mov       r7, r10
    lea      r8d, [r5+5]
%%p1:
    FLY_HRAW  r6
    mova  [r7], m0
    mova  [r7+mmsize], m1
    add       r6, r3
    add       r7, RS
    dec      r8d
    jg %%p1
    mov       r7, r10
    mov       r9, r0
    mov      r8d, r5d
%%p2:
    mova      m0, [r7]
    mova      m1, [r7+mmsize]
    paddw     m0, [r7+5*RS]
    paddw     m1, [r7+5*RS+mmsize]
    mova      m2, [r7+RS]
    mova      m3, [r7+RS+mmsize]
    paddw     m2, [r7+4*RS]
    paddw     m3, [r7+4*RS+mmsize]
    mova      m4, [r7+2*RS]
    mova     m10, [r7+2*RS+mmsize]
    paddw     m4, [r7+3*RS]
    paddw    m10, [r7+3*RS+mmsize]
    FLY_FILT_H m0, m2, m4
    FLY_FILT_H m1, m3, m10
    pmulhrsw  m0, m9
    pmulhrsw  m1, m9
    packuswb  m0, m1
    pshufb    m0, m8
    movu    [r9], FLY_ST
    add       r7, RS
    add       r9, r1
    dec      r8d
    jg %%p2
%endmacro

%macro FLY_C_LOOP 0
%%loop:
    cmp      r4d, FLY_STEP
    jl %%done
    FLY_CSTRIP
    add       r0, FLY_STEP
    add       r2, FLY_STEP
    sub      r4d, FLY_STEP
    jmp %%loop
%%done:
%endmacro

%macro HPEL_FLY_C 1 ; cpu
%assign FLY_CSTACK -((FLY_BR+5)*2*mmsize+mmsize)
cglobal hpel_fly_c, 6,11,11, FLY_CSTACK
    lea      r10, [rsp+mmsize-1]
    and      r10, ~(mmsize-1)       ; the row buffer, aligned
    FLY_CONST m5, fly_15
    FLY_CONST m6, fly_20
    FLY_CONST m7, fly_51
    FLY_CONST m8, fly_shuf
    FLY_CONST m9, fly_512
    FLY_C_LOOP
%if mmsize == 64
    INIT_YMM %1
    FLY_C_LOOP
%endif
    ; 16 columns: the ymm code, its first half stored
%ifidn %1, avx2
%else
    INIT_YMM %1
%endif
    %define FLY_STEP 16
    %define FLY_ST xm0
    FLY_C_LOOP
    %define FLY_STEP mmsize
    %define FLY_ST m0
%ifidn %1, avx2
    INIT_YMM %1
%else
    INIT_ZMM %1
%endif
    RET
%endmacro

INIT_YMM avx2
HPEL_FLY_H avx2
HPEL_FLY_V avx2
HPEL_FLY_C avx2
INIT_ZMM avx512
HPEL_FLY_H avx512
HPEL_FLY_V avx512
HPEL_FLY_C avx512

%endif ; !HIGH_BIT_DEPTH
