;*****************************************************************************
;* deblock-a.asm: x86 deblocking
;*****************************************************************************
;* Copyright (C) 2005-2014 x264 project
;*
;* Authors: Loren Merritt <lorenm@u.washington.edu>
;*          Jason Garrett-Glaser <darkshikari@gmail.com>
;*          Oskar Arvidsson <oskar@irock.se>
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

load_bytes_zmm_shuf: dd 0x50404032, 0x70606053, 0xd0c0c0b4, 0xf0e0e0d5
                     dd 0x50404036, 0x70606057, 0xd0c0c0b8, 0xf0e0e0d9
                     dd 0x50104001, 0x70306023, 0xd090c083, 0xf0b0e0a5
                     dd 0x50104005, 0x70306027, 0xd090c087, 0xf0b0e0a9
; vpermb indices into scan8 bytes 8..39 (left) and 4..35 (top)
strength_cur_idx: times 2 db 4,5,6,7,12,13,14,15,20,21,22,23,28,29,30,31
strength_nb_idx:  db 3,4,5,6,11,12,13,14,19,20,21,22,27,28,29,30
                  db 0,1,2,3,8,9,10,11,16,17,18,19,24,25,26,27

; 8-bit h luma, vpermi2b over 16 rows of p3..q3: column pairs [pN|qN] of 16 rows
%macro DB_COLS16 4
%rep 4
%assign %%r 0
%rep 16
    db 8*%%r+%1
%assign %%r %%r+1
%endrep
%rotate 1
%endrep
%endmacro
; and back from [p0|q0|p1|q1], [p2|q2|p3|q3] to 8 rows of p3..q3
%macro DB_ROWS8 1
%assign %%r %1
%rep 8
    db 96+%%r, 64+%%r, 32+%%r, %%r, 16+%%r, 48+%%r, 80+%%r, 112+%%r
%assign %%r %%r+1
%endrep
%endmacro
h_luma_p01_idx: DB_COLS16 3, 4, 2, 5
h_luma_p23_idx: DB_COLS16 1, 6, 0, 7
h_luma_q01_idx: DB_COLS16 4, 3, 5, 2
h_luma_q23_idx: DB_COLS16 6, 1, 7, 0
h_luma_rows0_idx: DB_ROWS8 0
h_luma_rows8_idx: DB_ROWS8 8
chroma422_tc_shuf: times 16 db 0
                   times 16 db 1
                   times 16 db 2
                   times 16 db 3
; MBAFF: rows 0-7 <-> [pN|qN] qword pairs
%macro DB_COLS8 8
%rep 8
%assign %%r 0
%rep 8
    db 8*%%r+%1
%assign %%r %%r+1
%endrep
%rotate 1
%endrep
%endmacro
mbaff_p_idx: DB_COLS8 3, 4, 2, 5, 1, 6, 0, 7
mbaff_q_idx: DB_COLS8 4, 3, 5, 2, 6, 1, 7, 0
%macro DB_ROWS8M 0
%assign %%r 0
%rep 8
    db 48+%%r, 32+%%r, 16+%%r, %%r, 8+%%r, 24+%%r, 40+%%r, 56+%%r
%assign %%r %%r+1
%endrep
%endmacro
mbaff_rows_idx: DB_ROWS8M
load_bytes_shuf: times 2 db 3,4,5,6,11,12,13,14,4,5,6,7,12,13,14,15
insert_top_shuf: dd 0,1,4,5,7,2,3,6
deblock_tc_shuf_avx2: db 0,0,0,0,0,0,0,0, 1,1,1,1,1,1,1,1, 2,2,2,2,2,2,2,2, 3,3,3,3,3,3,3,3
transpose_shuf: db 0,4,8,12,1,5,9,13,2,6,10,14,3,7,11,15
; gf2p8affineqb: bit 0 = x.1^x.2 (x.2^x.3), i.e. (((x>>1)+1)>>1)&1 (x>>2)
gf_par1: dq 0x0600000000000000
gf_par2: dq 0x0c00000000000000
mbaff_tc_shuf: times 2 db 0,0,1,1,2,2,3,3

SECTION .text

cextern pb_0
cextern pb_1
cextern pb_3
cextern pb_a1
cextern pw_2
cextern pw_1
cextern pw_4
cextern pw_00ff
cextern pw_pixel_max
cextern pb_unpackbd1

; 16 bytes of rows: %1-%8 rows 0-7 to lane 0 of m0-m7, %9-%16 rows 8-15 to lane 1
%macro LOAD_ROWS_LANES 16
    movu        xm0, %1
    vinserti128  m0, m0, %9, 1
    movu        xm1, %2
    vinserti128  m1, m1, %10, 1
    movu        xm2, %3
    vinserti128  m2, m2, %11, 1
    movu        xm3, %4
    vinserti128  m3, m3, %12, 1
    movu        xm4, %5
    vinserti128  m4, m4, %13, 1
    movu        xm5, %6
    vinserti128  m5, m5, %14, 1
    movu        xm6, %7
    vinserti128  m6, m6, %15, 1
    movu        xm7, %8
    vinserti128  m7, m7, %16, 1
%endmacro

%define ROWS16(b0, b4, b8, b12, s, s3) [b0], [b0+s], [b0+s*2], [b0+s3], \
    [b4], [b4+s], [b4+s*2], [b4+s3], \
    [b8], [b8+s], [b8+s*2], [b8+s3], \
    [b12], [b12+s], [b12+s*2], [b12+s3]

%if HIGH_BIT_DEPTH
; out: %4 = |%1-%2|-%3
; clobbers: %5
%macro ABS_SUB 5
    psubusw %5, %2, %1
    psubusw %4, %1, %2
    por     %4, %5
    psubw   %4, %3
%endmacro

; out: %1 = %2 > %3; %2 may be memory
%macro PCMPGTW_MR 3
%ifnum sizeof%2
    pcmpgtw %1, %2, %3
%else
    mova    %1, %2
    pcmpgtw %1, %3
%endif
%endmacro

; out: %4 = |%1-%2|<%3
%macro DIFF_LT   5
%if cpuflag(ssse3)
    ; exact: |%1-%2| <= pixel_max fits a signed word
    psubw   %5, %1, %2
    pabsw   %5, %5
    PCMPGTW_MR %4, %3, %5
%else
    psubusw %4, %2, %1
    psubusw %5, %1, %2
    por     %5, %4 ; |%1-%2|
    pxor    %4, %4
    psubw   %5, %3 ; |%1-%2|-%3
    pcmpgtw %4, %5 ; 0 > |%1-%2|-%3
%endif
%endmacro

%macro LOAD_AB 4
    movd       %1, %3
    movd       %2, %4
    SPLATW     %1, %1
    SPLATW     %2, %2
%endmacro

; in:  %2=tc reg
; out: %1=splatted tc
%macro LOAD_TC 2
%if mmsize == 8
    pshufw      %1, [%2-1], 0
%elif mmsize == 32
    vpbroadcastd %1, [%2]
    pshufb      %1, [deblock_tc_shuf_avx2]
%else
    movd        %1, [%2]
    punpcklbw   %1, %1
    pshuflw     %1, %1, q1100
    pshufd      %1, %1, q1100
%endif
    psraw       %1, 8
%endmacro

; in: %1=p1, %2=p0, %3=q0, %4=q1
;     %5=alpha, %6=beta, %7-%9=tmp
; out: %7=mask
%macro LOAD_MASK 9
%if cpuflag(ssse3)
    psubw       %8, %2, %3
    pabsw       %8, %8
    PCMPGTW_MR  %7, %5, %8     ; |p0-q0| < alpha
    psubw       %8, %1, %2
    pabsw       %8, %8
    psubw       %9, %3, %4
    pabsw       %9, %9
    pmaxsw      %8, %9
    PCMPGTW_MR  %9, %6, %8     ; max(|p1-p0|, |q1-q0|) < beta
    pand        %7, %9
%else
    ABS_SUB     %2, %3, %5, %8, %7 ; |p0-q0| - alpha
    ABS_SUB     %1, %2, %6, %9, %7 ; |p1-p0| - beta
    pand        %8, %9
    ABS_SUB     %3, %4, %6, %9, %7 ; |q1-q0| - beta
    pxor        %7, %7
    pand        %8, %9
    pcmpgtw     %7, %8
%endif
%endmacro

; in: %1=p0, %2=q0, %3=p1, %4=q1, %5=mask, %6=tmp, %7=tmp
; out: %1=p0', m2=q0'
%macro DEBLOCK_P0_Q0 7
    psubw   %3, %4
    pxor    %7, %7
    paddw   %3, [pw_4]
    psubw   %7, %5
    psubw   %6, %2, %1
    psllw   %6, 2
    paddw   %3, %6
    psraw   %3, 3
    mova    %6, [pw_pixel_max]
    CLIPW   %3, %7, %5
    pxor    %7, %7
    paddw   %1, %3
    psubw   %2, %3
    CLIPW   %1, %7, %6
    CLIPW   %2, %7, %6
%endmacro

; in: %1=x2, %2=x1, %3=p0, %4=q0 %5=mask&tc, %6=tmp
%macro LUMA_Q1 6
    pavgw       %6, %3, %4      ; (p0+q0+1)>>1
    paddw       %1, %6
    pxor        %6, %6
    psraw       %1, 1
    psubw       %6, %5
    psubw       %1, %2
    CLIPW       %1, %6, %5
    paddw       %1, %2
%endmacro

; in: %1=x2, %2=x1, %3=(p0+q0+1)>>1, %4=mask&tc (clobbered), %5=tmp
; clip((x2+avg)>>1, x1-tc, x1+tc), as LUMA_Q1
%macro LUMA_Q1_AVG 5
    paddw       %1, %3
    psraw       %1, 1
    psubw       %5, %2, %4
    paddw       %4, %2
    pmaxsw      %1, %5
    pminsw      %1, %4
%endmacro

%macro LUMA_DEBLOCK_ONE 3
    DIFF_LT     m5, %1, bm, m4, m6
    pxor        m6, m6
    mova        %3, m4
    pcmpgtw     m6, tcm
    pand        m4, tcm
    pandn       m6, m7
    pand        m4, m6
    LUMA_Q1 m5, %2, m1, m2, m4, m6
%endmacro

%macro LUMA_H_STORE 2
%if mmsize == 8
    movq        [r0-4], m0
    movq        [r0+r1-4], m1
    movq        [r0+r1*2-4], m2
    movq        [r0+%2-4], m3
%else
    movq        [r0-4], m0
    movhps      [r0+r1-4], m0
    movq        [r0+r1*2-4], m1
    movhps      [%1-4], m1
    movq        [%1+r1-4], m2
    movhps      [%1+r1*2-4], m2
    movq        [%1+%2-4], m3
    movhps      [%1+r1*4-4], m3
%endif
%endmacro

%macro DEBLOCK_LUMA 0
;-----------------------------------------------------------------------------
; void deblock_v_luma( uint16_t *pix, intptr_t stride, int alpha, int beta, int8_t *tc0 )
;-----------------------------------------------------------------------------
cglobal deblock_v_luma, 5,5,8,0-5*mmsize
    %define tcm [rsp]
    %define ms1 [rsp+mmsize]
    %define ms2 [rsp+mmsize*2]
    %define am  [rsp+mmsize*3]
    %define bm  [rsp+mmsize*4]
    add         r1, r1
    LOAD_AB     m4, m5, r2d, r3d
    mov         r3, 32/mmsize
    mov         r2, r0
    sub         r0, r1
    mova        am, m4
    sub         r0, r1
    mova        bm, m5
    sub         r0, r1
.loop:
    mova        m0, [r0+r1]
    mova        m1, [r0+r1*2]
    mova        m2, [r2]
    mova        m3, [r2+r1]

    LOAD_MASK   m0, m1, m2, m3, am, bm, m7, m4, m6
    LOAD_TC     m6, r4
    mova       tcm, m6

    mova        m5, [r0]
    LUMA_DEBLOCK_ONE m1, m0, ms1
    mova   [r0+r1], m5

    mova        m5, [r2+r1*2]
    LUMA_DEBLOCK_ONE m2, m3, ms2
    mova   [r2+r1], m5

    pxor        m5, m5
    mova        m6, tcm
    pcmpgtw     m5, tcm
    psubw       m6, ms1
    pandn       m5, m7
    psubw       m6, ms2
    pand        m5, m6
    DEBLOCK_P0_Q0 m1, m2, m0, m3, m5, m7, m6
    mova [r0+r1*2], m1
    mova      [r2], m2

    add         r0, mmsize
    add         r2, mmsize
    add         r4, mmsize/8
    dec         r3
    jg .loop
    RET

cglobal deblock_h_luma, 5,6,8,0-7*mmsize
    %define tcm [rsp]
    %define ms1 [rsp+mmsize]
    %define ms2 [rsp+mmsize*2]
    %define p1m [rsp+mmsize*3]
    %define p2m [rsp+mmsize*4]
    %define am  [rsp+mmsize*5]
    %define bm  [rsp+mmsize*6]
    add         r1, r1
    LOAD_AB     m4, m5, r2d, r3d
    mov         r3, r1
    mova        am, m4
    add         r3, r1
    mov         r5, 32/mmsize
    mova        bm, m5
    add         r3, r1
%if mmsize == 16
    mov         r2, r0
    add         r2, r3
%endif
.loop:
%if mmsize == 8
    movq        m2, [r0-8]     ; y q2 q1 q0
    movq        m7, [r0+0]
    movq        m5, [r0+r1-8]
    movq        m3, [r0+r1+0]
    movq        m0, [r0+r1*2-8]
    movq        m6, [r0+r1*2+0]
    movq        m1, [r0+r3-8]
    TRANSPOSE4x4W 2, 5, 0, 1, 4
    SWAP         2, 7
    movq        m7, [r0+r3]
    TRANSPOSE4x4W 2, 3, 6, 7, 4
%else
    movu        m5, [r0-8]     ; y q2 q1 q0 p0 p1 p2 x
    movu        m0, [r0+r1-8]
    movu        m2, [r0+r1*2-8]
    movu        m3, [r2-8]
    TRANSPOSE4x4W 5, 0, 2, 3, 6
    mova       tcm, m3

    movu        m4, [r2+r1-8]
    movu        m1, [r2+r1*2-8]
    movu        m3, [r2+r3-8]
    movu        m7, [r2+r1*4-8]
    TRANSPOSE4x4W 4, 1, 3, 7, 6

    mova        m6, tcm
    punpcklqdq  m6, m7
    punpckhqdq  m5, m4
    SBUTTERFLY qdq, 0, 1, 7
    SBUTTERFLY qdq, 2, 3, 7
%endif

    mova       p2m, m6
    LOAD_MASK   m0, m1, m2, m3, am, bm, m7, m4, m6
    LOAD_TC     m6, r4
    mova       tcm, m6

    LUMA_DEBLOCK_ONE m1, m0, ms1
    mova       p1m, m5

    mova        m5, p2m
    LUMA_DEBLOCK_ONE m2, m3, ms2
    mova       p2m, m5

    pxor        m5, m5
    mova        m6, tcm
    pcmpgtw     m5, tcm
    psubw       m6, ms1
    pandn       m5, m7
    psubw       m6, ms2
    pand        m5, m6
    DEBLOCK_P0_Q0 m1, m2, m0, m3, m5, m7, m6
    mova        m0, p1m
    mova        m3, p2m
    TRANSPOSE4x4W 0, 1, 2, 3, 4
    LUMA_H_STORE r2, r3

    add         r4, mmsize/8
    lea         r0, [r0+r1*(mmsize/2)]
    lea         r2, [r2+r1*(mmsize/2)]
    dec         r5
    jg .loop
    RET
%endmacro

%if ARCH_X86_64
; in:  m0=p1, m1=p0, m2=q0, m3=q1, m8=p2, m9=q2
;      m12=alpha, m13=beta
; out: m0=p1', m3=q1', m1=p0', m2=q0'
; clobbers: m4, m5, m6, m7, m10, m11, m14
%macro DEBLOCK_LUMA_INTER_SSE2 0-1 0 ; 1: mbaff, 2: tc0 bytes in xm14 (avx2)
%if cpuflag(avx512)
%if %1 == 2
    vpbroadcastd m6, xm14
    pshufb      m6, [deblock_tc_shuf_avx2]
    psraw       m6, 8
%elif %1
    movd        m6, [r4]
    punpcklbw   m6, m6
    punpcklwd   m6, m6
    psraw       m6, 8
%else
    LOAD_TC     m6, r4
%endif
    psubw       m4, m1, m2
    psubw       m5, m0, m1
    psubw       m7, m3, m2
    psubw      m10, m8, m1
    psubw      m11, m9, m2
    pabsw       m4, m4
    pabsw       m5, m5
    pabsw       m7, m7
    pabsw      m10, m10
    pabsw      m11, m11
    pmaxsw      m5, m7
    vpcmpgtw    k1, m12, m4     ; |p0-q0| < alpha
    vpcmpgtw    k2, m13, m5     ; max(|p1-p0|, |q1-q0|) < beta
    vpcmpgtw    k3, m13, m10    ; ap
    vpcmpgtw    k4, m13, m11    ; aq
    vpmovw2m    k5, m6          ; tc0 < 0: bS 0
    kandw       k1, k1, k2
    kandnw      k1, k5, k1
    kandw       k3, k3, k1
    kandw       k4, k4, k1
    vmovdqu16   m6 {k1}{z}, m6  ; tc0 & mask
    psubw       m5, m2, m1
    psubw       m7, m0, m3
    psllw       m5, 2
    paddw       m5, m7
    paddw       m5, [pw_4]
    psraw       m5, 3           ; ((q0-p0)*4 + p1-q1 + 4) >> 3
    mova        m7, m6
    paddw       m7 {k3}, m7, [pw_1]
    paddw       m7 {k4}, m7, [pw_1] ; tc = tc0+ap+aq
    pxor       m14, m14
    psubw      m10, m14, m7
    pmaxsw      m5, m10
    pminsw      m5, m7          ; delta
    pavgw       m4, m1, m2      ; (p0+q0+1)>>1
    psubw       m7, m14, m6
    paddw      m10, m8, m4
    paddw      m11, m9, m4
    psraw      m10, 1
    psraw      m11, 1
    psubw      m10, m0
    psubw      m11, m3
    pmaxsw     m10, m7
    pmaxsw     m11, m7
    pminsw     m10, m6
    pminsw     m11, m6
    paddw      m10, m0
    paddw      m11, m3
    vpblendmw   m8 {k3}, m0, m10 ; p1'
    vpblendmw   m9 {k4}, m3, m11 ; q1'
    paddw       m1, m5
    psubw       m2, m5
    mova        m4, [pw_pixel_max]
    pmaxsw      m1, m14
    pmaxsw      m2, m14
    pminsw      m1, m4
    pminsw      m2, m4
%else
    LOAD_MASK   m0, m1, m2, m3, m12, m13, m7, m4, m6
%if %1 == 2
    vpbroadcastd m6, xm14
    pshufb      m6, [deblock_tc_shuf_avx2]
    psraw       m6, 8
%elif %1
    movd        m6, [r4]
    punpcklbw   m6, m6
    punpcklwd   m6, m6       ; tc0[i] covers rows 2i, 2i+1
    psraw       m6, 8
%else
    LOAD_TC     m6, r4
%endif
    DIFF_LT     m8, m1, m13, m10, m4
    DIFF_LT     m9, m2, m13, m11, m4
    pand       m14, m6, m7
    pxor        m4, m4
    pmaxsw      m6, m14, m4     ; tc = max(tc0 & mask, 0)
    psraw      m14, 15
    pandn      m14, m7          ; mask, but not where tc0 < 0 (bS 0)
    pavgw       m4, m1, m2      ; (p0+q0+1)>>1
    pand        m5, m10, m6
    LUMA_Q1_AVG m8, m0, m4, m5, m7
    pand        m5, m11, m6
    LUMA_Q1_AVG m9, m3, m4, m5, m7
    psubw       m6, m10
    psubw       m6, m11         ; tc + ap + aq
    pand        m4, m6, m14
    DEBLOCK_P0_Q0 m1, m2, m0, m3, m4, m5, m6

%endif
    SWAP         0, 8
    SWAP         3, 9
%endmacro

; in: r0=pix, r1=stride, r2=3*stride, r5=pix+3*stride, r4=tc0, m12=alpha, m13=beta
%macro DEBLOCK_H_LUMA_8ROWS 1 ; mbaff
    movu        m8, [r0-8]     ; y q2 q1 q0 p0 p1 p2 x
    movu        m0, [r0+r1-8]
    movu        m2, [r0+r1*2-8]
    movu        m9, [r5-8]
    movu        m5, [r5+r1-8]
    movu        m1, [r5+r1*2-8]
    movu        m3, [r5+r2-8]
    movu        m7, [r5+r1*4-8]

    TRANSPOSE4x4W 8, 0, 2, 9, 10
    TRANSPOSE4x4W 5, 1, 3, 7, 10

    punpckhqdq  m8, m5
    SBUTTERFLY qdq, 0, 1, 10
    SBUTTERFLY qdq, 2, 3, 10
    punpcklqdq  m9, m7

    DEBLOCK_LUMA_INTER_SSE2 %1

    TRANSPOSE4x4W 0, 1, 2, 3, 4
    LUMA_H_STORE r5, r2
%endmacro

%macro DEBLOCK_LUMA_64 0
cglobal deblock_v_luma, 5,5,15
    %define p2 m8
    %define p1 m0
    %define p0 m1
    %define q0 m2
    %define q1 m3
    %define q2 m9
    %define mask0 m7
    %define mask1 m10
    %define mask2 m11
    add         r1, r1
    LOAD_AB    m12, m13, r2d, r3d
    mov         r2, r0
    sub         r0, r1
    sub         r0, r1
    sub         r0, r1
    mov         r3, 2
.loop:
    mova        p2, [r0]
    mova        p1, [r0+r1]
    mova        p0, [r0+r1*2]
    mova        q0, [r2]
    mova        q1, [r2+r1]
    mova        q2, [r2+r1*2]
    DEBLOCK_LUMA_INTER_SSE2
    mova   [r0+r1], p1
    mova [r0+r1*2], p0
    mova      [r2], q0
    mova   [r2+r1], q1
    add         r0, mmsize
    add         r2, mmsize
    add         r4, 2
    dec         r3
    jg .loop
    RET

