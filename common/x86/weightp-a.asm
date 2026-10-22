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

; weightp_chroma_ref_row
align 64
; 8-bit vpermt2b: per output dword (u 0-7, v 8-15) bytes A, B of the row, C, D of the row below
wcr_idx8:
%assign wcr_o 0
%rep 16
    db 2*(wcr_o&7)+(wcr_o>>3), 2*(wcr_o&7)+(wcr_o>>3)+2, 64+2*(wcr_o&7)+(wcr_o>>3), 66+2*(wcr_o&7)+(wcr_o>>3)
%assign wcr_o wcr_o+1
%endrep
; high bit depth vpermw: per output dword words A, B of a row
wcr_idx16:
%assign wcr_o 0
%rep 16
    dw 2*(wcr_o&7)+(wcr_o>>3), 2*(wcr_o&7)+(wcr_o>>3)+2
%assign wcr_o wcr_o+1
%endrep
; per (d8y << 3) + d8x: 8-bit bytes cA, cB, cC, cD; high bit depth words
wcr_tap:
%assign wcr_o 0
%rep 64
%if HIGH_BIT_DEPTH
    dw (8-(wcr_o&7))*(8-(wcr_o>>3)), (wcr_o&7)*(8-(wcr_o>>3)), (8-(wcr_o&7))*(wcr_o>>3), (wcr_o&7)*(wcr_o>>3)
%else
    db (8-(wcr_o&7))*(8-(wcr_o>>3)), (wcr_o&7)*(8-(wcr_o>>3)), (8-(wcr_o&7))*(wcr_o>>3), (wcr_o&7)*(wcr_o>>3)
%endif
%assign wcr_o wcr_o+1
%endrep
wcr_pd32:  times 16 dd 32
wcr_pw512: times 16 dw 512
wcr_pdmax: times 4 dd 0xffff0000
wcr_pwmax: times 2 dw 0, 0, 0xff, 0xff
align 32
; avx2: words u0 v0 u1 v1 ... of a lane to u0 u1 u2 u3 v0 v1 v2 v3
wcr_wdeint:  times 2 db 0,1,4,5,8,9,12,13,2,3,6,7,10,11,14,15
wcr_dperm:   dd 0,4,1,5,2,6,3,7
wcr_b08:     db 0,8,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1

%if HIGH_BIT_DEPTH == 0
; pixel_sad_avg2_w, pixel_satd_avg2_pre_w (8-bit)
align 64
; vpermq: rows k, k, k+4, k+4 of 8 rows of 8, k = 0-3
wav_q8:      dq 0,0,4,4,0,0,0,0, 1,1,5,5,0,0,0,0, 2,2,6,6,0,0,0,0, 3,3,7,7,0,0,0,0
; vpermt2q: qword 0 of each 16 byte row of 2 zmm
wav_qeven:   dq 0,2,4,6,8,10,12,14
wav_hmul16:  times 16 db 1
             times 8 db 1, -1
wav_hmul8:   times 2 db 1,1,1,1,1,1,1,1,1,-1,1,-1,1,-1,1,-1
wav_pw1:     times 8 dw 1
%endif

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
INIT_ZMM avx512icl
WEIGHTP_SATD8_SEARCH

;-----------------------------------------------------------------------------
; void weightp_chroma_ref_row( pixel *dst[2], intptr_t stride, pixel *ref, int16_t (*mvs)[2], int n,
;                              int height, int32_t *sum[2], uint32_t *minmax[2], const int16_t (*ws)[2],
;                              int32_t *wsum[6] )
; A block row of u and v a register: 8-bit, vpermt2b of the row and the row below to the
; 4 taps of each output dword and vpdpbusd by the 4 bilinear weights; high bit depth,
; vpermw of each row to tap pairs, two vpdpwssd. Slot pairs u q, v q+3 in the halves.
;-----------------------------------------------------------------------------
; stack: sum, minmax, wsum pointers, slots set (bits), mv step, mvy multiplier, zero mv
%define WCR_SUM   0
%define WCR_MM    16
%define WCR_WSUM  32
%define WCR_VALID 80
%define WCR_MVST  88
%define WCR_MVMUL 96
%define WCR_ZMV   104

; one output row from the taps in m%1 (8-bit) or the tap pairs of the row in m%1 and the
; row below in m%2 (high bit depth), stored at row offset %3
%macro WCR_ROW 3
%if HIGH_BIT_DEPTH
    mova         m2, m12
    vpdpwssd     m2, m%1, m10
    vpdpwssd     m2, m%2, m11
    psrld        m2, 6
    vpmovdw      ym3, m2
    movu         [r12+%3], xm3
    vextracti32x4 [r13+%3], ym3, 1
    vpdpwssd     ym6, ym3, ym13
    pminuw       ym7, ym3
    pmaxuw       ym8, ym3
