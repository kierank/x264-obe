;*****************************************************************************
;* lowres-a.asm: fused lowres analysis loops
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

%if HIGH_BIT_DEPTH == 0 && UNIX64

SECTION_RODATA 32

; pixel-a.asm's intra_satd_lowres tables
li_hmul_8p:    times 8 db 1
               times 4 db 1, -1
               times 8 db 1
               times 4 db 1, -1
li_dc_shufb:   db 0,0,0,0,1,1,1,1,0,0,0,0,1,1,1,1, 2,2,2,2,3,3,3,3,2,2,2,2,3,3,3,3
li_pw_17408:   times 16 dw 17408 ; pmulhrsw: (17*x+16)>>5
li_p_x:        times 2 dw -3, -2, -1, 0, 1, 2, 3, 4
li_p_y:        times 8 dw -3
               times 8 dw 1
li_shuf_ul:    times 2 db 0, 1, 2, 3, 4, 8, 7, 7, 8, 9,10,11,12,13,14,15
li_shuf_t2:    times 2 db 1, 2, 3, 4, 5, 6, 7, 8, 9,10,11,12,13,14,15,15
li_p_wh:       db -4,-3,-2,-1, 0, 1, 2, 3, 4, 0, 0, 0, 0, 0, 0, 0
li_p_wv:       db  0, 0, 0, 0, 0, 0, 0, 4, 3, 2, 1, 0,-1,-2,-3,-4
li_p_wa:       db  0, 0, 0, 0, 0, 0, 0,16,16, 0, 0, 0, 0, 0, 0, 0
ALIGN 32
li_h0:         times 16 db 15
               times 16 db 11
li_h1:         times 16 db 14
               times 16 db 10
li_h2:         times 16 db 13
               times 16 db  9
li_h3:         times 16 db 12
               times 16 db  8
; rows (k, k+4) of the x9 predictions, each row twice
li_ddl0:       db  1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8
               db  5, 6, 7, 8, 9,10,11,12, 5, 6, 7, 8, 9,10,11,12
li_ddl1:       db  2, 3, 4, 5, 6, 7, 8, 9, 2, 3, 4, 5, 6, 7, 8, 9
               db  6, 7, 8, 9,10,11,12,13, 6, 7, 8, 9,10,11,12,13
li_ddl2:       db  3, 4, 5, 6, 7, 8, 9,10, 3, 4, 5, 6, 7, 8, 9,10
               db  7, 8, 9,10,11,12,13,14, 7, 8, 9,10,11,12,13,14
li_ddl3:       db  4, 5, 6, 7, 8, 9,10,11, 4, 5, 6, 7, 8, 9,10,11
               db  8, 9,10,11,12,13,14,15, 8, 9,10,11,12,13,14,15
li_vl0:        db  0, 1, 2, 3, 4, 5, 6, 7, 0, 1, 2, 3, 4, 5, 6, 7
               db  2, 3, 4, 5, 6, 7, 8, 9, 2, 3, 4, 5, 6, 7, 8, 9
li_vl1:        db  1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8
               db  3, 4, 5, 6, 7, 8, 9,10, 3, 4, 5, 6, 7, 8, 9,10
li_vl2:        db  1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8
               db  3, 4, 5, 6, 7, 8, 9,10, 3, 4, 5, 6, 7, 8, 9,10
li_vl3:        db  2, 3, 4, 5, 6, 7, 8, 9, 2, 3, 4, 5, 6, 7, 8, 9
               db  4, 5, 6, 7, 8, 9,10,11, 4, 5, 6, 7, 8, 9,10,11
li_ddr0:       db  8, 9,10,11,12,13,14,15, 8, 9,10,11,12,13,14,15
               db  4, 5, 6, 7, 8, 9,10,11, 4, 5, 6, 7, 8, 9,10,11
li_ddr1:       db  7, 8, 9,10,11,12,13,14, 7, 8, 9,10,11,12,13,14
               db  3, 4, 5, 6, 7, 8, 9,10, 3, 4, 5, 6, 7, 8, 9,10
li_ddr2:       db  6, 7, 8, 9,10,11,12,13, 6, 7, 8, 9,10,11,12,13
               db  2, 3, 4, 5, 6, 7, 8, 9, 2, 3, 4, 5, 6, 7, 8, 9
li_ddr3:       db  5, 6, 7, 8, 9,10,11,12, 5, 6, 7, 8, 9,10,11,12
               db  1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8
li_vr0:        db  8, 9,10,11,12,13,14,15, 8, 9,10,11,12,13,14,15
               db  5, 7, 8, 9,10,11,12,13, 5, 7, 8, 9,10,11,12,13
li_vr1:        db  8, 9,10,11,12,13,14,15, 8, 9,10,11,12,13,14,15
               db  4, 6, 8, 9,10,11,12,13, 4, 6, 8, 9,10,11,12,13
li_vr2:        db  7, 8, 9,10,11,12,13,14, 7, 8, 9,10,11,12,13,14
               db  3, 5, 7, 8, 9,10,11,12, 3, 5, 7, 8, 9,10,11,12
li_vr3:        db  6, 8, 9,10,11,12,13,14, 6, 8, 9,10,11,12,13,14
               db  2, 4, 6, 8, 9,10,11,12, 2, 4, 6, 8, 9,10,11,12
li_hd0:        db  3, 8, 9,10,11,12,13,14, 3, 8, 9,10,11,12,13,14
               db  7, 8, 9,10,11,12,13,14, 7, 8, 9,10,11,12,13,14
