;*****************************************************************************
;* weightp-a.asm: x86 weighted prediction analysis
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

; weightp_satd8_search
; packssdw of even | odd columns back to column order
wsrch_deint: times 4 db 0,1,8,9,2,3,10,11,4,5,12,13,6,7,14,15
; vpermd: block i's dword to lane i
wsrch_lidx:  dd 0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3
; 16 * the offset step, j = 1, 2, 3
wsrch_jdc:   times 16 dd 16<<(BIT_DEPTH-8)
             times 16 dd 32<<(BIT_DEPTH-8)
             times 16 dd 48<<(BIT_DEPTH-8)
wsrch_pw1:   times 32 dw 1
wsrch_pwmax: times 32 dw PIXEL_MAX
wsrch_pwd:   times 32 dw 1<<(BIT_DEPTH-8)
; per denom: 1 << (BIT_DEPTH - denom), rounding << 5, 1 << (denom + 5)
wsrch_pow:
%assign wsrch_d 0
%rep 8
    dd 1<<(BIT_DEPTH-wsrch_d)
%assign wsrch_d wsrch_d+1
%endrep
wsrch_rnd32: dd 0, 32, 64, 128, 256, 512, 1024, 2048
wsrch_pow5:  dd 32, 64, 128, 256, 512, 1024, 2048, 4096
wsrch_tail:  db 0, 1, 3, 7

SECTION .text

%if ARCH_X86_64
;-----------------------------------------------------------------------------
; void weightp_satd8_search( uint32_t (*cost)[4], pixel *r, pixel *f, intptr_t stride, int n,
;                            uint16_t *icost, const int16_t (*wp)[4], int nk )
; mmsize/16 blocks a pass, lanes = blocks, rows in registers. Per weight k, mode A:
; pmulhrsw( x << (15-BIT_DEPTH), scale << (BIT_DEPTH-denom) ) is exactly
; (x * scale + round) >> denom while scale << (BIT_DEPTH-denom) fits (always at 8-bit);
; mode B (else, high bit depth): even and odd columns as dwords, the rounding and
; offset in the accumulator. Offsets j > 0 from the 4 4x4 DCs while no pixel clips
; (the max of the unclipped rows, unsigned, <= PIXEL_MAX - j), else by a satd each.
; Blocks past n: icost 0, so they add 0.
;-----------------------------------------------------------------------------
; weights, 64 bytes each: mul, offset, lim (word pairs), offsets, mode,
; (s,0), (0,s), rounding + offset << 5, step << denom + 5, denom + 5
%define WS_PT  0
%define WS_ACC (WS_PT+10*64)
%define WS_XS  (WS_ACC+10*mmsize)
%define WS_FS  (WS_XS+8*mmsize)

; psubw m%1, fenc row %2 (0-3) of the upper (FLO) or lower (FHI) half
%if HIGH_BIT_DEPTH
%macro WS_FROW 3 ; dst, base, row
%if %3 == 0
    psubw        m%1, [%2]
%elif %3 == 1
    psubw        m%1, [%2+r3]
%elif %3 == 2
    psubw        m%1, [%2+2*r3]
%else
    psubw        m%1, [%2+r8]
%endif
%endmacro
%macro WS_FLO 2
    WS_FROW %1, r2, %2
%endmacro
%macro WS_FHI 2
    WS_FROW %1, r12, %2
%endmacro
%else
%macro WS_FLO 2
    psubw        m%1, [rsp+WS_FS+(%2)*mmsize]
%endmacro
%macro WS_FHI 2
    psubw        m%1, [rsp+WS_FS+(%2+4)*mmsize]
%endmacro
%endif

; per 128-bit lane: [a0+a1, a2+a3, b0+b1, b2+b3]
%macro WS_PHADDD 3 ; dst/a, b, tmp
%if cpuflag(avx512)
    shufps       m%3, m%1, m%2, q3131
    shufps       m%1, m%2, q2020
    paddd        m%1, m%3
%else
    phaddd       m%1, m%2
%endif
%endmacro

; m%1 = row %2 weighted, unclipped, mode A: m9 = mul, offset m%3
%macro WS_WA 3
    pmulhrsw     m%1, m9, [rsp+WS_XS+(%2)*mmsize]
    paddsw       m%1, m%3
%endmacro

; mode B: m9 = (s,0), m10 = (0,s), m11 = rounding + offset, xm15 = shift
%macro WS_WB 3 ; dst, row, tmp
%if cpuflag(avx512)
    mova         m%1, m11
    mova         m%3, m11
    vpdpwssd     m%1, m9, [rsp+WS_XS+(%2)*mmsize]
    vpdpwssd     m%3, m10, [rsp+WS_XS+(%2)*mmsize]