%assign wcr_i 0
%rep 3
%assign wcr_s 19+wcr_i
%assign wcr_r 22+wcr_i
%assign wcr_d 25+wcr_i
%assign wcr_a 16+wcr_i
    cmp          r14d, wcr_i
    jle %%done
    pmaddwd      m29, m2, m %+ wcr_s
    paddd        m29, m %+ wcr_r
    vpsrlvd      m29, m29, m %+ wcr_d
    paddd        m %+ wcr_a, m29
%assign wcr_i wcr_i+1
%endrep
%else
    pxor         xm2, xm2
    vpdpbusd     m2, m%1, m10
    vpmovdw      ym3, m2
    pmulhrsw     ym3, ym12
    vpmovwb      xm4, ym3
    movq         [r12+%3], xm4
    movhps       [r13+%3], xm4
    psadbw       xm5, xm4, xm14
    paddq        xm6, xm5
    pminub       xm7, xm4
    pmaxub       xm8, xm4
    psllw        ym28, ym3, 7
%assign wcr_i 0
%rep 3
%assign wcr_s 19+wcr_i
%assign wcr_a 16+wcr_i
    cmp          r14d, wcr_i
    jle %%done
    pmulhrsw     ym29, ym28, ym %+ wcr_s
    vpdpwssd     ym %+ wcr_a, ym29, ym13
%assign wcr_i wcr_i+1
%endrep
%endif
%%done:
%endmacro

; the sums of the halves of slot pair %1's accumulator (8-bit: ymm) stored to wsum q %1 and %1+3 if set
%macro WCR_SLOTEND 1
%assign wcr_a 16+%1
%if HIGH_BIT_DEPTH
    vshufi32x4   m29, m %+ wcr_a, m %+ wcr_a, q2301
    paddd        m %+ wcr_a, m29
%endif
    pshufd       m29, m %+ wcr_a, q1032
    paddd        m %+ wcr_a, m29
    pshufd       m29, m %+ wcr_a, q2301
    paddd        m %+ wcr_a, m29
    test         byte [rsp+WCR_VALID], 1<<%1
    jz %%v
    mov          r11, [rsp+WCR_WSUM+8*%1]
    movd         [r11+r6], xm %+ wcr_a
%%v:
    test         byte [rsp+WCR_VALID], 8<<%1
    jz %%done
    mov          r11, [rsp+WCR_WSUM+8*%1+24]
%if HIGH_BIT_DEPTH
    vextracti32x4 xm29, m %+ wcr_a, 2
%else
    vextracti32x4 xm29, ym %+ wcr_a, 1
%endif
    movd         [r11+r6], xm29
%%done:
%endmacro

; pointers to the stack, mvs, the mvy multiplier; no slots yet
%macro WCR_START 0
    FIX_STRIDES  r1
    mov          r10, [r0+8]
    mov          r0, [r0]
    mov          r11, [r6]
    mov          [rsp+WCR_SUM], r11
    mov          r11, [r6+8]
    mov          [rsp+WCR_SUM+8], r11
    mov          r11, [r7]
    mov          [rsp+WCR_MM], r11
    mov          r11, [r7+8]
    mov          [rsp+WCR_MM+8], r11
%assign wcr_q 0
%rep 6
    mov          r11, [r9+8*wcr_q]
    mov          [rsp+WCR_WSUM+8*wcr_q], r11
%assign wcr_q wcr_q+1
%endrep
    ; mvs: none, a zero one, step 0
    mov          qword [rsp+WCR_MVST], 4
    mov          dword [rsp+WCR_ZMV], 0
    lea          r11, [rsp+WCR_ZMV]
    test         r3, r3
    jnz .mvs
    mov          r3, r11
    mov          qword [rsp+WCR_MVST], 0
.mvs:
    ; 2*mvy >> v_shift
    mov          dword [rsp+WCR_MVMUL], 2
    cmp          r5d, 16
    je .mvmul
    mov          dword [rsp+WCR_MVMUL], 1
.mvmul:
    ; slots: set bits, pairs to do (r14), per pair u | v constants
    xor          r14d, r14d
    mov          dword [rsp+WCR_VALID], 0
%endmacro

; r8 = the source of the block at r3's mv, r9 = its taps index, r11 = wcr_tap
%macro WCR_BLOCKSRC 0
    movsx        r7d, word [r3]             ; mvx
    movsx        r8d, word [r3+2]
    imul         r8d, [rsp+WCR_MVMUL]       ; mvy
    mov          r9d, r8d
    and          r9d, 7
    mov          r11d, r7d
    and          r11d, 7
    lea          r9d, [r11+8*r9]
    sar          r7d, 3
    sar          r8d, 3
    movsxd       r7, r7d
    movsxd       r8, r8d
    imul         r8, r1
    lea          r8, [r8+r7*2*SIZEOF_PIXEL]
    add          r8, r2
    lea          r11, [wcr_tap]