li_hd1:        db  2, 7, 3, 8, 9,10,11,12, 2, 7, 3, 8, 9,10,11,12
               db  5, 6, 7, 8, 9,10,11,12, 5, 6, 7, 8, 9,10,11,12
li_hd2:        db  1, 6, 2, 7, 3, 8, 9,10, 1, 6, 2, 7, 3, 8, 9,10
               db  3, 4, 5, 6, 7, 8, 9,10, 3, 4, 5, 6, 7, 8, 9,10
li_hd3:        db  0, 5, 1, 6, 2, 7, 3, 8, 0, 5, 1, 6, 2, 7, 3, 8
               db  1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8
li_hu0:        db 13,12,11,10, 9, 8, 7, 6,13,12,11,10, 9, 8, 7, 6
               db  5, 4, 3, 2, 1, 0,15,15, 5, 4, 3, 2, 1, 0,15,15
li_hu1:        db 11,10, 9, 8, 7, 6, 5, 4,11,10, 9, 8, 7, 6, 5, 4
               db  3, 2, 1, 0,15,15,15,15, 3, 2, 1, 0,15,15,15,15
li_hu2:        db  9, 8, 7, 6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2
               db  1, 0,15,15,15,15,15,15, 1, 0,15,15,15,15,15,15
li_hu3:        db  7, 6, 5, 4, 3, 2, 1, 0, 7, 6, 5, 4, 3, 2, 1, 0
               db 15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15

; x264_hpel_ref0, x264_hpel_ref1
li_hpel_ref:   db 0,1,1,1,0,1,1,1,2,3,3,3,0,1,1,1
               db 0,0,1,0,2,2,3,2,2,2,3,2,2,2,3,2

SECTION .text

cextern pb_1
cextern pw_1
cextern pw_4
cextern pw_16

%define TRANS TRANS_SSE4

; x264_lowres_i_t (encoder/lowres.h); the layout is checked in encoder/slicetype.c
struc lowres_i
    .fenc_pre:       resq 1
    .intra:          resq 1
    .fenc:           resq 1
    .intra_cost:     resq 1
    .costs:          resq 1
    .inv_qscale:     resq 1
    .output_inter:   resq 1
    .output_intra:   resq 1
    .corr_intra:     resq 1
    .stride:         resq 1
    .penalty:        resd 1
    .corr_intra_max: resd 1
    .mb_width:       resd 1
    .mb_height:      resd 1
    .slice_start:    resd 1
    .start_x:        resd 1
    .end_x:          resd 1
    .start_y:        resd 1
    .end_y:          resd 1
endstruc

; x264_lowres_b_t (encoder/lowres.h); the layout is checked in encoder/slicetype.c
struc lowres_b
    .fenc_pre:       resq 1
    .intra:          resq 1
    .bi:             resq 1
    .bi4:            resq 1
    .fenc:           resq 1
    .ref0:           resq 4
    .ref1:           resq 4
    .mvs:            resq 2
    .mv_costs:       resq 2
    .mvr:            resq 1
    .costs:          resq 1
    .intra_cost:     resq 1
    .inv_qscale:     resq 1
    .output_inter:   resq 1
    .output_intra:   resq 1
    .corr_intra:     resq 1
    .corr_inter:     resq 1
    .stride:         resq 1
    .lambda:         resd 1
    .dist_scale_factor: resd 1
    .bipred_weight:  resd 1
    .mv_range:       resd 1
    .mb_width:       resd 1
    .mb_height:      resd 1
    .slice_start:    resd 1
    .start_x:        resd 1
    .end_x:          resd 1
    .start_y:        resd 1
    .end_y:          resd 1
    .corr_intra_max: resd 1
    .corr_inter_max: resd 1
endstruc

; lowres_b_mbs stack: outgoing arguments, fenc_pre and the LI_REGS slots, locals
%assign LB_ARGS 0
%assign LB_PRE 32
%assign LB_ROW   LB_PRE+7*32
%assign LB_SCORE LB_ROW+4
%assign LB_XMIN  LB_ROW+8
%assign LB_XMAX  LB_ROW+12
%assign LB_YMIN  LB_ROW+16
%assign LB_YMAX  LB_ROW+20
%assign LB_BC    LB_ROW+24
%assign LB_LIST  LB_ROW+28
%assign LB_DMV0  LB_ROW+32
%assign LB_DMV1  LB_ROW+36
%assign LB_MV0   LB_ROW+40
%assign LB_MV1   LB_ROW+44
%assign LB_STACK (LB_ROW+48+31) & ~31

%macro PRED4x4_LOWPASS 5
    pavgb       %5, %2, %3
    pxor        %3, %2
    pand        %3, [pb_1]
    psubusb     %5, %3
    pavgb       %1, %4, %5
%endmacro

; %3 = per-lane interleave-and-add of %4, %5 at element size %2; %6 tmp
%macro HADD_ILV 6 ; w/d, size, dst, src1, src2, tmp
    punpckl%2   %6, %4, %5
    punpckh%2   %3, %4, %5
    padd%1      %3, %6
%endmacro

; pairwise max of the words of m%1, m%2 across the satd's last stage, into m%1
%macro LI_HMAX 4 ; a, b, 2*tmp
%if cpuflag(avx512icl)
    vpblendmw   m%3 {k1}, m%1, m%2
    vpshldd     m%2, m%1, m%2, 16
    pmaxsw      m%1, m%3, m%2
%else
    HADAMARD 1, max, %1, %2, %3, %4
%endif
%endmacro

