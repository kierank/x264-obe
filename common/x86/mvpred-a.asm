;*****************************************************************************
;* mvpred-a.asm: x86 motion vector prediction
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

SECTION_RODATA 32

mvref_ysh: dd 0, 1, 0, 1, 0, 1, 0, 0
mvref_rnd: dd 128

; h->mb offsets, asserted in mvpred.c
%define MB_WIDTH         0
%define MB_HEIGHT        4
%define MB_STRIDE       20
%define MB_X            48
%define MB_Y            52
%define MB_XY           56
%define MB_INTERLACED  100
%define MB_LEFT_XY     340
%define MB_TOP_XY      348
%define MB_TOPLEFT_XY  352
%define MB_TOPRIGHT_XY 356
%define MB_MVR         512
%define MB_FIELD      1048
%define MVREF_MBAFF   1056
%define MVREF_TMVP    1060
%define MVREF_TCONV   1064
%define MVREF_L0MV    1072
%define MVREF_L0FIELD 1080
%define MVREF_TSCALE  1088

SECTION .text

;-----------------------------------------------------------------------------
; void mvpred_16x16( int8_t *ref, int16_t (*mv)[2], intptr_t i_ref, int16_t mvp[2] )
; void mvpred_pskip( int8_t *ref, int16_t (*mv)[2], int16_t mvp[2] )
; void mvpred( int8_t *ref, int16_t (*mv)[2], int16_t mvp[2], intptr_t mode, int16_t *mv_tr )
;
; ref and mv at the partition's scan8 index; refs are -2..127. m3 = which of
; a, b, c have i_ref: 1, 2, 4 that one; 0 a if b == c == -2 != a; else the
; median. mvpred: mode as in pixel.h, dir (1/2/4) that one if it is in m3.
;-----------------------------------------------------------------------------
%macro MVPRED16 1 ; pskip
%if %1
cglobal mvpred_pskip, 3,9,4
    mov          r3, r2
    xor         r2d, r2d
%else
cglobal mvpred_16x16, 4,9,4
%endif
    mov          r4, -4
    movsx       r6d, byte [r0-4]    ; c
    movsx       r7d, byte [r0-9]    ; d
    movsx       r8d, byte [r0-1]    ; a
    movsx       r0d, byte [r0-8]    ; b
    cmp         r6d, -2
    cmove       r6d, r7d
    mov          r7, -9
    cmove        r4, r7
    movd         m0, [r1-4]
    movd         m1, [r1-32]
    movd         m2, [r1+r4*4]
    pmaxsw       m3, m0, m1
    pminsw       m0, m1
    pminsw       m3, m2
    pmaxsw       m0, m3             ; median
%if %1
    ; r5 = 0 if a == -2 || b == -2 || !(a|A) || !(b|B)
    mov         r5d, [r1-4]
    or          r5d, r8d
    cmp         r8d, -2
    cmove       r5d, r2d
    mov         r7d, [r1-32]
    or          r7d, r0d
    cmp         r0d, -2
    cmove       r7d, r2d
    test        r7d, r7d
    cmovz       r5d, r2d
%endif
    lea         r7d, [r0+r6+4]      ; 0 iff b == c == -2
    cmp         r8d, -2
    cmove       r7d, r8d
    cmp         r8d, r2d
    sete        r8b
    movzx       r8d, r8b
    cmp         r0d, r2d
    sete        r0b
    movzx       r0d, r0b
    cmp         r6d, r2d
    sete        r6b
    movzx       r6d, r6b
    lea         r8d, [r8+r0*2]
    lea         r8d, [r8+r6*4]      ; m3
    movd        r2d, m0
    cmp         r8d, 1
    cmove       r2d, [r1-4]
    cmp         r8d, 2
    cmove       r2d, [r1-32]
    cmp         r8d, 4
    cmove       r2d, [r1+r4*4]
    or          r7d, r8d
    cmovz       r2d, [r1-4]
%if %1
    test        r5d, r5d
    cmovz       r2d, r5d
%endif
    mov         [r3], r2d
    RET
%endmacro

INIT_XMM avx2
MVPRED16 0
MVPRED16 1