%endmacro

; slot %1 of plane %2: the constants of half %2 of pair %1; set bit, pairs to do (r14)
%macro WCR_SLOTPARAM 2
%assign wcr_q %1+3*%2
%assign wcr_s 19+%1
%assign wcr_r 22+%1
%assign wcr_d 25+%1
    movsx        r11d, word [r8+4*wcr_q]    ; scale
    movsx        r9d, word [r8+4*wcr_q+2]   ; denom
    test         r11d, r11d
    jge %%set
    xor          r11d, r11d
    xor          r9d, r9d
    jmp %%unset
%%set:
    or           dword [rsp+WCR_VALID], 1<<wcr_q
    mov          r14d, %1+1
%%unset:
%if HIGH_BIT_DEPTH
    vpbroadcastd ym29, r11d
    vinserti32x8 m %+ wcr_s, m %+ wcr_s, ym29, %2
    lea          r11, [wsrch_rnd32]
    mov          r11d, [r11+4*r9]
    shr          r11d, 5
    vpbroadcastd ym29, r11d
    vinserti32x8 m %+ wcr_r, m %+ wcr_r, ym29, %2
    vpbroadcastd ym29, r9d
    vinserti32x8 m %+ wcr_d, m %+ wcr_d, ym29, %2
%else
    imul         r11d, [r7+4*r9]
    vpbroadcastw xm29, r11d
    vinserti32x4 ym %+ wcr_s, ym %+ wcr_s, xm29, %2
%endif
%endmacro

INIT_ZMM avx512icl
cglobal weightp_chroma_ref_row, 10,15,30, -112
    WCR_START
    lea          r7, [wsrch_pow]
    WCR_SLOTPARAM 0, 0
    WCR_SLOTPARAM 0, 1
    WCR_SLOTPARAM 1, 0
    WCR_SLOTPARAM 1, 1
    WCR_SLOTPARAM 2, 0
    WCR_SLOTPARAM 2, 1
%if HIGH_BIT_DEPTH
    movu         m9, [wcr_idx16]
%else
    movu         m9, [wcr_idx8]
%endif
%if HIGH_BIT_DEPTH
    mova         m12, [wcr_pd32]
%else
    mova         ym12, [wcr_pw512]
%endif
    mova         ym13, [wsrch_pw1]
    pxor         xm14, xm14
    xor          r6d, r6d
.block:
    WCR_BLOCKSRC
%if HIGH_BIT_DEPTH
    vpbroadcastd m10, [r11+8*r9]
    vpbroadcastd m11, [r11+8*r9+4]
%else
    vpbroadcastd m10, [r11+4*r9]
%endif
    pxor         xm6, xm6
    vpternlogd   ym7, ym7, ym7, 0xff
    pxor         xm8, xm8
    pxor         xm16, xm16
    pxor         xm17, xm17
    pxor         xm18, xm18
    mov          r12, r0
    mov          r13, r10
    mov          r9d, r5d
%if HIGH_BIT_DEPTH
    movu         m15, [r8]
    vpermw       m15, m9, m15
.rows:
    movu         m1, [r8+r1]
    vpermw       m1, m9, m1
    WCR_ROW 15, 1, 0
    lea          r8, [r8+2*r1]
    movu         m15, [r8]
    vpermw       m15, m9, m15
    WCR_ROW 1, 15, r1
%else
    movu         ym0, [r8]
.rows:
    movu         ym1, [r8+r1]
    vpermt2b     m0, m9, m1
    WCR_ROW 0, 1, 0
    lea          r8, [r8+2*r1]
    movu         ym0, [r8]
    vpermt2b     m1, m9, m0
    WCR_ROW 1, 0, r1
%endif
    lea          r12, [r12+2*r1]
    lea          r13, [r13+2*r1]
    sub          r9d, 2
    jg .rows
    ; sums, min | max << 16
%if HIGH_BIT_DEPTH
    pshufd       ym29, ym6, q1032
    paddd        ym6, ym29
    pshufd       ym29, ym6, q2301
    paddd        ym6, ym29
    mov          r11, [rsp+WCR_SUM]
    movd         [r11+r6], xm6
    vextracti32x4 xm6, ym6, 1
    mov          r11, [rsp+WCR_SUM+8]
    movd         [r11+r6], xm6
    vpternlogd   ym8, ym8, ym8, 0x55
    vinserti32x8 m7, m7, ym8, 1
    pshufd       m29, m7, q1032
    pminuw       m7, m29
    pshufd       m29, m7, q2301
    pminuw       m7, m29
    psrld        m29, m7, 16
    pminuw       m7, m29
    vpmovdw      ym7, m7
    vextracti32x4 xm8, ym7, 1
    punpcklwd    xm29, xm7, xm8
    punpckhwd    xm7, xm8
    punpckldq    xm7, xm29, xm7
    pxor         xm7, [wcr_pdmax]