; fenc_pre row pairs (k, k+4) and the per-MB constants of LI_SATD_FLAT: avx2 on the
; stack, avx512icl in m16-m22
%macro LI_REGS 1 ; stack offset of the avx2 slots (7*32 bytes)
%if cpuflag(avx512icl)
%define LI_FPRE0 m16
%define LI_FPRE1 m17
%define LI_FPRE2 m18
%define LI_FPRE3 m19
%define LI_HF0 m20
%define LI_A2  m21
%define LI_S13 m22
%else
%xdefine LI_FPRE0 [rsp+%1+0*32]
%xdefine LI_FPRE1 [rsp+%1+1*32]
%xdefine LI_FPRE2 [rsp+%1+2*32]
%xdefine LI_FPRE3 [rsp+%1+3*32]
%xdefine LI_HF0 [rsp+%1+4*32]
%xdefine LI_A2  [rsp+%1+5*32]
%xdefine LI_S13 [rsp+%1+6*32]
%endif
%endmacro

; m0-m3: the difference, 8-bit after the first (pmaddubsw) stage; m4, m5 tmp.
; %1 = words summing to the satd
%macro LI_SATD 1
    HADAMARD4_V  0, 1, 2, 3, 4
    ABSW2        m0, m2, m0, m2, m4, m5
    ABSW2        m1, m3, m1, m3, m4, m5
    LI_HMAX      0, 2, 4, 5
    LI_HMAX      1, 3, 4, 5
    paddw        %1, m0, m1
%endmacro

; LI_SATD of a prediction whose first stage m4 is the same in every row pair (V, DC):
; the vertical transform of (m4 - fenc_pre) is (4*m4 - HF0, -HF1, -HF2, -HF3), HF the
; transform of fenc_pre, exact in 16 bits; |HF2| and the max of |HF1|, |HF3| are per MB
%macro LI_SATD_FLAT 1
    psllw        m4, 2
    psubw        m0, m4, LI_HF0
    pabsw        m0, m0
%if cpuflag(avx512icl)
    vpblendmw    m4 {k1}, m0, LI_A2
    vpshldd      m2, m0, LI_A2, 16
    pmaxsw       m0, m4, m2
%else
    mova         m2, LI_A2
    LI_HMAX      0, 2, 4, 5
%endif
    paddw        %1, m0, LI_S13
%endmacro

; m0-m3 prediction rows (k, k+4), each row twice -> less fenc_pre's first stage
%macro LI_PRE8 0
    pmaddubsw    m0, m15
    pmaddubsw    m1, m15
    pmaddubsw    m2, m15
    pmaddubsw    m3, m15
    psubw        m0, LI_FPRE0
    psubw        m1, LI_FPRE1
    psubw        m2, LI_FPRE2
    psubw        m3, LI_FPRE3
%endmacro

%macro LI_SHUF8 5 ; tables suffix, 4*sources
    pshufb       m0, %2, [li_%1 %+ 0]
    pshufb       m1, %3, [li_%1 %+ 1]
    pshufb       m2, %4, [li_%1 %+ 2]
    pshufb       m3, %5, [li_%1 %+ 3]
    LI_PRE8
%endmacro

; 8 pixel rows %3 and %4 as [%3 %3 | %4 %4]
%macro LI_DUP8 4 ; dst, tmp, 2*mem
%if cpuflag(avx512icl)
    vpbroadcastq m%1, %3
    vpbroadcastq m%1 {k7}, %4
%else
    vpbroadcastq m%1, %3
    vpbroadcastq m%2, %4
    vpblendd     m%1, m%1, m%2, 0xf0
%endif
%endmacro

; fenc_pre of the 8x8 at r1 + r2 (r1 = src - stride, r2 = stride, r3 = 3*stride,
; r4 = r1 + 4*stride) into m0-m3 and LI_FPRE0-3; m15 = hmul_8p, avx512icl: k7
%macro LI_FENC_PRE 0
    ; fenc_pre: rows (k, k+4) of the plane's 8x8, first stage
    LI_DUP8      0, 4, [r1+r2],   [r4+r2]
    LI_DUP8      1, 5, [r1+2*r2], [r4+2*r2]
    LI_DUP8      2, 4, [r1+r3],   [r4+r3]
    LI_DUP8      3, 5, [r4],      [r4+4*r2]
    pmaddubsw    m0, m15
    pmaddubsw    m1, m15
    pmaddubsw    m2, m15
    pmaddubsw    m3, m15
    mova  LI_FPRE0, m0
    mova  LI_FPRE1, m1
    mova  LI_FPRE2, m2
    mova  LI_FPRE3, m3
%endmacro