cglobal mvpred, 5,9,4
    movsx        r5, r3b
    movsx       r6d, byte [r0+r5]   ; c
    lea          r5, [r1+r5*4]      ; &C
    movsx       r7d, byte [r0-9]    ; d
    lea          r8, [r1-36]
    cmp         r6d, -2
    cmove       r6d, r7d
    cmove        r5, r8
    mov         r7d, r3d
    sar         r7d, 24             ; i_ref_tr
    test        r3d, 0x1000
    cmovnz      r6d, r7d
    cmovnz       r5, r4
    movsx       r7d, byte [r0-1]    ; a
    movsx       r8d, byte [r0-8]    ; b
    movsx       r0d, byte [r0]      ; i_ref
    movd         m0, [r1-4]
    movd         m1, [r1-32]
    movd         m2, [r5]
    pmaxsw       m3, m0, m1
    pminsw       m0, m1
    pminsw       m3, m2
    pmaxsw       m0, m3             ; median
    lea         r4d, [r8+r6+4]      ; 0 iff b == c == -2
    cmp         r7d, -2
    cmove       r4d, r7d
    cmp         r7d, r0d
    sete        r7b
    movzx       r7d, r7b
    cmp         r8d, r0d
    sete        r8b
    movzx       r8d, r8b
    cmp         r6d, r0d
    sete        r6b
    movzx       r6d, r6b
    lea         r7d, [r7+r8*2]
    lea         r7d, [r7+r6*4]      ; m3
    movd        r0d, m0
    cmp         r7d, 1
    cmove       r0d, [r1-4]
    cmp         r7d, 2
    cmove       r0d, [r1-32]
    cmp         r7d, 4
    cmove       r0d, [r5]
    or          r4d, r7d
    cmovz       r0d, [r1-4]
    shr         r3d, 9
    and         r3d, 7              ; dir
    lea          r6, [r1-4]
    lea          r8, [r1-32]
    cmp         r3d, 1
    cmove        r5, r6
    cmp         r3d, 2
    cmove        r5, r8
    test        r7d, r3d
    cmovnz      r0d, [r5]
    mov         [r2], r0d
    RET

;-----------------------------------------------------------------------------
; int mvpred_ref16x16( int16_t (*mvc)[2], void *mb, intptr_t i_list, intptr_t i_ref )
;
; mvc[] written up to 2 entries past the count.
;-----------------------------------------------------------------------------
; mvc[r6] = the neighbour at xy (offset %1) in the units of this mb, r6 += xy >= 0
%macro IMVP 1
    mov         r7d, [r1+%1]
    test        r7d, r7d
    cmovs       r7d, [r1+MB_XY]
    movsxd       r7, r7d
    mov          r4, [r1+MB_FIELD]
    movzx       r4d, byte [r4+r7]
    sub         r4d, r5d
    neg         r4d                 ; 1 + MB_INTERLACED - field[xy]
    lea          r8, [r3*2]
    shrx         r8, r8, r4
    mov          r8, [r9+r8*8]      ; mvr[i_list][i_ref<<1>>shift]
    mov         r8d, [r8+r7*4]
    mov    [r0+r6*4], r8w
    sar         r8d, 16
    add         r8d, r8d
    sarx        r8d, r8d, r4d
    mov  [r0+r6*4+2], r8w
    cmp   dword [r1+%1], 0x80000000
    adc         r6d, 0
%endmacro

INIT_YMM avx2
cglobal mvpred_ref16x16, 4,10,4
    shl         r2d, 5              ; i_list*32
    cmp   dword [r1+MVREF_MBAFF], 0
    jne .mbaff
    lea          r4, [r2+r3]
    mov          r4, [r1+r4*8+MB_MVR]
    movsxd       r5, dword [r1+MB_LEFT_XY]
    movsxd       r6, dword [r1+MB_TOP_XY]
    movsxd       r7, dword [r1+MB_TOPLEFT_XY]
    movsxd       r8, dword [r1+MB_TOPRIGHT_XY]
    mov         r5d, [r4+r5*4]
    mov         r6d, [r4+r6*4]
    mov         r7d, [r4+r7*4]
    mov         r8d, [r4+r8*4]
    mov      [r0+ 0], r5d
    mov      [r0+ 4], r6d
    mov      [r0+ 8], r7d
    mov      [r0+12], r8d
    mov         r6d, 4