%else
    mov          r11, [rsp+WCR_SUM]
    movd         [r11+r6], xm6
    mov          r11, [rsp+WCR_SUM+8]
    vpextrd      [r11+r6], xm6, 2
    vpternlogd   xm8, xm8, xm8, 0x55
    vinserti32x4 ym7, ym7, xm8, 1
    psrlq        ym29, ym7, 32
    pminub       ym7, ym29
    psrlq        ym29, ym7, 16
    pminub       ym7, ym29
    psrlq        ym29, ym7, 8
    pminub       ym7, ym29
    vpmovqb      xm7, ym7
    pmovzxbw     xm7, xm7
    pxor         xm7, [wcr_pwmax]
    pshuflw      xm7, xm7, q3120
%endif
    mov          r11, [rsp+WCR_MM]
    movd         [r11+r6], xm7
    mov          r11, [rsp+WCR_MM+8]
    vpextrd      [r11+r6], xm7, 1
    ; the slots
    cmp          r14d, 0
    jle .slotend
    WCR_SLOTEND 0
    cmp          r14d, 1
    jle .slotend
    WCR_SLOTEND 1
    cmp          r14d, 2
    jle .slotend
    WCR_SLOTEND 2
.slotend:
    add          r0, 8*SIZEOF_PIXEL
    add          r10, 8*SIZEOF_PIXEL
    add          r2, 16*SIZEOF_PIXEL
    add          r3, [rsp+WCR_MVST]
    add          r6, 4
    dec          r4d
    jg .block
    RET

; avx2: the tap pairs of a row, outputs u0 v0 u1 v1 u2 v2 u3 v3 | u4 v4 ... v7
%macro WCR2_PAIRS 2 ; dst, src
    movu         m%1, [%2]
    vpermq       m%1, m%1, q2110
    psrldq       m10, m%1, 2
    punpcklbw    m%1, m10
%endmacro

; high bit depth: lo = outputs u0 v0 u1 v1 | u2 v2 u3 v3, hi = u4 v4 ... v7, a dword each
%macro WCR2_PAIRS16 3 ; dst lo, dst hi, src
    movu         m%1, [%3]
    movu         m%2, [%3+16]
    vpermq       m%1, m%1, q2110
    vpermq       m%2, m%2, q2110
    psrldq       m10, m%1, 4
    punpcklwd    m%1, m10
    psrldq       m10, m%2, 4
    punpcklwd    m%2, m10
%endmacro

%if HIGH_BIT_DEPTH
%define WCR2_ACC0 8
%define WCR2_ACC1 14
%define WCR2_ACC2 15
%else
%define WCR2_ACC0 11
%define WCR2_ACC1 12
%define WCR2_ACC2 13
%endif
%define WCR2_K 128

; an output row from the pairs of the row and the row below, at row offset %3
%macro WCR2_ROW8 3
    pmaddubsw    m4, m%1, m2
    pmaddubsw    m10, m%2, m3
    paddw        m4, m10
    pmulhrsw     m4, [wcr_pw512]
    pshufb       m4, m15
    vpermq       m4, m4, q3120
    packuswb     m5, m4, m4
    vpermq       m5, m5, q2020
    movq         [r12+%3], xm5
    movhps       [r13+%3], xm5
    psadbw       xm10, xm5, xm14
    paddq        xm6, xm10
    pminub       xm7, xm5
    pmaxub       xm8, xm5
    psllw        m9, m4, 7
    cmp          r14d, 0
    jle %%done
    pmulhrsw     m10, m9, [rsp+WCR2_K]
    pmaddwd      m10, [wsrch_pw1]
    paddd        m %+ WCR2_ACC0, m10
    cmp          r14d, 1
    jle %%done
    pmulhrsw     m10, m9, [rsp+WCR2_K+32]
    pmaddwd      m10, [wsrch_pw1]
    paddd        m %+ WCR2_ACC1, m10
    cmp          r14d, 2
    jle %%done
    pmulhrsw     m10, m9, [rsp+WCR2_K+64]
    pmaddwd      m10, [wsrch_pw1]
    paddd        m %+ WCR2_ACC2, m10
%%done:
%endmacro