;-----------------------------------------------------------------------------
; intra_satd_lowres of the 8x8 at r1 + r2 (r1 = src - stride, r2 = stride, r3 = 3*stride,
; r4 = r1 + 4*stride) from its fenc_pre in m0-m3 and LI_FPRE0-3, the per-MB constants
; computed here: the minimum in r6d. m15 = hmul_8p; avx512icl: k1-k6 as set in LI_KMASKS.
;-----------------------------------------------------------------------------
%macro LI_INTRA 0
    HADAMARD4_V  0, 1, 2, 3, 4
    mova      LI_HF0, m0
    pabsw        m2, m2
    mova       LI_A2, m2
    pabsw        m1, m1
    pabsw        m3, m3
    LI_HMAX      1, 3, 4, 5
    mova      LI_S13, m1

    movq        xm0, [r1+2*r2-8]
    punpcklbw   xm0, [r1+r2-8]
    movq        xm1, [r4-8]
    punpcklbw   xm1, [r1+r3-8]
    movq        xm2, [r4+2*r2-8]
    punpcklbw   xm2, [r4+r2-8]
    movq        xm3, [r4+4*r2-8]
    punpcklbw   xm3, [r4+r3-8]
    punpckhwd   xm1, xm0
    punpckhwd   xm3, xm2
    punpckhdq   xm3, xm1              ; l7..l0 in bytes 8-15
    vinserti128 m12, m3, xm3, 1
    vbroadcasti128 m11, [r1-1]        ; lt t0..t14
    vbroadcasti128 m10, [r1]          ; t0..t15
    ; edge E[i] = F2(U[i-1], U[i], U[i+1]), U = l7 l7 l6..l0 lt t0..t15 t15,
    ; in the bytes of predict_8x8_filter's edge: E6..E15 in m14, E16..E31 in m13
    palignr      m9, m11, m12, 1
    pshufb       m9, [li_shuf_ul]     ; U5..U15: l6 l7 l7 l6..l0 lt
    pslldq       m0, m9, 1
    palignr      m1, m10, m9, 1
    PRED4x4_LOWPASS m14, m0, m1, m9, m2
    pshufb       m0, m10, [li_shuf_t2]
    PRED4x4_LOWPASS m13, m11, m0, m10, m1

    ; v
    vpbroadcastq m4, [r1]
    pmaddubsw    m4, m15
    LI_SATD_FLAT m6
    ; h
    LI_SHUF8 h, m12, m12, m12, m12
    LI_SATD      m7
    HADD_ILV  w,  wd,  m6,  m6,  m7, m4 ; (v h) x4
    ; dc
%if cpuflag(avx512icl)
    vpblendmd   xm4 {k3}, xm10, xm12  ; t0..t7 l7..l0
    pmaddubsw   xm4, [pb_1]
    pmaddwd     xm4, [pw_1]
    packssdw    xm4, xm4              ; s0 s1 s3 s2
%else
    vpblendd    xm4, xm10, xm12, 0x0c ; t0..t7 l7..l0
    pmaddubsw   xm4, [pb_1]
    phaddw      xm4, xm4              ; s0 s1 s3 s2
%endif
    pshuflw     xm5, xm4, q1210
    pshuflw     xm4, xm4, q2213
    paddw       xm4, xm5              ; s0+s2 2*s1 2*s3 s1+s3
    paddw       xm4, [pw_4]
    psrlw       xm4, 3
    packuswb    xm4, xm4
    vpbroadcastd m4, xm4
    pshufb       m4, [li_dc_shufb]
    pmaddubsw    m4, m15
    LI_SATD_FLAT m7
    ; p: clip((a + 16 + b*(x-3) + c*(y-3)) >> 5)
    pmaddubsw   xm0, xm11, [li_p_wh]
    pmaddubsw   xm1, xm9, [li_p_wv]
%if cpuflag(avx512icl)
    vpblendmd   xm2 {k3}, xm10, xm12
    pmaddubsw   xm2, [li_p_wa]
    HADD_ILV  w, wd, xm0, xm0, xm1, xm3
    punpckldq   xm3, xm0, xm2
    punpckhdq   xm0, xm2
    paddw       xm0, xm3
    pshufd      xm3, xm0, q1032
    paddw       xm0, xm3              ; H V, words 2+3: 16*t7+16*l7
%else
    vpblendd    xm2, xm10, xm12, 0x0c
    pmaddubsw   xm2, [li_p_wa]
    phaddw      xm0, xm1
    phaddw      xm0, xm2
    phaddw      xm0, xm0              ; H V 16*t7 16*l7
%endif
    pmulhrsw    xm1, xm0, [li_pw_17408] ; b c
    pmaddwd     xm0, [pw_1]
    pshufd      xm0, xm0, q1111
    vpbroadcastw m0, xm0              ; a
    vpbroadcastw m2, xm1
    psrld       xm1, 16
    vpbroadcastw m4, xm1              ; c
    paddw        m0, [pw_16]
    pmullw       m2, [li_p_x]
    paddw        m0, m2
    pmullw       m2, m4, [li_p_y]
    paddw        m0, m2               ; rows 0 | 4
    paddw        m1, m0, m4
    paddw        m2, m1, m4
    paddw        m3, m2, m4
    psraw        m0, 5
    psraw        m1, 5
    psraw        m2, 5
    psraw        m3, 5
    packuswb     m0, m0
    packuswb     m1, m1
    packuswb     m2, m2
    packuswb     m3, m3
    LI_PRE8
    LI_SATD      m8
    HADD_ILV  w,  wd,  m7,  m7,  m8, m4 ; (dc p) x4
    HADD_ILV  w,  dq,  m6,  m6,  m7, m4 ; (v h dc p) x2

    ; ddl, vl
    pshufb      m10, m13, [li_shuf_t2] ; E17..E32
    pslldq      m11, m13, 1
    pavgb        m9, m13, m10
    PRED4x4_LOWPASS m12, m11, m10, m13, m0
    LI_SHUF8 ddl, m12, m12, m12, m12
    LI_SATD      m7
    LI_SHUF8 vl, m9, m12, m9, m12
    LI_SATD      m8
    HADD_ILV  w,  wd,  m7,  m7,  m8, m4 ; (ddl vl) x4
    ; ddr, vr
    palignr     m10, m13, m14, 8      ; E8..E23
    palignr     m11, m13, m14, 7      ; E7..E22
    palignr     m12, m13, m14, 6      ; E6..E21
    pavgb        m9, m10, m11
    PRED4x4_LOWPASS m11, m12, m10, m11, m0
    LI_SHUF8 ddr, m11, m11, m11, m11
    LI_SATD      m8