cglobal deblock_h_luma, 5,7,15
    add         r1, r1
    LOAD_AB    m12, m13, r2d, r3d
    mov         r2, r1
    add         r2, r1
    add         r2, r1
    mov         r5, r0
    add         r5, r2
    mov         r6, 2
.loop:
    DEBLOCK_H_LUMA_8ROWS 0
    add         r4, 2
    lea         r0, [r0+r1*8]
    lea         r5, [r5+r1*8]
    dec         r6
    jg .loop
    RET

;-----------------------------------------------------------------------------
; void deblock_h_luma_mbaff( uint16_t *pix, intptr_t stride, int alpha, int beta, int8_t *tc0 )
;-----------------------------------------------------------------------------
cglobal deblock_h_luma_mbaff, 5,6,15
    add         r1, r1
    LOAD_AB    m12, m13, r2d, r3d
    lea         r2, [r1*3]
    lea         r5, [r0+r2]
    DEBLOCK_H_LUMA_8ROWS 1
    RET
%endmacro

INIT_XMM sse2
DEBLOCK_LUMA_64
INIT_XMM avx
DEBLOCK_LUMA_64

;-----------------------------------------------------------------------------
; 10-bit deblock_v_luma / deblock_h_luma, AVX2: the whole 16 pixel edge in one
; pass. h_luma keeps rows 0-7 in lane 0 and rows 8-15 in lane 1, so its
; transposes stay lane-local and both directions see the same tc layout:
; words 0-3, 4-7 | 8-11, 12-15 = tc0[0], tc0[1] | tc0[2], tc0[3].
;-----------------------------------------------------------------------------
%macro DEBLOCK_H_LOAD_ROW 3 ; dst (number), row 0-7 address, row 8-15 address
    movu       xm%1, %2
    vinserti128 m%1, m%1, %3, 1
%endmacro

%macro DEBLOCK_LUMA_64_AVX2 0
cglobal deblock_v_luma, 5,5,15
    %define p2 m8
    %define p1 m0
    %define p0 m1
    %define q0 m2
    %define q1 m3
    %define q2 m9
    %define mask0 m7
    %define mask1 m10
    %define mask2 m11
    add         r1, r1
    movd       xm12, r2d
    movd       xm13, r3d
    vpbroadcastw m12, xm12
    vpbroadcastw m13, xm13
    mov         r2, r0
    sub         r0, r1
    sub         r0, r1
    sub         r0, r1
    movu        p2, [r0]
    movu        p1, [r0+r1]
    movu        p0, [r0+r1*2]
    movu        q0, [r2]
    movu        q1, [r2+r1]
    movu        q2, [r2+r1*2]
    DEBLOCK_LUMA_INTER_SSE2
    movu   [r0+r1], p1
    movu [r0+r1*2], p0
    movu      [r2], q0
    movu   [r2+r1], q1
    RET


cglobal deblock_h_luma, 5,7,15
    add         r1, r1
    movd       xm12, r2d
    movd       xm13, r3d
    vpbroadcastw m12, xm12
    vpbroadcastw m13, xm13
    lea         r2, [r1*3]
    lea         r5, [r0+r2]
    lea         r3, [r0+r1*8]
    lea         r6, [r5+r1*8]
    DEBLOCK_H_LOAD_ROW 8, [r0-8],      [r3-8]       ; y q2 q1 q0 p0 p1 p2 x
    DEBLOCK_H_LOAD_ROW 0, [r0+r1-8],   [r3+r1-8]
    DEBLOCK_H_LOAD_ROW 2, [r0+r1*2-8], [r3+r1*2-8]
    DEBLOCK_H_LOAD_ROW 9, [r5-8],      [r6-8]
    DEBLOCK_H_LOAD_ROW 5, [r5+r1-8],   [r6+r1-8]
    DEBLOCK_H_LOAD_ROW 1, [r5+r1*2-8], [r6+r1*2-8]
    DEBLOCK_H_LOAD_ROW 3, [r5+r2-8],   [r6+r2-8]
    DEBLOCK_H_LOAD_ROW 7, [r5+r1*4-8], [r6+r1*4-8]

    TRANSPOSE4x4W 8, 0, 2, 9, 10
    TRANSPOSE4x4W 5, 1, 3, 7, 10

    punpckhqdq  m8, m5
    SBUTTERFLY qdq, 0, 1, 10
    SBUTTERFLY qdq, 2, 3, 10
    punpcklqdq  m9, m7

    DEBLOCK_LUMA_INTER_SSE2

    TRANSPOSE4x4W 0, 1, 2, 3, 4
    movq        [r0-4], xm0
    movhps      [r0+r1-4], xm0
    movq        [r0+r1*2-4], xm1
    movhps      [r5-4], xm1
    movq        [r5+r1-4], xm2
    movhps      [r5+r1*2-4], xm2
    movq        [r5+r2-4], xm3
    movhps      [r5+r1*4-4], xm3
    vextracti128 xm0, m0, 1
    vextracti128 xm1, m1, 1
    vextracti128 xm2, m2, 1
    vextracti128 xm3, m3, 1
    movq        [r3-4], xm0
    movhps      [r3+r1-4], xm0
    movq        [r3+r1*2-4], xm1
    movhps      [r6-4], xm1
    movq        [r6+r1-4], xm2
    movhps      [r6+r1*2-4], xm2
    movq        [r6+r2-4], xm3
    movhps      [r6+r1*4-4], xm3
    RET
%endmacro

INIT_YMM avx2
DEBLOCK_LUMA_64_AVX2
INIT_YMM avx512icl
DEBLOCK_LUMA_64_AVX2

;-----------------------------------------------------------------------------
; 10-bit luma intra, avx512icl: the whole 16 pixel edge per ymm, k-masks for
; the alpha/beta tests and the output selects.
;-----------------------------------------------------------------------------
; %1-%6 = p0 p1 p2 p3 q0 q1, %7 = strong mask, %8/%9 = p0'/p1' out
; in: k1 = filter mask, m15 = pw_2; p2' is written over p2; clobbers m12-m14
%macro LUMA_INTRA10_SIDE 9
    paddw      m12, m%3, m%2
    paddw      m12, m%1
    paddw      m12, m%5
    paddw      m12, m15         ; p2+p1+p0+q0+2
    psubw      m13, m12, m%3
    psubw      m13, m%5
    paddw      m13, m%6
    paddw      m13, m%2
    psrlw      m13, 2           ; (2*p1+p0+q1+2)>>2
    vpblendmw  m%8 {k1}, m%1, m13
    paddw      m13, m12, m12
    psubw      m13, m%3
    paddw      m13, m%6
    psrlw      m13, 3           ; (p2+2*p1+2*p0+2*q0+q1+4)>>3
    vmovdqu16  m%8 {%7}, m13
    psrlw      m13, m12, 2      ; (p2+p1+p0+q0+2)>>2
    vpblendmw  m%9 {%7}, m%2, m13
    paddw      m14, m%4, m%3
    paddw      m14, m14
    paddw      m14, m15
    paddw      m14, m12
    psrlw      m14, 3           ; (2*p3+3*p2+p1+p0+q0+4)>>3
    vmovdqu16  m%3 {%7}, m14
%endmacro

; in: m0-m3 = p0-p3, m4-m7 = q0-q3, r2d = alpha, r3d = beta
; out: m0-m2, m4-m6 filtered
%macro LUMA_INTRA10_ICL 0
    vpbroadcastw m8, r2d
    vpbroadcastw m9, r3d
    shr        r2d, 2
    add        r2d, 2
    vpbroadcastw m10, r2d
    vpbroadcastd m15, [pw_2]
    psubw      m11, m0, m4
    psubw      m12, m1, m0
    psubw      m13, m5, m4
    pabsw      m11, m11         ; |p0-q0|
    pabsw      m12, m12
    pabsw      m13, m13
    pmaxsw     m12, m13         ; max(|p1-p0|, |q1-q0|)
    psubw      m13, m2, m0
    psubw      m14, m6, m4
    pabsw      m13, m13         ; |p2-p0|
    pabsw      m14, m14         ; |q2-q0|
    vpcmpgtw    k1, m8, m11
    vpcmpgtw    k2, m9, m12
    vpcmpgtw    k3, m10, m11
    vpcmpgtw    k4, m9, m13
    vpcmpgtw    k5, m9, m14
    kandw       k1, k1, k2      ; filter
    kandw       k3, k3, k1
    kandw       k4, k4, k3      ; strong p
    kandw       k5, k5, k3      ; strong q
    LUMA_INTRA10_SIDE 0, 1, 2, 3, 4, 5, k4, 8, 9
    LUMA_INTRA10_SIDE 4, 5, 6, 7, 0, 1, k5, 10, 11
    SWAP         0, 8
    SWAP         1, 9
    SWAP         4, 10
    SWAP         5, 11
%endmacro

INIT_YMM avx512icl
cglobal deblock_v_luma_intra, 4,6,16
    add         r1, r1
    lea         r4, [r1*4]
    lea         r5, [r1*3]
    neg         r4
    add         r4, r0          ; pix-4*stride
    movu        m0, [r4+r5]
    movu        m1, [r4+r1*2]
    movu        m2, [r4+r1]
    movu        m3, [r4]
    movu        m4, [r0]
    movu        m5, [r0+r1]
    movu        m6, [r0+r1*2]
    movu        m7, [r0+r5]
    LUMA_INTRA10_ICL
    movu   [r4+r5], m0
    movu [r4+r1*2], m1
    movu   [r4+r1], m2
    movu      [r0], m4
    movu   [r0+r1], m5
    movu [r0+r1*2], m6
    RET

; rows 0-7 | 8-15 per ymm, so the transposes stay lane-local
INIT_YMM avx512icl
cglobal deblock_h_luma_intra, 4,8,16
    add         r1, r1
    lea         r5, [r1*3]
    lea         r4, [r0+r1*4]
    lea         r6, [r0+r1*8]
    lea         r7, [r4+r1*8]
    DEBLOCK_H_LOAD_ROW 3, [r0-8],      [r6-8]
    DEBLOCK_H_LOAD_ROW 2, [r0+r1-8],   [r6+r1-8]
    DEBLOCK_H_LOAD_ROW 1, [r0+r1*2-8], [r6+r1*2-8]
    DEBLOCK_H_LOAD_ROW 0, [r0+r5-8],   [r6+r5-8]
    DEBLOCK_H_LOAD_ROW 4, [r4-8],      [r7-8]
    DEBLOCK_H_LOAD_ROW 5, [r4+r1-8],   [r7+r1-8]
    DEBLOCK_H_LOAD_ROW 6, [r4+r1*2-8], [r7+r1*2-8]
    DEBLOCK_H_LOAD_ROW 7, [r4+r5-8],   [r7+r5-8]
    TRANSPOSE8x8W 3, 2, 1, 0, 4, 5, 6, 7, 8
    LUMA_INTRA10_ICL
    TRANSPOSE8x8W 3, 2, 1, 0, 4, 5, 6, 7, 8
    movu        [r0-8], xm3
    vextracti128 [r6-8], m3, 1
    movu     [r0+r1-8], xm2
    vextracti128 [r6+r1-8], m2, 1
    movu   [r0+r1*2-8], xm1
    vextracti128 [r6+r1*2-8], m1, 1
    movu     [r0+r5-8], xm0
    vextracti128 [r6+r5-8], m0, 1
    movu        [r4-8], xm4
    vextracti128 [r7-8], m4, 1
    movu     [r4+r1-8], xm5
    vextracti128 [r7+r1-8], m5, 1
    movu   [r4+r1*2-8], xm6
    vextracti128 [r7+r1*2-8], m6, 1
    movu     [r4+r5-8], xm7
    vextracti128 [r7+r5-8], m7, 1
    RET

;-----------------------------------------------------------------------------
; void deblock_luma_mb( uint16_t *pix, intptr_t stride, uint8_t bs[2][8][4],
;                       x264_deblock_edge_t e[3], int edges )
; All luma edges of one macroblock: vertical edges left to right on a transposed
; copy of the block, then horizontal edges top to bottom.
; e[0] left edge, e[1] top edge, e[2] inner edges; edges bit dir*4+edge.
;-----------------------------------------------------------------------------
; %1-%6: p2 p1 p0 q0 q1 q2 addresses; m12=alpha, m13=beta, xm14=tc0
%macro LUMA_MB_EDGE16 6
    movu        m8, [%1]
    movu        m0, [%2]
    movu        m1, [%3]
    movu        m2, [%4]
    movu        m3, [%5]
    movu        m9, [%6]
    DEBLOCK_LUMA_INTER_SSE2 2
    movu      [%2], m0
    movu      [%3], m1
    movu      [%4], m2
    movu      [%5], m3
    SWAP         3, 9
    SWAP         0, 8
%endmacro

; in: m0-m7 = rows 0-7 | rows 8-15 of 8 words
; out: m0,m4,m2,m6,m1,m5,m3,m7 = columns 0-7 of 16 words
%macro TRANSPOSE8x8W_LANES 0
    SBUTTERFLY wd, 0, 1, 8
    SBUTTERFLY wd, 2, 3, 8
    SBUTTERFLY wd, 4, 5, 8
    SBUTTERFLY wd, 6, 7, 8
    SBUTTERFLY dq, 0, 2, 8
    SBUTTERFLY dq, 1, 3, 8
    SBUTTERFLY dq, 4, 6, 8
    SBUTTERFLY dq, 5, 7, 8
    SBUTTERFLY qdq, 0, 4, 8
    SBUTTERFLY qdq, 2, 6, 8
    SBUTTERFLY qdq, 1, 5, 8
    SBUTTERFLY qdq, 3, 7, 8
%endmacro

; %1-%8: destinations of rows 0-7 (or columns), %9-%16: rows 8-15
%macro STORE_8x8W_LANES 16
    movu        %1, xm0
    vextracti128 %9, m0, 1
    movu        %2, xm4
    vextracti128 %10, m4, 1
    movu        %3, xm2
    vextracti128 %11, m2, 1
    movu        %4, xm6
    vextracti128 %12, m6, 1
    movu        %5, xm1
    vextracti128 %13, m1, 1
    movu        %6, xm5
    vextracti128 %14, m5, 1
    movu        %7, xm3
    vextracti128 %15, m3, 1
    movu        %8, xm7
    vextracti128 %16, m7, 1
%endmacro

; %1: first column
%macro STORE_COLS16 1
    mova [COL16(%1+0)], m0
    mova [COL16(%1+1)], m4
    mova [COL16(%1+2)], m2
    mova [COL16(%1+3)], m6
    mova [COL16(%1+4)], m1
    mova [COL16(%1+5)], m5
    mova [COL16(%1+6)], m3
    mova [COL16(%1+7)], m7
%endmacro

; %1: first column
%macro LOAD_COLS16 1
    mova         m0, [COL16(%1+0)]
    mova         m1, [COL16(%1+1)]
    mova         m2, [COL16(%1+2)]
    mova         m3, [COL16(%1+3)]
    mova         m4, [COL16(%1+4)]
    mova         m5, [COL16(%1+5)]
    mova         m6, [COL16(%1+6)]
    mova         m7, [COL16(%1+7)]
%endmacro

%define COL16(x) rsp+((x)+4)*32

%macro DEBLOCK_LUMA_MB 0
cglobal deblock_luma_mb, 5,13,16, 0-20*32
    ; stack: columns -4..15
    add         r1, r1
    lea         r5, [r1*3]
    lea         r7, [r0+r1*4]
    lea         r6, [r0+r1*8]
    lea         r8, [r7+r1*8]
%if cpuflag(avx512)
    movu        xm0, [r2]
    vinserti128  m0, m0, [r2+32], 1
    vptestmd     k1, m0, m0
    kmovb       r9d, k1
%else
    movu        xm0, [r2]
    movu        xm1, [r2+32]
    pxor        xm2, xm2
    pcmpeqd     xm0, xm2
    pcmpeqd     xm1, xm2
    movmskps    r9d, xm0
    movmskps   r10d, xm1
    shl        r10d, 4
    or          r9d, r10d
    not         r9d
%endif
    and         r4d, r9d          ; drop edges with bS 0
    test        r4d, 15
    jz .horizontal

    ; only the 8-column groups the active edges touch
    test        r4d, 7
    jz .vload8
    LOAD_ROWS_LANES ROWS16(r0, r7, r6, r8, r1, r5)
    TRANSPOSE8x8W_LANES
    STORE_COLS16 0
.vload8:
    test        r4d, 12
    jz .vloadl
    LOAD_ROWS_LANES ROWS16(r0+16, r7+16, r6+16, r8+16, r1, r5)
    TRANSPOSE8x8W_LANES
    STORE_COLS16 8
.vloadl:
    test        r4d, 1
    jz .vedges
    LOAD_ROWS_LANES ROWS16(r0-16, r7-16, r6-16, r8-16, r1, r5)
    punpckhwd    m1, m0, m1
    punpckhwd    m3, m2, m3
    punpckhwd    m5, m4, m5
    punpckhwd    m7, m6, m7
    punpckldq    m0, m1, m3
    punpckhdq    m1, m3
    punpckldq    m4, m5, m7
    punpckhdq    m5, m7
    punpcklqdq   m2, m0, m4
    punpckhqdq   m0, m4
    punpcklqdq   m3, m1, m5
    punpckhqdq   m1, m5
    mova [COL16(-4)], m2
    mova [COL16(-3)], m0
    mova [COL16(-2)], m3
    mova [COL16(-1)], m1

.vedges:
    mov         r9d, r4d
    and         r9d, 15
    xor        r10d, r10d         ; bs offset
    xor        r11d, r11d         ; class*8
    lea         r12, [COL16(-3)]
.vloop:
    test        r9d, 1
    jz .vnext
    movd       xm14, [r2+r10]
    movd       xm15, [r3+r11]
    pshufb     xm14, xm15, xm14
    vpbroadcastw m12, [r3+r11+4]
    vpbroadcastw m13, [r3+r11+6]
    LUMA_MB_EDGE16 r12, r12+32, r12+64, r12+96, r12+128, r12+160
.vnext:
    mov        r11d, 16
    add        r10d, 4
    add         r12, 128
    shr         r9d, 1
    jnz .vloop

    test        r4d, 1
    jz .vstore
    mova         m0, [COL16(-4)]
    mova         m2, [COL16(-2)]
    punpckhwd    m1, m0, [COL16(-3)]
    punpcklwd    m0, [COL16(-3)]
    punpckhwd    m3, m2, [COL16(-1)]
    punpcklwd    m2, [COL16(-1)]
    punpckhdq    m4, m0, m2       ; rows 2,3 | 10,11
    punpckldq    m0, m2           ; rows 0,1 | 8,9
    punpckhdq    m5, m1, m3       ; rows 6,7 | 14,15
    punpckldq    m1, m3           ; rows 4,5 | 12,13
    movq        [r0-8], xm0
    movhps      [r0+r1-8], xm0
    movq        [r0+r1*2-8], xm4
    movhps      [r0+r5-8], xm4
    movq        [r7-8], xm1
    movhps      [r7+r1-8], xm1
    movq        [r7+r1*2-8], xm5
    movhps      [r7+r5-8], xm5
    vextracti128 xm0, m0, 1
    vextracti128 xm4, m4, 1
    vextracti128 xm1, m1, 1
    vextracti128 xm5, m5, 1
    movq        [r6-8], xm0
    movhps      [r6+r1-8], xm0
    movq        [r6+r1*2-8], xm4
    movhps      [r6+r5-8], xm4
    movq        [r8-8], xm1
    movhps      [r8+r1-8], xm1
    movq        [r8+r1*2-8], xm5
    movhps      [r8+r5-8], xm5
.vstore:
    test        r4d, 7
    jz .vstore8
    LOAD_COLS16 0
    TRANSPOSE8x8W_LANES
    STORE_8x8W_LANES ROWS16(r0, r7, r6, r8, r1, r5)
.vstore8:
    test        r4d, 12
    jz .horizontal
    LOAD_COLS16 8
    TRANSPOSE8x8W_LANES
    STORE_8x8W_LANES ROWS16(r0+16, r7+16, r6+16, r8+16, r1, r5)

.horizontal:
    mov         r9d, r4d
    shr         r9d, 4
    jz .end
    mov        r10d, 32
    mov        r11d, 8
    sub         r0, r5            ; row -3
.hloop:
    test        r9d, 1
    jz .hnext
    movd       xm14, [r2+r10]
    movd       xm15, [r3+r11]
    pshufb     xm14, xm15, xm14
    vpbroadcastw m12, [r3+r11+4]
    vpbroadcastw m13, [r3+r11+6]
    lea         r12, [r0+r5]
    LUMA_MB_EDGE16 r0, r0+r1, r0+r1*2, r12, r12+r1, r12+r1*2
.hnext:
    mov        r11d, 16
    add        r10d, 4
    lea         r0, [r0+r1*4]
    shr         r9d, 1
    jnz .hloop
.end:
    RET
%endmacro

INIT_YMM avx2
DEBLOCK_LUMA_MB
INIT_YMM avx512icl
DEBLOCK_LUMA_MB
%endif

%macro SWAPMOVA 2
%ifid %1
    SWAP %1, %2
%else
    mova %1, %2
%endif
%endmacro

; in: t0-t2: tmp registers
;     %1=p0 %2=p1 %3=p2 %4=p3 %5=q0 %6=q1 %7=mask0
;     %8=mask1p %9=2 %10=p0' %11=p1' %12=p2'
%macro LUMA_INTRA_P012 12 ; p0..p3 in memory
%if ARCH_X86_64
    paddw     t0, %3, %2
    mova      t2, %4
    paddw     t2, %3
%else
    mova      t0, %3
    mova      t2, %4
    paddw     t0, %2
    paddw     t2, %3
%endif
    paddw     t0, %1
    paddw     t2, t2
    paddw     t0, %5
    paddw     t2, %9
    paddw     t0, %9    ; (p2 + p1 + p0 + q0 + 2)
    paddw     t2, t0    ; (2*p3 + 3*p2 + p1 + p0 + q0 + 4)

    psrlw     t2, 3
    psrlw     t1, t0, 2
    psubw     t2, %3
    psubw     t1, %2
    pand      t2, %8
    pand      t1, %8
    paddw     t2, %3
    paddw     t1, %2
    SWAPMOVA %11, t1

    psubw     t1, t0, %3
    paddw     t0, t0
    psubw     t1, %5
    psubw     t0, %3
    paddw     t1, %6
    paddw     t1, %2
    paddw     t0, %6
    psrlw     t1, 2     ; (2*p1 + p0 + q1 + 2)/4
    psrlw     t0, 3     ; (p2 + 2*p1 + 2*p0 + 2*q0 + q1 + 4)>>3

    pxor      t0, t1
    pxor      t1, %1
    pand      t0, %8
    pand      t1, %7
    pxor      t0, t1
    pxor      t0, %1
    SWAPMOVA %10, t0
    SWAPMOVA %12, t2