; (x * scale + round) >> denom of the dwords of m6 and m7, pair %1, added to m%2
%macro WCR2_SLOT16 2
    pmaddwd      m9, m6, [rsp+WCR2_K+96*%1]
    paddd        m9, [rsp+WCR2_K+96*%1+32]
    vpsrlvd      m9, m9, [rsp+WCR2_K+96*%1+64]
    paddd        m%2, m9
    pmaddwd      m9, m7, [rsp+WCR2_K+96*%1]
    paddd        m9, [rsp+WCR2_K+96*%1+32]
    vpsrlvd      m9, m9, [rsp+WCR2_K+96*%1+64]
    paddd        m%2, m9
%endmacro

%macro WCR2_ROW16 5
    pmaddwd      m6, m%1, m4
    pmaddwd      m10, m%3, m5
    paddd        m6, m10
    paddd        m6, [wcr_pd32]
    psrld        m6, 6
    pmaddwd      m7, m%2, m4
    pmaddwd      m10, m%4, m5
    paddd        m7, m10
    paddd        m7, [wcr_pd32]
    psrld        m7, 6
    cmp          r14d, 0
    jle %%done
    WCR2_SLOT16 0, WCR2_ACC0
    cmp          r14d, 1
    jle %%done
    WCR2_SLOT16 1, WCR2_ACC1
    cmp          r14d, 2
    jle %%done
    WCR2_SLOT16 2, WCR2_ACC2
%%done:
    packusdw     m6, m7
    pshufb       m6, [wcr_wdeint]
    mova         m10, [wcr_dperm]
    vpermd       m6, m10, m6
    movu         [r12+%5], xm6
    vextracti128 [r13+%5], m6, 1
    pmaddwd      m10, m6, [wsrch_pw1]
    paddd        m11, m10
    pminuw       m12, m6
    pmaxuw       m13, m6
%endmacro

; slot %1 of plane %2 (avx2): set bit, pairs to do, the constants of pair %1 on the stack
%macro WCR2_SLOTPARAM 2
%assign wcr_q %1+3*%2
    movsx        r11d, word [r8+4*wcr_q]
    movsx        r9d, word [r8+4*wcr_q+2]
    test         r11d, r11d
    jge %%set
    xor          r11d, r11d
    xor          r9d, r9d
    jmp %%unset
%%set:
    or           dword [rsp+WCR_VALID], 1<<wcr_q
    mov          r14d, %1+1
%%unset:
%if HIGH_BIT_DEPTH
    ; dwords u, v alternating: scale, rounding, denom
    mov          [rsp+WCR2_K+96*%1+4*%2], r11d
    mov          [rsp+WCR2_K+96*%1+4*%2+8], r11d
    mov          [rsp+WCR2_K+96*%1+4*%2+16], r11d
    mov          [rsp+WCR2_K+96*%1+4*%2+24], r11d
    lea          r11, [wsrch_rnd32]
    mov          r11d, [r11+4*r9]
    shr          r11d, 5
    mov          [rsp+WCR2_K+96*%1+4*%2+32], r11d
    mov          [rsp+WCR2_K+96*%1+4*%2+40], r11d
    mov          [rsp+WCR2_K+96*%1+4*%2+48], r11d
    mov          [rsp+WCR2_K+96*%1+4*%2+56], r11d
    mov          [rsp+WCR2_K+96*%1+4*%2+64], r9d
    mov          [rsp+WCR2_K+96*%1+4*%2+72], r9d
    mov          [rsp+WCR2_K+96*%1+4*%2+80], r9d
    mov          [rsp+WCR2_K+96*%1+4*%2+88], r9d
%else
    imul         r11d, [r7+4*r9]
    movd         xm10, r11d
    vpbroadcastw xm10, xm10
    mova         [rsp+WCR2_K+32*%1+16*%2], xm10
%endif
%endmacro

; the sums of slot pair %1 (accumulator %2) to wsum q %1 and %1+3 if set
%macro WCR2_SLOTEND 2
    vextracti128 xm10, m%2, 1
%if HIGH_BIT_DEPTH
    paddd        xm10, xm%2
    pshufd       xm9, xm10, q1032
    paddd        xm9, xm10                  ; u, v
%else
    phaddd       xm9, xm%2, xm10            ; u01 u23 v01 v23
    phaddd       xm9, xm9
%endif
    test         byte [rsp+WCR_VALID], 1<<%1
    jz %%v
    mov          r11, [rsp+WCR_WSUM+8*%1]
    movd         [r11+r6], xm9
%%v:
    test         byte [rsp+WCR_VALID], 8<<%1
    jz %%done
    mov          r11, [rsp+WCR_WSUM+8*%1+24]
    pextrd       [r11+r6], xm9, 1
%%done:
%endmacro