%if cpuflag(avx512icl)
    vpblendmd   m10 {k5}, m9, m11
%else
    vpblendd    m10, m9, m11, 0x33
%endif
    LI_SHUF8 vr, m10, m11, m10, m11
    LI_SATD     m12
    HADD_ILV  w,  wd,  m8,  m8, m12, m4 ; (ddr vr) x4
    HADD_ILV  w,  dq,  m7,  m7,  m8, m4 ; (ddl vl ddr vr) x2
    HADD_ILV  w, qdq,  m6,  m6,  m7, m4 ; v h dc p ddl vl ddr vr
    ; hd, hu
    pshufd      m10, m9, q0001
%if cpuflag(avx512icl)
    vpblendmd   m10 {k6}, m10, m11
    punpcklbw   m11, m9
    vpblendmd   m10 {k4}, m10, m11    ; rows 0-3 | rows 4-7
%else
    pblendw     m10, m11, q3330
    punpcklbw   m11, m9
    vpblendd    m10, m10, m11, 0xf0   ; rows 0-3 | rows 4-7
%endif
    LI_SHUF8 hd, m10, m10, m10, m10
    LI_SATD      m7
    pshufd      m10, m14, q1000
%if cpuflag(avx512icl)
    vpblendmw   m11 {k2}, m11, m10    ; E7 in byte 15
%else
    pblendw     m11, m11, m10, 0x80   ; E7 in byte 15
%endif
    LI_SHUF8 hu, m11, m11, m11, m11
    LI_SATD      m8
    HADD_ILV  w,  wd,  m7,  m7,  m8, m4 ; (hd hu) x4
    pshufd       m4, m7, q1032
    paddw        m7, m4
    pshufd       m4, m7, q2301
    paddw        m7, m4               ; hd hu hd hu

%if cpuflag(avx512icl)
    vinserti128  m0, m6, xm7, 1
    vshufi32x4   m1, m6, m7, 3
%else
    vperm2i128   m0, m6, m7, 0x20
    vperm2i128   m1, m6, m7, 0x31
%endif
    paddw        m0, m1
    vextracti128 xm1, m0, 1
    pminuw      xm0, xm1
%if cpuflag(avx512icl)
    pshufd      xm1, xm0, q1032
    pminuw      xm0, xm1
    pshuflw     xm1, xm0, q1032
    pminuw      xm0, xm1
    psrld       xm1, xm0, 16
    pminuw      xm0, xm1
%else
    phminposuw  xm0, xm0
%endif
    movd        r6d, xm0
    movzx       r6d, r6w
%endmacro

; k1 words 0x5555, k2 words 0x8080, k3-k6 dwords 0x0c 0xf0 0x33 0xee, k7 qwords 0xc
%macro LI_KMASKS 0
%if cpuflag(avx512icl)
    mov         r6d, 0x80805555
    kmovd        k1, r6d
    kshiftrd     k2, k1, 16
    mov         r6d, 0xee33f00c
    kmovd        k3, r6d
    kshiftrd     k4, k3, 8
    kshiftrd     k5, k3, 16
    kshiftrd     k6, k3, 24
    mov         r6d, 0xc
    kmovd        k7, r6d
%endif
%endmacro

;-----------------------------------------------------------------------------
; void lowres_i_mbs( x264_lowres_i_t *c )
;-----------------------------------------------------------------------------
; r0: c, r2: stride, r3: 3*stride, r5: mb_x, r7: mb_y, r8: mb_xy, r9: row, r10: score
%macro LOWRES_I_MBS 0
LI_REGS 0
cglobal lowres_i_mbs, 1,15,LI_NREGS, LI_STACK
    LI_KMASKS
    mova        m15, [li_hmul_8p]
    mov          r2, [r0+lowres_i.stride]
    lea          r3, [r2*3]
    mov         r7d, [r0+lowres_i.start_y]
    cmp         r7d, [r0+lowres_i.end_y]
    jl .end
.row:
    mov         r9d, r7d
    sub         r9d, [r0+lowres_i.slice_start]
    add         r9d, 4
    mov         r5d, [r0+lowres_i.start_x]
    cmp         r5d, [r0+lowres_i.end_x]
    jl .rownext
.col:
    mov         r8d, r7d
    imul        r8d, [r0+lowres_i.mb_width]
    add         r8d, r5d
    ; b_frame_score_mb
    xor        r10d, r10d
    mov        r11d, [r0+lowres_i.mb_width]
    mov        r12d, [r0+lowres_i.mb_height]
    cmp        r11d, 2
    jle .score1
    cmp        r12d, 2
    jle .score1
    test        r5d, r5d
    jle .score0
    dec        r11d
    cmp         r5d, r11d
    jge .score0
    test        r7d, r7d
    jle .score0
    dec        r12d
    cmp         r7d, r12d
    jge .score0
.score1:
    mov        r10d, 1