.temporal:
    cmp   dword [r1+MVREF_TMVP], 0
    je .end
    mov         r5d, [r1+MB_INTERLACED]
    mov         r7d, [r1+MB_Y]
    and         r7d, 1
    lea         r4d, [r5*2+r7]
    shl         r4d, 5
    add         r4d, r3d
    lea         r4d, [r4+r2*4]      ; [i_list][MB_INTERLACED][mb_y&1][i_ref]
    vpbroadcastd m3, [r1+r4*4+MVREF_TSCALE]
    vpbroadcastd m2, [mvref_rnd]
    movsxd       r4, dword [r1+MB_XY]
    xor         r2d, r2d
    mov         r8d, [r1+MB_X]
    inc         r8d
    cmp         r8d, [r1+MB_WIDTH]
    setl        r2b                 ; right
    xor         r3d, r3d
    mov         r8d, [r1+MB_Y]
    inc         r8d
    cmp         r8d, [r1+MB_HEIGHT]
    setl        r3b                 ; below
    mov         r8d, [r1+MB_STRIDE]
    imul        r8d, r3d
    add          r8, r4
    lea          r7, [r4+r2]
    mov          r9, [r1+MVREF_L0MV]
    vmovd       xm0, [r9+r4*4]
    vpinsrd     xm0, xm0, [r9+r7*4], 1
    vpinsrd     xm0, xm0, [r9+r8*4], 2
    vpmovsxwd    m0, xm0            ; x y of the mb, its right and below
    cmp   dword [r1+MVREF_TCONV], 0
    je .tnoconv
    ; y*2 >> (1 + MB_INTERLACED - l0_field[xy])
    mov          r9, [r1+MVREF_L0FIELD]
    movzx       r4d, byte [r9+r4]
    movzx       r7d, byte [r9+r7]
    movzx       r8d, byte [r9+r8]
    shl         r7d, 16
    shl          r8, 32
    or          r4d, r7d
    or           r4, r8
    shl          r4, 8
    inc         r5d
    mov          r9, 0x10001000100
    imul         r5, r9
    sub          r5, r4             ; the shifts in bytes 1, 3, 5
    vmovq       xm1, r5
    vpmovzxbd    m1, xm1
    vpsllvd      m0, m0, [mvref_ysh]
    vpsravd      m0, m0, m1
    vpmulld      m0, m0, m3
    vpaddd       m0, m0, m2
    vpsrad       m0, m0, 8
    jmp .tpack
.tnoconv:
    vpmulld      m0, m0, m3
    vpaddd       m0, m0, m2
    vpsrad       m0, m0, 8
    vpslld       m0, m0, 16
    vpsrad       m0, m0, 16         ; int16 truncation
.tpack:
    vpackssdw    m0, m0, m0
    vpermq       m0, m0, q0020
    vmovq  [r0+r6*4], xm0
    lea         r7d, [r6+r2+1]
    vpextrd [r0+r7*4], xm0, 2
    lea         r6d, [r7+r3]
.end:
    RET

.mbaff:
    lea          r9, [r1+r2*8+MB_MVR]
    mov         r5d, [r1+MB_INTERLACED]
    inc         r5d
    xor         r6d, r6d
    IMVP MB_LEFT_XY
    IMVP MB_TOP_XY
    IMVP MB_TOPLEFT_XY
    IMVP MB_TOPRIGHT_XY
    ; MB_INTERLACED && (mb_y&1): the top mb of the pair
    mov         r7d, [r1+MB_Y]
    and         r7d, [r1+MB_INTERLACED]
    mov         r4d, [r1+MB_STRIDE]
    imul        r4d, r7d
    movsxd       r8, dword [r1+MB_XY]
    sub          r8, r4
    mov          r4, [r9+r3*8]
    mov         r4d, [r4+r8*4]
    mov  [r0+r6*4], r4d
    add         r6d, r7d
    jmp .temporal