INIT_YMM avx2
cglobal weightp_chroma_ref_row, 10,15,16, -416
    WCR_START
    xor          r14d, r14d
    mov          dword [rsp+WCR_VALID], 0
    lea          r7, [wsrch_pow]
    WCR2_SLOTPARAM 0, 0
    WCR2_SLOTPARAM 0, 1
    WCR2_SLOTPARAM 1, 0
    WCR2_SLOTPARAM 1, 1
    WCR2_SLOTPARAM 2, 0
    WCR2_SLOTPARAM 2, 1
%if HIGH_BIT_DEPTH == 0
    mova         m15, [wcr_wdeint]
    pxor         xm14, xm14
%endif
    xor          r6d, r6d
.block:
    WCR_BLOCKSRC
%if HIGH_BIT_DEPTH
    vpbroadcastd m4, [r11+8*r9]
    vpbroadcastd m5, [r11+8*r9+4]
    pxor         m11, m11
    pcmpeqb      m12, m12
    pxor         m13, m13
%else
    vpbroadcastw m2, [r11+4*r9]
    vpbroadcastw m3, [r11+4*r9+2]
    pxor         xm6, xm6
    pcmpeqb      xm7, xm7
    pxor         xm8, xm8
%endif
    pxor         m %+ WCR2_ACC0, m %+ WCR2_ACC0
    pxor         m %+ WCR2_ACC1, m %+ WCR2_ACC1
    pxor         m %+ WCR2_ACC2, m %+ WCR2_ACC2
    mov          r12, r0
    mov          r13, r10
    mov          r9d, r5d
%if HIGH_BIT_DEPTH
    WCR2_PAIRS16 0, 1, r8
.rows:
    add          r8, r1
    WCR2_PAIRS16 2, 3, r8
    WCR2_ROW16 0, 1, 2, 3, 0
    add          r8, r1
    WCR2_PAIRS16 0, 1, r8
    WCR2_ROW16 2, 3, 0, 1, r1
%else
    WCR2_PAIRS 0, r8
.rows:
    add          r8, r1
    WCR2_PAIRS 1, r8
    WCR2_ROW8 0, 1, 0
    add          r8, r1
    WCR2_PAIRS 0, r8
    WCR2_ROW8 1, 0, r1
%endif
    lea          r12, [r12+2*r1]
    lea          r13, [r13+2*r1]
    sub          r9d, 2
    jg .rows
    ; sums, min | max << 16
%if HIGH_BIT_DEPTH
    vextracti128 xm10, m11, 1
    phaddd       xm11, xm10
    phaddd       xm11, xm11
    mov          r11, [rsp+WCR_SUM]
    movd         [r11+r6], xm11
    mov          r11, [rsp+WCR_SUM+8]
    pextrd       [r11+r6], xm11, 1
    pshufd       m10, m12, q1032
    pminuw       m12, m10
    pshufd       m10, m12, q2301
    pminuw       m12, m10
    psrld        m10, m12, 16
    pminuw       m12, m10
    pshufd       m10, m13, q1032
    pmaxuw       m13, m10
    pshufd       m10, m13, q2301
    pmaxuw       m13, m10
    psrld        m10, m13, 16
    pmaxuw       m13, m10
    punpcklwd    m12, m13
    mov          r11, [rsp+WCR_MM]
    movd         [r11+r6], xm12
    vextracti128 xm12, m12, 1
    mov          r11, [rsp+WCR_MM+8]
    movd         [r11+r6], xm12
%else
    mov          r11, [rsp+WCR_SUM]
    movd         [r11+r6], xm6
    mov          r11, [rsp+WCR_SUM+8]
    pextrd       [r11+r6], xm6, 2
    psrlq        xm10, xm7, 32
    pminub       xm7, xm10
    psrlq        xm10, xm7, 16
    pminub       xm7, xm10
    psrlq        xm10, xm7, 8
    pminub       xm7, xm10
    psrlq        xm10, xm8, 32
    pmaxub       xm8, xm10
    psrlq        xm10, xm8, 16
    pmaxub       xm8, xm10
    psrlq        xm10, xm8, 8
    pmaxub       xm8, xm10
    mova         xm10, [wcr_b08]
    pshufb       xm7, xm10
    pshufb       xm8, xm10
    punpcklbw    xm7, xm8
    pmovzxbw     xm7, xm7
    mov          r11, [rsp+WCR_MM]
    movd         [r11+r6], xm7
    mov          r11, [rsp+WCR_MM+8]
    pextrd       [r11+r6], xm7, 1
%endif
    ; the slots
    cmp          r14d, 0
    jle .slotend
    WCR2_SLOTEND 0, WCR2_ACC0
    cmp          r14d, 1
    jle .slotend
    WCR2_SLOTEND 1, WCR2_ACC1
    cmp          r14d, 2
    jle .slotend
    WCR2_SLOTEND 2, WCR2_ACC2