.score0:
    mov         r11, [r0+lowres_i.output_intra]
    test        r11, r11
    jz .inter
    ; the 8x8 at fenc + 8*(mb_x + mb_y*stride)
    movsxd       r1, r7d
    imul         r1, r2
    movsxd      r12, r5d
    add          r1, r12
    shl          r1, 3
    add          r1, [r0+lowres_i.fenc]
    sub          r1, r2
    lea          r4, [r1+4*r2]
    LI_FENC_PRE
    LI_INTRA
    mov        r12d, [r0+lowres_i.penalty]
    add         r6d, r12d
    ; the 8-bit lookahead's correction, floor penalty
    mov         r13, [r0+lowres_i.corr_intra]
    test        r13, r13
    jz .icorr
    mov        r14d, [r0+lowres_i.corr_intra_max]
    cmp         r6d, r14d
    cmovb      r14d, r6d
    movzx      r14d, byte [r13+r14]
    cmp        r12d, r6d
    cmovg      r12d, r6d
    sub         r6d, r14d
    cmp         r6d, r12d
    cmovl       r6d, r12d
.icorr:
    mov         r13, [r0+lowres_i.intra_cost]
    mov  [r13+r8*2], r6w
    mov        r12d, r6d
    mov         r13, [r0+lowres_i.inv_qscale]
    test        r13, r13
    jz .intranoaq
    movzx      r13d, word [r13+r8*2]
    imul       r12d, r13d
    add        r12d, 128
    sar        r12d, 8
.intranoaq:
    add  [r11+r9*4], r12d
    test       r10d, r10d
    jz .inter
    add        [r11], r6d
    add      [r11+4], r12d
.inter:
    ; every MB intra: the cost is i_intra_cost, clipped
    mov         r13, [r0+lowres_i.intra_cost]
    movzx       r6d, word [r13+r8*2]
    mov         r11, [r0+lowres_i.output_inter]
    add      [r11+8], r10d
    mov        r12d, (1<<14)-1         ; LOWRES_COST_MASK
    cmp         r6d, r12d
    cmova       r6d, r12d
    mov         r13, [r0+lowres_i.costs]
    mov  [r13+r8*2], r6w

    dec         r5d
    cmp         r5d, [r0+lowres_i.end_x]
    jge .col
.rownext:
    dec         r7d
    cmp         r7d, [r0+lowres_i.end_y]
    jge .row
.end:
    RET
%endmacro

; x264_mc_hpel_pair of the packed mv %5 over the planes at c+%6, at the MB (R14 = pel):
; %1 (%2 dword) = dst[0], %3 (%4 dword) = dst[1]; rax, rdi, R9-R11 clobbered
%macro LB_PAIR 6
    mov        R11d, %5
    movsx       R9d, R11w
    sar        R11d, 16
    mov         eax, R11d
    and         eax, 3
    mov        R10d, R9d
    and        R10d, 3
    lea         edi, [R10+rax*4]      ; qpel_idx
    sar        R11d, 2
    movsxd      R11, R11d
    imul        R11, rbp
    sar         R9d, 2
    movsxd       R9, R9d
    add         R11, R9
    add         R11, R14              ; pel + offset
    lea          R9, [li_hpel_ref]
    movzx        %2, byte [R9+rdi]
    mov          %1, [rbx+%6+%1*8]
    add          %1, R11
    xor          %4, %4
    cmp         eax, 3
    cmove        %3, rbp
    add          %1, %3
    test        edi, 5
    jz %%one
    movzx        %4, byte [R9+rdi+16]
    mov          %3, [rbx+%6+%3*8]
    add          %3, R11
    xor         eax, eax
    cmp        R10d, 3
    sete         al
    add          %3, rax
    jmp %%done
%%one:
    mov          %3, %1
%%done:
%endmacro

; TRY_BIDIR of the packed mvs %1, %2 (dwords), penalty %3*lambda
%macro LB_BIDIR 3
    LB_PAIR     rcx, ecx, R8, R8d, %2, lowres_b.ref1
    LB_PAIR     rsi, esi, rdx, edx, %1, lowres_b.ref0
    mov          R9, rbp
    mov         eax, [rbx+lowres_b.bipred_weight]
    mov  [rsp+LB_ARGS], rax
    lea         rdi, [rsp+LB_PRE]
    call [rbx+lowres_b.bi4]
%if %3
    mov         ecx, [rbx+lowres_b.lambda]
    lea         ecx, [rcx+rcx*4]
    add         eax, ecx
%endif
    cmp         eax, [rsp+LB_BC]
    jge %%no
    mov  [rsp+LB_BC], eax
    mov dword [rsp+LB_LIST], 3
%%no:
%endmacro

; %1 = x264_clip3( %1, [rsp+%2], [rsp+%3] ); %4 tmp
%macro LB_CLIP3 4
    mov          %4, %1
    cmp          %1, [rsp+%3]
    cmovg        %4, [rsp+%3]
    cmp          %1, [rsp+%2]
    cmovl        %4, [rsp+%2]
    mov          %1, %4
%endmacro

;-----------------------------------------------------------------------------
; void lowres_b_mbs( x264_lowres_b_t *c )
;-----------------------------------------------------------------------------
; rbx: c, rbp: stride, R12: mb_x, R13: mb_y, R14: pel offset, R15: mb_xy (callee-saved:
; satd_bi / satd_bi4 are called with the C ABI on fenc_pre at rsp+LB_PRE)
%macro LOWRES_B_MBS 0
cglobal lowres_b_mbs, 1,15,LI_NREGS, LB_STACK
    mov         rbx, r0
    mov         rbp, [rbx+lowres_b.stride]
    mov        R13d, [rbx+lowres_b.start_y]
    cmp        R13d, [rbx+lowres_b.end_y]
    jl .end