%endmacro

%macro LUMA_INTRA_INIT 1
    %define t0 m4
    %define t1 m5
    %define t2 m6
    %define t3 m7
    %assign i 4
%rep %1
    CAT_XDEFINE t, i, [rsp+mmsize*(i-4)]
    %assign i i+1
%endrep
    add     r1, r1
%endmacro

; in: %1-%3=tmp, %4=p2, %5=q2
%macro LUMA_INTRA_INTER 5
    LOAD_AB t0, t1, r2d, r3d
    mova    %1, t0
    LOAD_MASK m0, m1, m2, m3, %1, t1, t0, t2, t3
%if ARCH_X86_64
    mova    %2, t0        ; mask0
    psrlw   t3, %1, 2
%else
    mova    t3, %1
    mova    %2, t0        ; mask0
    psrlw   t3, 2
%endif
    paddw   t3, [pw_2]    ; alpha/4+2
    DIFF_LT m1, m2, t3, t2, t0 ; t2 = |p0-q0| < alpha/4+2
    pand    t2, %2
    mova    t3, %5        ; q2
    mova    %1, t2        ; mask1
    DIFF_LT t3, m2, t1, t2, t0 ; t2 = |q2-q0| < beta
    pand    t2, %1
    mova    t3, %4        ; p2
    mova    %3, t2        ; mask1q
    DIFF_LT t3, m1, t1, t2, t0 ; t2 = |p2-p0| < beta
    pand    t2, %1
    mova    %1, t2        ; mask1p
%endmacro

%macro LUMA_H_INTRA_LOAD 0
%if mmsize == 8
    movu    t0, [r0-8]
    movu    t1, [r0+r1-8]
    movu    m0, [r0+r1*2-8]
    movu    m1, [r0+r4-8]
    TRANSPOSE4x4W 4, 5, 0, 1, 2
    mova    t4, t0        ; p3
    mova    t5, t1        ; p2

    movu    m2, [r0]
    movu    m3, [r0+r1]
    movu    t0, [r0+r1*2]
    movu    t1, [r0+r4]
    TRANSPOSE4x4W 2, 3, 4, 5, 6
    mova    t6, t0        ; q2
    mova    t7, t1        ; q3
%else
    movu    t0, [r0-8]
    movu    t1, [r0+r1-8]
    movu    m0, [r0+r1*2-8]
    movu    m1, [r0+r5-8]
    movu    m2, [r4-8]
    movu    m3, [r4+r1-8]
    movu    t2, [r4+r1*2-8]
    movu    t3, [r4+r5-8]
    TRANSPOSE8x8W 4, 5, 0, 1, 2, 3, 6, 7, t4, t5
    mova    t4, t0        ; p3
    mova    t5, t1        ; p2
    mova    t6, t2        ; q2
    mova    t7, t3        ; q3
%endif
%endmacro

; in: %1=q3 %2=q2' %3=q1' %4=q0' %5=p0' %6=p1' %7=p2' %8=p3 %9=tmp
%macro LUMA_H_INTRA_STORE 9
%if mmsize == 8
    TRANSPOSE4x4W %1, %2, %3, %4, %9
    movq       [r0-8], m%1
    movq       [r0+r1-8], m%2
    movq       [r0+r1*2-8], m%3
    movq       [r0+r4-8], m%4
    movq       m%1, %8
    TRANSPOSE4x4W %5, %6, %7, %1, %9
    movq       [r0], m%5
    movq       [r0+r1], m%6
    movq       [r0+r1*2], m%7
    movq       [r0+r4], m%1
%else
    TRANSPOSE2x4x4W %1, %2, %3, %4, %9
    movq       [r0-8], m%1
    movq       [r0+r1-8], m%2
    movq       [r0+r1*2-8], m%3
    movq       [r0+r5-8], m%4
    movhps     [r4-8], m%1
    movhps     [r4+r1-8], m%2
    movhps     [r4+r1*2-8], m%3
    movhps     [r4+r5-8], m%4
%ifnum %8
    SWAP       %1, %8
%else
    mova       m%1, %8
%endif
    TRANSPOSE2x4x4W %5, %6, %7, %1, %9
    movq       [r0], m%5
    movq       [r0+r1], m%6
    movq       [r0+r1*2], m%7
    movq       [r0+r5], m%1
    movhps     [r4], m%5
    movhps     [r4+r1], m%6
    movhps     [r4+r1*2], m%7
    movhps     [r4+r5], m%1
%endif
%endmacro

; in: r0=pix, r1=stride, r4=pix+4*stride, r5=3*stride, m0=pw_2
%macro DEBLOCK_H_LUMA_INTRA_8ROWS 0
    movu    q3, [r0-8]
    movu    q2, [r0+r1-8]
    movu    q1, [r0+r1*2-8]
    movu    q0, [r0+r5-8]
    movu    p0, [r4-8]
    movu    p1, [r4+r1-8]
    movu    p2, [r4+r1*2-8]
    movu    p3, [r4+r5-8]
    TRANSPOSE8x8W 5, 8, 9, 10, 11, 12, 13, 4, 1

    LOAD_AB m1, m2, r2d, r3d
    LOAD_MASK q1, q0, p0, p1, m1, m2, m3, t0, t1
    psrlw   m1, 2
    paddw   m1, m0 ; alpha/4+2
    DIFF_LT p0, q0, m1, m6, t0 ; m6 = |p0-q0| < alpha/4+2
    DIFF_LT q2, q0, m2, t1, t0 ; t1 = |q2-q0| < beta
    DIFF_LT p0, p2, m2, m7, t0 ; m7 = |p2-p0| < beta
    pand    m6, m3
    pand    m7, m6
    pand    m6, t1

    mova spill, q3
    LUMA_INTRA_P012 q0, q1, q2, q3, p0, p1, m3, m6, m0, m5, m1, q2
    LUMA_INTRA_P012 p0, p1, p2, p3, q0, q1, m3, m7, m0, p0, m6, p2
    mova    m7, spill

    LUMA_H_INTRA_STORE 7, 8, 1, 5, 11, 6, 13, 4, 14
%endmacro

%if ARCH_X86_64
;-----------------------------------------------------------------------------
; void deblock_v_luma_intra( uint16_t *pix, intptr_t stride, int alpha, int beta )
;-----------------------------------------------------------------------------
%macro DEBLOCK_LUMA_INTRA_64 0
cglobal deblock_v_luma_intra, 4,7,16
    %define t0 m1
    %define t1 m2
    %define t2 m4
    %define p2 m8
    %define p1 m9
    %define p0 m10
    %define q0 m11
    %define q1 m12
    %define q2 m13
    %define aa m5
    %define bb m14
    add     r1, r1
    lea     r4, [r1*4]
    lea     r5, [r1*3] ; 3*stride
    neg     r4
    add     r4, r0     ; pix-4*stride
    mov     r6, 2
    mova    m0, [pw_2]
    LOAD_AB aa, bb, r2d, r3d
.loop:
    mova    p2, [r4+r1]
    mova    p1, [r4+2*r1]
    mova    p0, [r4+r5]
    mova    q0, [r0]
    mova    q1, [r0+r1]
    mova    q2, [r0+2*r1]

    LOAD_MASK p1, p0, q0, q1, aa, bb, m3, t0, t1
    mova    t2, aa
    psrlw   t2, 2
    paddw   t2, m0 ; alpha/4+2
    DIFF_LT p0, q0, t2, m6, t0 ; m6 = |p0-q0| < alpha/4+2
    DIFF_LT p2, p0, bb, t1, t0 ; m7 = |p2-p0| < beta
    DIFF_LT q2, q0, bb, m7, t0 ; t1 = |q2-q0| < beta
    pand    m6, m3
    pand    m7, m6
    pand    m6, t1
    LUMA_INTRA_P012 p0, p1, p2, [r4], q0, q1, m3, m6, m0, [r4+r5], [r4+2*r1], [r4+r1]
    LUMA_INTRA_P012 q0, q1, q2, [r0+r5], p0, p1, m3, m7, m0, [r0], [r0+r1], [r0+2*r1]
    add     r0, mmsize
    add     r4, mmsize
    dec     r6
    jg .loop
    RET

;-----------------------------------------------------------------------------
; void deblock_h_luma_intra( uint16_t *pix, intptr_t stride, int alpha, int beta )
;-----------------------------------------------------------------------------
cglobal deblock_h_luma_intra, 4,7,16
    %define t0 m15
    %define t1 m14
    %define t2 m2
    %define q3 m5
    %define q2 m8
    %define q1 m9
    %define q0 m10
    %define p0 m11
    %define p1 m12
    %define p2 m13
    %define p3 m4
    %define spill [rsp]
    %assign pad 24-(stack_offset&15)
    SUB     rsp, pad
    add     r1, r1
    lea     r4, [r1*4]
    lea     r5, [r1*3] ; 3*stride
    add     r4, r0     ; pix+4*stride
    mov     r6, 2
    mova    m0, [pw_2]
.loop:
    DEBLOCK_H_LUMA_INTRA_8ROWS
    lea     r0, [r0+r1*8]
    lea     r4, [r4+r1*8]
    dec     r6
    jg .loop
    ADD    rsp, pad
    RET

;-----------------------------------------------------------------------------
; void deblock_h_luma_intra_mbaff( uint16_t *pix, intptr_t stride, int alpha, int beta )
;-----------------------------------------------------------------------------
cglobal deblock_h_luma_intra_mbaff, 4,6,16
    %assign pad 24-(stack_offset&15)
    SUB     rsp, pad
    add     r1, r1
    lea     r4, [r1*4]
    lea     r5, [r1*3] ; 3*stride
    add     r4, r0     ; pix+4*stride
    mova    m0, [pw_2]
    DEBLOCK_H_LUMA_INTRA_8ROWS
    ADD    rsp, pad
    RET
%endmacro

INIT_XMM sse2
DEBLOCK_LUMA_INTRA_64
INIT_XMM avx
DEBLOCK_LUMA_INTRA_64

%endif

%macro DEBLOCK_LUMA_INTRA 0
;-----------------------------------------------------------------------------
; void deblock_v_luma_intra( uint16_t *pix, intptr_t stride, int alpha, int beta )
;-----------------------------------------------------------------------------
cglobal deblock_v_luma_intra, 4,7,8,0-3*mmsize
    LUMA_INTRA_INIT 3
    lea     r4, [r1*4]
    lea     r5, [r1*3]
    neg     r4
    add     r4, r0
    mov     r6, 32/mmsize
.loop:
    mova    m0, [r4+r1*2] ; p1
    mova    m1, [r4+r5]   ; p0
    mova    m2, [r0]      ; q0
    mova    m3, [r0+r1]   ; q1
    LUMA_INTRA_INTER t4, t5, t6, [r4+r1], [r0+r1*2]
    LUMA_INTRA_P012 m1, m0, t3, [r4], m2, m3, t5, t4, [pw_2], [r4+r5], [r4+2*r1], [r4+r1]
    mova    t3, [r0+r1*2] ; q2
    LUMA_INTRA_P012 m2, m3, t3, [r0+r5], m1, m0, t5, t6, [pw_2], [r0], [r0+r1], [r0+2*r1]
    add     r0, mmsize
    add     r4, mmsize
    dec     r6
    jg .loop
    RET

;-----------------------------------------------------------------------------
; void deblock_h_luma_intra( uint16_t *pix, intptr_t stride, int alpha, int beta )
;-----------------------------------------------------------------------------
cglobal deblock_h_luma_intra, 4,7,8,0-8*mmsize
    LUMA_INTRA_INIT 8
%if mmsize == 8
    lea     r4, [r1*3]
    mov     r5, 32/mmsize
%else
    lea     r4, [r1*4]
    lea     r5, [r1*3] ; 3*stride
    add     r4, r0     ; pix+4*stride
    mov     r6, 32/mmsize
%endif
.loop:
    LUMA_H_INTRA_LOAD
    LUMA_INTRA_INTER t8, t9, t10, t5, t6

    LUMA_INTRA_P012 m1, m0, t3, t4, m2, m3, t9, t8, [pw_2], t8, t5, t11
    mova    t3, t6     ; q2
    LUMA_INTRA_P012 m2, m3, t3, t7, m1, m0, t9, t10, [pw_2], m4, t6, m5

    mova    m2, t4
    mova    m0, t11
    mova    m1, t5
    mova    m3, t8
    mova    m6, t6

    LUMA_H_INTRA_STORE 2, 0, 1, 3, 4, 6, 5, t7, 7

    lea     r0, [r0+r1*(mmsize/2)]
%if mmsize == 8
    dec     r5
%else
    lea     r4, [r4+r1*(mmsize/2)]
    dec     r6
%endif
    jg .loop
    RET
%endmacro

%if ARCH_X86_64 == 0
INIT_MMX mmx2
DEBLOCK_LUMA
DEBLOCK_LUMA_INTRA
INIT_XMM sse2
DEBLOCK_LUMA
DEBLOCK_LUMA_INTRA
INIT_XMM avx
DEBLOCK_LUMA
DEBLOCK_LUMA_INTRA
%endif
%endif ; HIGH_BIT_DEPTH

%if HIGH_BIT_DEPTH == 0
; expands to [base],...,[base+7*stride]
%define PASS8ROWS(base, base3, stride, stride3) \
    [base], [base+stride], [base+stride*2], [base3], \
    [base3+stride], [base3+stride*2], [base3+stride3], [base3+stride*4]

%define PASS8ROWS(base, base3, stride, stride3, offset) \
    PASS8ROWS(base+offset, base3+offset, stride, stride3)

; in: 4 rows of 8 bytes in m0..m3
; out: 8 rows of 4 bytes in %1..%8
%macro TRANSPOSE8x4B_STORE 8
    punpckhdq  m4, m0, m0
    punpckhdq  m5, m1, m1
    punpckhdq  m6, m2, m2

    punpcklbw  m0, m1
    punpcklbw  m2, m3
    punpcklwd  m1, m0, m2
    punpckhwd  m0, m2
    movd       %1, m1
    punpckhdq  m1, m1
    movd       %2, m1
    movd       %3, m0
    punpckhdq  m0, m0
    movd       %4, m0

    punpckhdq  m3, m3
    punpcklbw  m4, m5
    punpcklbw  m6, m3
    punpcklwd  m5, m4, m6
    punpckhwd  m4, m6
    movd       %5, m5
    punpckhdq  m5, m5
    movd       %6, m5
    movd       %7, m4
    punpckhdq  m4, m4
    movd       %8, m4
%endmacro

; in: 8 rows of 4 bytes in %9..%10
; out: 8 rows of 4 bytes in %1..%8
%macro STORE_8x4B 10
    movd   %1, %9
    pextrd %2, %9, 1
    pextrd %3, %9, 2
    pextrd %4, %9, 3
    movd   %5, %10
    pextrd %6, %10, 1
    pextrd %7, %10, 2
    pextrd %8, %10, 3
%endmacro

; in: 4 rows of 4 words in %1..%4
; out: 4 rows of 4 word in m0..m3
; clobbers: m4
%macro TRANSPOSE4x4W_LOAD 4-8
%if mmsize==8
    SWAP  1, 4, 2, 3
    movq  m0, %1
    movq  m1, %2
    movq  m2, %3
    movq  m3, %4
    TRANSPOSE4x4W 0, 1, 2, 3, 4
%else
    movq       m0, %1
    movq       m2, %2
    movq       m1, %3
    movq       m3, %4
    punpcklwd  m0, m2
    punpcklwd  m1, m3
    mova       m2, m0
    punpckldq  m0, m1
    punpckhdq  m2, m1
    movhlps    m1, m0
    movhlps    m3, m2
%endif
%endmacro

; in: 2 rows of 4 words in m1..m2
; out: 4 rows of 2 words in %1..%4
; clobbers: m0, m1
%macro TRANSPOSE4x2W_STORE 4-8
%if mmsize==8
    punpckhwd  m0, m1, m2
    punpcklwd  m1, m2
%else
    punpcklwd  m1, m2
    movhlps    m0, m1
%endif
    movd       %3, m0
    movd       %1, m1
    psrlq      m1, 32
    psrlq      m0, 32
    movd       %2, m1
    movd       %4, m0
%endmacro

; in: 4/8 rows of 4 words in %1..%8
; out: 4 rows of 4/8 word in m0..m3
; clobbers: m4, m5, m6, m7
%macro TRANSPOSE4x8W_LOAD 8
%if mmsize==8
    TRANSPOSE4x4W_LOAD %1, %2, %3, %4
%else
    movq       m0, %1
    movq       m2, %2
    movq       m1, %3
    movq       m3, %4
    punpcklwd  m0, m2
    punpcklwd  m1, m3
    mova       m2, m0
    punpckldq  m0, m1
    punpckhdq  m2, m1

    movq       m4, %5
    movq       m6, %6
    movq       m5, %7
    movq       m7, %8
    punpcklwd  m4, m6
    punpcklwd  m5, m7
    mova       m6, m4
    punpckldq  m4, m5
    punpckhdq  m6, m5

    punpckhqdq m1, m0, m4
    punpckhqdq m3, m2, m6
    punpcklqdq m0, m4
    punpcklqdq m2, m6
%endif
%endmacro

; in: 2 rows of 4/8 words in m1..m2
; out: 4/8 rows of 2 words in %1..%8
; clobbers: m0, m1
%macro TRANSPOSE8x2W_STORE 8
%if mmsize==8
    TRANSPOSE4x2W_STORE %1, %2, %3, %4
%else
    punpckhwd  m0, m1, m2
    punpcklwd  m1, m2
    movd       %5, m0
    movd       %1, m1
    psrldq     m1, 4
    psrldq     m0, 4
    movd       %2, m1
    movd       %6, m0
    psrldq     m1, 4
    psrldq     m0, 4
    movd       %3, m1
    movd       %7, m0
    psrldq     m1, 4
    psrldq     m0, 4
    movd       %4, m1
    movd       %8, m0
%endif
%endmacro

%macro SBUTTERFLY3 4
    punpckh%1  %4, %2, %3
    punpckl%1  %2, %3
%endmacro

; in: 8 rows of 8 (only the middle 6 pels are used) in %1..%8
; out: 6 rows of 8 in [%9+0*16] .. [%9+5*16]
%macro TRANSPOSE6x8_MEM 9
    RESET_MM_PERMUTATION
%if cpuflag(avx)
    ; input:
    ; _ABCDEF_
    ; _GHIJKL_
    ; _MNOPQR_
    ; _STUVWX_
    ; _YZabcd_
    ; _efghij_
    ; _klmnop_
    ; _qrstuv_

    movh      m0, %1
    movh      m2, %2
    movh      m1, %3
    movh      m3, %4
    punpcklbw m0, m2       ; __ AG BH CI DJ EK FL __
    punpcklbw m1, m3       ; __ MS NT OU PV QW RX __
    movh      m2, %5
    movh      m3, %6
    punpcklbw m2, m3       ; __ Ye Zf ag bh ci dj __
    movh      m3, %7
    movh      m4, %8
    punpcklbw m3, m4       ; __ kq lr ms nt ou pv __

    SBUTTERFLY wd, 0, 1, 4 ; __ __ AG MS BH NT CI OU
                           ; DJ PV EK QW FL RX __ __
    SBUTTERFLY wd, 2, 3, 4 ; __ __ Ye kq Zf lr ag ms
                           ; bh nt ci ou dj pv __ __
    SBUTTERFLY dq, 0, 2, 4 ; __ __ __ __ AG MS Ye kq
                           ; BH NT Zf lr CI FL OU RX
    SBUTTERFLY dq, 1, 3, 4 ; DJ PV bh nt EK QW Zf lr
                           ; FL RX dj pv __ __ __ __
    movhps [%9+0x00], m0
    movh   [%9+0x10], m2
    movhps [%9+0x20], m2
    movh   [%9+0x30], m1
    movhps [%9+0x40], m1
    movh   [%9+0x50], m3
%else
    movq  m0, %1
    movq  m1, %2
    movq  m2, %3
    movq  m3, %4
    movq  m4, %5
    movq  m5, %6
    movq  m6, %7
    SBUTTERFLY bw, 0, 1, 7
    SBUTTERFLY bw, 2, 3, 7
    SBUTTERFLY bw, 4, 5, 7
    movq  [%9+0x10], m3
    SBUTTERFLY3 bw, m6, %8, m7
    SBUTTERFLY wd, 0, 2, 3
    SBUTTERFLY wd, 4, 6, 3
    punpckhdq m0, m4
    movq  [%9+0x00], m0
    SBUTTERFLY3 wd, m1, [%9+0x10], m3
    SBUTTERFLY wd, 5, 7, 0
    SBUTTERFLY dq, 1, 5, 0
    SBUTTERFLY dq, 2, 6, 0
    punpckldq m3, m7
    movq  [%9+0x10], m2
    movq  [%9+0x20], m6
    movq  [%9+0x30], m1
    movq  [%9+0x40], m5
    movq  [%9+0x50], m3
%endif
    RESET_MM_PERMUTATION
%endmacro


; in: 8 rows of 8 in %1..%8
; out: 8 rows of 8 in %9..%16
%macro TRANSPOSE8x8_MEM 16
    RESET_MM_PERMUTATION
%if cpuflag(avx)
    movh      m0, %1
    movh      m4, %2
    movh      m1, %3
    movh      m5, %4
    movh      m2, %5
    movh      m3, %7
    punpcklbw m0, m4
    punpcklbw m1, m5
    movh      m4, %6
    movh      m5, %8
    punpcklbw m2, m4
    punpcklbw m3, m5
    SBUTTERFLY wd, 0, 1, 4
    SBUTTERFLY wd, 2, 3, 4
    SBUTTERFLY dq, 0, 2, 4
    SBUTTERFLY dq, 1, 3, 4
    movh    %9, m0
    movhps %10, m0
    movh   %11, m2
    movhps %12, m2
    movh   %13, m1
    movhps %14, m1
    movh   %15, m3
    movhps %16, m3