.slotend:
    add          r0, 8*SIZEOF_PIXEL
    add          r10, 8*SIZEOF_PIXEL
    add          r2, 16*SIZEOF_PIXEL
    add          r3, [rsp+WCR_MVST]
    add          r6, 4
    dec          r4d
    jg .block
    RET

%if HIGH_BIT_DEPTH == 0
;-----------------------------------------------------------------------------
; int pixel_sad_avg2_w_WxH( uint8_t *fenc, uint8_t *src1, uint8_t *src2, intptr_t stride, const uint8_t *lut )
; int pixel_satd_avg2_pre_w_WxH( int16_t *fenc_pre, uint8_t *src1, uint8_t *src2, intptr_t stride,
;                                const uint8_t *lut )
; sad / satd_avg2_pre of lut[ pavgb( src1, src2 ) ]: the weight as a 256-byte table in 4 zmm,
; two vpermi2b of the 7 low bits, the halves picked by bit 7 (vpmovb2m). 4 rows of 16 or
; 8 rows of 8 a zmm; satd as satd_avg2_pre avx512icl (fenc_pre's rows, opmask transform).
;-----------------------------------------------------------------------------
; m%1 = lut[ m%1 ] (m%2 clobbered), tables in m12-m15
%macro WAV_LUT 2
    vpmovb2m     k3, m%1
    mova         m%2, m%1
    vpermi2b     m%1, m12, m13
    vpermi2b     m%2, m14, m15
    vmovdqu8     m%1 {k3}, m%2
%endmacro

%macro WAV_LUTLOAD 0
    movu         m12, [r4]
    movu         m13, [r4+64]
    movu         m14, [r4+128]
    movu         m15, [r4+192]
%endmacro

; m%1 = 4 rows of 16 from %2 (r5 = 3*stride), m%3 clobbered
%macro WAV_LOAD16 3
    movu         xm%1, [%2]
    vinserti32x4 ym%1, ym%1, [%2+r3], 1
    movu         xm%3, [%2+2*r3]
    vinserti32x4 ym%3, ym%3, [%2+r5], 1
    vinserti64x4 m%1, m%1, ym%3, 1
%endmacro

; m%1 = 8 rows of 8 from %2 and %3 = %2 + 4*stride, m%4, m%5 clobbered
%macro WAV_LOAD8 5
    movq         xm%1, [%2]
    movhps       xm%1, [%2+r3]
    movq         xm%4, [%2+2*r3]
    movhps       xm%4, [%2+r5]
    vinserti32x4 ym%1, ym%1, xm%4, 1
    movq         xm%4, [%3]
    movhps       xm%4, [%3+r3]
    movq         xm%5, [%3+2*r3]
    movhps       xm%5, [%3+r5]
    vinserti32x4 ym%4, ym%4, xm%5, 1
    vinserti64x4 m%1, m%1, ym%4, 1
%endmacro

; m0 = the weighted averages of the 16 wide rows at r1, r2, which move down 4 rows
%macro WAV_AVG16 0
    WAV_LOAD16 0, r1, 1
    WAV_LOAD16 2, r2, 3
    pavgb        m0, m2
    WAV_LUT 0, 1
    lea          r1, [r1+4*r3]
    lea          r2, [r2+4*r3]
%endmacro

; m0 = the weighted averages of the 8 wide rows at r1, r2 (r6, r7: 4 rows down), which
; move down 8 rows
%macro WAV_AVG8 0
    WAV_LOAD8 0, r1, r6, 1, 2
    WAV_LOAD8 3, r2, r7, 1, 2
    pavgb        m0, m3
    WAV_LUT 0, 1
    lea          r1, [r1+8*r3]
    lea          r2, [r2+8*r3]
    lea          r6, [r6+8*r3]
    lea          r7, [r7+8*r3]
%endmacro

%macro WAV_SAD 2 ; w, h
cglobal pixel_sad_avg2_w_%1x%2, 5,8,16
    WAV_LUTLOAD
    lea          r5, [3*r3]
%if %1 == 8
    lea          r6, [r1+4*r3]
    lea          r7, [r2+4*r3]
    mova         m5, [wav_qeven]
%endif
    pxor         xm6, xm6
%assign wav_i 0
%rep %1*%2/64
%if %1 == 16
    WAV_AVG16
    psadbw       m0, [r0+64*wav_i]
%else
    WAV_AVG8
    movu         m1, [r0+128*wav_i]
    vpermt2q     m1, m5, [r0+128*wav_i+64]
    psadbw       m0, m1
%endif
    paddq        m6, m0
%assign wav_i wav_i+1
%endrep
    vextracti64x4 ym0, m6, 1
    paddq        ym6, ym0
    vextracti32x4 xm0, ym6, 1
    paddq        xm6, xm0
    punpckhqdq   xm0, xm6, xm6
    paddq        xm6, xm0
    movd         eax, xm6
    RET
%endmacro

; satd_avg2_pre_avx512icl's 8x4 (SATD_ICL_8x4) on ym0-ym3, k1 = 0x5555, into ym6
%macro WAV_HMAX 3 ; a, b, tmp
    vpblendmw    ym%3 {k1}, ym%1, ym%2
    vpshldd      ym%2, ym%1, ym%2, 16
    pmaxsw       ym%1, ym%3, ym%2
%endmacro

%macro WAV_8x4 1 ; first
    paddw        ym0, ym1
    paddw        ym2, ym3
    paddw        ym1, ym1
    paddw        ym3, ym3
    psubw        ym1, ym0
    psubw        ym3, ym2
    paddw        ym0, ym2
    paddw        ym1, ym3
    paddw        ym2, ym2
    paddw        ym3, ym3
    psubw        ym2, ym0
    psubw        ym3, ym1
    pabsw        ym0, ym0
    pabsw        ym2, ym2
    pabsw        ym1, ym1
    pabsw        ym3, ym3
    WAV_HMAX 0, 2, 4
    WAV_HMAX 1, 3, 5
%if %1
    paddw        ym6, ym0, ym1
%else
    paddw        ym0, ym1
    paddw        ym6, ym0
%endif
%endmacro

; 16 wide: 4 rows of m0 less fenc_pre rows %1-%1+3, satd into ym6
%macro WAV_PRE16 2 ; fenc_pre row, first
    vextracti64x4 ym8, m0, 1
    vshufi32x4   ym1, ym0, ym0, 3
    vshufi32x4   ym0, ym0, ym0, 0
    vshufi32x4   ym3, ym8, ym8, 3
    vshufi32x4   ym2, ym8, ym8, 0
    pmaddubsw    ym0, ym7
    pmaddubsw    ym1, ym7
    pmaddubsw    ym2, ym7
    pmaddubsw    ym3, ym7
    psubw        ym0, [r0+(%1+0)*32]
    psubw        ym1, [r0+(%1+1)*32]
    psubw        ym2, [r0+(%1+2)*32]
    psubw        ym3, [r0+(%1+3)*32]
    WAV_8x4 %2
%endmacro

; 8 wide: rows k, k+4 of the 8 rows of m0 a register, less fenc_pre's (offset %1)
%macro WAV_PRE8 2 ; fenc_pre offset, first
    vpermq       m1, m9, m0
    vpermq       m2, m10, m0
    vpermq       m3, m11, m0
    vpermq       m0, m8, m0
    pmaddubsw    ym0, ym7
    pmaddubsw    ym1, ym7
    pmaddubsw    ym2, ym7
    pmaddubsw    ym3, ym7
    psubw        ym0, [r0+%1]
    psubw        ym1, [r0+%1+32]
    psubw        ym2, [r0+%1+64]
    psubw        ym3, [r0+%1+96]
    WAV_8x4 %2
%endmacro

%macro WAV_SATD 2 ; w, h
cglobal pixel_satd_avg2_pre_w_%1x%2, 5,8,16
    WAV_LUTLOAD
    lea          r5, [3*r3]
    mov          r6d, 0x5555
    kmovd        k1, r6d
%if %1 == 8
    lea          r6, [r1+4*r3]
    lea          r7, [r2+4*r3]
    mova         ym7, [wav_hmul8]
    mova         m8, [wav_q8]
    mova         m9, [wav_q8+64]
    mova         m10, [wav_q8+128]
    mova         m11, [wav_q8+192]
%assign wav_i 0
%rep %2/8
    WAV_AVG8
    WAV_PRE8 128*wav_i, wav_i == 0
%assign wav_i wav_i+1
%endrep
%else
    mova         ym7, [wav_hmul16]
%assign wav_i 0
%rep %2/4
    WAV_AVG16
    WAV_PRE16 4*wav_i, wav_i == 0
%assign wav_i wav_i+1
%endrep
%endif
    vextracti32x4 xm0, ym6, 1
    paddw        xm0, xm6
    pmaddwd      xm0, [wav_pw1]
    pshufd       xm1, xm0, q1032
    paddd        xm0, xm1
    pshufd       xm1, xm0, q2301
    paddd        xm0, xm1
    movd         eax, xm0
    RET
%endmacro

INIT_ZMM avx512icl
WAV_SAD 16, 16
WAV_SAD 16, 8
WAV_SAD 8, 16
WAV_SAD 8, 8
WAV_SATD 16, 16
WAV_SATD 16, 8
WAV_SATD 8, 16
WAV_SATD 8, 8
%endif ; !HIGH_BIT_DEPTH
%endif ; ARCH_X86_64