.row:
    ; y spel limits of slicetype_mb_cost
    mov         eax, R13d
    shl         eax, 5
    neg         eax
    sub         eax, 48
    mov         ecx, [rbx+lowres_b.mv_range]
    neg         ecx
    cmp         eax, ecx
    cmovl       eax, ecx
    mov  [rsp+LB_YMIN], eax
    mov         eax, [rbx+lowres_b.mb_height]
    sub         eax, R13d
    dec         eax
    shl         eax, 5
    add         eax, 48
    mov         ecx, [rbx+lowres_b.mv_range]
    dec         ecx
    cmp         eax, ecx
    cmovg       eax, ecx
    mov  [rsp+LB_YMAX], eax
    mov         eax, R13d
    sub         eax, [rbx+lowres_b.slice_start]
    add         eax, 4
    mov   [rsp+LB_ROW], eax
    mov        R12d, [rbx+lowres_b.start_x]
    cmp        R12d, [rbx+lowres_b.end_x]
    jl .rownext

.col:
    mov         eax, R13d
    imul        eax, [rbx+lowres_b.mb_width]
    add         eax, R12d
    mov        R15d, eax
    movsxd      rax, R13d
    imul        rax, rbp
    movsxd      rcx, R12d
    add         rax, rcx
    lea         R14, [rax*8]
    ; b_frame_score_mb
    xor         eax, eax
    mov         ecx, [rbx+lowres_b.mb_width]
    mov         edx, [rbx+lowres_b.mb_height]
    cmp         ecx, 2
    jle .score1
    cmp         edx, 2
    jle .score1
    test       R12d, R12d
    jle .score0
    dec         ecx
    cmp        R12d, ecx
    jge .score0
    test       R13d, R13d
    jle .score0
    dec         edx
    cmp        R13d, edx
    jge .score0
.score1:
    mov         eax, 1
.score0:
    mov [rsp+LB_SCORE], eax
    ; x spel limits
    mov         eax, R12d
    shl         eax, 5
    neg         eax
    sub         eax, 48
    mov         ecx, [rbx+lowres_b.mv_range]
    neg         ecx
    cmp         eax, ecx
    cmovl       eax, ecx
    mov  [rsp+LB_XMIN], eax
    mov         eax, [rbx+lowres_b.mb_width]
    sub         eax, R12d
    dec         eax
    shl         eax, 5
    add         eax, 48
    mov         ecx, [rbx+lowres_b.mv_range]
    dec         ecx
    cmp         eax, ecx
    cmovg       eax, ecx
    mov  [rsp+LB_XMAX], eax

    ; fenc_pre to rsp+LB_PRE
    LI_KMASKS
    mova        m15, [li_hmul_8p]
    mov          r2, rbp
    lea          r3, [rbp*3]
    mov          r1, [rbx+lowres_b.fenc]
    add          r1, R14
    sub          r1, r2
    lea          r4, [r1+4*r2]
    LI_FENC_PRE
%if cpuflag(avx512icl)
    mova [rsp+LB_PRE+0*32], m0
    mova [rsp+LB_PRE+1*32], m1
    mova [rsp+LB_PRE+2*32], m2
    mova [rsp+LB_PRE+3*32], m3
%endif

    mov dword [rsp+LB_BC], 1<<28      ; COST_MAX
    mov dword [rsp+LB_LIST], 0
    ; the scaled mvs of fref1, clipped
    xor         eax, eax
    xor         edx, edx
    mov         rsi, [rbx+lowres_b.mvr]
    test        rsi, rsi
    jz .dmv
    movsx       ecx, word [rsi+R15*4]
    movsx       R8d, word [rsi+R15*4+2]
    mov         R9d, [rbx+lowres_b.dist_scale_factor]
    mov         eax, ecx
    imul        eax, R9d
    add         eax, 128
    sar         eax, 8
    movsx       eax, ax               ; dmv[0][0]
    mov         edx, eax
    sub         edx, ecx
    movsx       edx, dx               ; dmv[1][0]
    LB_CLIP3    eax, LB_XMIN, LB_XMAX, R10d
    LB_CLIP3    edx, LB_XMIN, LB_XMAX, R10d
    mov        R10d, R8d
    imul       R10d, R9d
    add        R10d, 128
    sar        R10d, 8
    movsx      R10d, R10w             ; dmv[0][1]
    mov        R11d, R10d
    sub        R11d, R8d
    movsx      R11d, R11w             ; dmv[1][1]
    LB_CLIP3   R10d, LB_YMIN, LB_YMAX, ecx
    LB_CLIP3   R11d, LB_YMIN, LB_YMAX, ecx
    movzx       eax, ax
    shl        R10d, 16
    or          eax, R10d
    movzx       edx, dx
    shl        R11d, 16
    or          edx, R11d
.dmv:
    mov  [rsp+LB_DMV0], eax
    mov  [rsp+LB_DMV1], edx
    LB_BIDIR    [rsp+LB_DMV0], [rsp+LB_DMV1], 0
    mov         eax, [rsp+LB_DMV0]
    or          eax, [rsp+LB_DMV1]
    jz .lists
    ; mv 0
    lea         rdi, [rsp+LB_PRE]
    mov         rsi, [rbx+lowres_b.ref0]
    add         rsi, R14
    mov         rdx, rbp
    mov         rcx, [rbx+lowres_b.ref1]
    add         rcx, R14
    mov          R8, rbp
    mov         R9d, [rbx+lowres_b.bipred_weight]
    call [rbx+lowres_b.bi]
    cmp         eax, [rsp+LB_BC]
    jge .lists
    mov  [rsp+LB_BC], eax
    mov dword [rsp+LB_LIST], 3