%else
    movq  m0, %1
    movq  m1, %2
    movq  m2, %3
    movq  m3, %4
    movq  m4, %5
    movq  m5, %6
    movq  m6, %7
    SBUTTERFLY bw, 0, 1, 7
    SBUTTERFLY bw, 2, 3, 7
    SBUTTERFLY bw, 4, 5, 7
    SBUTTERFLY3 bw, m6, %8, m7
    movq  %9,  m5
    SBUTTERFLY wd, 0, 2, 5
    SBUTTERFLY wd, 4, 6, 5
    SBUTTERFLY wd, 1, 3, 5
    movq  %11, m6
    movq  m6,  %9
    SBUTTERFLY wd, 6, 7, 5
    SBUTTERFLY dq, 0, 4, 5
    SBUTTERFLY dq, 1, 6, 5
    movq  %9,  m0
    movq  %10, m4
    movq  %13, m1
    movq  %14, m6
    SBUTTERFLY3 dq, m2, %11, m0
    SBUTTERFLY dq, 3, 7, 4
    movq  %11, m2
    movq  %12, m0
    movq  %15, m3
    movq  %16, m7
%endif
    RESET_MM_PERMUTATION
%endmacro

; out: %4 = |%1-%2|>%3
; clobbers: %5
%macro DIFF_GT 5
%if avx_enabled == 0
    mova    %5, %2
    mova    %4, %1
    psubusb %5, %1
    psubusb %4, %2
%else
    psubusb %5, %2, %1
    psubusb %4, %1, %2
%endif
    por     %4, %5
    psubusb %4, %3
%endmacro

; out: %4 = |%1-%2|>%3
; clobbers: %5
%macro DIFF_GT2 5-6
%if %0<6
    psubusb %4, %1, %2
    psubusb %5, %2, %1
%else
    mova    %4, %1
    mova    %5, %2
    psubusb %4, %2
    psubusb %5, %1
%endif
    psubusb %5, %3
    psubusb %4, %3
    pcmpeqb %4, %5
%endmacro

; in: m0=p1 m1=p0 m2=q0 m3=q1 %1=alpha %2=beta
; out: m5=beta-1, m7=mask, %3=alpha-1
; clobbers: m4,m6
%macro LOAD_MASK 2-3
%if cpuflag(ssse3)
    movd     m4, %1
    movd     m5, %2
    pxor     m6, m6
    pshufb   m4, m6
    pshufb   m5, m6
%else
    movd     m4, %1
    movd     m5, %2
    punpcklbw m4, m4
    punpcklbw m5, m5
    SPLATW   m4, m4
    SPLATW   m5, m5
%endif
    mova     m6, [pb_1]
    psubusb  m4, m6              ; alpha - 1
    psubusb  m5, m6              ; beta - 1
%if %0>2
    mova     %3, m4
%endif
    DIFF_GT  m1, m2, m4, m7, m6 ; |p0-q0| > alpha-1
    DIFF_GT  m0, m1, m5, m4, m6 ; |p1-p0| > beta-1
    por      m7, m4
    DIFF_GT  m3, m2, m5, m4, m6 ; |q1-q0| > beta-1
    por      m7, m4
    pxor     m6, m6
    pcmpeqb  m7, m6
%endmacro

; in: m0=p1 m1=p0 m2=q0 m3=q1 m7=(tc&mask)
; out: m1=p0' m2=q0'
; clobbers: m0,3-6
%macro DEBLOCK_P0_Q0 0
    pxor    m5, m1, m2   ; p0^q0
    pand    m5, [pb_1]   ; (p0^q0)&1
    pcmpeqb m4, m4
    pxor    m3, m4
    pavgb   m3, m0       ; (p1 - q1 + 256)>>1
    pavgb   m3, [pb_3]   ; (((p1 - q1 + 256)>>1)+4)>>1 = 64+2+(p1-q1)>>2
    pxor    m4, m1
    pavgb   m4, m2       ; (q0 - p0 + 256)>>1
    pavgb   m3, m5
    paddusb m3, m4       ; d+128+33
    mova    m6, [pb_a1]
    psubusb m6, m3
    psubusb m3, [pb_a1]
    pminub  m6, m7
    pminub  m3, m7
    psubusb m1, m6
    psubusb m2, m3
    paddusb m1, m3
    paddusb m2, m6
%endmacro

; in: m1=p0 m2=q0
;     %1=p1 %2=q2 %3=[q2] %4=[q1] %5=tc0 %6=tmp
; out: [q1] = clip( (q2+((p0+q0+1)>>1))>>1, q1-tc0, q1+tc0 )
; clobbers: q2, tmp, tc0
%macro LUMA_Q1 6
    pavgb   %6, m1, m2
    pavgb   %2, %6       ; avg(p2,avg(p0,q0))
    pxor    %6, %3
    pand    %6, [pb_1]   ; (p2^avg(p0,q0))&1
    psubusb %2, %6       ; (p2+((p0+q0+1)>>1))>>1
    psubusb %6, %1, %5
    paddusb %5, %1
    pmaxub  %2, %6
    pminub  %2, %5
    mova    %4, %2
%endmacro

%if ARCH_X86_64
;-----------------------------------------------------------------------------
; void deblock_v_luma( uint8_t *pix, intptr_t stride, int alpha, int beta, int8_t *tc0 )
;-----------------------------------------------------------------------------
%macro DEBLOCK_LUMA 0
cglobal deblock_v_luma, 5,5,10
    movd    m8, [r4] ; tc0
    lea     r4, [r1*3]
    neg     r4
    add     r4, r0     ; pix-3*stride

    mova    m0, [r4+r1]   ; p1
    mova    m1, [r4+2*r1] ; p0
    mova    m2, [r0]      ; q0
    mova    m3, [r0+r1]   ; q1
    LOAD_MASK r2d, r3d

%if cpuflag(avx)
    pshufb   m8, [pb_unpackbd1]
    pblendvb m9, m7, m6, m8
%else
    punpcklbw m8, m8
    punpcklbw m8, m8 ; tc = 4x tc0[3], 4x tc0[2], 4x tc0[1], 4x tc0[0]
    pcmpeqb m9, m9
    pcmpeqb m9, m8
    pandn   m9, m7
%endif
    pand    m8, m9

    mova    m3, [r4] ; p2
    DIFF_GT2 m1, m3, m5, m6, m7 ; |p2-p0| > beta-1
    pand    m6, m9
    psubb   m7, m8, m6 ; tc++
    pand    m6, m8
    LUMA_Q1 m0, m3, [r4], [r4+r1], m6, m4

    mova    m4, [r0+2*r1] ; q2
    DIFF_GT2 m2, m4, m5, m6, m3 ; |q2-q0| > beta-1
    pand    m6, m9
    pand    m8, m6
    psubb   m7, m6
    mova    m3, [r0+r1]
    LUMA_Q1 m3, m4, [r0+2*r1], [r0+r1], m8, m6

    DEBLOCK_P0_Q0
    mova    [r4+2*r1], m1
    mova    [r0], m2
    RET

;-----------------------------------------------------------------------------
; void deblock_h_luma( uint8_t *pix, intptr_t stride, int alpha, int beta, int8_t *tc0 )
;-----------------------------------------------------------------------------

%if cpuflag(avx)
INIT_XMM cpuname
%else
INIT_MMX cpuname
%endif
cglobal deblock_h_luma, 5,9,0,0x60+16*WIN64
    lea    r8, [r1*3]
    lea    r6, [r0-4]
    lea    r5, [r0-4+r8]
%if WIN64
    %define pix_tmp rsp+0x30 ; shadow space + r4
%else
    %define pix_tmp rsp
%endif

    ; transpose 6x16 -> tmp space
    TRANSPOSE6x8_MEM  PASS8ROWS(r6, r5, r1, r8), pix_tmp
    lea    r6, [r6+r1*8]
    lea    r5, [r5+r1*8]
    TRANSPOSE6x8_MEM  PASS8ROWS(r6, r5, r1, r8), pix_tmp+8

    ; vertical filter
    ; alpha, beta, tc0 are still in r2d, r3d, r4
    ; don't backup r6, r5, r7, r8 because deblock_v_luma_sse2 doesn't use them
    mov    r7, r1
    lea    r0, [pix_tmp+0x30]
    mov    r1d, 0x10
%if WIN64
    mov    [rsp+0x20], r4
%endif
    call   deblock_v_luma

    ; transpose 16x4 -> original space  (only the middle 4 rows were changed by the filter)
    add    r6, 2
    add    r5, 2
%if cpuflag(sse4)
    mova   m0, [pix_tmp+0x10]
    mova   m1, [pix_tmp+0x20]
    mova   m2, [pix_tmp+0x30]
    mova   m3, [pix_tmp+0x40]
    SBUTTERFLY bw, 0, 1, 4
    SBUTTERFLY bw, 2, 3, 4
    SBUTTERFLY wd, 0, 2, 4
    SBUTTERFLY wd, 1, 3, 4
    STORE_8x4B PASS8ROWS(r6, r5, r7, r8), m1, m3
    shl    r7, 3
    sub    r6, r7
    sub    r5, r7
    shr    r7, 3
    STORE_8x4B PASS8ROWS(r6, r5, r7, r8), m0, m2
%else
    movq   m0, [pix_tmp+0x18]
    movq   m1, [pix_tmp+0x28]
    movq   m2, [pix_tmp+0x38]
    movq   m3, [pix_tmp+0x48]
    TRANSPOSE8x4B_STORE  PASS8ROWS(r6, r5, r7, r8)

    shl    r7, 3
    sub    r6, r7
    sub    r5, r7
    shr    r7, 3
    movq   m0, [pix_tmp+0x10]
    movq   m1, [pix_tmp+0x20]
    movq   m2, [pix_tmp+0x30]
    movq   m3, [pix_tmp+0x40]
    TRANSPOSE8x4B_STORE  PASS8ROWS(r6, r5, r7, r8)
%endif

    RET
%endmacro

INIT_XMM sse2
DEBLOCK_LUMA
INIT_XMM avx
DEBLOCK_LUMA

;-----------------------------------------------------------------------------
; void deblock_luma_mb( uint8_t *pix, intptr_t stride, uint8_t bs[2][8][4],
;                       x264_deblock_edge_t e[3], int edges )
; All luma edges of one macroblock: vertical edges left to right on a transposed
; copy of the block, then horizontal edges top to bottom.
; e[0] left edge, e[1] top edge, e[2] inner edges; edges bit dir*4+edge.
;-----------------------------------------------------------------------------
; LUMA_Q1 on xmm
%macro LUMA_MB_Q1 6
    pavgb    %6, xm1, xm2
    pavgb    %2, %6           ; avg(p2,avg(p0,q0))
    pxor     %6, %3
    pand     %6, [pb_1]       ; (p2^avg(p0,q0))&1
    psubusb  %2, %6           ; (p2+((p0+q0+1)>>1))>>1
    psubusb  %6, %1, %5
    paddusb  %5, %1
    pmaxub   %2, %6
    pminub   %2, %5
    mova     %4, %2
%endmacro

; %1-%6: p2 p1 p0 q0 q1 q2 addresses, [%7]: alpha-1, beta-1; xm8: tc0 (<0: skip)
%macro LUMA_MB_EDGE 7
    mova     xm0, [%2]        ; p1
    mova     xm1, [%3]        ; p0
    mova     xm2, [%4]        ; q0
    mova     xm3, [%5]        ; q1
    mova     xm5, [%7+16]
    DIFF_GT  xm1, xm2, [%7], xm7, xm6 ; |p0-q0| > alpha-1
    DIFF_GT  xm0, xm1, xm5, xm4, xm6  ; |p1-p0| > beta-1
    por      xm7, xm4
    DIFF_GT  xm3, xm2, xm5, xm4, xm6  ; |q1-q0| > beta-1
    por      xm7, xm4
    pxor     xm6, xm6
    pcmpeqb  xm7, xm6
    pblendvb xm9, xm7, xm6, xm8
    pand     xm8, xm9
    mova     xm3, [%1]        ; p2
    DIFF_GT2 xm1, xm3, xm5, xm6, xm7  ; |p2-p0| > beta-1
    pand     xm6, xm9
    psubb    xm7, xm8, xm6    ; tc++
    pand     xm6, xm8
    LUMA_MB_Q1 xm0, xm3, [%1], [%2], xm6, xm4
    mova     xm4, [%6]        ; q2
    DIFF_GT2 xm2, xm4, xm5, xm6, xm3  ; |q2-q0| > beta-1
    pand     xm6, xm9
    pand     xm8, xm6
    psubb    xm7, xm6
    mova     xm3, [%5]
    LUMA_MB_Q1 xm3, xm4, [%6], [%5], xm8, xm6
    pxor     xm5, xm1, xm2    ; p0^q0
    pand     xm5, [pb_1]      ; (p0^q0)&1
    pcmpeqb  xm4, xm4
    pxor     xm3, xm4
    pavgb    xm3, xm0         ; (p1 - q1 + 256)>>1
    pavgb    xm3, [pb_3]      ; (((p1 - q1 + 256)>>1)+4)>>1 = 64+2+(p1-q1)>>2
    pxor     xm4, xm1
    pavgb    xm4, xm2         ; (q0 - p0 + 256)>>1
    pavgb    xm3, xm5
    paddusb  xm3, xm4         ; d+128+33
    mova     xm6, [pb_a1]
    psubusb  xm6, xm3
    psubusb  xm3, [pb_a1]
    pminub   xm6, xm7
    pminub   xm3, xm7
    psubusb  xm1, xm6
    psubusb  xm2, xm3
    paddusb  xm1, xm3
    paddusb  xm2, xm6
    mova     [%3], xm1
    mova     [%4], xm2
%endmacro

; in: m0-m7 = rows 0-7 | rows 8-15 of 16 bytes
; out: m0,m4,m2,m6,m1,m5,m3,m7 = columns 0|1, 2|3, ..., 14|15 of 16 bytes
%macro TRANSPOSE16x16B_LANES 0
    SBUTTERFLY bw, 0, 1, 8
    SBUTTERFLY bw, 2, 3, 8
    SBUTTERFLY bw, 4, 5, 8
    SBUTTERFLY bw, 6, 7, 8
    SBUTTERFLY wd, 0, 2, 8
    SBUTTERFLY wd, 4, 6, 8
    SBUTTERFLY wd, 1, 3, 8
    SBUTTERFLY wd, 5, 7, 8
    SBUTTERFLY dq, 0, 4, 8
    SBUTTERFLY dq, 2, 6, 8
    SBUTTERFLY dq, 1, 5, 8
    SBUTTERFLY dq, 3, 7, 8
    vpermq     m0, m0, q3120
    vpermq     m4, m4, q3120
    vpermq     m2, m2, q3120
    vpermq     m6, m6, q3120
    vpermq     m1, m1, q3120
    vpermq     m5, m5, q3120
    vpermq     m3, m3, q3120
    vpermq     m7, m7, q3120
%endmacro

; %1-%16: destinations of rows (or columns) 0-15
%macro STORE_16x16B_LANES 16
    movu        %1, xm0
    vextracti128 %2, m0, 1
    movu        %3, xm4
    vextracti128 %4, m4, 1
    movu        %5, xm2
    vextracti128 %6, m2, 1
    movu        %7, xm6
    vextracti128 %8, m6, 1
    movu        %9, xm1
    vextracti128 %10, m1, 1
    movu        %11, xm5
    vextracti128 %12, m5, 1
    movu        %13, xm3
    vextracti128 %14, m3, 1
    movu        %15, xm7
    vextracti128 %16, m7, 1
%endmacro

%define COLS8(x) [rsp+3*32+((x)+4)*16], [rsp+3*32+((x)+5)*16], [rsp+3*32+((x)+6)*16], [rsp+3*32+((x)+7)*16], \
    [rsp+3*32+((x)+8)*16], [rsp+3*32+((x)+9)*16], [rsp+3*32+((x)+10)*16], [rsp+3*32+((x)+11)*16]
%define COL(x) rsp+3*32+((x)+4)*16

INIT_YMM avx2
cglobal deblock_luma_mb, 5,13,16, 0-(3*32+20*16)
    ; stack: 3 x (alpha-1, beta-1), then columns -4..15
    mova       xm15, [pb_1]
%assign dbmb_i 0
%rep 3
    vpbroadcastb xm0, [r3+8*dbmb_i+4]
    vpbroadcastb xm1, [r3+8*dbmb_i+6]
    psubusb     xm0, xm15
    psubusb     xm1, xm15
    mova [rsp+32*dbmb_i], xm0
    mova [rsp+32*dbmb_i+16], xm1
%assign dbmb_i dbmb_i+1
%endrep
    lea         r5, [r1*3]
    lea         r7, [r0+r1*4]
    lea         r6, [r0+r1*8]
    lea         r8, [r7+r1*8]
    movu        xm0, [r2]
    movu        xm1, [r2+32]
    pxor        xm2, xm2
    pcmpeqd     xm0, xm2
    pcmpeqd     xm1, xm2
    movmskps    r9d, xm0
    movmskps   r10d, xm1
    shl        r10d, 4
    or          r9d, r10d
    not         r9d
    and         r4d, r9d          ; drop edges with bS 0
    test        r4d, 15
    jz .horizontal

    LOAD_ROWS_LANES ROWS16(r0, r7, r6, r8, r1, r5)
    TRANSPOSE16x16B_LANES
    STORE_16x16B_LANES COLS8(0), COLS8(8)
    test        r4d, 1
    jz .vedges
    LOAD_ROWS_LANES ROWS16(r0-16, r7-16, r6-16, r8-16, r1, r5)
    punpckhbw    m0, m1
    punpckhbw    m2, m3
    punpckhbw    m4, m5
    punpckhbw    m6, m7
    punpckhwd    m0, m2           ; columns -4..-1 of rows 0-3 | 8-11
    punpckhwd    m4, m6
    punpckldq    m1, m0, m4
    punpckhdq    m0, m4
    vpermq       m1, m1, q3120
    vpermq       m0, m0, q3120
    mova        [COL(-4)], xm1
    vextracti128 [COL(-3)], m1, 1
    mova        [COL(-2)], xm0
    vextracti128 [COL(-1)], m0, 1

.vedges:
    mov         r9d, r4d
    and         r9d, 15
    xor        r10d, r10d         ; bs offset
    xor        r11d, r11d         ; class*8
    lea         r12, [COL(-3)]
.vloop:
    test        r9d, 1
    jz .vnext
    movd        xm8, [r2+r10]
    movd        xm9, [r3+r11]
    pshufb      xm8, xm9, xm8
    pshufb      xm8, [pb_unpackbd1]
    LUMA_MB_EDGE r12, r12+16, r12+32, r12+48, r12+64, r12+80, rsp+r11*4
.vnext:
    mov        r11d, 16
    add        r10d, 4
    add         r12, 64
    shr         r9d, 1
    jnz .vloop

    test        r4d, 1
    jz .vstore
    mova        xm0, [COL(-4)]
    mova        xm2, [COL(-2)]
    punpckhbw   xm4, xm0, [COL(-3)]
    punpcklbw   xm0, [COL(-3)]
    punpckhbw   xm5, xm2, [COL(-1)]
    punpcklbw   xm2, [COL(-1)]
    punpckhwd   xm1, xm0, xm2
    punpcklwd   xm0, xm2
    punpckhwd   xm3, xm4, xm5
    punpcklwd   xm4, xm5
    movd        [r0-4], xm0
    pextrd      [r0+r1-4], xm0, 1
    pextrd      [r0+r1*2-4], xm0, 2
    pextrd      [r0+r5-4], xm0, 3
    movd        [r7-4], xm1
    pextrd      [r7+r1-4], xm1, 1
    pextrd      [r7+r1*2-4], xm1, 2
    pextrd      [r7+r5-4], xm1, 3
    movd        [r6-4], xm4
    pextrd      [r6+r1-4], xm4, 1
    pextrd      [r6+r1*2-4], xm4, 2
    pextrd      [r6+r5-4], xm4, 3
    movd        [r8-4], xm3
    pextrd      [r8+r1-4], xm3, 1
    pextrd      [r8+r1*2-4], xm3, 2
    pextrd      [r8+r5-4], xm3, 3
.vstore:
    LOAD_ROWS_LANES COLS8(0), COLS8(8)
    TRANSPOSE16x16B_LANES
    STORE_16x16B_LANES ROWS16(r0, r7, r6, r8, r1, r5)

.horizontal:
    mov         r9d, r4d
    shr         r9d, 4
    jz .end
    mov        r10d, 32
    mov        r11d, 8
    sub         r0, r5            ; row -3
.hloop:
    test        r9d, 1
    jz .hnext
    movd        xm8, [r2+r10]
    movd        xm9, [r3+r11]
    pshufb      xm8, xm9, xm8
    pshufb      xm8, [pb_unpackbd1]
    lea         r12, [r0+r5]
    LUMA_MB_EDGE r0, r0+r1, r0+r1*2, r12, r12+r1, r12+r1*2, rsp+r11*4
.hnext:
    mov        r11d, 16
    add        r10d, 4
    lea         r0, [r0+r1*4]
    shr         r9d, 1
    jnz .hloop
.end:
    RET

%else

%macro DEBLOCK_LUMA 2
;-----------------------------------------------------------------------------
; void deblock_v8_luma( uint8_t *pix, intptr_t stride, int alpha, int beta, int8_t *tc0 )
;-----------------------------------------------------------------------------
cglobal deblock_%1_luma, 5,5,8,2*%2
    lea     r4, [r1*3]
    neg     r4
    add     r4, r0 ; pix-3*stride

    mova    m0, [r4+r1]   ; p1
    mova    m1, [r4+2*r1] ; p0
    mova    m2, [r0]      ; q0
    mova    m3, [r0+r1]   ; q1
    LOAD_MASK r2d, r3d

    mov     r3, r4mp
    movd    m4, [r3] ; tc0
%if cpuflag(avx)
    pshufb   m4, [pb_unpackbd1]
    mova   [esp+%2], m4 ; tc
    pblendvb m4, m7, m6, m4
%else
    punpcklbw m4, m4
    punpcklbw m4, m4 ; tc = 4x tc0[3], 4x tc0[2], 4x tc0[1], 4x tc0[0]
    mova   [esp+%2], m4 ; tc
    pcmpeqb m3, m3
    pcmpgtb m4, m3
    pand    m4, m7