%else
    pmaddwd      m%1, m9, [rsp+WS_XS+(%2)*mmsize]
    pmaddwd      m%3, m10, [rsp+WS_XS+(%2)*mmsize]
    paddd        m%1, m11
    paddd        m%3, m11
%endif
    psrad        m%1, xm15
    psrad        m%3, xm15
    packssdw     m%1, m%3
    pshufb       m%1, [wsrch_deint]
%endmacro

; clip, less fenc row %2
%macro WS_CD 2
    pmaxsw       m%1, m12
    pminsw       m%1, m13
%assign %%r %2
%if %%r < 4
    WS_FLO %1, %%r
%else
    WS_FHI %1, %%r-4
%endif
%endmacro

; satd of rows m0-m3 (8 columns, two 4x4, a lane), added to m6 (%1: m6 =);
; m4, m5 clobbered
%macro WS_SATD4 1
    paddw        m4, m0, m1
    psubw        m1, m0
    paddw        m5, m2, m3
    psubw        m3, m2
    punpcklwd    m0, m4, m1
    punpckhwd    m1, m4, m1
    punpcklwd    m2, m5, m3
    punpckhwd    m3, m5, m3
    paddw        m4, m0, m2
    psubw        m2, m0
    paddw        m5, m1, m3
    psubw        m3, m1
    punpckldq    m0, m4, m2
    punpckhdq    m2, m4, m2
    punpckldq    m1, m5, m3
    punpckhdq    m3, m5, m3
    paddw        m4, m0, m2
    psubw        m2, m0
    paddw        m5, m1, m3
    psubw        m3, m1
    punpcklqdq   m0, m4, m2
    punpckhqdq   m2, m4, m2
    punpcklqdq   m1, m5, m3
    punpckhqdq   m3, m5, m3
    pabsw        m0, m0
    pabsw        m2, m2
    pabsw        m1, m1
    pabsw        m3, m3
    pmaxsw       m0, m2
    pmaxsw       m1, m3
%if %1
    paddw        m6, m0, m1
%else
    paddw        m6, m0
    paddw        m6, m1
%endif
%endmacro

; m6 = satd of the 8 rows weighted by mode %1 (0: A, offset m%2; 1: B), lanes
; broadcast; m4, m5 clobbered
%macro WS_FULL 2
%assign %%h 0
%rep 2
%if %1
    WS_WB 0, 4*%%h+0, 4
    WS_WB 1, 4*%%h+1, 5
    WS_WB 2, 4*%%h+2, 4
    WS_WB 3, 4*%%h+3, 5
%else
    WS_WA 0, 4*%%h+0, %2
    WS_WA 1, 4*%%h+1, %2
    WS_WA 2, 4*%%h+2, %2
    WS_WA 3, 4*%%h+3, %2
%endif
    WS_CD 0, 4*%%h+0
    WS_CD 1, 4*%%h+1
    WS_CD 2, 4*%%h+2
    WS_CD 3, 4*%%h+3
    WS_SATD4 !%%h
%assign %%h %%h+1
%endrep
    WS_BASE
%endmacro

; m6 words to the sum of its lane, in every dword of it
%macro WS_BASE 0
    HADDUWD      m6, m4
%if cpuflag(avx512)
    pshufd       m4, m6, q1032
    paddd        m6, m4
    pshufd       m4, m6, q2301
    paddd        m6, m4
%else
    phaddd       m6, m6
    phaddd       m6, m6
%endif
%endmacro

; m8 lane %1 (0-3) = m6
%macro WS_LANE 1
%if cpuflag(avx512)
    mov          r6d, 0x1111<<%1
    kmovw        k2, r6d
    vmovdqa32    m8 {k2}, m6
%elif mmsize == 32
    vpblendd     m8, m6, 0x11<<%1
%endif
%endmacro

%macro WEIGHTP_SATD8_SEARCH 0
cglobal weightp_satd8_search, 8,13,16, 10*64+26*mmsize
    FIX_STRIDES  r3
    mov          r4d, r4d
    ; the weights
    lea          r9, [rsp+WS_PT]
    lea          r10, [wsrch_pow]
    mov          r11d, r7d