.lists:
    mov         rsi, [rbx+lowres_b.mvs]
    mov         eax, [rsi+R15*4]
    mov   [rsp+LB_MV0], eax
    mov         rsi, [rbx+lowres_b.mvs+8]
    mov         eax, [rsi+R15*4]
    mov   [rsp+LB_MV1], eax
    mov         rsi, [rbx+lowres_b.mv_costs]
    mov         eax, [rsi+R15*4]
    cmp         eax, [rsp+LB_BC]
    jge .list1
    mov  [rsp+LB_BC], eax
    mov dword [rsp+LB_LIST], 1
.list1:
    mov         rsi, [rbx+lowres_b.mv_costs+8]
    mov         eax, [rsi+R15*4]
    cmp         eax, [rsp+LB_BC]
    jge .list2
    mov  [rsp+LB_BC], eax
    mov dword [rsp+LB_LIST], 2
.list2:
    mov         eax, [rsp+LB_MV0]
    or          eax, [rsp+LB_MV1]
    jz .intra
    LB_BIDIR    [rsp+LB_MV0], [rsp+LB_MV1], 5

.intra:
    mov         rsi, [rbx+lowres_b.output_intra]
    test        rsi, rsi
    jz .inter
    LI_KMASKS
    mova        m15, [li_hmul_8p]
    mova         m0, [rsp+LB_PRE+0*32]
    mova         m1, [rsp+LB_PRE+1*32]
    mova         m2, [rsp+LB_PRE+2*32]
    mova         m3, [rsp+LB_PRE+3*32]
%if cpuflag(avx512icl)
    mova   LI_FPRE0, m0
    mova   LI_FPRE1, m1
    mova   LI_FPRE2, m2
    mova   LI_FPRE3, m3
%endif
    mov          r2, rbp
    lea          r3, [rbp*3]
    mov          r1, [rbx+lowres_b.fenc]
    add          r1, R14
    sub          r1, r2
    lea          r4, [r1+4*r2]
    LI_INTRA
    mov         ecx, [rbx+lowres_b.lambda]
    lea         ecx, [rcx+rcx*4+4]
    add         eax, ecx
    ; the 8-bit lookahead's correction, floor 5*lambda + 4
    mov         rdx, [rbx+lowres_b.corr_intra]
    test        rdx, rdx
    jz .icorr
    mov         esi, [rbx+lowres_b.corr_intra_max]
    cmp         eax, esi
    cmovb       esi, eax
    movzx       esi, byte [rdx+rsi]
    cmp         ecx, eax
    cmovg       ecx, eax
    sub         eax, esi
    cmp         eax, ecx
    cmovl       eax, ecx
.icorr:
    mov         rcx, [rbx+lowres_b.intra_cost]
    mov  [rcx+R15*2], ax
    mov         ecx, eax
    mov         rdx, [rbx+lowres_b.inv_qscale]
    test        rdx, rdx
    jz .intranoaq
    movzx       edx, word [rdx+R15*2]
    imul        ecx, edx
    add         ecx, 128
    sar         ecx, 8
.intranoaq:
    mov         rdx, [rbx+lowres_b.output_intra]
    movsxd      rsi, dword [rsp+LB_ROW]
    add  [rdx+rsi*4], ecx
    cmp dword [rsp+LB_SCORE], 0
    je .inter
    add       [rdx], eax
    add     [rdx+4], ecx

.inter:
    mov         ecx, [rsp+LB_BC]
    add         ecx, 4
    ; the 8-bit lookahead's correction, floor 4
    mov         rdx, [rbx+lowres_b.corr_inter]
    test        rdx, rdx
    jz .bcorr
    mov         eax, [rbx+lowres_b.corr_inter_max]
    cmp         ecx, eax
    cmovb       eax, ecx
    movzx       eax, byte [rdx+rax]
    mov         edx, 4
    cmp         edx, ecx
    cmovg       edx, ecx
    sub         ecx, eax
    cmp         ecx, edx
    cmovl       ecx, edx
.bcorr:
    mov         eax, ecx
    mov         rsi, [rbx+lowres_b.inv_qscale]
    test        rsi, rsi
    jz .internoaq
    movzx       esi, word [rsi+R15*2]
    imul        eax, esi
    add         eax, 128
    sar         eax, 8
.internoaq:
    mov         rdx, [rbx+lowres_b.output_inter]
    movsxd      rsi, dword [rsp+LB_ROW]
    add  [rdx+rsi*4], eax
    cmp dword [rsp+LB_SCORE], 0
    je .noscore
    add       [rdx], ecx
    add     [rdx+4], eax
.noscore:
    mov         eax, (1<<14)-1        ; LOWRES_COST_MASK
    cmp         ecx, eax
    cmovl       eax, ecx
    mov         ecx, [rsp+LB_LIST]
    shl         ecx, 14
    add         eax, ecx
    mov         rdx, [rbx+lowres_b.costs]
    mov  [rdx+R15*2], ax

    dec        R12d
    cmp        R12d, [rbx+lowres_b.end_x]
    jge .col
.rownext:
    dec        R13d
    cmp        R13d, [rbx+lowres_b.end_y]
    jge .row
.end:
    RET
%endmacro

INIT_YMM avx2
%assign LI_STACK 7*32
%assign LI_NREGS 16
LOWRES_I_MBS
LI_REGS LB_PRE
LOWRES_B_MBS

INIT_YMM avx512icl
%assign LI_STACK 0
%assign LI_NREGS 23
LOWRES_I_MBS
LI_REGS LB_PRE
LOWRES_B_MBS

%endif ; !HIGH_BIT_DEPTH && UNIX64