%endif
    mova   [esp], m4 ; mask

    mova    m3, [r4] ; p2
    DIFF_GT2 m1, m3, m5, m6, m7 ; |p2-p0| > beta-1
    pand    m6, m4
    pand    m4, [esp+%2] ; tc
    psubb   m7, m4, m6
    pand    m6, m4
    LUMA_Q1 m0, m3, [r4], [r4+r1], m6, m4

    mova    m4, [r0+2*r1] ; q2
    DIFF_GT2 m2, m4, m5, m6, m3 ; |q2-q0| > beta-1
    mova    m5, [esp] ; mask
    pand    m6, m5
    mova    m5, [esp+%2] ; tc
    pand    m5, m6
    psubb   m7, m6
    mova    m3, [r0+r1]
    LUMA_Q1 m3, m4, [r0+2*r1], [r0+r1], m5, m6

    DEBLOCK_P0_Q0
    mova    [r4+2*r1], m1
    mova    [r0], m2
    RET

;-----------------------------------------------------------------------------
; void deblock_h_luma( uint8_t *pix, intptr_t stride, int alpha, int beta, int8_t *tc0 )
;-----------------------------------------------------------------------------
%if cpuflag(avx)
INIT_XMM cpuname
%else
INIT_MMX cpuname
%endif
cglobal deblock_h_luma, 1,5,8,0x60+12
    mov    r3, r1m
    lea    r4, [r3*3]
    sub    r0, 4
    lea    r1, [r0+r4]
    %define pix_tmp esp+12
    ; esp is intentionally misaligned to make it aligned after pushing the arguments for deblock_%1_luma.

    ; transpose 6x16 -> tmp space
    TRANSPOSE6x8_MEM  PASS8ROWS(r0, r1, r3, r4), pix_tmp
    lea    r0, [r0+r3*8]
    lea    r1, [r1+r3*8]
    TRANSPOSE6x8_MEM  PASS8ROWS(r0, r1, r3, r4), pix_tmp+8

    ; vertical filter
    lea    r0, [pix_tmp+0x30]
    PUSH   dword r4m
    PUSH   dword r3m
    PUSH   dword r2m
    PUSH   dword 16
    PUSH   dword r0
    call   deblock_%1_luma
%ifidn %1, v8
    add    dword [esp   ], 8 ; pix_tmp+0x38
    add    dword [esp+16], 2 ; tc0+2
    call   deblock_%1_luma
%endif
    ADD    esp, 20

    ; transpose 16x4 -> original space  (only the middle 4 rows were changed by the filter)
    mov    r0, r0mp
    sub    r0, 2
    lea    r1, [r0+r4]

%if cpuflag(avx)
    mova   m0, [pix_tmp+0x10]
    mova   m1, [pix_tmp+0x20]
    mova   m2, [pix_tmp+0x30]
    mova   m3, [pix_tmp+0x40]
    SBUTTERFLY bw, 0, 1, 4
    SBUTTERFLY bw, 2, 3, 4
    SBUTTERFLY wd, 0, 2, 4
    SBUTTERFLY wd, 1, 3, 4
    STORE_8x4B PASS8ROWS(r0, r1, r3, r4), m0, m2
    lea    r0, [r0+r3*8]
    lea    r1, [r1+r3*8]
    STORE_8x4B PASS8ROWS(r0, r1, r3, r4), m1, m3
%else
    movq   m0, [pix_tmp+0x10]
    movq   m1, [pix_tmp+0x20]
    movq   m2, [pix_tmp+0x30]
    movq   m3, [pix_tmp+0x40]
    TRANSPOSE8x4B_STORE  PASS8ROWS(r0, r1, r3, r4)

    lea    r0, [r0+r3*8]
    lea    r1, [r1+r3*8]
    movq   m0, [pix_tmp+0x18]
    movq   m1, [pix_tmp+0x28]
    movq   m2, [pix_tmp+0x38]
    movq   m3, [pix_tmp+0x48]
    TRANSPOSE8x4B_STORE  PASS8ROWS(r0, r1, r3, r4)
%endif

    RET
%endmacro ; DEBLOCK_LUMA

INIT_MMX mmx2
DEBLOCK_LUMA v8, 8
INIT_XMM sse2
DEBLOCK_LUMA v, 16
INIT_XMM avx
DEBLOCK_LUMA v, 16

%endif ; ARCH



%macro LUMA_INTRA_P012 4 ; p0..p3 in memory
%if ARCH_X86_64
    pavgb t0, p2, p1
    pavgb t1, p0, q0
%else
    mova  t0, p2
    mova  t1, p0
    pavgb t0, p1
    pavgb t1, q0
%endif
    pavgb t0, t1 ; ((p2+p1+1)/2 + (p0+q0+1)/2 + 1)/2
    mova  t5, t1
%if ARCH_X86_64
    paddb t2, p2, p1
    paddb t3, p0, q0
%else
    mova  t2, p2
    mova  t3, p0
    paddb t2, p1
    paddb t3, q0
%endif
    paddb t2, t3
    mova  t3, t2
    mova  t4, t2
    psrlw t2, 1
    pavgb t2, mpb_0
    pxor  t2, t0
    pand  t2, mpb_1
    psubb t0, t2 ; p1' = (p2+p1+p0+q0+2)/4;

%if ARCH_X86_64
    pavgb t1, p2, q1
    psubb t2, p2, q1
%else
    mova  t1, p2
    mova  t2, p2
    pavgb t1, q1
    psubb t2, q1
%endif
    paddb t3, t3
    psubb t3, t2 ; p2+2*p1+2*p0+2*q0+q1
    pand  t2, mpb_1
    psubb t1, t2
    pavgb t1, p1
    pavgb t1, t5 ; (((p2+q1)/2 + p1+1)/2 + (p0+q0+1)/2 + 1)/2
    psrlw t3, 2
    pavgb t3, mpb_0
    pxor  t3, t1
    pand  t3, mpb_1
    psubb t1, t3 ; p0'a = (p2+2*p1+2*p0+2*q0+q1+4)/8

    pxor  t3, p0, q1
    pavgb t2, p0, q1
    pand  t3, mpb_1
    psubb t2, t3
    pavgb t2, p1 ; p0'b = (2*p1+p0+q0+2)/4

    pxor  t1, t2
    pxor  t2, p0
    pand  t1, mask1p
    pand  t2, mask0
    pxor  t1, t2
    pxor  t1, p0
    mova  %1, t1 ; store p0

    mova  t1, %4 ; p3
    paddb t2, t1, p2
    pavgb t1, p2
    pavgb t1, t0 ; (p3+p2+1)/2 + (p2+p1+p0+q0+2)/4
    paddb t2, t2
    paddb t2, t4 ; 2*p3+3*p2+p1+p0+q0
    psrlw t2, 2
    pavgb t2, mpb_0
    pxor  t2, t1
    pand  t2, mpb_1
    psubb t1, t2 ; p2' = (2*p3+3*p2+p1+p0+q0+4)/8

    pxor  t0, p1
    pxor  t1, p2
    pand  t0, mask1p
    pand  t1, mask1p
    pxor  t0, p1
    pxor  t1, p2
    mova  %2, t0 ; store p1
    mova  %3, t1 ; store p2
%endmacro

%macro LUMA_INTRA_SWAP_PQ 0
    %define q1 m0
    %define q0 m1
    %define p0 m2
    %define p1 m3
    %define p2 q2
    %define mask1p mask1q
%endmacro

%macro DEBLOCK_LUMA_INTRA 1
    %define p1 m0
    %define p0 m1
    %define q0 m2
    %define q1 m3
    %define t0 m4
    %define t1 m5
    %define t2 m6
    %define t3 m7
%if ARCH_X86_64
    %define p2 m8
    %define q2 m9
    %define t4 m10
    %define t5 m11
    %define mask0 m12
    %define mask1p m13
%if WIN64
    %define mask1q [rsp]
%else
    %define mask1q [rsp-24]
%endif
    %define mpb_0 m14
    %define mpb_1 m15
%else
    %define spill(x) [esp+16*x]
    %define p2 [r4+r1]
    %define q2 [r0+2*r1]
    %define t4 spill(0)
    %define t5 spill(1)
    %define mask0 spill(2)
    %define mask1p spill(3)
    %define mask1q spill(4)
    %define mpb_0 [pb_0]
    %define mpb_1 [pb_1]
%endif

;-----------------------------------------------------------------------------
; void deblock_v_luma_intra( uint8_t *pix, intptr_t stride, int alpha, int beta )
;-----------------------------------------------------------------------------
cglobal deblock_%1_luma_intra, 4,6,16,0-(1-ARCH_X86_64)*0x50-WIN64*0x10
    lea     r4, [r1*4]
    lea     r5, [r1*3] ; 3*stride
    neg     r4
    add     r4, r0     ; pix-4*stride
    mova    p1, [r4+2*r1]
    mova    p0, [r4+r5]
    mova    q0, [r0]
    mova    q1, [r0+r1]
%if ARCH_X86_64
    pxor    mpb_0, mpb_0
    mova    mpb_1, [pb_1]
    LOAD_MASK r2d, r3d, t5 ; m5=beta-1, t5=alpha-1, m7=mask0
    SWAP    7, 12 ; m12=mask0
    pavgb   t5, mpb_0
    pavgb   t5, mpb_1 ; alpha/4+1
    movdqa  p2, [r4+r1]
    movdqa  q2, [r0+2*r1]
    DIFF_GT2 p0, q0, t5, t0, t3    ; t0 = |p0-q0| > alpha/4+1
    DIFF_GT2 p0, p2, m5, t2, t5, 1 ; mask1 = |p2-p0| > beta-1
    DIFF_GT2 q0, q2, m5, t4, t5, 1 ; t4 = |q2-q0| > beta-1
    pand    t0, mask0
    pand    t4, t0
    pand    t2, t0
    mova    mask1q, t4
    mova    mask1p, t2
%else
    LOAD_MASK r2d, r3d, t5 ; m5=beta-1, t5=alpha-1, m7=mask0
    mova    m4, t5
    mova    mask0, m7
    pavgb   m4, [pb_0]
    pavgb   m4, [pb_1] ; alpha/4+1
    DIFF_GT2 p0, q0, m4, m6, m7    ; m6 = |p0-q0| > alpha/4+1
    pand    m6, mask0
    DIFF_GT2 p0, p2, m5, m4, m7, 1 ; m4 = |p2-p0| > beta-1
    pand    m4, m6
    mova    mask1p, m4
    DIFF_GT2 q0, q2, m5, m4, m7, 1 ; m4 = |q2-q0| > beta-1
    pand    m4, m6
    mova    mask1q, m4
%endif
    LUMA_INTRA_P012 [r4+r5], [r4+2*r1], [r4+r1], [r4]
    LUMA_INTRA_SWAP_PQ
    LUMA_INTRA_P012 [r0], [r0+r1], [r0+2*r1], [r0+r5]
.end:
    REP_RET

%if cpuflag(avx)
INIT_XMM cpuname
%else
INIT_MMX cpuname
%endif
%if ARCH_X86_64
;-----------------------------------------------------------------------------
; void deblock_h_luma_intra( uint8_t *pix, intptr_t stride, int alpha, int beta )
;-----------------------------------------------------------------------------
cglobal deblock_h_luma_intra, 4,9,0,0x80
    lea    r8, [r1*3]
    lea    r6, [r0-4]
    lea    r5, [r0-4+r8]
%if WIN64
    %define pix_tmp rsp+0x20 ; shadow space
%else
    %define pix_tmp rsp