.pt:
    movsx        r12d, word [r6+2]          ; denom
    movsx        r8d, word [r6]             ; scale
    mov          [r9+20], r8d               ; (s,0)
    shl          r8d, 16
    mov          [r9+24], r8d               ; (0,s)
    movsx        r8d, word [r6]
    imul         r8d, [r10+4*r12]           ; mul
    mov          dword [r9+16], 0
    cmp          r8d, 0x7fff
    seta         byte [r9+16]               ; mode
    mov          [r9], r8w
    mov          [r9+2], r8w
    movsx        r8d, word [r6+4]           ; offset
    mov          [r9+4], r8w
    mov          [r9+6], r8w
    imul         r8d, [r10+(wsrch_pow5-wsrch_pow)+4*r12]
    add          r8d, [r10+(wsrch_rnd32-wsrch_pow)+4*r12]
    mov          [r9+28], r8d               ; (rounding + offset << denom) << 5
    mov          r8d, [r10+(wsrch_pow5-wsrch_pow)+4*r12]
    shl          r8d, BIT_DEPTH-8
    mov          [r9+32], r8d               ; step << denom + 5
    add          r12d, 5
    mov          [r9+36], r12d
    mov          dword [r9+40], 0
    movsx        r8d, word [r6+6]           ; offsets
    mov          [r9+12], r8d
    dec          r8d
    imul         r8d, -(1<<(BIT_DEPTH-8))
    add          r8d, PIXEL_MAX
    mov          [r9+8], r8w
    mov          [r9+10], r8w
    add          r6, 8
    add          r9, 64
    dec          r11d
    jg .pt
    lea          r8, [3*r3]
    ; the accumulators
    pxor         xm0, xm0
    lea          r9, [rsp+WS_ACC]
    mov          r11d, r7d
.acc0:
    mova         [r9], m0
    add          r9, mmsize
    dec          r11d
    jg .acc0
    pxor         m12, m12
    mova         m13, [wsrch_pwmax]
.group:
    ; icost of the blocks, 0 past n
%if mmsize == 64
    mov          r6d, 15
    cmp          r4d, 4
    jge .icmask
    lea          r6, [wsrch_tail]
    movzx        r6d, byte [r6+r4]
.icmask:
    kmovb        k1, r6d
    vpmovzxwd    xm14 {k1}{z}, [r5]
%else
    cmp          r4d, 2
    jl .ic1
    movd         xm14, [r5]
    jmp .ic
.ic1:
    movzx        r6d, word [r5]
    movd         xm14, r6d
.ic:
    pmovzxwd     xm14, xm14
%endif
    mova         m0, [wsrch_lidx]
    vpermd       m14, m0, m14
%if HIGH_BIT_DEPTH
    pslld        m14, BIT_DEPTH-8
%endif
    ; x << 15-BIT_DEPTH and fenc
    lea          r6, [r1+4*r3]
%if HIGH_BIT_DEPTH
    lea          r12, [r2+4*r3]
%assign %%i 0
%rep 4
%if %%i == 0
    %xdefine %%o 0
%elif %%i == 1
    %xdefine %%o r3
%elif %%i == 2
    %xdefine %%o 2*r3
%else
    %xdefine %%o r8
%endif
    psllw        m0, [r1+%%o], 15-BIT_DEPTH
    psllw        m1, [r6+%%o], 15-BIT_DEPTH
    mova         [rsp+WS_XS+%%i*mmsize], m0
    mova         [rsp+WS_XS+(%%i+4)*mmsize], m1
%assign %%i %%i+1
%endrep
%else
    lea          r12, [r2+4*r3]
%assign %%i 0
%rep 4
%if %%i == 0
    %xdefine %%o 0
%elif %%i == 1
    %xdefine %%o r3
%elif %%i == 2
    %xdefine %%o 2*r3
%else
    %xdefine %%o r8
%endif
    pmovzxbw     m0, [r1+%%o]
    pmovzxbw     m1, [r6+%%o]
    pmovzxbw     m2, [r2+%%o]
    pmovzxbw     m3, [r12+%%o]
    psllw        m0, 15-BIT_DEPTH
    psllw        m1, 15-BIT_DEPTH
    mova         [rsp+WS_XS+%%i*mmsize], m0
    mova         [rsp+WS_XS+(%%i+4)*mmsize], m1
    mova         [rsp+WS_FS+%%i*mmsize], m2
    mova         [rsp+WS_FS+(%%i+4)*mmsize], m3
%assign %%i %%i+1
%endrep
%endif
    lea          r9, [rsp+WS_PT]
    lea          r10, [rsp+WS_ACC]
    mov          r11d, r7d
.k:
%if HIGH_BIT_DEPTH
    cmp          dword [r9+16], 0
    jne .kb
%endif
    vpbroadcastd m9, [r9]
    vpbroadcastd m10, [r9+4]
    cmp          dword [r9+12], 1
    je .k1
    ; offsets 0 to n-1: the satd at 0, the DCs and the max of the unclipped rows
%assign %%h 0
%rep 2
    WS_WA 0, 4*%%h+0, 10
    WS_WA 1, 4*%%h+1, 10
    WS_WA 2, 4*%%h+2, 10
    WS_WA 3, 4*%%h+3, 10
%if %%h
    pmaxuw       m11, m0
    pmaxuw       m11, m1
%else
    pmaxuw       m11, m0, m1
%endif
    pmaxuw       m11, m2
    pmaxuw       m11, m3
    WS_CD 0, 4*%%h+0
    WS_CD 1, 4*%%h+1
    WS_CD 2, 4*%%h+2
    WS_CD 3, 4*%%h+3
%if %%h
    paddw        m7, m0, m1
    paddw        m7, m2
    paddw        m7, m3
    pmaddwd      m7, [wsrch_pw1]
%else
    paddw        m8, m0, m1
    paddw        m8, m2
    paddw        m8, m3
    pmaddwd      m8, [wsrch_pw1]
%endif
    WS_SATD4 !%%h
%assign %%h %%h+1
%endrep
    WS_BASE
    vpbroadcastd m4, [r9+8]
%if cpuflag(avx512)
    vpcmpuw      k1, m11, m4, 6
    kortestd     k1, k1
%else
    psubusw      m11, m4
    ptest        m11, m11
%endif
    jnz .kslow
    ; c(j) = c(0) + sum( |D + 16j| - |D| ) / 2
    WS_PHADDD 8, 7, 4                       ; the 4 DCs
    pabsd        m0, m8
    paddd        m1, m8, [wsrch_jdc]
    paddd        m2, m8, [wsrch_jdc+64]
    paddd        m3, m8, [wsrch_jdc+128]
    pabsd        m1, m1
    pabsd        m2, m2
    pabsd        m3, m3
    WS_PHADDD 0, 1, 4
    WS_PHADDD 2, 3, 4
    WS_PHADDD 0, 2, 4
    pshufd       m1, m0, q0000
    psubd        m0, m1
    psrad        m0, 1
    paddd        m0, m6
    jmp .kstore
.kslow:
    ; clips: a satd per offset
    mova         m8, m6
    mova         m7, m10
%assign %%j 1
%rep 3
    paddw        m7, [wsrch_pwd]
    WS_FULL 0, 7
    WS_LANE %%j
%if %%j < 3
    cmp          dword [r9+12], %%j+1
    jle .kslowend
%endif
%assign %%j %%j+1
%endrep
.kslowend:
    mova         m0, m8
    jmp .kstore
%if HIGH_BIT_DEPTH
.kb:
    vpbroadcastd m9, [r9+20]
    vpbroadcastd m10, [r9+24]
    vpbroadcastd m11, [r9+28]
    vpbroadcastd m7, [r9+32]
    movq         xm15, [r9+36]
    WS_FULL 1, 0
    mova         m8, m6
%assign %%j 1
%rep 3
    cmp          dword [r9+12], %%j
    jle .kbend
    paddd        m11, m7
    WS_FULL 1, 0
    WS_LANE %%j
%assign %%j %%j+1
%endrep
.kbend:
    mova         m0, m8
    jmp .kstore
%endif
.k1:
    WS_FULL 0, 10
    mova         m0, m6
.kstore:
    pminud       m0, m14
    paddd        m0, [r10]
    mova         [r10], m0
    add          r9, 64
    add          r10, mmsize
    dec          r11d
    jg .k
    add          r1, mmsize/2*SIZEOF_PIXEL
    add          r2, mmsize/2*SIZEOF_PIXEL
    add          r5, mmsize/8
    sub          r4d, mmsize/16
    jg .group
    ; lanes to cost
    lea          r10, [rsp+WS_ACC]
.fold:
    mova         m0, [r10]
%if mmsize == 64
    vextracti32x8 ym1, m0, 1
    paddd        ym0, ym1
    vextracti32x4 xm1, ym0, 1
%else
    vextracti128 xm1, m0, 1
%endif
    paddd        xm0, xm1
    movu         xm1, [r0]
    paddd        xm0, xm1
    movu         [r0], xm0
    add          r0, 16
    add          r10, mmsize
    dec          r7d
    jg .fold
    RET
%endmacro

INIT_YMM avx2
WEIGHTP_SATD8_SEARCH
%endif ; ARCH_X86_64