%endif

    ; transpose 8x16 -> tmp space
    TRANSPOSE8x8_MEM  PASS8ROWS(r6, r5, r1, r8), PASS8ROWS(pix_tmp, pix_tmp+0x30, 0x10, 0x30)
    lea    r6, [r6+r1*8]
    lea    r5, [r5+r1*8]
    TRANSPOSE8x8_MEM  PASS8ROWS(r6, r5, r1, r8), PASS8ROWS(pix_tmp+8, pix_tmp+0x38, 0x10, 0x30)

    mov    r7, r1
    lea    r0, [pix_tmp+0x40]
    mov    r1, 0x10
    call   deblock_v_luma_intra

    ; transpose 16x6 -> original space (but we can't write only 6 pixels, so really 16x8)
    lea    r5, [r6+r8]
    TRANSPOSE8x8_MEM  PASS8ROWS(pix_tmp+8, pix_tmp+0x38, 0x10, 0x30), PASS8ROWS(r6, r5, r7, r8)
    shl    r7, 3
    sub    r6, r7
    sub    r5, r7
    shr    r7, 3
    TRANSPOSE8x8_MEM  PASS8ROWS(pix_tmp, pix_tmp+0x30, 0x10, 0x30), PASS8ROWS(r6, r5, r7, r8)
    RET
%else
cglobal deblock_h_luma_intra, 2,4,8,0x80
    lea    r3,  [r1*3]
    sub    r0,  4
    lea    r2,  [r0+r3]
    %define pix_tmp rsp

    ; transpose 8x16 -> tmp space
    TRANSPOSE8x8_MEM  PASS8ROWS(r0, r2, r1, r3), PASS8ROWS(pix_tmp, pix_tmp+0x30, 0x10, 0x30)
    lea    r0,  [r0+r1*8]
    lea    r2,  [r2+r1*8]
    TRANSPOSE8x8_MEM  PASS8ROWS(r0, r2, r1, r3), PASS8ROWS(pix_tmp+8, pix_tmp+0x38, 0x10, 0x30)

    lea    r0,  [pix_tmp+0x40]
    PUSH   dword r3m
    PUSH   dword r2m
    PUSH   dword 16
    PUSH   r0
    call   deblock_%1_luma_intra
%ifidn %1, v8
    add    dword [rsp], 8 ; pix_tmp+8
    call   deblock_%1_luma_intra
%endif
    ADD    esp, 16

    mov    r1,  r1m
    mov    r0,  r0mp
    lea    r3,  [r1*3]
    sub    r0,  4
    lea    r2,  [r0+r3]
    ; transpose 16x6 -> original space (but we can't write only 6 pixels, so really 16x8)
    TRANSPOSE8x8_MEM  PASS8ROWS(pix_tmp, pix_tmp+0x30, 0x10, 0x30), PASS8ROWS(r0, r2, r1, r3)
    lea    r0,  [r0+r1*8]
    lea    r2,  [r2+r1*8]
    TRANSPOSE8x8_MEM  PASS8ROWS(pix_tmp+8, pix_tmp+0x38, 0x10, 0x30), PASS8ROWS(r0, r2, r1, r3)
    RET
%endif ; ARCH_X86_64
%endmacro ; DEBLOCK_LUMA_INTRA

INIT_XMM sse2
DEBLOCK_LUMA_INTRA v
INIT_XMM avx
DEBLOCK_LUMA_INTRA v
%if ARCH_X86_64 == 0
INIT_MMX mmx2
DEBLOCK_LUMA_INTRA v8
%endif

%if ARCH_X86_64
;-----------------------------------------------------------------------------
; avx512icl luma intra: one ymm pass covers both sides of the edge, lane 0 the
; p side and lane 1 the q side. gf2p8affineqb gives the rounding parity bits
; and k-masks select the outputs.
;-----------------------------------------------------------------------------
; in: m0-m3 = [p0|q0] [p1|q1] [p2|q2] [p3|q3], m4 = [q0|p0], m5 = [q1|p1]
;     r2d = alpha, r3d = beta
; out: m0-m2 = p0' p1' p2' | q0' q1' q2'
; clobbers: ym6-ym14, k1-k5, r2
%macro LUMA_INTRA_ICL 3 ; x|y, qwords, dwords
    vpbroadcastb %1m12, r2d
    vpbroadcastb %1m13, r3d
    shr        r2d, 2
    add        r2d, 2
    vpbroadcastb %1m14, r2d
    pminub      %1m6, %1m0, %1m4
    pmaxub      %1m7, %1m0, %1m4
    psubb       %1m7, %1m6            ; |p0-q0|
    pminub      %1m6, %1m1, %1m0
    pmaxub      %1m8, %1m1, %1m0
    psubb       %1m8, %1m6            ; |p1-p0| | |q1-q0|
    pminub      %1m6, %1m5, %1m4
    pmaxub     %1m10, %1m5, %1m4
    psubb      %1m10, %1m6            ; |q1-q0| | |p1-p0|
    pminub      %1m6, %1m2, %1m0
    pmaxub      %1m9, %1m2, %1m0
    psubb       %1m9, %1m6            ; |p2-p0| | |q2-q0|
    vpcmpub     k1, %1m7, %1m12, 1    ; |p0-q0| < alpha
    vpcmpub     k2, %1m8, %1m13, 1
    vpcmpub     k3, %1m10, %1m13, 1
    vpcmpub     k4, %1m7, %1m14, 1    ; |p0-q0| < (alpha>>2)+2
    vpcmpub     k5, %1m9, %1m13, 1    ; |p2-p0| < beta
    kandd       k1, k1, k2
    kandd       k1, k1, k3          ; normal
    kandd       k2, k4, k5
    kandd       k2, k2, k1          ; strong

    pavgb       %1m6, %1m2, %1m1
    pavgb       %1m7, %1m0, %1m4
    pavgb       %1m6, %1m7            ; ((p2+p1+1)/2 + (p0+q0+1)/2 + 1)/2
    paddb       %1m8, %1m2, %1m1
    paddb       %1m9, %1m0, %1m4
    paddb       %1m8, %1m9            ; p2+p1+p0+q0
    paddb       %1m9, %1m8, %1m8
    vgf2p8affineqb %1m10, %1m8, [gf_par1]{1to%2}, 0
    vpternlogd  %1m10, %1m6, [pb_1]{1to%3}, 0x28 ; (%1m10 ^ %1m6) & 1
    psubb       %1m6, %1m10           ; p1' = (p2+p1+p0+q0+2)/4

    pavgb      %1m10, %1m2, %1m5
    psubb      %1m11, %1m2, %1m5
    psubb       %1m9, %1m11           ; p2+2*p1+2*p0+2*q0+q1
    vpandd     %1m11, [pb_1]{1to%3}
    psubb      %1m10, %1m11
    pavgb      %1m10, %1m1
    pavgb      %1m10, %1m7            ; (((p2+q1)/2 + p1+1)/2 + (p0+q0+1)/2 + 1)/2
    vgf2p8affineqb %1m9, %1m9, [gf_par2]{1to%2}, 0
    vpternlogd  %1m9, %1m10, [pb_1]{1to%3}, 0x28
    psubb      %1m10, %1m9            ; p0'a = (p2+2*p1+2*p0+2*q0+q1+4)/8

    pxor        %1m9, %1m0, %1m5
    pavgb      %1m11, %1m0, %1m5
    vpandd      %1m9, [pb_1]{1to%3}
    psubb      %1m11, %1m9
    pavgb      %1m11, %1m1            ; p0'b = (2*p1+p0+q1+2)/4
    vmovdqu8    %1m0 {k1}, %1m11
    vmovdqu8    %1m0 {k2}, %1m10

    paddb       %1m9, %1m3, %1m2
    pavgb      %1m10, %1m3, %1m2
    pavgb      %1m10, %1m6            ; (p3+p2+1)/2 + (p2+p1+p0+q0+2)/4
    paddb       %1m9, %1m9
    paddb       %1m9, %1m8            ; 2*p3+3*p2+p1+p0+q0
    vgf2p8affineqb %1m9, %1m9, [gf_par2]{1to%2}, 0
    vpternlogd  %1m9, %1m10, [pb_1]{1to%3}, 0x28
    psubb      %1m10, %1m9            ; p2' = (2*p3+3*p2+p1+p0+q0+4)/8
    vmovdqu8    %1m1 {k2}, %1m6
    vmovdqu8    %1m2 {k2}, %1m10
%endmacro

INIT_YMM avx512icl
;-----------------------------------------------------------------------------
; void deblock_v_luma_intra( uint8_t *pix, intptr_t stride, int alpha, int beta )
;-----------------------------------------------------------------------------
cglobal deblock_v_luma_intra, 4,6,15
    lea         r4, [r1*4]
    lea         r5, [r1*3]
    neg         r4
    add         r4, r0            ; pix-4*stride
    movu       xm0, [r4+r5]
    movu       xm1, [r4+r1*2]
    movu       xm2, [r4+r1]
    movu       xm3, [r4]
    vinserti128 m0, m0, [r0], 1
    vinserti128 m1, m1, [r0+r1], 1
    vinserti128 m2, m2, [r0+r1*2], 1
    vinserti128 m3, m3, [r0+r5], 1
    movu       xm4, [r0]
    movu       xm5, [r0+r1]
    vinserti128 m4, m4, [r4+r5], 1
    vinserti128 m5, m5, [r4+r1*2], 1
    LUMA_INTRA_ICL y, 4, 8
    movu   [r4+r5], xm0
    vextracti128 [r0], m0, 1
    movu [r4+r1*2], xm1
    vextracti128 [r0+r1], m1, 1
    movu   [r4+r1], xm2
    vextracti128 [r0+r1*2], m2, 1
    RET

;-----------------------------------------------------------------------------
; void deblock_h_luma_intra( uint8_t *pix, intptr_t stride, int alpha, int beta )
;-----------------------------------------------------------------------------
; rows 0-7 | 8-15 of p3..q3 <-> column pairs, one vpermi2b per 64 bytes
INIT_ZMM avx512icl
cglobal deblock_h_luma_intra, 4,9,15
    lea         r5, [r1*3]
    lea         r6, [r0-4]
    lea         r7, [r6+r1*4]
    lea         r8, [r6+r1*8]
    lea         r4, [r7+r1*8]
    movq       xm6, [r6]
    movhps     xm6, [r6+r1]
    movq       xm0, [r6+r1*2]
    movhps     xm0, [r6+r5]
    movq       xm1, [r7]
    movhps     xm1, [r7+r1]
    movq       xm2, [r7+r1*2]
    movhps     xm2, [r7+r5]
    movq       xm7, [r8]
    movhps     xm7, [r8+r1]
    movq       xm3, [r8+r1*2]
    movhps     xm3, [r8+r5]
    movq       xm4, [r4]
    movhps     xm4, [r4+r1]
    movq       xm5, [r4+r1*2]
    movhps     xm5, [r4+r5]
    vinserti128 ym6, ym6, xm0, 1
    vinserti128 ym1, ym1, xm2, 1
    vinserti128 ym7, ym7, xm3, 1
    vinserti128 ym4, ym4, xm5, 1
    vinserti64x4 m6, m6, ym1, 1     ; rows 0-7
    vinserti64x4 m7, m7, ym4, 1     ; rows 8-15
    mova       m0, [h_luma_p01_idx]
    mova       m2, [h_luma_p23_idx]
    mova       m4, [h_luma_q01_idx]
    vpermi2b   m0, m6, m7
    vpermi2b   m2, m6, m7
    vpermi2b   m4, m6, m7
    vextracti64x4 ym1, m0, 1
    vextracti64x4 ym3, m2, 1
    vextracti64x4 ym5, m4, 1
    LUMA_INTRA_ICL y, 4, 8
    vinserti64x4 m0, m0, ym1, 1
    vinserti64x4 m2, m2, ym3, 1
    mova       m6, [h_luma_rows0_idx]
    mova       m7, [h_luma_rows8_idx]
    vpermi2b   m6, m0, m2
    vpermi2b   m7, m0, m2
    movq       [r6], xm6
    movhps  [r6+r1], xm6
    vextracti32x4 xm0, m6, 1
    vextracti32x4 xm1, m6, 2
    vextracti32x4 xm2, m6, 3
    movq  [r6+r1*2], xm0
    movhps  [r6+r5], xm0
    movq       [r7], xm1
    movhps  [r7+r1], xm1
    movq  [r7+r1*2], xm2
    movhps  [r7+r5], xm2
    movq       [r8], xm7
    movhps  [r8+r1], xm7
    vextracti32x4 xm0, m7, 1
    vextracti32x4 xm1, m7, 2
    vextracti32x4 xm2, m7, 3
    movq  [r8+r1*2], xm0
    movhps  [r8+r5], xm0
    movq       [r4], xm1
    movhps  [r4+r1], xm1
    movq  [r4+r1*2], xm2
    movhps  [r4+r5], xm2
    RET

;-----------------------------------------------------------------------------
; avx512icl luma inter, same lane layout as LUMA_INTRA_ICL. The p0/q0 delta is
; computed once in lane 0 and applied to q0 with its sign swapped.
;-----------------------------------------------------------------------------
; in: ym0-ym2 = [p0|q0] [p1|q1] [p2|q2], ym4-ym6 = [q0|p0] [q1|p1] [q2|p2]
;     r2d = alpha, r3d = beta, r4 = tc0
; out: ym0-ym1 = p0' p1' | q0' q1'
; clobbers: ym7-ym15, k1-k6
%macro LUMA_INTER_ICL 4 ; x|y, qwords, dwords, tc0 shuffle
    vpbroadcastb %1m12, r2d
    vpbroadcastb %1m13, r3d
    vpbroadcastd %1m14, [r4]
    pshufb      %1m14, [%4] ; tc0
    pminub      %1m7, %1m0, %1m4
    pmaxub      %1m8, %1m0, %1m4
    psubb       %1m8, %1m7            ; |p0-q0|
    pminub      %1m7, %1m1, %1m0
    pmaxub      %1m9, %1m1, %1m0
    psubb       %1m9, %1m7            ; |p1-p0| | |q1-q0|
    pminub      %1m7, %1m5, %1m4
    pmaxub     %1m10, %1m5, %1m4
    psubb      %1m10, %1m7            ; |q1-q0| | |p1-p0|
    pminub      %1m7, %1m2, %1m0
    pmaxub     %1m11, %1m2, %1m0
    psubb      %1m11, %1m7            ; |p2-p0| | |q2-q0|
    pminub      %1m7, %1m6, %1m4
    pmaxub     %1m15, %1m6, %1m4
    psubb      %1m15, %1m7            ; |q2-q0| | |p2-p0|
    vpcmpub     k1, %1m8, %1m12, 1
    vpcmpub     k2, %1m9, %1m13, 1
    vpcmpub     k3, %1m10, %1m13, 1
    vpmovb2m    k4, %1m14            ; tc0 < 0: bS 0
    vpcmpub     k5, %1m11, %1m13, 1   ; ap | aq
    vpcmpub     k6, %1m15, %1m13, 1   ; aq | ap
    kandd       k1, k1, k2
    kandnd      k3, k4, k3
    kandd       k1, k1, k3          ; mask
    kandd       k5, k5, k1
    kandd       k6, k6, k1
    vmovdqu8    %1m7 {k1}{z}, %1m14
    vmovdqu8    %1m9 {k5}{z}, %1m14   ; tc0 for p1 | q1
    paddb       %1m7 {k5}, %1m7, [pb_1]
    paddb       %1m7 {k6}, %1m7, [pb_1] ; tc = tc0+ap+aq
    pavgb       %1m8, %1m0, %1m4       ; (p0+q0+1)>>1

    pxor       xm10, xm0, xm4
    vpandd     xm10, [pb_1]{1to4}   ; (p0^q0)&1
    vpternlogd xm11, xm5, xm5, 0x33 ; ~q1
    pavgb      xm11, xm1            ; (p1 - q1 + 256)>>1
    pavgb      xm11, [pb_3]         ; (((p1 - q1 + 256)>>1)+4)>>1 = 64+2+(p1-q1)>>2
    vpternlogd xm12, xm0, xm0, 0x33 ; ~p0
    pavgb      xm12, xm4            ; (q0 - p0 + 256)>>1
    pavgb      xm11, xm10
    paddusb    xm11, xm12           ; d+128+33
    mova       xm10, [pb_a1]
    psubusb    xm10, xm11
    psubusb    xm11, [pb_a1]
    pminub     xm10, xm7            ; -d
    pminub     xm11, xm7            ; +d
%ifidn %1, y
    vinserti128 ym12, ym10, xm11, 1
    vinserti128 ym11, ym11, xm10, 1
%else
    punpcklqdq xm12, xm10, xm11
    punpcklqdq xm11, xm11, xm10
%endif
    psubusb     %1m0, %1m12
    paddusb     %1m0, %1m11           ; p0' | q0'

    pavgb      %1m10, %1m2, %1m8
    vpternlogd  %1m8, %1m2, [pb_1]{1to%3}, 0x28 ; (p2 ^ avg(p0,q0)) & 1
    psubusb    %1m10, %1m8            ; (p2+((p0+q0+1)>>1))>>1
    psubusb     %1m8, %1m1, %1m9
    paddusb     %1m9, %1m1
    pmaxub     %1m10, %1m8
    pminub      %1m1, %1m10, %1m9      ; p1' | q1'
%endmacro

;-----------------------------------------------------------------------------
; void deblock_h_luma( uint8_t *pix, intptr_t stride, int alpha, int beta, int8_t *tc0 )
;-----------------------------------------------------------------------------
INIT_ZMM avx512icl
cglobal deblock_h_luma, 5,10,16
    lea         r5, [r1*3]
    lea         r6, [r0-4]
    lea         r7, [r6+r1*4]
    lea         r8, [r6+r1*8]
    lea         r9, [r7+r1*8]
    movq       xm8, [r6]
    movhps     xm8, [r6+r1]
    movq       xm0, [r6+r1*2]
    movhps     xm0, [r6+r5]
    movq       xm1, [r7]
    movhps     xm1, [r7+r1]
    movq       xm2, [r7+r1*2]
    movhps     xm2, [r7+r5]
    movq       xm9, [r8]
    movhps     xm9, [r8+r1]
    movq       xm3, [r8+r1*2]
    movhps     xm3, [r8+r5]
    movq       xm4, [r9]
    movhps     xm4, [r9+r1]
    movq       xm5, [r9+r1*2]
    movhps     xm5, [r9+r5]
    vinserti128 ym8, ym8, xm0, 1
    vinserti128 ym1, ym1, xm2, 1
    vinserti128 ym9, ym9, xm3, 1
    vinserti128 ym4, ym4, xm5, 1
    vinserti64x4 m8, m8, ym1, 1     ; rows 0-7
    vinserti64x4 m9, m9, ym4, 1     ; rows 8-15
    mova        m0, [h_luma_p01_idx]
    mova        m2, [h_luma_p23_idx]
    mova        m4, [h_luma_q01_idx]
    mova        m6, [h_luma_q23_idx]
    vpermi2b    m0, m8, m9
    vpermi2b    m2, m8, m9
    vpermi2b    m4, m8, m9
    vpermi2b    m6, m8, m9
    vextracti64x4 ym1, m0, 1
    vextracti64x4 ym3, m2, 1
    vextracti64x4 ym5, m4, 1
    LUMA_INTER_ICL y, 4, 8, pb_unpackbd1
    vinserti64x4 m0, m0, ym1, 1
    vinserti64x4 m2, m2, ym3, 1
    mova        m6, [h_luma_rows0_idx]
    mova        m7, [h_luma_rows8_idx]
    vpermi2b    m6, m0, m2
    vpermi2b    m7, m0, m2
    movq       [r6], xm6
    movhps  [r6+r1], xm6
    vextracti32x4 xm0, m6, 1
    vextracti32x4 xm1, m6, 2
    vextracti32x4 xm2, m6, 3
    movq  [r6+r1*2], xm0
    movhps  [r6+r5], xm0
    movq       [r7], xm1
    movhps  [r7+r1], xm1
    movq  [r7+r1*2], xm2
    movhps  [r7+r5], xm2
    movq       [r8], xm7
    movhps  [r8+r1], xm7
    vextracti32x4 xm0, m7, 1
    vextracti32x4 xm1, m7, 2
    vextracti32x4 xm2, m7, 3
    movq  [r8+r1*2], xm0
    movhps  [r8+r5], xm0
    movq       [r9], xm1
    movhps  [r9+r1], xm1
    movq  [r9+r1*2], xm2
    movhps  [r9+r5], xm2
    RET

;-----------------------------------------------------------------------------
; avx512icl MBAFF mixed edge, 8 rows: one vpermb turns the 8x8 block of
; p3..q3 into [pN|qN] qword pairs, the xmm forms of the filters above run once.
;-----------------------------------------------------------------------------
; in: r0 = pix, r1 = stride; out: m8 = rows 0-7 of p3..q3, r5 = 3*stride,
; r6 = pix-4, r7 = pix-4+4*stride
%macro LUMA_MBAFF_LOAD_ICL 0
    lea         r5, [r1*3]
    lea         r6, [r0-4]
    lea         r7, [r6+r1*4]
    movq       xm8, [r6]
    movhps     xm8, [r6+r1]
    movq       xm0, [r6+r1*2]
    movhps     xm0, [r6+r5]
    movq       xm1, [r7]
    movhps     xm1, [r7+r1]
    movq       xm2, [r7+r1*2]
    movhps     xm2, [r7+r5]
    vinserti128 ym8, ym8, xm0, 1
    vinserti128 ym1, ym1, xm2, 1
    vinserti64x4 m8, m8, ym1, 1
%endmacro

; in: xm0-xm3 = [pN|qN] N = 0..3; stores rows 0-7
%macro LUMA_MBAFF_STORE_ICL 0
    vinserti128 ym0, ym0, xm1, 1
    vinserti128 ym2, ym2, xm3, 1
    vinserti64x4 m0, m0, ym2, 1
    mova        m6, [mbaff_rows_idx]
    vpermb      m6, m6, m0
    vextracti32x4 xm0, m6, 1
    vextracti32x4 xm1, m6, 2
    vextracti32x4 xm2, m6, 3
    movq       [r6], xm6
    movhps  [r6+r1], xm6
    movq  [r6+r1*2], xm0
    movhps  [r6+r5], xm0
    movq       [r7], xm1
    movhps  [r7+r1], xm1
    movq  [r7+r1*2], xm2
    movhps  [r7+r5], xm2
%endmacro

INIT_ZMM avx512icl
;-----------------------------------------------------------------------------
; void deblock_h_luma_mbaff( uint8_t *pix, intptr_t stride, int alpha, int beta, int8_t *tc0 )
;-----------------------------------------------------------------------------
cglobal deblock_h_luma_mbaff, 5,8,16
    LUMA_MBAFF_LOAD_ICL
    mova        m0, [mbaff_p_idx]
    mova        m4, [mbaff_q_idx]
    vpermb      m0, m0, m8
    vpermb      m4, m4, m8
    vextracti32x4 xm1, m0, 1
    vextracti32x4 xm2, m0, 2
    vextracti32x4 xm3, m0, 3
    vextracti32x4 xm5, m4, 1
    vextracti32x4 xm6, m4, 2
    LUMA_INTER_ICL x, 2, 4, mbaff_tc_shuf
    LUMA_MBAFF_STORE_ICL
    RET

;-----------------------------------------------------------------------------
; void deblock_h_luma_intra_mbaff( uint8_t *pix, intptr_t stride, int alpha, int beta )
;-----------------------------------------------------------------------------
cglobal deblock_h_luma_intra_mbaff, 4,8,15
    LUMA_MBAFF_LOAD_ICL
    mova        m0, [mbaff_p_idx]
    mova        m4, [mbaff_q_idx]
    vpermb      m0, m0, m8
    vpermb      m4, m4, m8
    vextracti32x4 xm1, m0, 1
    vextracti32x4 xm2, m0, 2
    vextracti32x4 xm3, m0, 3
    vextracti32x4 xm5, m4, 1
    LUMA_INTRA_ICL x, 2, 4
    LUMA_MBAFF_STORE_ICL
    RET
%endif ; ARCH_X86_64

%if ARCH_X86_64
;-----------------------------------------------------------------------------
; MBAFF mixed edge: 8 rows, tc0[i] covers rows 2i, 2i+1. Each column pair
; [pN|qN] fills one xmm and [qN|pN] is its half swap, so one pass of the
; vertical filter covers both sides of the edge.
;-----------------------------------------------------------------------------
; %1 = [%2.hi | %3.lo]
%macro PUNPCK_HL 3
%if cpuflag(ssse3)
    palignr  %1, %3, %2, 8
%else
    shufpd   %1, %2, %3, 1
%endif
%endmacro

; %1 = [%2.lo | %3.hi]
%macro PUNPCK_LH 3
%if cpuflag(sse4)
    pblendw  %1, %2, %3, 0xf0
%else
    shufpd   %1, %2, %3, 2
%endif
%endmacro

; in: r0=pix-4, r1=stride, r5=3*stride, r6=r0+r5
; out: one column per qword: m0=[p3|p2] m4=[p1|p0] m2=[q0|q1] m6=[q2|q3]
%macro LUMA_MBAFF_LOAD 0
    movq       m0, [r0]
    movq       m1, [r0+r1]
    movq       m2, [r0+r1*2]
    movq       m3, [r6]
    movq       m4, [r6+r1]
    movq       m5, [r6+r1*2]
    movq       m6, [r6+r5]
    movq       m7, [r6+r1*4]
    punpcklbw  m0, m1
    punpcklbw  m2, m3
    punpcklbw  m4, m5
    punpcklbw  m6, m7
    SBUTTERFLY wd, 0, 2, 1
    SBUTTERFLY wd, 4, 6, 1
    SBUTTERFLY dq, 0, 4, 1
    SBUTTERFLY dq, 2, 6, 1
%endmacro

%macro DEBLOCK_LUMA_MBAFF 0
;-----------------------------------------------------------------------------
; void deblock_h_luma_mbaff( uint8_t *pix, intptr_t stride, int alpha, int beta, int8_t *tc0 )
;-----------------------------------------------------------------------------
cglobal deblock_h_luma_mbaff, 5,7,13
    sub        r0, 4
    lea        r5, [r1*3]
    lea        r6, [r0+r5]
    LUMA_MBAFF_LOAD
    PUNPCK_HL  m8, m0, m6     ; p2 q2
    PUNPCK_HL  m1, m4, m2     ; p0 q0
    PUNPCK_LH  m0, m4, m2     ; p1 q1
    PUNPCK_HL  m3, m2, m4     ; q1 p1
    PUNPCK_LH  m2, m2, m4     ; q0 p0
    movd       m9, [r4]
    LOAD_MASK  r2d, r3d       ; m5=beta-1, m7=mask, m6=0
    punpcklbw  m9, m9
    punpcklqdq m9, m9
%if cpuflag(avx)
    pblendvb  m10, m7, m6, m9
%else
    pcmpeqb   m10, m10
    pcmpeqb   m10, m9
    pandn     m10, m7
%endif
    pand       m9, m10
    DIFF_GT2   m1, m8, m5, m6, m7 ; ap | aq
    pand       m6, m10
    pshufd     m4, m6, q1032
    psubb      m7, m9, m6
    psubb      m7, m4         ; tc0+ap+aq
    pand       m6, m9
    mova      m11, m8
    LUMA_Q1    m0, m11, m8, m12, m6, m4 ; m12 = p1' q1'
    DEBLOCK_P0_Q0             ; low qwords: m1 = p0', m2 = q0'
    punpcklqdq m1, m2         ; p0' q0'

    punpcklbw  m0, m12, m1
    punpckhbw  m1, m12
    SBUTTERFLY wd, 0, 1, 2    ; p1' p0' q0' q1' of rows 0-3, 4-7
%if cpuflag(sse4)
    STORE_8x4B PASS8ROWS(r0, r6, r1, r5, 2), m0, m1
%else
    movd       [r0+2], m0
    movd       [r6+r1+2], m1
    psrldq     m0, 4
    psrldq     m1, 4
    movd       [r0+r1+2], m0
    movd       [r6+r1*2+2], m1
    psrldq     m0, 4
    psrldq     m1, 4
    movd       [r0+r1*2+2], m0
    movd       [r6+r5+2], m1
    psrldq     m0, 4
    psrldq     m1, 4
    movd       [r6+2], m0
    movd       [r6+r1*4+2], m1
%endif
    RET

;-----------------------------------------------------------------------------
; void deblock_h_luma_intra_mbaff( uint8_t *pix, intptr_t stride, int alpha, int beta )
;-----------------------------------------------------------------------------
cglobal deblock_h_luma_intra_mbaff, 4,7,16
    %define p1 m0
    %define p0 m1
    %define q0 m2
    %define q1 m3
    %define t0 m4
    %define t1 m5
    %define t2 m6
    %define t3 m7
    %define p2 m8
    %define p3 m9
    %define t4 m10
    %define t5 m11
    %define mask0 m12
    %define mask1p m13
    %define mpb_0 m14
    %define mpb_1 m15
    sub        r0, 4
    lea        r5, [r1*3]
    lea        r6, [r0+r5]
    LUMA_MBAFF_LOAD
    PUNPCK_HL  p2, m0, m6     ; p2 q2
    PUNPCK_LH  p3, m0, m6     ; p3 q3
    PUNPCK_HL  p0, m4, m2     ; p0 q0
    PUNPCK_LH  p1, m4, m2     ; p1 q1
    PUNPCK_HL  q1, m2, m4     ; q1 p1
    PUNPCK_LH  q0, m2, m4     ; q0 p0
    pxor    mpb_0, mpb_0
    mova    mpb_1, [pb_1]
    LOAD_MASK r2d, r3d, t5    ; m5=beta-1, t5=alpha-1, m7=mask0
    SWAP    7, 12             ; m12=mask0
    pavgb   t5, mpb_0
    pavgb   t5, mpb_1         ; alpha/4+1
    DIFF_GT2 p0, q0, t5, t0, t3         ; t0 = |p0-q0| > alpha/4+1
    DIFF_GT2 p0, p2, m5, mask1p, t5, 1  ; |p2-p0| > beta-1 | |q2-q0| > beta-1
    pand    t0, mask0
    pand    mask1p, t0
    LUMA_INTRA_P012 p0, p1, p2, p3

    punpcklbw  m4, m9, m8
    punpckhbw  m8, m9
    punpcklbw  m5, m0, m1
    punpckhbw  m1, m0
    SBUTTERFLY wd, 4, 5, 6
    SBUTTERFLY wd, 1, 8, 6
    SBUTTERFLY dq, 4, 1, 6
    SBUTTERFLY dq, 5, 8, 6
    movq       [r0], m4
    movhps     [r0+r1], m4
    movq       [r0+r1*2], m1
    movhps     [r6], m1
    movq       [r6+r1], m5
    movhps     [r6+r1*2], m5
    movq       [r6+r5], m8
    movhps     [r6+r1*4], m8
    RET
%endmacro

INIT_XMM sse2
DEBLOCK_LUMA_MBAFF
INIT_XMM avx
DEBLOCK_LUMA_MBAFF
%endif ; ARCH_X86_64
%endif ; !HIGH_BIT_DEPTH

%if HIGH_BIT_DEPTH
; in: %1=p0, %2=q0, %3=p1, %4=q1, %5=mask, %6=tmp, %7=tmp, %8=pw_2 (optional)
; out: %1=p0', %2=q0'
%macro CHROMA_DEBLOCK_P0_Q0_INTRA 7-8
%if %0 == 8
    paddw   %6, %8, %3
%else
    mova    %6, [pw_2]
    paddw   %6, %3
%endif
    paddw   %6, %4
    paddw   %7, %6, %2
    paddw   %6, %1
    paddw   %6, %3
    paddw   %7, %4
    psraw   %6, 2
    psraw   %7, 2
%if cpuflag(avx)
    pblendvb %1, %1, %6, %5
    pblendvb %2, %2, %7, %5
%else
    psubw   %6, %1
    psubw   %7, %2
    pand    %6, %5
    pand    %7, %5
    paddw   %1, %6
    paddw   %2, %7
%endif
%endmacro

; out: m0-m3
; clobbers: m4-m7
%macro CHROMA_H_LOAD 0-1
    movq        m0, [r0-8] ; p1 p1 p0 p0
    movq        m2, [r0]   ; q0 q0 q1 q1
    movq        m5, [r0+r1-8]
    movq        m7, [r0+r1]
%if mmsize == 8
    mova        m1, m0
    mova        m3, m2
    punpckldq   m0, m5 ; p1
    punpckhdq   m1, m5 ; p0
    punpckldq   m2, m7 ; q0
    punpckhdq   m3, m7 ; q1
%else
    movq        m4, [r0+r1*2-8]
    movq        m6, [r0+r1*2]
    movq        m1, [r0+%1-8]
    movq        m3, [r0+%1]
    punpckldq   m0, m5 ; p1 ... p0 ...
    punpckldq   m2, m7 ; q0 ... q1 ...
    punpckldq   m4, m1
    punpckldq   m6, m3
    punpckhqdq  m1, m0, m4 ; p0
    punpcklqdq  m0, m4 ; p1
    punpckhqdq  m3, m2, m6 ; q1
    punpcklqdq  m2, m6 ; q0
%endif
%endmacro

%macro CHROMA_V_LOAD 1
    mova        m0, [r0]    ; p1
    mova        m1, [r0+r1] ; p0
    mova        m2, [%1]    ; q0
    mova        m3, [%1+r1] ; q1
%endmacro

; clobbers: m1, m2, m3
%macro CHROMA_H_STORE 0-1
    SBUTTERFLY dq, 1, 2, 3
%if mmsize == 8
    movq      [r0-4], m1
    movq   [r0+r1-4], m2
%else
    movq      [r0-4], m1
    movq [r0+r1*2-4], m2
    movhps [r0+r1-4], m1
    movhps [r0+%1-4], m2
%endif
%endmacro

%macro CHROMA_V_STORE 0
    mova [r0+1*r1], m1
    mova [r0+2*r1], m2
%endmacro

%macro DEBLOCK_CHROMA 0
cglobal deblock_inter_body
    LOAD_AB     m4, m5, r2d, r3d
    LOAD_MASK   m0, m1, m2, m3, m4, m5, m7, m6, m4
    pxor        m4, m4
    LOAD_TC     m6, r4
    pmaxsw      m6, m4
    pand        m7, m6
    DEBLOCK_P0_Q0 m1, m2, m0, m3, m7, m5, m6
    ret

;-----------------------------------------------------------------------------
; void deblock_v_chroma( uint16_t *pix, intptr_t stride, int alpha, int beta, int8_t *tc0 )
;-----------------------------------------------------------------------------
cglobal deblock_v_chroma, 5,7,8
    FIX_STRIDES r1
    mov         r5, r0
    sub         r0, r1
    sub         r0, r1
    mov         r6, 32/mmsize
.loop:
    CHROMA_V_LOAD r5
    call        deblock_inter_body
    CHROMA_V_STORE
    add         r0, mmsize
    add         r5, mmsize
    add         r4, mmsize/8
    dec         r6
    jg .loop
    RET

;-----------------------------------------------------------------------------
; void deblock_h_chroma( uint16_t *pix, intptr_t stride, int alpha, int beta, int8_t *tc0 )
;-----------------------------------------------------------------------------
cglobal deblock_h_chroma, 5,7,8
    add         r1, r1
    mov         r5, 32/mmsize
%if mmsize == 16
    lea         r6, [r1*3]
%endif
.loop:
    CHROMA_H_LOAD r6
    call        deblock_inter_body
    CHROMA_H_STORE r6
    lea         r0, [r0+r1*(mmsize/4)]
    add         r4, mmsize/8
    dec         r5
    jg .loop
    RET


cglobal deblock_intra_body
    LOAD_AB     m4, m5, r2d, r3d
    LOAD_MASK   m0, m1, m2, m3, m4, m5, m7, m6, m4
    CHROMA_DEBLOCK_P0_Q0_INTRA m1, m2, m0, m3, m7, m5, m6
    ret

;-----------------------------------------------------------------------------
; void deblock_v_chroma_intra( uint16_t *pix, intptr_t stride, int alpha, int beta )
;-----------------------------------------------------------------------------
cglobal deblock_v_chroma_intra, 4,6,8
    add         r1, r1
    mov         r5, 32/mmsize
    movd        m5, r3d
    mov         r4, r0
    sub         r0, r1
    sub         r0, r1
    SPLATW      m5, m5
.loop:
    CHROMA_V_LOAD r4
    call        deblock_intra_body
    CHROMA_V_STORE
    add         r0, mmsize
    add         r4, mmsize
    dec         r5
    jg .loop
    RET

;-----------------------------------------------------------------------------
; void deblock_h_chroma_intra( uint16_t *pix, intptr_t stride, int alpha, int beta )
;-----------------------------------------------------------------------------
cglobal deblock_h_chroma_intra, 4,6,8
    add         r1, r1
    mov         r4, 32/mmsize
%if mmsize == 16
    lea         r5, [r1*3]
%endif
.loop:
    CHROMA_H_LOAD r5
    call        deblock_intra_body
    CHROMA_H_STORE r5
    lea         r0, [r0+r1*(mmsize/4)]
    dec         r4
    jg .loop
    RET

;-----------------------------------------------------------------------------
; void deblock_h_chroma_intra_mbaff( uint16_t *pix, intptr_t stride, int alpha, int beta )
;-----------------------------------------------------------------------------
cglobal deblock_h_chroma_intra_mbaff, 4,6,8
    add         r1, r1
%if mmsize == 8
    mov         r4, 16/mmsize
.loop:
%else
    lea         r5, [r1*3]
%endif
    CHROMA_H_LOAD r5
    LOAD_AB     m4, m5, r2d, r3d
    LOAD_MASK   m0, m1, m2, m3, m4, m5, m7, m6, m4
    CHROMA_DEBLOCK_P0_Q0_INTRA m1, m2, m0, m3, m7, m5, m6
    CHROMA_H_STORE r5
%if mmsize == 8
    lea         r0, [r0+r1*(mmsize/4)]
    dec         r4
    jg .loop
%endif
    RET

;-----------------------------------------------------------------------------
; void deblock_h_chroma_mbaff( uint16_t *pix, intptr_t stride, int alpha, int beta, int8_t *tc0 )
;-----------------------------------------------------------------------------
cglobal deblock_h_chroma_mbaff, 5,7,8
    add         r1, r1
    lea         r6, [r1*3]
%if mmsize == 8
    mov         r5, 16/mmsize
.loop:
%endif
    CHROMA_H_LOAD r6
    LOAD_AB     m4, m5, r2d, r3d
    LOAD_MASK   m0, m1, m2, m3, m4, m5, m7, m6, m4
    movd      m6, [r4]
    punpcklbw m6, m6
    psraw m6, 8
    punpcklwd m6, m6
    pxor      m4, m4
    pmaxsw    m6, m4
    pand m7, m6
    DEBLOCK_P0_Q0 m1, m2, m0, m3, m7, m5, m6
    CHROMA_H_STORE r6
%if mmsize == 8
    lea         r0, [r0+r1*(mmsize/4)]
    add         r4, mmsize/4
    dec         r5
    jg .loop
%endif
    RET

;-----------------------------------------------------------------------------
; void deblock_h_chroma_422_intra( uint16_t *pix, intptr_t stride, int alpha, int beta )
;-----------------------------------------------------------------------------
cglobal deblock_h_chroma_422_intra, 4,6,8
    add         r1, r1
    mov         r4, 64/mmsize
%if mmsize == 16
    lea         r5, [r1*3]
%endif
.loop:
    CHROMA_H_LOAD r5
    call        deblock_intra_body
    CHROMA_H_STORE r5
    lea         r0, [r0+r1*(mmsize/4)]
    dec         r4
    jg .loop
    RET

;-----------------------------------------------------------------------------
; void deblock_h_chroma_422( uint16_t *pix, intptr_t stride, int alpha, int beta, int8_t *tc0 )
;-----------------------------------------------------------------------------
cglobal deblock_h_chroma_422, 5,7,8
    add         r1, r1
    mov         r5, 64/mmsize
    lea         r6, [r1*3]
.loop:
    CHROMA_H_LOAD r6
    LOAD_AB     m4, m5, r2m, r3d
    LOAD_MASK   m0, m1, m2, m3, m4, m5, m7, m6, m4
    pxor        m4, m4
    movd        m6, [r4-1]
    psraw       m6, 8
    SPLATW      m6, m6
    pmaxsw      m6, m4
    pand        m7, m6
    DEBLOCK_P0_Q0 m1, m2, m0, m3, m7, m5, m6
    CHROMA_H_STORE r6
    lea         r0, [r0+r1*(mmsize/4)]
%if mmsize == 16
    inc         r4
%else
    mov         r2, r5
    and         r2, 1
    add         r4, r2 ; increment once every 2 iterations
%endif
    dec         r5
    jg .loop
    RET
%endmacro ; DEBLOCK_CHROMA

%if ARCH_X86_64 == 0
INIT_MMX mmx2
DEBLOCK_CHROMA
%endif
INIT_XMM sse2
DEBLOCK_CHROMA
INIT_XMM avx
DEBLOCK_CHROMA

%if ARCH_X86_64
;-----------------------------------------------------------------------------
; 10-bit chroma, AVX2. h does 8 rows per pass with rows 0-3 in lane 0 and
; rows 4-7 in lane 1, so each lane has the xmm layout (a row's u,v pair per
; dword); v does the whole 16 word edge at once.
;-----------------------------------------------------------------------------
; in: %1=3*stride, %2=r0+4*stride
; out: m0=p1, m1=p0, m2=q0, m3=q1
%macro CHROMA_H_LOAD_AVX2 2
    movu         xm0, [r0-8]           ; p1 p1 p0 p0 q0 q0 q1 q1
    movu         xm1, [r0+r1-8]
    movu         xm2, [r0+r1*2-8]
    movu         xm3, [r0+%1-8]
    vinserti128   m0, m0, [%2-8], 1
    vinserti128   m1, m1, [%2+r1-8], 1
    vinserti128   m2, m2, [%2+r1*2-8], 1
    vinserti128   m3, m3, [%2+%1-8], 1
    TRANSPOSE4x4D 0, 1, 2, 3, 7
%endmacro

; clobbers: m1, m2, m3
%macro CHROMA_H_STORE_AVX2 2
    SBUTTERFLY   dq, 1, 2, 3
    movq         [r0-4], xm1
    movhps       [r0+r1-4], xm1
    movq         [r0+r1*2-4], xm2
    movhps       [r0+%1-4], xm2
    vextracti128 xm1, m1, 1
    vextracti128 xm2, m2, 1
    movq         [%2-4], xm1
    movhps       [%2+r1-4], xm1
    movq         [%2+r1*2-4], xm2
    movhps       [%2+%1-4], xm2
%endmacro

; out: m4=alpha, m5=beta
%macro CHROMA_AB_AVX2 0
    movd         xm4, r2d
    movd         xm5, r3d
    vpbroadcastw  m4, xm4
    vpbroadcastw  m5, xm5
%endmacro

INIT_YMM avx2
;-----------------------------------------------------------------------------
; void deblock_v_chroma( uint16_t *pix, intptr_t stride, int alpha, int beta, int8_t *tc0 )
;-----------------------------------------------------------------------------
cglobal deblock_v_chroma, 5,5,8
    add          r1, r1
    CHROMA_AB_AVX2
    lea          r2, [r1*3]
    sub          r0, r1
    sub          r0, r1
    movu         m0, [r0]      ; p1
    movu         m1, [r0+r1]   ; p0
    movu         m2, [r0+r1*2] ; q0
    movu         m3, [r0+r2]   ; q1
    LOAD_MASK    m0, m1, m2, m3, m4, m5, m7, m6, m4
    LOAD_TC      m6, r4
    pxor         m4, m4
    pmaxsw       m6, m4
    pand         m7, m6
    DEBLOCK_P0_Q0 m1, m2, m0, m3, m7, m5, m6
    movu    [r0+r1], m1
    movu  [r0+r1*2], m2
    RET

;-----------------------------------------------------------------------------
; void deblock_h_chroma( uint16_t *pix, intptr_t stride, int alpha, int beta, int8_t *tc0 )
;-----------------------------------------------------------------------------
cglobal deblock_h_chroma, 5,7,8
    add          r1, r1
    CHROMA_AB_AVX2
    lea          r5, [r1*3]
    lea          r6, [r0+r1*4]
    CHROMA_H_LOAD_AVX2 r5, r6
    LOAD_MASK    m0, m1, m2, m3, m4, m5, m7, m6, m4
    LOAD_TC      m6, r4        ; tc0[i] covers 2 rows
    pxor         m4, m4
    pmaxsw       m6, m4
    pand         m7, m6
    DEBLOCK_P0_Q0 m1, m2, m0, m3, m7, m5, m6
    CHROMA_H_STORE_AVX2 r5, r6
    RET

;-----------------------------------------------------------------------------
; void deblock_h_chroma_422( uint16_t *pix, intptr_t stride, int alpha, int beta, int8_t *tc0 )
;-----------------------------------------------------------------------------
cglobal deblock_h_chroma_422, 5,7,11
    add          r1, r1
    CHROMA_AB_AVX2
    LOAD_TC      m8, r4        ; qword i = tc0[i]
    pxor         m6, m6
    pmaxsw       m8, m6
    vpermq       m9, m8, q3322 ; rows 8-11 | 12-15
    vpermq       m8, m8, q1100 ; rows 0-3 | 4-7
    lea          r5, [r1*3]
    lea          r6, [r0+r1*4]
    mov          r4d, 2
.loop:
    CHROMA_H_LOAD_AVX2 r5, r6
    LOAD_MASK    m0, m1, m2, m3, m4, m5, m7, m6, m10
    pand         m7, m8
    DEBLOCK_P0_Q0 m1, m2, m0, m3, m7, m6, m10
    CHROMA_H_STORE_AVX2 r5, r6
    lea          r0, [r0+r1*8]
    lea          r6, [r6+r1*8]
    mova         m8, m9
    dec          r4d
    jg .loop
    RET

;-----------------------------------------------------------------------------
; void deblock_v_chroma_intra( uint16_t *pix, intptr_t stride, int alpha, int beta )
;-----------------------------------------------------------------------------
cglobal deblock_v_chroma_intra, 4,4,8
    add          r1, r1
    CHROMA_AB_AVX2
    lea          r2, [r1*3]
    sub          r0, r1
    sub          r0, r1
    movu         m0, [r0]      ; p1
    movu         m1, [r0+r1]   ; p0
    movu         m2, [r0+r1*2] ; q0
    movu         m3, [r0+r2]   ; q1
    LOAD_MASK    m0, m1, m2, m3, m4, m5, m7, m6, m4
    vpbroadcastd m4, [pw_2]
    CHROMA_DEBLOCK_P0_Q0_INTRA m1, m2, m0, m3, m7, m5, m6, m4
    movu    [r0+r1], m1
    movu  [r0+r1*2], m2
    RET

;-----------------------------------------------------------------------------
; void deblock_h_chroma_intra( uint16_t *pix, intptr_t stride, int alpha, int beta )
;-----------------------------------------------------------------------------
cglobal deblock_h_chroma_intra, 4,6,8
    add          r1, r1
    CHROMA_AB_AVX2
    lea          r4, [r1*3]
    lea          r5, [r0+r1*4]
    CHROMA_H_LOAD_AVX2 r4, r5
    LOAD_MASK    m0, m1, m2, m3, m4, m5, m7, m6, m4
    vpbroadcastd m4, [pw_2]
    CHROMA_DEBLOCK_P0_Q0_INTRA m1, m2, m0, m3, m7, m5, m6, m4
    CHROMA_H_STORE_AVX2 r4, r5
    RET

;-----------------------------------------------------------------------------
; void deblock_h_chroma_422_intra( uint16_t *pix, intptr_t stride, int alpha, int beta )
;-----------------------------------------------------------------------------
cglobal deblock_h_chroma_422_intra, 4,6,10
    add          r1, r1
    CHROMA_AB_AVX2
    vpbroadcastd m8, [pw_2]
    lea          r4, [r1*3]
    lea          r5, [r0+r1*4]
    mov          r2d, 2
.loop:
    CHROMA_H_LOAD_AVX2 r4, r5
    LOAD_MASK    m0, m1, m2, m3, m4, m5, m7, m6, m9
    CHROMA_DEBLOCK_P0_Q0_INTRA m1, m2, m0, m3, m7, m6, m9, m8
    CHROMA_H_STORE_AVX2 r4, r5
    lea          r0, [r0+r1*8]
    lea          r5, [r5+r1*8]
    dec          r2d
    jg .loop
    RET
%endif ; ARCH_X86_64

%if ARCH_X86_64
;-----------------------------------------------------------------------------
; 10-bit 4:2:2 h chroma, avx512icl: all 16 rows in one zmm pass, rows 4i..4i+3
; in lane i, so the dword transposes stay lane-local and lane i takes tc0[i].
;-----------------------------------------------------------------------------
; in: r5 = 3*stride, r6 = r0+4*stride, r7 = r0+8*stride, r8 = r0+12*stride
%macro CHROMA_H_LOAD_ZMM 0
    movu         xm0, [r0-8]
    movu         xm1, [r0+r1-8]
    movu         xm2, [r0+r1*2-8]
    movu         xm3, [r0+r5-8]
%assign %%i 1
%rep 3
%if %%i == 1
    %define %%b r6
%elif %%i == 2
    %define %%b r7
%else
    %define %%b r8
%endif
    vinserti32x4  m0, m0, [%%b-8], %%i
    vinserti32x4  m1, m1, [%%b+r1-8], %%i
    vinserti32x4  m2, m2, [%%b+r1*2-8], %%i
    vinserti32x4  m3, m3, [%%b+r5-8], %%i
%assign %%i %%i+1
%endrep
    TRANSPOSE4x4D 0, 1, 2, 3, 7
%endmacro

; in: m1 = p0', m2 = q0'
%macro CHROMA_H_STORE_ZMM 0
    SBUTTERFLY   dq, 1, 2, 3
    movq         [r0-4], xm1
    movhps       [r0+r1-4], xm1
    movq         [r0+r1*2-4], xm2
    movhps       [r0+r5-4], xm2
%assign %%i 1
%rep 3
%if %%i == 1
    %define %%b r6
%elif %%i == 2
    %define %%b r7
%else
    %define %%b r8
%endif
    vextracti32x4 xm3, m1, %%i
    vextracti32x4 xm4, m2, %%i
    movq         [%%b-4], xm3
    movhps       [%%b+r1-4], xm3
    movq         [%%b+r1*2-4], xm4
    movhps       [%%b+r5-4], xm4
%assign %%i %%i+1
%endrep
%endmacro

; in: m0-m3 = p1 p0 q0 q1, m4/m5 = alpha/beta; out: k1; clobbers m6-m8
%macro CHROMA_MASK_ICL 0
    psubw        m6, m1, m2
    psubw        m7, m0, m1
    psubw        m8, m3, m2
    pabsw        m6, m6
    pabsw        m7, m7
    pabsw        m8, m8
    pmaxsw       m7, m8
    vpcmpgtw     k1, m4, m6
    vpcmpgtw     k2, m5, m7
    kandd        k1, k1, k2
%endmacro

%macro CHROMA_H_START_ZMM 0
    add          r1, r1
    vpbroadcastw  m4, r2d
    vpbroadcastw  m5, r3d
    lea          r5, [r1*3]
    lea          r6, [r0+r1*4]
    lea          r7, [r0+r1*8]
    lea          r8, [r6+r1*8]
%endmacro

INIT_ZMM avx512icl
;-----------------------------------------------------------------------------
; void deblock_h_chroma_422( uint16_t *pix, intptr_t stride, int alpha, int beta, int8_t *tc0 )
;-----------------------------------------------------------------------------
cglobal deblock_h_chroma_422, 5,9,11
    CHROMA_H_START_ZMM
    vpbroadcastd m9, [r4]
    pshufb       m9, [chroma422_tc_shuf]
    psraw        m9, 8             ; lane i = tc0[i]
    CHROMA_H_LOAD_ZMM
    CHROMA_MASK_ICL
    vmovdqu16    m7 {k1}{z}, m9
    pxor         m6, m6
    pmaxsw       m7, m6
    vpbroadcastd m10, [pw_4]
    psubw        m8, m2, m1
    psubw        m4, m0, m3
    psllw        m8, 2
    paddw        m8, m4
    paddw        m8, m10
    psraw        m8, 3           ; ((q0-p0)*4 + p1-q1 + 4) >> 3
    psubw        m5, m6, m7
    pmaxsw       m8, m5
    pminsw       m8, m7
    vpbroadcastd m10, [pw_pixel_max]
    paddw        m1, m8
    psubw        m2, m8
    pmaxsw       m1, m6
    pmaxsw       m2, m6
    pminsw       m1, m10
    pminsw       m2, m10
    CHROMA_H_STORE_ZMM
    RET

;-----------------------------------------------------------------------------
; void deblock_h_chroma_422_intra( uint16_t *pix, intptr_t stride, int alpha, int beta )
;-----------------------------------------------------------------------------
cglobal deblock_h_chroma_422_intra, 4,9,11
    CHROMA_H_START_ZMM
    CHROMA_H_LOAD_ZMM
    CHROMA_MASK_ICL
    vpbroadcastd m9, [pw_2]
    paddw        m6, m0, m9
    paddw        m6, m3
    paddw        m7, m6, m2
    paddw        m6, m1
    paddw        m6, m0
    paddw        m7, m3
    psraw        m6, 2           ; (2*p1 + p0 + q1 + 2) >> 2
    psraw        m7, 2           ; (2*q1 + q0 + p1 + 2) >> 2
    vmovdqu16    m1 {k1}, m6
    vmovdqu16    m2 {k1}, m7
    CHROMA_H_STORE_ZMM
    RET
%endif ; ARCH_X86_64
%endif ; HIGH_BIT_DEPTH

%if HIGH_BIT_DEPTH == 0
%macro CHROMA_V_START 0
    mov    t5, r0
    sub    t5, r1
    sub    t5, r1
%if mmsize==8
    mov   dword r0m, 2
.loop:
%endif
%endmacro

%macro CHROMA_H_START 0
    sub    r0, 4
    lea    t6, [r1*3]
    mov    t5, r0
    add    r0, t6
%endmacro

%macro CHROMA_V_LOOP 1
%if mmsize==8
    add   r0, 8
    add   t5, 8
%if %1
    add   r4, 2
%endif
    dec   dword r0m
    jg .loop
%endif
%endmacro

%macro CHROMA_H_LOOP 1
%if mmsize==8
    lea   r0, [r0+r1*4]
    lea   t5, [t5+r1*4]
%if %1
    add   r4, 2
%endif
    dec   dword r0m
    jg .loop
%endif
%endmacro

%define t5 r5
%define t6 r6

%macro DEBLOCK_CHROMA 0
cglobal chroma_inter_body
    LOAD_MASK  r2d, r3d
    movd       m6, [r4] ; tc0
    punpcklbw  m6, m6
    punpcklbw  m6, m6
    pand       m7, m6
    DEBLOCK_P0_Q0
    ret

;-----------------------------------------------------------------------------
; void deblock_v_chroma( uint8_t *pix, intptr_t stride, int alpha, int beta, int8_t *tc0 )
;-----------------------------------------------------------------------------
cglobal deblock_v_chroma, 5,6,8
    CHROMA_V_START
    mova  m0, [t5]
    mova  m1, [t5+r1]
    mova  m2, [r0]
    mova  m3, [r0+r1]
    call chroma_inter_body
    mova  [t5+r1], m1
    mova  [r0], m2
    CHROMA_V_LOOP 1
    RET

;-----------------------------------------------------------------------------
; void deblock_h_chroma( uint8_t *pix, intptr_t stride, int alpha, int beta, int8_t *tc0 )
;-----------------------------------------------------------------------------
cglobal deblock_h_chroma, 5,7,8
    CHROMA_H_START
%if mmsize==8
    mov   dword r0m, 2
.loop:
%endif
    TRANSPOSE4x8W_LOAD PASS8ROWS(t5, r0, r1, t6)
    call chroma_inter_body
    TRANSPOSE8x2W_STORE PASS8ROWS(t5, r0, r1, t6, 2)
    CHROMA_H_LOOP 1
    RET
%endmacro ; DEBLOCK_CHROMA

INIT_XMM sse2
DEBLOCK_CHROMA
INIT_XMM avx
DEBLOCK_CHROMA
%if ARCH_X86_64 == 0
INIT_MMX mmx2
DEBLOCK_CHROMA
%endif

;-----------------------------------------------------------------------------
; void deblock_h_chroma_mbaff( uint8_t *pix, intptr_t stride, int alpha, int beta, int8_t *tc0 )
;-----------------------------------------------------------------------------
%macro DEBLOCK_H_CHROMA_420_MBAFF 0
cglobal deblock_h_chroma_mbaff, 5,7,8
    CHROMA_H_START
    TRANSPOSE4x4W_LOAD PASS8ROWS(t5, r0, r1, t6)
    LOAD_MASK  r2d, r3d
    movd       m6, [r4] ; tc0
    punpcklbw  m6, m6
    pand       m7, m6
    DEBLOCK_P0_Q0
    TRANSPOSE4x2W_STORE PASS8ROWS(t5, r0, r1, t6, 2)
    RET
%endmacro

INIT_XMM sse2
DEBLOCK_H_CHROMA_420_MBAFF
%if ARCH_X86_64 == 0
INIT_MMX mmx2
DEBLOCK_H_CHROMA_420_MBAFF
%endif

%macro DEBLOCK_H_CHROMA_422 0
cglobal deblock_h_chroma_422, 5,8,8
%if ARCH_X86_64
    %define cntr r7
%else
    %define cntr dword r0m
%endif
    CHROMA_H_START
    mov  cntr, 32/mmsize
.loop:
    TRANSPOSE4x8W_LOAD PASS8ROWS(t5, r0, r1, t6)
    LOAD_MASK  r2d, r3d
    movd       m6, [r4] ; tc0
    punpcklbw  m6, m6
%if mmsize == 16
    punpcklbw  m6, m6
    punpcklbw  m6, m6
%else
    pshufw     m6, m6, q0000
%endif
    pand       m7, m6
    DEBLOCK_P0_Q0
    TRANSPOSE8x2W_STORE PASS8ROWS(t5, r0, r1, t6, 2)
    lea   r0, [r0+r1*(mmsize/2)]
    lea   t5, [t5+r1*(mmsize/2)]
    add   r4, mmsize/8
    dec   cntr
    jg .loop
    RET
%endmacro

INIT_MMX mmx2
DEBLOCK_H_CHROMA_422
INIT_XMM sse2
DEBLOCK_H_CHROMA_422
INIT_XMM avx
DEBLOCK_H_CHROMA_422

; in: %1=p0 %2=p1 %3=q1
; out: p0 = (p0 + q1 + 2*p1 + 2) >> 2
%macro CHROMA_INTRA_P0 3
    pxor    m4, %1, %3
    pand    m4, [pb_1] ; m4 = (p0^q1)&1
    pavgb   %1, %3
    psubusb %1, m4
    pavgb   %1, %2     ; dst = avg(p1, avg(p0,q1) - ((p0^q1)&1))
%endmacro

%define t5 r4
%define t6 r5

%macro DEBLOCK_CHROMA_INTRA_BODY 0
cglobal chroma_intra_body
    LOAD_MASK r2d, r3d
    mova   m5, m1
    mova   m6, m2
    CHROMA_INTRA_P0  m1, m0, m3
    CHROMA_INTRA_P0  m2, m3, m0
%if cpuflag(avx)
    pblendvb m1, m5, m1, m7
    pblendvb m2, m6, m2, m7
%else
    psubb  m1, m5
    psubb  m2, m6
    pand   m1, m7
    pand   m2, m7
    paddb  m1, m5
    paddb  m2, m6
%endif
    ret
%endmacro

%macro DEBLOCK_CHROMA_INTRA 0
;-----------------------------------------------------------------------------
; void deblock_v_chroma_intra( uint8_t *pix, intptr_t stride, int alpha, int beta )
;-----------------------------------------------------------------------------
cglobal deblock_v_chroma_intra, 4,5,8
    CHROMA_V_START
    mova  m0, [t5]
    mova  m1, [t5+r1]
    mova  m2, [r0]
    mova  m3, [r0+r1]
    call chroma_intra_body
    mova  [t5+r1], m1
    mova  [r0], m2
    CHROMA_V_LOOP 0
    RET

;-----------------------------------------------------------------------------
; void deblock_h_chroma_intra( uint8_t *pix, intptr_t stride, int alpha, int beta )
;-----------------------------------------------------------------------------
cglobal deblock_h_chroma_intra, 4,6,8
    CHROMA_H_START
%if mmsize==8
    mov   dword r0m, 2
.loop:
%endif
    TRANSPOSE4x8W_LOAD  PASS8ROWS(t5, r0, r1, t6)
    call chroma_intra_body
    TRANSPOSE8x2W_STORE PASS8ROWS(t5, r0, r1, t6, 2)
    CHROMA_H_LOOP 0
    RET

cglobal deblock_h_chroma_422_intra, 4,7,8
    CHROMA_H_START
    mov   r6d, 32/mmsize
.loop:
    TRANSPOSE4x8W_LOAD  PASS8ROWS(t5, r0, r1, t6)
    call chroma_intra_body
    TRANSPOSE8x2W_STORE PASS8ROWS(t5, r0, r1, t6, 2)
    lea   r0, [r0+r1*(mmsize/2)]
    lea   t5, [t5+r1*(mmsize/2)]
    dec  r6d
    jg .loop
    RET
%endmacro ; DEBLOCK_CHROMA_INTRA

INIT_XMM sse2
DEBLOCK_CHROMA_INTRA_BODY
DEBLOCK_CHROMA_INTRA
INIT_XMM avx
DEBLOCK_CHROMA_INTRA_BODY
DEBLOCK_CHROMA_INTRA
INIT_MMX mmx2
DEBLOCK_CHROMA_INTRA_BODY
%if ARCH_X86_64 == 0
DEBLOCK_CHROMA_INTRA
%endif

;-----------------------------------------------------------------------------
; void deblock_h_chroma_intra_mbaff( uint8_t *pix, intptr_t stride, int alpha, int beta )
;-----------------------------------------------------------------------------
INIT_MMX mmx2
cglobal deblock_h_chroma_intra_mbaff, 4,6,8
    CHROMA_H_START
    TRANSPOSE4x4W_LOAD  PASS8ROWS(t5, r0, r1, t6)
    call chroma_intra_body
    TRANSPOSE4x2W_STORE PASS8ROWS(t5, r0, r1, t6, 2)
    RET
%endif ; !HIGH_BIT_DEPTH



;-----------------------------------------------------------------------------
; static void deblock_strength( uint8_t nnz[48], int8_t ref[2][40], int16_t mv[2][40][2],
;                               uint8_t bs[2][4][4], int mvy_limit, int bframe )
;-----------------------------------------------------------------------------

%define scan8start (4+1*8)
%define nnz r0+scan8start
%define ref r1+scan8start
%define mv  r2+scan8start*4
%define bs0 r3
%define bs1 r3+32

%macro LOAD_BYTES_MMX 1
    movd      m2, [%1+8*0-1]
    movd      m0, [%1+8*0]
    movd      m3, [%1+8*2-1]
    movd      m1, [%1+8*2]
    punpckldq m2, [%1+8*1-1]
    punpckldq m0, [%1+8*1]
    punpckldq m3, [%1+8*3-1]
    punpckldq m1, [%1+8*3]
%endmacro

%macro DEBLOCK_STRENGTH_REFS_MMX 0
    LOAD_BYTES_MMX ref
    pxor      m2, m0
    pxor      m3, m1
    por       m2, [bs0+0]
    por       m3, [bs0+8]
    movq [bs0+0], m2
    movq [bs0+8], m3

    movd      m2, [ref-8*1]
    movd      m3, [ref+8*1]
    punpckldq m2, m0  ; row -1, row 0
    punpckldq m3, m1  ; row  1, row 2
    pxor      m0, m2
    pxor      m1, m3
    por       m0, [bs1+0]
    por       m1, [bs1+8]
    movq [bs1+0], m0
    movq [bs1+8], m1
%endmacro

%macro DEBLOCK_STRENGTH_MVS_MMX 2
    mova      m0, [mv-%2]
    mova      m1, [mv-%2+8]
    psubw     m0, [mv]
    psubw     m1, [mv+8]
    packsswb  m0, m1
    ABSB      m0, m1
    psubusb   m0, m7
    packsswb  m0, m0
    por       m0, [%1]
    movd    [%1], m0
%endmacro

%macro DEBLOCK_STRENGTH_NNZ_MMX 1
    por       m2, m0
    por       m3, m1
    mova      m4, [%1]
    mova      m5, [%1+8]
    pminub    m2, m6
    pminub    m3, m6
    pminub    m4, m6 ; mv ? 1 : 0
    pminub    m5, m6
    paddb     m2, m2 ; nnz ? 2 : 0
    paddb     m3, m3
    pmaxub    m2, m4
    pmaxub    m3, m5
%endmacro

%macro LOAD_BYTES_XMM 1
    movu      m2, [%1-4] ; FIXME could be aligned if we changed nnz's allocation
    movu      m1, [%1+12]
    pslldq    m0, m2, 1
    shufps    m2, m1, q3131 ; cur nnz, all rows
    pslldq    m1, 1
    shufps    m0, m1, q3131 ; left neighbors
    pslldq    m1, m2, 4
    movd      m3, [%1-8] ; could be palignr if nnz was aligned
    por       m1, m3 ; top neighbors
%endmacro

INIT_MMX mmx2
cglobal deblock_strength, 6,6
    ; Prepare mv comparison register
    shl      r4d, 8
    add      r4d, 3 - (1<<8)
    movd      m7, r4d
    SPLATW    m7, m7
    mova      m6, [pb_1]
    pxor      m0, m0
    mova [bs0+0], m0
    mova [bs0+8], m0
    mova [bs1+0], m0
    mova [bs1+8], m0

.lists:
    DEBLOCK_STRENGTH_REFS_MMX
    mov      r4d, 4
.mvs:
    DEBLOCK_STRENGTH_MVS_MMX bs0, 4
    DEBLOCK_STRENGTH_MVS_MMX bs1, 4*8
    add       r2, 4*8
    add       r3, 4
    dec      r4d
    jg .mvs
    add       r1, 40
    add       r2, 4*8
    sub       r3, 16
    dec      r5d
    jge .lists

    ; Check nnz
    LOAD_BYTES_MMX nnz
    DEBLOCK_STRENGTH_NNZ_MMX bs0
    ; Transpose column output
    SBUTTERFLY bw, 2, 3, 4
    SBUTTERFLY bw, 2, 3, 4
    mova [bs0+0], m2
    mova [bs0+8], m3
    movd      m2, [nnz-8*1]
    movd      m3, [nnz+8*1]
    punpckldq m2, m0  ; row -1, row 0
    punpckldq m3, m1  ; row  1, row 2
    DEBLOCK_STRENGTH_NNZ_MMX bs1
    mova [bs1+0], m2
    mova [bs1+8], m3
    RET

%macro DEBLOCK_STRENGTH_XMM 0
cglobal deblock_strength, 6,6,7
    ; Prepare mv comparison register
    shl      r4d, 8
    add      r4d, 3 - (1<<8)
    movd      m6, r4d
    SPLATW    m6, m6
    pxor      m4, m4 ; bs0
    pxor      m5, m5 ; bs1

.lists:
    ; Check refs
    LOAD_BYTES_XMM ref
    pxor      m0, m2
    pxor      m1, m2
    por       m4, m0
    por       m5, m1

    ; Check mvs
%if cpuflag(ssse3)
    mova      m0, [mv+4*8*0]
    mova      m1, [mv+4*8*1]
    palignr   m3, m0, [mv+4*8*0-16], 12
    palignr   m2, m1, [mv+4*8*1-16], 12
    psubw     m0, m3
    psubw     m1, m2
    packsswb  m0, m1

    mova      m2, [mv+4*8*2]
    mova      m1, [mv+4*8*3]
    palignr   m3, m2, [mv+4*8*2-16], 12
    psubw     m2, m3
    palignr   m3, m1, [mv+4*8*3-16], 12
    psubw     m1, m3
    packsswb  m2, m1
%else
    movu      m0, [mv-4+4*8*0]
    movu      m1, [mv-4+4*8*1]
    movu      m2, [mv-4+4*8*2]
    movu      m3, [mv-4+4*8*3]
    psubw     m0, [mv+4*8*0]
    psubw     m1, [mv+4*8*1]
    psubw     m2, [mv+4*8*2]
    psubw     m3, [mv+4*8*3]
    packsswb  m0, m1
    packsswb  m2, m3
%endif
    ABSB      m0, m1
    ABSB      m2, m3
    psubusb   m0, m6
    psubusb   m2, m6
    packsswb  m0, m2
    por       m4, m0

    mova      m0, [mv+4*8*-1]
    mova      m1, [mv+4*8* 0]
    mova      m2, [mv+4*8* 1]
    mova      m3, [mv+4*8* 2]
    psubw     m0, m1
    psubw     m1, m2
    psubw     m2, m3
    psubw     m3, [mv+4*8* 3]
    packsswb  m0, m1
    packsswb  m2, m3
    ABSB      m0, m1
    ABSB      m2, m3
    psubusb   m0, m6
    psubusb   m2, m6
    packsswb  m0, m2
    por       m5, m0
    add       r1, 40
    add       r2, 4*8*5
    dec      r5d
    jge .lists

    ; Check nnz
    LOAD_BYTES_XMM nnz
    por       m0, m2
    por       m1, m2
    mova      m6, [pb_1]
    pminub    m0, m6
    pminub    m1, m6
    pminub    m4, m6 ; mv ? 1 : 0
    pminub    m5, m6
    paddb     m0, m0 ; nnz ? 2 : 0
    paddb     m1, m1
    pmaxub    m4, m0
    pmaxub    m5, m1
%if cpuflag(ssse3)
    pshufb    m4, [transpose_shuf]
%else
    movhlps   m3, m4
    punpcklbw m4, m3
    movhlps   m3, m4
    punpcklbw m4, m3
%endif
    mova   [bs1], m5
    mova   [bs0], m4
    RET
%endmacro

INIT_XMM sse2
DEBLOCK_STRENGTH_XMM
INIT_XMM ssse3
DEBLOCK_STRENGTH_XMM
INIT_XMM avx
DEBLOCK_STRENGTH_XMM

%macro LOAD_BYTES_YMM 1
    movu         m0, [%1-4]             ; ___E FGHI ___J KLMN ___O PQRS ___T UVWX
    pshufb       m0, [load_bytes_shuf]  ; EFGH JKLM FGHI KLMN OPQR TUVW PQRS UVWX
    mova         m2, [insert_top_shuf]
    vpermq       m1, m0, q3131          ; FGHI KLMN PQRS UVWX x2
    vpermd       m0, m2, m0             ; EFGH JKLM OPQR TUVW ____ FGHI KLMN PQRS
    vpbroadcastd m2, [%1-8]             ; ABCD ....
    vpblendd     m0, m0, m2, 00010000b  ; EFGH JKLM OPQR TUVW ABCD FGHI KLMN PQRS
%endmacro

INIT_YMM avx2
cglobal deblock_strength, 6,6,7
    ; Prepare mv comparison register
    shl      r4d, 8
    add      r4d, 3 - (1<<8)
    movd     xm6, r4d
    vpbroadcastw m6, xm6
    pxor      m5, m5 ; bs0,bs1

.lists:
    ; Check refs
    LOAD_BYTES_YMM ref
    pxor      m0, m1
    por       m5, m0

    ; Check mvs
    movu     xm0, [mv-4+4*8*0]
    vinserti128 m0, m0, [mv+4*8*-1], 1
    vbroadcasti128  m2, [mv+4*8* 0]
    vinserti128 m1, m2, [mv-4+4*8*1], 0
    vbroadcasti128  m3, [mv+4*8* 1]
    psubw     m0, m2
    psubw     m1, m3

    vinserti128 m2, m3, [mv-4+4*8*2], 0
    vbroadcasti128  m4, [mv+4*8* 2]
    vinserti128 m3, m4, [mv-4+4*8*3], 0
    psubw     m2, m4
    vbroadcasti128  m4, [mv+4*8* 3]
    psubw     m3, m4
    packsswb  m0, m1
    packsswb  m2, m3
    pabsb     m0, m0
    pabsb     m2, m2
    psubusb   m0, m6
    psubusb   m2, m6
    packsswb  m0, m2
    por       m5, m0

    add       r1, 40
    add       r2, 4*8*5
    dec      r5d
    jge .lists

    ; Check nnz
    LOAD_BYTES_YMM nnz
    por       m0, m1
    mova      m6, [pb_1]
    pminub    m0, m6
    pminub    m5, m6 ; mv ? 1 : 0
    paddb     m0, m0 ; nnz ? 2 : 0
    pmaxub    m5, m0
    vextracti128 [bs1], m5, 1
    pshufb   xm5, [transpose_shuf]
    mova   [bs0], xm5
    RET

%if UNIX64
    DECLARE_REG_TMP 5
%else
    DECLARE_REG_TMP 4
%endif

%macro LOAD_BYTES_ZMM 1
    vpermd m1, m6, [%1-12]
    pshufb m1, m7 ; EF FG GH HI JK KL LM MN OP PQ QR RS TU UV VW WX
%endmacro         ; AF BG CH DI FK GL HM IN KP LQ MR NS PU QV RW SX

INIT_ZMM avx512
cglobal deblock_strength, 5,5
    mova            m6, [load_bytes_zmm_shuf]
    shl            r4d, 8
    add            r4d, 3 - (1<<8)
    vpbroadcastw    m5, r4d
    mov            r4d, 0x34cc34cc ; {1,-1} * 11001100b
    kmovb           k1, r4d
    vpbroadcastd    m4, r4d
    movifnidn      t0d, r5m
    psrld           m7, m6, 4
    pxor           xm3, xm3

.lists:
    vbroadcasti64x2 m2,      [mv+32]
    vinserti64x2    m0, m2,  [mv-32], 2
    vbroadcasti64x2 m1,      [mv+ 0]
    vinserti64x2    m0, m0,  [mv- 4], 0
    vbroadcasti64x2 m1 {k1}, [mv+64]
    vinserti64x2    m0, m0,  [mv+60], 1
    psubw           m0, m1
    vinserti64x2    m1, m1,  [mv+28], 0
    vbroadcasti64x2 m2 {k1}, [mv+96]
    vinserti64x2    m1, m1,  [mv+92], 1
    psubw           m1, m2
    packsswb        m0, m1
    pabsb           m0, m0
    psubusb         m0, m5

    LOAD_BYTES_ZMM ref
    pmaddubsw       m1, m4           ; E-F F-G G-H H-I ...
    vpternlogd      m3, m0, m1, 0xfe ; m3 | m0 | m1
    add             r1, 40
    add             r2, 4*8*5
    dec            t0d
    jge .lists

    LOAD_BYTES_ZMM nnz
    mova           ym2, [pb_1]
    vptestmw        k1, m1, m1
    vptestmw        k2, m3, m3
    vpaddb         ym0 {k1}{z}, ym2, ym2 ; nnz ? 2 : 0
    vpmaxub        ym0 {k2}, ym2         ; mv  ? 1 : 0
    vextracti128 [bs1], ym0, 1
    pshufb         xm0, [transpose_shuf]
    mova         [bs0], xm0
    RET

; avx512icl: vpermb gathers the cur/left/top ref and nnz bytes
%if ARCH_X86_64
INIT_YMM avx512icl
cglobal deblock_strength, 6,6,9
    shl            r4d, 8
    add            r4d, 3 - (1<<8)
    vpbroadcastw    m5, r4d
    mov            r4d, 0xffff0000
    kmovd           k1, r4d
    mova            m6, [strength_cur_idx]
    mova            m7, [strength_nb_idx]
    pxor           xm8, xm8

.lists:
    movu            m1, [ref-4]
    vpermb          m0, m6, m1
    vpermb          m2, m7, m1
    vpermb          m2 {k1}, m7, [ref-8]
    vpternlogd      m8, m0, m2, 0xf6 ; m8 | (cur ^ nb)

    movu           xm0, [mv-4+4*8*0]
    vinserti128     m0, m0, [mv+4*8*-1], 1
    vbroadcasti128  m2, [mv+4*8* 0]
    vinserti128     m1, m2, [mv-4+4*8*1], 0
    vbroadcasti128  m3, [mv+4*8* 1]
    psubw           m0, m2
    psubw           m1, m3
    vinserti128     m2, m3, [mv-4+4*8*2], 0
    vbroadcasti128  m4, [mv+4*8* 2]
    vinserti128     m3, m4, [mv-4+4*8*3], 0
    psubw           m2, m4
    vbroadcasti128  m4, [mv+4*8* 3]
    psubw           m3, m4
    packsswb        m0, m1
    packsswb        m2, m3
    pabsb           m0, m0
    pabsb           m2, m2
    psubusb         m0, m5
    psubusb         m2, m5
    packsswb        m0, m2
    por             m8, m0

    add             r1, 40
    add             r2, 4*8*5
    dec            r5d
    jge .lists

    movu            m1, [nnz-4]
    vpermb          m0, m6, m1
    vpermb          m2, m7, m1
    vpermb          m2 {k1}, m7, [nnz-8]
    mova            m3, [pb_1]
    por             m0, m2
    pminub          m8, m3           ; mv ? 1 : 0
    vptestmb        k2, m0, m0
    paddb           m8 {k2}, m3, m3  ; nnz ? 2
    vextracti128 [bs1], m8, 1
    pshufb         xm8, [transpose_shuf]
    mova         [bs0], xm8
    RET
%endif
