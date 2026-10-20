;*****************************************************************************
;* predict-a.asm: x86 intra prediction
;*****************************************************************************
;* Copyright (C) 2005-2014 x264 project
;*
;* Authors: Loren Merritt <lorenm@u.washington.edu>
;*          Holger Lubitz <holger@lubitz.org>
;*          Jason Garrett-Glaser <darkshikari@gmail.com>
;*          Henrik Gramner <henrik@gramner.com>
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

SECTION_RODATA 32

pw_43210123: times 2 dw -3, -2, -1, 0, 1, 2, 3, 4
pw_m3:       times 16 dw -3
pw_m7:       times 16 dw -7
pb_00s_ff:   times 8 db 0
pb_0s_ff:    times 7 db 0
             db 0xff
shuf_fixtr:  db 0, 1, 2, 3, 4, 5, 6, 7, 7, 7, 7, 7, 7, 7, 7, 7
shuf_nop:    db 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
shuf_hu:     db 7,6,5,4,3,2,1,0,0,0,0,0,0,0,0,0
shuf_vr:     db 2,4,6,8,9,10,11,12,13,14,15,0,1,3,5,7
pw_reverse:  db 14,15,12,13,10,11,8,9,6,7,4,5,2,3,0,1
%if HIGH_BIT_DEPTH == 0
ALIGN 16
pb_128:      times 16 db 0x80
%endif
%if HIGH_BIT_DEPTH
pb_p8x8c_rows:  times 8 db -3
                times 8 db -2
                times 8 db -1
                times 8 db 0
pb_p8x16c_rows: times 8 db -7
                times 8 db -6
                times 8 db -5
                times 8 db -4
%else
pb_p8c_rows:    times 8 db 0
                times 8 db 4
                times 8 db 1
                times 8 db 5
pb_p16_rows:    times 8 db 0
                times 8 db 2
                times 8 db 1
                times 8 db 3
%endif
%if HIGH_BIT_DEPTH
pw_ddl_icl:     dw 1,2,3,4,5,6,7,8,2,3,4,5,6,7,8,9
                dw 3,4,5,6,7,8,9,10,4,5,6,7,8,9,10,11
pw_ddr_icl:     dw 7,8,9,10,11,12,13,14,6,7,8,9,10,11,12,13
                dw 5,6,7,8,9,10,11,12,4,5,6,7,8,9,10,11
pw_vl_icl:      dw 0,1,2,3,4,5,6,7,33,34,35,36,37,38,39,40
                dw 1,2,3,4,5,6,7,8,34,35,36,37,38,39,40,41
pw_vr_icl:      dw 7,8,9,10,11,12,13,14,39,40,41,42,43,44,45,46
                dw 38,7,8,9,10,11,12,13,37,39,40,41,42,43,44,45
pw_vr4_icl:     dw 36,38,7,8,9,10,11,12,35,37,39,40,41,42,43,44
                dw 34,36,38,7,8,9,10,11,33,35,37,39,40,41,42,43
pw_hd_icl:      dw 7,39,40,41,42,43,44,45,6,38,7,39,40,41,42,43
                dw 5,37,6,38,7,39,40,41,4,36,5,37,6,38,7,39
pw_hd4_icl:     dw 3,35,4,36,5,37,6,38,2,34,3,35,4,36,5,37
                dw 1,33,2,34,3,35,4,36,0,32,1,33,2,34,3,35
pw_hu_icl:      dw 0,32,1,33,2,34,3,35,1,33,2,34,3,35,4,36
                dw 2,34,3,35,4,36,5,37,3,35,4,36,5,37,6,38
pw_hu_left:     dw 7,6,5,4,3,2,1,0,0,0,0,0,0,0,0,0
%else
pb_hd_icl:      db 1,65,2,66,3,67,4,68,5,69,6,70,7,71,72,73
                db 74,75,76,77,78,79,80,81,82,83,84,85,86,87,88,89
                db 0,64,1,65,2,66,3,67,4,68,5,69,6,70,7,71
                db 72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,87
pb_hu_icl:      db 0,64,1,65,2,66,3,67,4,68,5,69,6,70,7,71
                db 8,72,9,73,10,74,11,75,12,76,13,77,14,78,15,79
                db 1,65,2,66,3,67,4,68,5,69,6,70,7,71,8,72
                db 9,73,10,74,11,75,12,76,13,77,14,78,15,79,16,80
%endif
%if HIGH_BIT_DEPTH
pw_filt_left:   dw 27,31,31,27,23,19,15,11,7,3,35,36,0,0,0,0
                dw 31,31,27,23,19,15,11,7,3,35,36,0,0,0,0,0
                dw 31,27,23,19,15,11,7,3,35,36,0,0,0,0,0,0
pw_filt_fixtr:  dw 0,1,2,3,4,5,6,7,7,7,7,7,7,7,7,7
pw_filt_nop:    dw 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
pw_filt_r:      dw 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,15
pw_filt_l:      dw 0,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14
pq_rowpair_icl: dq 0, 8, 16, 24, 64, 72, 80, 88
%else
pb_filt_left:   db 55,63,63,55,47,39,31,23,15,7,71,72,0,0,0,0
pb_filt_r:      db 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,15
pb_filt_l:      db 0,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14
%endif
%if HIGH_BIT_DEPTH
pw_8x8h_icl:    times 8 dw 7
                times 8 dw 6
                times 8 dw 5
                times 8 dw 4
pq_rowquad_icl: dq 0, 8, 64, 72, 128, 136, 192, 200
%else
pb_8x8h_icl:    times 32 db 7
                times 32 db 6
%endif
%if HIGH_BIT_DEPTH == 0
pb_c_dc_icl:    times 4 db 0
                times 4 db 4
                times 24 db 0
                times 4 db 0
                times 4 db 4
                times 24 db 0
pb_c_left16_icl: db 7,15,23,31,39,47,55,63,71,79,87,95,103,111,119,127
pb_c_dc8_icl:   db 64,65,66,67,68,69,70,71,7,15,23,31,39,47,55,63
pd_c_dc16a_icl: dd 0,1,3,1,4,1,5,1
pd_c_dc16b_icl: dd 2,1,3,3,4,4,5,5
%endif
%if HIGH_BIT_DEPTH
pw_c_h_icl:     times 8 dw 3
                times 8 dw 7
                times 8 dw 11
                times 8 dw 15
pw_c_dc_icl:    dw 0,0,0,0,2,2,2,2
pw_c_dctop_icl: dw 0,0,0,0,4,4,4,4
pw_c_left16_icl: dw 3,7,11,15,19,23,27,31,35,39,43,47,51,55,59,63
pw_c_dc8_icl:   dw 32,33,34,35,36,37,38,39,3,7,11,15,19,23,27,31
pd_c_dc8a_icl:  dd 0,2,6,2,0,0,0,0
pd_c_dc8b_icl:  dd 4,2,6,6,0,0,0,0
pd_c_dc16a_icl: dd 0,2,6,2,8,2,10,2
pd_c_dc16b_icl: dd 4,2,6,6,8,8,10,10
%endif
%if HIGH_BIT_DEPTH
pw_e4_icl:       dw 15,15,11,7,3,23,24,25,26,27,28,29,30,31,31,31
                 dw 15,11,7,3,23,24,25,26,27,28,29,30,31,31,31,31
                 dw 11,7,3,23,24,25,26,27,28,29,30,31,31,31,31,31
pw_h4_icl:       dw 3,3,3,3,7,7,7,7,11,11,11,11,15,15,15,15
pw_dc4_icl:      dw 16,17,18,19,3,7,11,15,0,0,0,0,0,0,0,0,0,0,0,0
pq_rows4_icl:    dq 0, 64, 128, 192
pw_4x4_ddl_icl: dw 22,23,24,25,23,24,25,26,24,25,26,27,25,26,27,28
pw_4x4_ddr_icl: dw 20,21,22,23,19,20,21,22,18,19,20,21,17,18,19,20
pw_4x4_vr_icl: dw 5,6,7,8,20,21,22,23,19,5,6,7,18,20,21,22
pw_4x4_hd_icl: dw 4,20,21,22,3,19,4,20,2,18,3,19,1,17,2,18
pw_4x4_vl_icl: dw 6,7,8,9,22,23,24,25,7,8,9,10,23,24,25,26
pw_4x4_hu_icl: dw 3,18,2,17,2,17,1,16,1,16,0,0,0,0,0,0
%else
pb_e4_icl:       db 15,15,11,7,3,23,24,25,26,27,28,29,30,31,31,31
pb_h4_icl:       db 3,3,3,3,0,0,0,0,11,11,11,11,0,0,0,0
                 times 16 db 0
                 db 7,7,7,7,0,0,0,0,15,15,15,15,0,0,0,0
                 times 16 db 0
pb_dc4_icl:      db 16,17,18,19,3,7,11,15,0,0,0,0,0,0,0,0,0,0,0,0
pb_4x4_ddl_icl: db 70,71,72,73,0,0,0,0,72,73,74,75,0,0,0,0
                 db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                 db 71,72,73,74,0,0,0,0,73,74,75,76,0,0,0,0
                 db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
pb_4x4_ddr_icl: db 68,69,70,71,0,0,0,0,66,67,68,69,0,0,0,0
                 db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                 db 67,68,69,70,0,0,0,0,65,66,67,68,0,0,0,0
                 db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
pb_4x4_vr_icl: db 5,6,7,8,0,0,0,0,67,5,6,7,0,0,0,0
                 db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                 db 68,69,70,71,0,0,0,0,66,68,69,70,0,0,0,0
                 db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
pb_4x4_hd_icl: db 4,68,69,70,0,0,0,0,2,66,3,67,0,0,0,0
                 db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                 db 3,67,4,68,0,0,0,0,1,65,2,66,0,0,0,0
                 db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
pb_4x4_vl_icl: db 6,7,8,9,0,0,0,0,7,8,9,10,0,0,0,0
                 db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                 db 70,71,72,73,0,0,0,0,71,72,73,74,0,0,0,0
                 db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
pb_4x4_hu_icl: db 3,66,2,65,0,0,0,0,1,64,0,0,0,0,0,0
                 db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                 db 2,65,1,64,0,0,0,0,0,0,0,0,0,0,0,0
                 db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
%endif

SECTION .text

cextern pb_0
cextern pb_1
cextern pb_3
cextern pw_1
cextern pw_2
cextern pw_4
cextern pw_8
cextern pw_16
cextern pw_512
cextern pw_00ff
cextern pw_pixel_max
cextern pw_0to15

%macro STORE8 1
    mova [r0+0*FDEC_STRIDEB], %1
    mova [r0+1*FDEC_STRIDEB], %1
    add  r0, 4*FDEC_STRIDEB
    mova [r0-2*FDEC_STRIDEB], %1
    mova [r0-1*FDEC_STRIDEB], %1
    mova [r0+0*FDEC_STRIDEB], %1
    mova [r0+1*FDEC_STRIDEB], %1
    mova [r0+2*FDEC_STRIDEB], %1
    mova [r0+3*FDEC_STRIDEB], %1
%endmacro

%macro STORE16 1-4
%if %0 > 1
    mov  r1d, 2*%0
.loop:
    mova [r0+0*FDEC_STRIDEB+0*mmsize], %1
    mova [r0+0*FDEC_STRIDEB+1*mmsize], %2
    mova [r0+1*FDEC_STRIDEB+0*mmsize], %1
    mova [r0+1*FDEC_STRIDEB+1*mmsize], %2
%ifidn %0, 4
    mova [r0+0*FDEC_STRIDEB+2*mmsize], %3
    mova [r0+0*FDEC_STRIDEB+3*mmsize], %4
    mova [r0+1*FDEC_STRIDEB+2*mmsize], %3
    mova [r0+1*FDEC_STRIDEB+3*mmsize], %4
    add  r0, 2*FDEC_STRIDEB
%else ; %0 == 2
    add  r0, 4*FDEC_STRIDEB
    mova [r0-2*FDEC_STRIDEB+0*mmsize], %1
    mova [r0-2*FDEC_STRIDEB+1*mmsize], %2
    mova [r0-1*FDEC_STRIDEB+0*mmsize], %1
    mova [r0-1*FDEC_STRIDEB+1*mmsize], %2
%endif
    dec  r1d
    jg .loop
%else ; %0 == 1
    STORE8 %1
%if HIGH_BIT_DEPTH ; Different code paths to reduce code size
    add  r0, 6*FDEC_STRIDEB
    mova [r0-2*FDEC_STRIDEB], %1
    mova [r0-1*FDEC_STRIDEB], %1
    mova [r0+0*FDEC_STRIDEB], %1
    mova [r0+1*FDEC_STRIDEB], %1
    add  r0, 4*FDEC_STRIDEB
    mova [r0-2*FDEC_STRIDEB], %1
    mova [r0-1*FDEC_STRIDEB], %1
    mova [r0+0*FDEC_STRIDEB], %1
    mova [r0+1*FDEC_STRIDEB], %1
%else
    add  r0, 8*FDEC_STRIDE
    mova [r0-4*FDEC_STRIDE], %1
    mova [r0-3*FDEC_STRIDE], %1
    mova [r0-2*FDEC_STRIDE], %1
    mova [r0-1*FDEC_STRIDE], %1
    mova [r0+0*FDEC_STRIDE], %1
    mova [r0+1*FDEC_STRIDE], %1
    mova [r0+2*FDEC_STRIDE], %1
    mova [r0+3*FDEC_STRIDE], %1
%endif ; HIGH_BIT_DEPTH
%endif
%endmacro

%macro PRED_H_LOAD 2 ; reg, offset
%if cpuflag(avx2)
    vpbroadcastpix %1, [r0+(%2)*FDEC_STRIDEB-SIZEOF_PIXEL]
%elif HIGH_BIT_DEPTH
    movd           %1, [r0+(%2)*FDEC_STRIDEB-4]
    SPLATW         %1, %1, 1
%else
    SPLATB_LOAD    %1, r0+(%2)*FDEC_STRIDE-1, m2
%endif
%endmacro

%macro PRED_H_STORE 3 ; reg, offset, width
%assign %%w %3*SIZEOF_PIXEL
%if %%w == 8
    movq [r0+(%2)*FDEC_STRIDEB], %1
%else
    %assign %%i 0
    %rep %%w/mmsize
        mova [r0+(%2)*FDEC_STRIDEB+%%i], %1
    %assign %%i %%i+mmsize
    %endrep
%endif
%endmacro

%macro PRED_H_4ROWS 2 ; width, inc_ptr
    PRED_H_LOAD  m0, 0
    PRED_H_LOAD  m1, 1
    PRED_H_STORE m0, 0, %1
    PRED_H_STORE m1, 1, %1
    PRED_H_LOAD  m0, 2
%if %2
    add          r0, 4*FDEC_STRIDEB
%endif
    PRED_H_LOAD  m1, 3-4*%2
    PRED_H_STORE m0, 2-4*%2, %1
    PRED_H_STORE m1, 3-4*%2, %1
%endmacro

; %1 = (%1 ^ %2) & 1 in each byte
%macro PARITY_B 2
%if sizeof%1 == 64
    vpternlogd  %1, %2, [pb_1]{1to16}, 0x28
%elif sizeof%1 == 32
    vpternlogd  %1, %2, [pb_1]{1to8}, 0x28
%else
    vpternlogd  %1, %2, [pb_1]{1to4}, 0x28
%endif
%endmacro

; dest, left, right, src, tmp
; output: %1 = (t[n-1] + t[n]*2 + t[n+1] + 2) >> 2
%macro PRED8x8_LOWPASS 4-5
%if HIGH_BIT_DEPTH
    paddw       %2, %3
    psrlw       %2, 1
    pavgw       %1, %4, %2
%elif cpuflag(avx512icl)
    pavgb       %5, %2, %3
    PARITY_B    %2, %3
    psubb       %5, %2
    pavgb       %1, %4, %5
%else
    mova        %5, %2
    pavgb       %2, %3
    pxor        %3, %5
    pand        %3, [pb_1]
    psubusb     %2, %3
    pavgb       %1, %4, %2
%endif
%endmacro

;-----------------------------------------------------------------------------
; void predict_4x4_h( pixel *src )
;-----------------------------------------------------------------------------
%if HIGH_BIT_DEPTH
INIT_XMM avx2
cglobal predict_4x4_h, 1,1
    PRED_H_4ROWS 4, 0
    RET
%endif

;-----------------------------------------------------------------------------
; void predict_4x4_ddl( pixel *src )
;-----------------------------------------------------------------------------
%macro PREDICT_4x4_DDL 0
cglobal predict_4x4_ddl, 1,1
    movu    m1, [r0-FDEC_STRIDEB]
    PSLLPIX m2, m1, 1
    mova    m0, m1
%if HIGH_BIT_DEPTH
    PSRLPIX m1, m1, 1
    pshufhw m1, m1, q2210
%else
    pxor    m1, m2
    PSRLPIX m1, m1, 1
    pxor    m1, m0
%endif
    PRED8x8_LOWPASS m0, m2, m1, m0, m3

%assign Y 0
%rep 4
    PSRLPIX m0, m0, 1
    movh   [r0+Y*FDEC_STRIDEB], m0
%assign Y (Y+1)
%endrep

    RET
%endmacro

%if HIGH_BIT_DEPTH
INIT_XMM sse2
PREDICT_4x4_DDL
INIT_XMM avx
PREDICT_4x4_DDL
INIT_MMX mmx2
cglobal predict_4x4_ddl, 1,2
    movu    m1, [r0-FDEC_STRIDEB+4]
    PRED8x8_LOWPASS m0, m1, [r0-FDEC_STRIDEB+0], [r0-FDEC_STRIDEB+2]
    mova    m3, [r0-FDEC_STRIDEB+8]
    mova    [r0+0*FDEC_STRIDEB], m0
    pshufw  m4, m3, q3321
    PRED8x8_LOWPASS m2, m4, [r0-FDEC_STRIDEB+6], m3
    mova    [r0+3*FDEC_STRIDEB], m2
    pshufw  m1, m0, q0021
    punpckldq m1, m2
    mova    [r0+1*FDEC_STRIDEB], m1
    psllq   m0, 16
    PALIGNR m2, m0, 6, m0
    mova    [r0+2*FDEC_STRIDEB], m2
    RET
%else ; !HIGH_BIT_DEPTH
INIT_MMX mmx2
PREDICT_4x4_DDL
%endif

;-----------------------------------------------------------------------------
; void predict_4x4_vr( pixel *src )
;-----------------------------------------------------------------------------
%if HIGH_BIT_DEPTH == 0
INIT_MMX ssse3
cglobal predict_4x4_vr, 1,1
    movd    m1, [r0-1*FDEC_STRIDEB]        ; ........t3t2t1t0
    mova    m4, m1
    palignr m1, [r0-1*FDEC_STRIDEB-8], 7   ; ......t3t2t1t0lt
    pavgb   m4, m1
    palignr m1, [r0+0*FDEC_STRIDEB-8], 7   ; ....t3t2t1t0ltl0
    mova    m0, m1
    palignr m1, [r0+1*FDEC_STRIDEB-8], 7   ; ..t3t2t1t0ltl0l1
    mova    m2, m1
    palignr m1, [r0+2*FDEC_STRIDEB-8], 7   ; t3t2t1t0ltl0l1l2
    PRED8x8_LOWPASS m2, m0, m1, m2, m3
    pshufw  m0, m2, 0
    psrlq   m2, 16
    movd    [r0+0*FDEC_STRIDEB], m4
    palignr m4, m0, 7
    movd    [r0+1*FDEC_STRIDEB], m2
    psllq   m0, 8
    movd    [r0+2*FDEC_STRIDEB], m4
    palignr m2, m0, 7
    movd    [r0+3*FDEC_STRIDEB], m2
    RET
%endif ; !HIGH_BIT_DEPTH

;-----------------------------------------------------------------------------
; void predict_4x4_ddr( pixel *src )
;-----------------------------------------------------------------------------
%macro PREDICT_4x4 4
cglobal predict_4x4_ddr, 1,1
%if HIGH_BIT_DEPTH
    movu      m2, [r0-1*FDEC_STRIDEB-8]
    pinsrw    m2, [r0+0*FDEC_STRIDEB-2], 2
    pinsrw    m2, [r0+1*FDEC_STRIDEB-2], 1
    pinsrw    m2, [r0+2*FDEC_STRIDEB-2], 0
    movhps    m3, [r0+3*FDEC_STRIDEB-8]
%else ; !HIGH_BIT_DEPTH
    movd      m0, [r0+2*FDEC_STRIDEB-4]
    movd      m1, [r0+0*FDEC_STRIDEB-4]
    punpcklbw m0, [r0+1*FDEC_STRIDEB-4]
    punpcklbw m1, [r0-1*FDEC_STRIDEB-4]
    punpckhwd m0, m1
    movd      m2, [r0-1*FDEC_STRIDEB]
%if cpuflag(ssse3)
    palignr   m2, m0, 4
%else
    psllq     m2, 32
    punpckhdq m0, m2
    SWAP       2, 0
%endif
    movd      m3, [r0+3*FDEC_STRIDEB-4]
    psllq     m3, 32
%endif ; !HIGH_BIT_DEPTH

    PSRLPIX   m1, m2, 1
    mova      m0, m2
    PALIGNR   m2, m3, 7*SIZEOF_PIXEL, m3
    PRED8x8_LOWPASS m0, m2, m1, m0, m3
%assign Y 3
    movh      [r0+Y*FDEC_STRIDEB], m0
%rep 3
%assign Y (Y-1)
    PSRLPIX   m0, m0, 1
    movh      [r0+Y*FDEC_STRIDEB], m0
%endrep
    RET

;-----------------------------------------------------------------------------
; void predict_4x4_vr( pixel *src )
;-----------------------------------------------------------------------------
cglobal predict_4x4_vr, 1,1
%if HIGH_BIT_DEPTH
    movu      m1, [r0-1*FDEC_STRIDEB-8]
    pinsrw    m1, [r0+0*FDEC_STRIDEB-2], 2
    pinsrw    m1, [r0+1*FDEC_STRIDEB-2], 1
    pinsrw    m1, [r0+2*FDEC_STRIDEB-2], 0
%else ; !HIGH_BIT_DEPTH
    movd      m0, [r0+2*FDEC_STRIDEB-4]
    movd      m1, [r0+0*FDEC_STRIDEB-4]
    punpcklbw m0, [r0+1*FDEC_STRIDEB-4]
    punpcklbw m1, [r0-1*FDEC_STRIDEB-4]
    punpckhwd m0, m1
    movd      m1, [r0-1*FDEC_STRIDEB]
%if cpuflag(ssse3)
    palignr   m1, m0, 4
%else
    psllq     m1, 32
    punpckhdq m0, m1
    SWAP       1, 0
%endif
%endif ; !HIGH_BIT_DEPTH
    PSRLPIX   m2, m1, 1
    PSRLPIX   m0, m1, 2
    pavg%1    m4, m1, m2
    PSRLPIX   m4, m4, 3
    PRED8x8_LOWPASS m2, m0, m1, m2, m3
    PSLLPIX   m0, m2, 6
    PSRLPIX   m2, m2, 2
    movh      [r0+0*FDEC_STRIDEB], m4
    PALIGNR   m4, m0, 7*SIZEOF_PIXEL, m3
    movh      [r0+1*FDEC_STRIDEB], m2
    PSLLPIX   m0, m0, 1
    movh      [r0+2*FDEC_STRIDEB], m4
    PALIGNR   m2, m0, 7*SIZEOF_PIXEL, m0
    movh      [r0+3*FDEC_STRIDEB], m2
    RET

;-----------------------------------------------------------------------------
; void predict_4x4_hd( pixel *src )
;-----------------------------------------------------------------------------
cglobal predict_4x4_hd, 1,1
%if HIGH_BIT_DEPTH
    movu      m1, [r0-1*FDEC_STRIDEB-8]
    PSLLPIX   m1, m1, 1
    pinsrw    m1, [r0+0*FDEC_STRIDEB-2], 3
    pinsrw    m1, [r0+1*FDEC_STRIDEB-2], 2
    pinsrw    m1, [r0+2*FDEC_STRIDEB-2], 1
    pinsrw    m1, [r0+3*FDEC_STRIDEB-2], 0
%else
    movd      m0, [r0-1*FDEC_STRIDEB-4] ; lt ..
    punpckldq m0, [r0-1*FDEC_STRIDEB]   ; t3 t2 t1 t0 lt .. .. ..
    PSLLPIX   m0, m0, 1                 ; t2 t1 t0 lt .. .. .. ..
    movd      m1, [r0+3*FDEC_STRIDEB-4] ; l3
    punpcklbw m1, [r0+2*FDEC_STRIDEB-4] ; l2 l3
    movd      m2, [r0+1*FDEC_STRIDEB-4] ; l1
    punpcklbw m2, [r0+0*FDEC_STRIDEB-4] ; l0 l1
    punpckh%3 m1, m2                    ; l0 l1 l2 l3
    punpckh%4 m1, m0                    ; t2 t1 t0 lt l0 l1 l2 l3
%endif
    PSRLPIX   m2, m1, 1                 ; .. t2 t1 t0 lt l0 l1 l2
    PSRLPIX   m0, m1, 2                 ; .. .. t2 t1 t0 lt l0 l1
    pavg%1    m5, m1, m2
    PRED8x8_LOWPASS m3, m1, m0, m2, m4
    punpckl%2 m5, m3
    PSRLPIX   m3, m3, 4
    PALIGNR   m3, m5, 6*SIZEOF_PIXEL, m4
%assign Y 3
    movh      [r0+Y*FDEC_STRIDEB], m5
%rep 2
%assign Y (Y-1)
    PSRLPIX   m5, m5, 2
    movh      [r0+Y*FDEC_STRIDEB], m5
%endrep
    movh      [r0+0*FDEC_STRIDEB], m3
    RET
%endmacro ; PREDICT_4x4

;-----------------------------------------------------------------------------
; void predict_4x4_ddr( pixel *src )
;-----------------------------------------------------------------------------
%if HIGH_BIT_DEPTH
INIT_MMX mmx2
cglobal predict_4x4_ddr, 1,1
    mova      m0, [r0+1*FDEC_STRIDEB-8]
    punpckhwd m0, [r0+0*FDEC_STRIDEB-8]
    mova      m3, [r0+3*FDEC_STRIDEB-8]
    punpckhwd m3, [r0+2*FDEC_STRIDEB-8]
    punpckhdq m3, m0

    pshufw  m0, m3, q3321
    pinsrw  m0, [r0-1*FDEC_STRIDEB-2], 3
    pshufw  m1, m0, q3321
    PRED8x8_LOWPASS m0, m1, m3, m0
    movq    [r0+3*FDEC_STRIDEB], m0

    movq    m2, [r0-1*FDEC_STRIDEB-0]
    pshufw  m4, m2, q2100
    pinsrw  m4, [r0-1*FDEC_STRIDEB-2], 0
    movq    m1, m4
    PALIGNR m4, m3, 6, m3
    PRED8x8_LOWPASS m1, m4, m2, m1
    movq    [r0+0*FDEC_STRIDEB], m1

    pshufw  m2, m0, q3321
    punpckldq m2, m1
    psllq   m0, 16
    PALIGNR m1, m0, 6, m0
    movq    [r0+1*FDEC_STRIDEB], m1
    movq    [r0+2*FDEC_STRIDEB], m2
    movd    [r0+3*FDEC_STRIDEB+4], m1
    RET

;-----------------------------------------------------------------------------
; void predict_4x4_hd( pixel *src )
;-----------------------------------------------------------------------------
cglobal predict_4x4_hd, 1,1
    mova      m0, [r0+1*FDEC_STRIDEB-8]
    punpckhwd m0, [r0+0*FDEC_STRIDEB-8]
    mova      m1, [r0+3*FDEC_STRIDEB-8]
    punpckhwd m1, [r0+2*FDEC_STRIDEB-8]
    punpckhdq m1, m0
    mova      m0, m1

    movu      m3, [r0-1*FDEC_STRIDEB-2]
    pshufw    m4, m1, q0032
    mova      m7, m3
    punpckldq m4, m3
    PALIGNR   m3, m1, 2, m2
    PRED8x8_LOWPASS m2, m4, m1, m3

    pavgw     m0, m3
    punpcklwd m5, m0, m2
    punpckhwd m4, m0, m2
    mova      [r0+3*FDEC_STRIDEB], m5
    mova      [r0+1*FDEC_STRIDEB], m4
    psrlq     m5, 32
    punpckldq m5, m4
    mova      [r0+2*FDEC_STRIDEB], m5

    pshufw    m4, m7, q2100
    mova      m6, [r0-1*FDEC_STRIDEB+0]
    pinsrw    m4, [r0+0*FDEC_STRIDEB-2], 0
    PRED8x8_LOWPASS m3, m4, m6, m7
    PALIGNR   m3, m0, 6, m0
    mova      [r0+0*FDEC_STRIDEB], m3
    RET

INIT_XMM sse2
PREDICT_4x4 w, wd, dq, qdq
INIT_XMM ssse3
PREDICT_4x4 w, wd, dq, qdq
INIT_XMM avx
PREDICT_4x4 w, wd, dq, qdq
%else ; !HIGH_BIT_DEPTH
INIT_MMX mmx2
PREDICT_4x4 b, bw, wd, dq
INIT_MMX ssse3
%define predict_4x4_vr_ssse3 predict_4x4_vr_ssse3_cache64
PREDICT_4x4 b, bw, wd, dq
%endif

;-----------------------------------------------------------------------------
; void predict_4x4_hu( pixel *src )
;-----------------------------------------------------------------------------
%if HIGH_BIT_DEPTH
INIT_MMX
cglobal predict_4x4_hu_mmx2, 1,1
    movq      m0, [r0+0*FDEC_STRIDEB-8]
    punpckhwd m0, [r0+1*FDEC_STRIDEB-8]
    movq      m1, [r0+2*FDEC_STRIDEB-8]
    punpckhwd m1, [r0+3*FDEC_STRIDEB-8]
    punpckhdq m0, m1
    pshufw    m1, m1, q3333
    movq      [r0+3*FDEC_STRIDEB], m1
    pshufw    m3, m0, q3321
    pshufw    m4, m0, q3332
    pavgw     m2, m0, m3
    PRED8x8_LOWPASS m3, m0, m4, m3
    punpcklwd m4, m2, m3
    mova      [r0+0*FDEC_STRIDEB], m4
    psrlq     m2, 16
    psrlq     m3, 16
    punpcklwd m2, m3
    mova      [r0+1*FDEC_STRIDEB], m2
    punpckhdq m2, m1
    mova      [r0+2*FDEC_STRIDEB], m2
    RET

%else ; !HIGH_BIT_DEPTH
INIT_MMX
cglobal predict_4x4_hu_mmx2, 1,1
    movd      m1, [r0+0*FDEC_STRIDEB-4]
    punpcklbw m1, [r0+1*FDEC_STRIDEB-4]
    movd      m0, [r0+2*FDEC_STRIDEB-4]
    punpcklbw m0, [r0+3*FDEC_STRIDEB-4]
    punpckhwd m1, m0
    movq      m0, m1
    punpckhbw m1, m1
    pshufw    m1, m1, q3333
    punpckhdq m0, m1
    movq      m2, m0
    movq      m3, m0
    movq      m5, m0
    psrlq     m3, 8
    psrlq     m2, 16
    pavgb     m5, m3
    PRED8x8_LOWPASS m3, m0, m2, m3, m4
    movd      [r0+3*FDEC_STRIDEB], m1
    punpcklbw m5, m3
    movd      [r0+0*FDEC_STRIDEB], m5
    psrlq     m5, 16
    movd      [r0+1*FDEC_STRIDEB], m5
    psrlq     m5, 16
    movd      [r0+2*FDEC_STRIDEB], m5
    RET
%endif ; HIGH_BIT_DEPTH

;-----------------------------------------------------------------------------
; void predict_4x4_vl( pixel *src )
;-----------------------------------------------------------------------------
%macro PREDICT_4x4_V1 1
cglobal predict_4x4_vl, 1,1
    movu        m1, [r0-FDEC_STRIDEB]
    PSRLPIX     m3, m1, 1
    PSRLPIX     m2, m1, 2
    pavg%1      m4, m3, m1
    PRED8x8_LOWPASS m0, m1, m2, m3, m5

    movh        [r0+0*FDEC_STRIDEB], m4
    movh        [r0+1*FDEC_STRIDEB], m0
    PSRLPIX     m4, m4, 1
    PSRLPIX     m0, m0, 1
    movh        [r0+2*FDEC_STRIDEB], m4
    movh        [r0+3*FDEC_STRIDEB], m0
    RET
%endmacro

%if HIGH_BIT_DEPTH
INIT_XMM sse2
PREDICT_4x4_V1 w
INIT_XMM avx
PREDICT_4x4_V1 w

INIT_MMX mmx2
cglobal predict_4x4_vl, 1,4
    mova    m1, [r0-FDEC_STRIDEB+0]
    mova    m2, [r0-FDEC_STRIDEB+8]
    mova    m0, m2
    PALIGNR m2, m1, 4, m4
    PALIGNR m0, m1, 2, m4
    mova    m3, m0
    pavgw   m3, m1
    mova    [r0+0*FDEC_STRIDEB], m3
    psrlq   m3, 16
    mova    [r0+2*FDEC_STRIDEB], m3
    PRED8x8_LOWPASS m0, m1, m2, m0
    mova    [r0+1*FDEC_STRIDEB], m0
    psrlq   m0, 16
    mova    [r0+3*FDEC_STRIDEB], m0

    movzx   r1d, word [r0-FDEC_STRIDEB+ 8]
    movzx   r2d, word [r0-FDEC_STRIDEB+10]
    movzx   r3d, word [r0-FDEC_STRIDEB+12]
    lea     r1d, [r1+r2+1]
    add     r3d, r2d
    lea     r3d, [r3+r1+1]
    shr     r1d, 1
    shr     r3d, 2
    mov     [r0+2*FDEC_STRIDEB+6], r1w
    mov     [r0+3*FDEC_STRIDEB+6], r3w
    RET
%else ; !HIGH_BIT_DEPTH
INIT_MMX mmx2
PREDICT_4x4_V1 b
%endif

;-----------------------------------------------------------------------------
; void predict_4x4_dc( pixel *src )
;-----------------------------------------------------------------------------
INIT_MMX mmx2
%if HIGH_BIT_DEPTH
cglobal predict_4x4_dc, 1,1
    mova   m2, [r0+0*FDEC_STRIDEB-4*SIZEOF_PIXEL]
    paddw  m2, [r0+1*FDEC_STRIDEB-4*SIZEOF_PIXEL]
    paddw  m2, [r0+2*FDEC_STRIDEB-4*SIZEOF_PIXEL]
    paddw  m2, [r0+3*FDEC_STRIDEB-4*SIZEOF_PIXEL]
    psrlq  m2, 48
    mova   m0, [r0-FDEC_STRIDEB]
    HADDW  m0, m1
    paddw  m0, [pw_4]
    paddw  m0, m2
    psrlw  m0, 3
    SPLATW m0, m0
    mova   [r0+0*FDEC_STRIDEB], m0
    mova   [r0+1*FDEC_STRIDEB], m0
    mova   [r0+2*FDEC_STRIDEB], m0
    mova   [r0+3*FDEC_STRIDEB], m0
    RET

%else ; !HIGH_BIT_DEPTH
cglobal predict_4x4_dc, 1,4
    pxor   mm7, mm7
    movd   mm0, [r0-FDEC_STRIDEB]
    psadbw mm0, mm7
    movd   r3d, mm0
    movzx  r1d, byte [r0-1]
%assign Y 1
%rep 3
    movzx  r2d, byte [r0+FDEC_STRIDEB*Y-1]
    add    r1d, r2d
%assign Y Y+1
%endrep
    lea    r1d, [r1+r3+4]
    shr    r1d, 3
    imul   r1d, 0x01010101
    mov   [r0+FDEC_STRIDEB*0], r1d
    mov   [r0+FDEC_STRIDEB*1], r1d
    mov   [r0+FDEC_STRIDEB*2], r1d
    mov   [r0+FDEC_STRIDEB*3], r1d
    RET
%endif ; HIGH_BIT_DEPTH

%macro PREDICT_FILTER 4
;-----------------------------------------------------------------------------
;void predict_8x8_filter( pixel *src, pixel edge[36], int i_neighbor, int i_filters )
;-----------------------------------------------------------------------------
cglobal predict_8x8_filter, 4,6,6
    add          r0, 0x58*SIZEOF_PIXEL
%define src r0-0x58*SIZEOF_PIXEL
%if ARCH_X86_64 == 0
    mov          r4, r1
%define t1 r4
%define t4 r1
%else
%define t1 r1
%define t4 r4
%endif
    test       r3b, 1
    je .check_top
    mov        t4d, r2d
    and        t4d, 8
    neg         t4
    mova        m0, [src+0*FDEC_STRIDEB-8*SIZEOF_PIXEL]
    punpckh%1%2 m0, [src+0*FDEC_STRIDEB-8*SIZEOF_PIXEL+t4*(FDEC_STRIDEB/8)]
    mova        m1, [src+2*FDEC_STRIDEB-8*SIZEOF_PIXEL]
    punpckh%1%2 m1, [src+1*FDEC_STRIDEB-8*SIZEOF_PIXEL]
    punpckh%2%3 m1, m0
    mova        m2, [src+4*FDEC_STRIDEB-8*SIZEOF_PIXEL]
    punpckh%1%2 m2, [src+3*FDEC_STRIDEB-8*SIZEOF_PIXEL]
    mova        m3, [src+6*FDEC_STRIDEB-8*SIZEOF_PIXEL]
    punpckh%1%2 m3, [src+5*FDEC_STRIDEB-8*SIZEOF_PIXEL]
    punpckh%2%3 m3, m2
    punpckh%3%4 m3, m1
    mova        m0, [src+7*FDEC_STRIDEB-8*SIZEOF_PIXEL]
    mova        m1, [src-1*FDEC_STRIDEB]
    PALIGNR     m4, m3, m0, 7*SIZEOF_PIXEL, m0
    PALIGNR     m1, m1, m3, 1*SIZEOF_PIXEL, m2
    PRED8x8_LOWPASS m3, m1, m4, m3, m5
    mova        [t1+8*SIZEOF_PIXEL], m3
    movzx      t4d, pixel [src+7*FDEC_STRIDEB-1*SIZEOF_PIXEL]
    movzx      r5d, pixel [src+6*FDEC_STRIDEB-1*SIZEOF_PIXEL]
    lea        t4d, [t4*3+2]
    add        t4d, r5d
    shr        t4d, 2
    mov         [t1+7*SIZEOF_PIXEL], t4%1
    mov         [t1+6*SIZEOF_PIXEL], t4%1
    test       r3b, 2
    je .done
.check_top:
%if SIZEOF_PIXEL==1 && cpuflag(ssse3)
INIT_XMM cpuname
    movu        m3, [src-1*FDEC_STRIDEB]
    movhps      m0, [src-1*FDEC_STRIDEB-8]
    test       r2b, 8
    je .fix_lt_2
.do_top:
    and        r2d, 4
%ifdef PIC
    lea         r3, [shuf_fixtr]
    pshufb      m3, [r3+r2*4]
%else
    pshufb      m3, [shuf_fixtr+r2*4] ; neighbor&MB_TOPRIGHT ? shuf_nop : shuf_fixtr
%endif
    psrldq      m1, m3, 15
    PALIGNR     m2, m3, m0, 15, m0
    PALIGNR     m1, m3, 1, m5
    PRED8x8_LOWPASS m0, m2, m1, m3, m5
    mova        [t1+16*SIZEOF_PIXEL], m0
    psrldq      m0, 15
    movd        [t1+32*SIZEOF_PIXEL], m0
.done:
    REP_RET
.fix_lt_2:
    pslldq      m0, m3, 15
    jmp .do_top

%else
    mova        m0, [src-1*FDEC_STRIDEB-8*SIZEOF_PIXEL]
    mova        m3, [src-1*FDEC_STRIDEB]
    mova        m1, [src-1*FDEC_STRIDEB+8*SIZEOF_PIXEL]
    test       r2b, 8
    je .fix_lt_2
    test       r2b, 4
    je .fix_tr_1
.do_top:
    PALIGNR     m2, m3, m0, 7*SIZEOF_PIXEL, m0
    PALIGNR     m0, m1, m3, 1*SIZEOF_PIXEL, m5
    PRED8x8_LOWPASS m4, m2, m0, m3, m5
    mova        [t1+16*SIZEOF_PIXEL], m4
    test       r3b, 4
    je .done
    PSRLPIX     m5, m1, 7
    PALIGNR     m2, m1, m3, 7*SIZEOF_PIXEL, m3
    PALIGNR     m5, m1, 1*SIZEOF_PIXEL, m4
    PRED8x8_LOWPASS m0, m2, m5, m1, m4
    mova        [t1+24*SIZEOF_PIXEL], m0
    PSRLPIX     m0, m0, 7
    movd        [t1+32*SIZEOF_PIXEL], m0
.done:
    REP_RET
.fix_lt_2:
    PSLLPIX     m0, m3, 7
    test       r2b, 4
    jne .do_top
.fix_tr_1:
    punpckh%1%2 m1, m3, m3
    pshuf%2     m1, m1, q3333
    jmp .do_top
%endif
%endmacro

%if HIGH_BIT_DEPTH
INIT_XMM sse2
PREDICT_FILTER w, d, q, dq
INIT_XMM ssse3
PREDICT_FILTER w, d, q, dq
INIT_XMM avx
PREDICT_FILTER w, d, q, dq
%else
INIT_MMX mmx2
PREDICT_FILTER b, w, d, q
INIT_MMX ssse3
PREDICT_FILTER b, w, d, q
%endif

%if ARCH_X86_64
;-----------------------------------------------------------------------------
; void predict_8x8_filter( pixel *src, pixel edge[36], int i_neighbor, int i_filters )
;-----------------------------------------------------------------------------
; avx512icl: the 8 rows ending at the left column go to qword lanes 0-7 by
; merge-masked vpbroadcastq, vpermi2b/vpermi2w gathers l6 l7 l7 l6 .. l0 lt t0
; from them; the top row's shifts are vpermb/vpermw, lt merged by k-mask.
INIT_ZMM avx512icl
cglobal predict_8x8_filter, 4,6
%if HIGH_BIT_DEPTH
    %define tx ym
%else
    %define tx xm
%endif
    test        r3b, 1
    jz .check_top
    mov         r4d, 1
    kmovb        k1, r4d
%assign Y 0
%rep 8
    vpbroadcastq m0{k1}, [r0+Y*FDEC_STRIDEB-8]
%if Y < 7
    kshiftlb     k1, k1, 1
%endif
%assign Y Y+1
%endrep
    mov         r4d, r2d
    and         r4d, 8
    neg          r4
    movq        xm1, [r0+r4*(FDEC_STRIDEB/8)-8] ; lt, or l0 without MB_TOPLEFT
    movhps      xm1, [r0-FDEC_STRIDEB]
    mov         r4d, 0x3ff
    kmovw        k2, r4d
%if HIGH_BIT_DEPTH
    movu        ym2, [pw_filt_left]
    movu        ym3, [pw_filt_left+32]
    movu        ym4, [pw_filt_left+64]
    vpermi2w     m2, m0, m1
    vpermi2w     m3, m0, m1
    vpermi2w     m4, m0, m1
    PRED8x8_LOWPASS ym2, ym2, ym4, ym3
    vmovdqu16 [r1+6*SIZEOF_PIXEL]{k2}, ym2
%else
    movu        xm2, [pb_filt_left]
    vpermi2b     m2, m0, m1
    psrldq      xm3, xm2, 1
    psrldq      xm4, xm2, 2
    PRED8x8_LOWPASS xm2, xm2, xm4, xm3, xm5
    vmovdqu8  [r1+6*SIZEOF_PIXEL]{k2}, xm2
%endif
    test        r3b, 2
    jz .done
.check_top:
    movu        tx %+ 3, [r0-FDEC_STRIDEB]
    mov         r4d, r2d
    and         r4d, 4
%if HIGH_BIT_DEPTH
    lea          r5, [pw_filt_fixtr]
    movu        ym0, [r5+r4*8]          ; neighbor&MB_TOPRIGHT ? pw_filt_nop : pw_filt_fixtr
    vpermw      ym3, ym0, ym3
    movu        ym0, [pw_filt_r]
    vpermw      ym1, ym0, ym3
    movu        ym0, [pw_filt_l]
    vpermw      ym2, ym0, ym3
%else
    lea          r5, [shuf_fixtr]
    pshufb      xm3, [r5+r4*4]
    movu        xm0, [pb_filt_r]
    vpermb      xm1, xm0, xm3
    movu        xm0, [pb_filt_l]
    vpermb      xm2, xm0, xm3
%endif
    shr         r2d, 3
    and         r2d, 1
    kmovb        k1, r2d
%if HIGH_BIT_DEPTH
    vpbroadcastw ym2{k1}, [r0-FDEC_STRIDEB-SIZEOF_PIXEL]
%else
    vpbroadcastb xm2{k1}, [r0-FDEC_STRIDEB-SIZEOF_PIXEL]
%endif
    PRED8x8_LOWPASS tx %+ 0, tx %+ 2, tx %+ 1, tx %+ 3, tx %+ 4
    movu [r1+16*SIZEOF_PIXEL], tx %+ 0
    mov         r4d, 0x8000
    kmovw        k2, r4d
%if HIGH_BIT_DEPTH
    vmovdqu16 [r1+17*SIZEOF_PIXEL]{k2}, ym0 ; edge[32] = edge[31]
%else
    vmovdqu8  [r1+17*SIZEOF_PIXEL]{k2}, xm0
%endif
.done:
    RET
    %undef tx
%endif ; ARCH_X86_64

;-----------------------------------------------------------------------------
; void predict_8x8_v( pixel *src, pixel *edge )
;-----------------------------------------------------------------------------
%macro PREDICT_8x8_V 0
cglobal predict_8x8_v, 2,2
    mova        m0, [r1+16*SIZEOF_PIXEL]
    STORE8      m0
    RET
%endmacro

%if HIGH_BIT_DEPTH
INIT_XMM sse
PREDICT_8x8_V
%else
INIT_MMX mmx2
PREDICT_8x8_V
%endif

;-----------------------------------------------------------------------------
; void predict_8x8_h( pixel *src, pixel edge[36] )
;-----------------------------------------------------------------------------
%macro PREDICT_8x8_H 2
cglobal predict_8x8_h, 2,2
    movu      m1, [r1+7*SIZEOF_PIXEL]
    add       r0, 4*FDEC_STRIDEB
    punpckl%1 m2, m1, m1
    punpckh%1 m1, m1
%assign Y 0
%rep 8
%assign i 1+Y/4
    SPLAT%2 m0, m %+ i, (3-Y)&3
    mova [r0+(Y-4)*FDEC_STRIDEB], m0
%assign Y Y+1
%endrep
    RET
%endmacro

%if HIGH_BIT_DEPTH
INIT_XMM sse2
PREDICT_8x8_H wd, D
%else
INIT_MMX mmx2
PREDICT_8x8_H bw, W
%endif

;-----------------------------------------------------------------------------
; void predict_8x8_dc( pixel *src, pixel *edge );
;-----------------------------------------------------------------------------
%if HIGH_BIT_DEPTH
INIT_XMM sse2
cglobal predict_8x8_dc, 2,2
    movu        m0, [r1+14]
    paddw       m0, [r1+32]
    HADDW       m0, m1
    paddw       m0, [pw_8]
    psrlw       m0, 4
    SPLATW      m0, m0
    STORE8      m0
    RET

%else ; !HIGH_BIT_DEPTH
INIT_MMX mmx2
cglobal predict_8x8_dc, 2,2
    pxor        mm0, mm0
    pxor        mm1, mm1
    psadbw      mm0, [r1+7]
    psadbw      mm1, [r1+16]
    paddw       mm0, [pw_8]
    paddw       mm0, mm1
    psrlw       mm0, 4
    pshufw      mm0, mm0, 0
    packuswb    mm0, mm0
    STORE8      mm0
    RET
%endif ; HIGH_BIT_DEPTH

;-----------------------------------------------------------------------------
; void predict_8x8_dc_top ( pixel *src, pixel *edge );
; void predict_8x8_dc_left( pixel *src, pixel *edge );
;-----------------------------------------------------------------------------
%if HIGH_BIT_DEPTH
%macro PREDICT_8x8_DC 3
cglobal %1, 2,2
    %3          m0, [r1+%2]
    HADDW       m0, m1
    paddw       m0, [pw_4]
    psrlw       m0, 3
    SPLATW      m0, m0
    STORE8      m0
    RET
%endmacro
INIT_XMM sse2
PREDICT_8x8_DC predict_8x8_dc_top , 32, mova
PREDICT_8x8_DC predict_8x8_dc_left, 14, movu

%else ; !HIGH_BIT_DEPTH
%macro PREDICT_8x8_DC 2
cglobal %1, 2,2
    pxor        mm0, mm0
    psadbw      mm0, [r1+%2]
    paddw       mm0, [pw_4]
    psrlw       mm0, 3
    pshufw      mm0, mm0, 0
    packuswb    mm0, mm0
    STORE8      mm0
    RET
%endmacro
INIT_MMX
PREDICT_8x8_DC predict_8x8_dc_top_mmx2, 16
PREDICT_8x8_DC predict_8x8_dc_left_mmx2, 7
%endif ; HIGH_BIT_DEPTH

; sse2 is faster even on amd for 8-bit, so there's no sense in spending exe
; size on the 8-bit mmx functions below if we know sse2 is available.
%macro PREDICT_8x8_DDLR 0
;-----------------------------------------------------------------------------
; void predict_8x8_ddl( pixel *src, pixel *edge )
;-----------------------------------------------------------------------------
cglobal predict_8x8_ddl, 2,2,7
    mova        m0, [r1+16*SIZEOF_PIXEL]
    mova        m1, [r1+24*SIZEOF_PIXEL]
%if cpuflag(cache64)
    movd        m5, [r1+32*SIZEOF_PIXEL]
    palignr     m3, m1, m0, 1*SIZEOF_PIXEL
    palignr     m5, m5, m1, 1*SIZEOF_PIXEL
    palignr     m4, m1, m0, 7*SIZEOF_PIXEL
%else
    movu        m3, [r1+17*SIZEOF_PIXEL]
    movu        m4, [r1+23*SIZEOF_PIXEL]
    movu        m5, [r1+25*SIZEOF_PIXEL]
%endif
    PSLLPIX     m2, m0, 1
    add         r0, FDEC_STRIDEB*4
    PRED8x8_LOWPASS m0, m2, m3, m0, m6
    PRED8x8_LOWPASS m1, m4, m5, m1, m6
    mova        [r0+3*FDEC_STRIDEB], m1
%assign Y 2
%rep 6
    PALIGNR     m1, m0, 7*SIZEOF_PIXEL, m2
    PSLLPIX     m0, m0, 1
    mova        [r0+Y*FDEC_STRIDEB], m1
%assign Y (Y-1)
%endrep
    PALIGNR     m1, m0, 7*SIZEOF_PIXEL, m0
    mova        [r0+Y*FDEC_STRIDEB], m1
    RET

;-----------------------------------------------------------------------------
; void predict_8x8_ddr( pixel *src, pixel *edge )
;-----------------------------------------------------------------------------
cglobal predict_8x8_ddr, 2,2,7
    add         r0, FDEC_STRIDEB*4
    mova        m0, [r1+ 8*SIZEOF_PIXEL]
    mova        m1, [r1+16*SIZEOF_PIXEL]
    ; edge[] is 32byte aligned, so some of the unaligned loads are known to be not cachesplit
    movu        m2, [r1+ 7*SIZEOF_PIXEL]
    movu        m5, [r1+17*SIZEOF_PIXEL]
%if cpuflag(cache64)
    palignr     m3, m1, m0, 1*SIZEOF_PIXEL
    palignr     m4, m1, m0, 7*SIZEOF_PIXEL
%else
    movu        m3, [r1+ 9*SIZEOF_PIXEL]
    movu        m4, [r1+15*SIZEOF_PIXEL]
%endif
    PRED8x8_LOWPASS m0, m2, m3, m0, m6
    PRED8x8_LOWPASS m1, m4, m5, m1, m6
    mova        [r0+3*FDEC_STRIDEB], m0
%assign Y -4
%rep 6
    PALIGNR     m1, m0, 7*SIZEOF_PIXEL, m2
    PSLLPIX     m0, m0, 1
    mova        [r0+Y*FDEC_STRIDEB], m1
%assign Y (Y+1)
%endrep
    PALIGNR     m1, m0, 7*SIZEOF_PIXEL, m0
    mova        [r0+Y*FDEC_STRIDEB], m1
    RET
%endmacro ; PREDICT_8x8_DDLR

%if HIGH_BIT_DEPTH
INIT_XMM sse2
PREDICT_8x8_DDLR
INIT_XMM ssse3
PREDICT_8x8_DDLR
INIT_XMM ssse3, cache64
PREDICT_8x8_DDLR
%elif ARCH_X86_64 == 0
INIT_MMX mmx2
PREDICT_8x8_DDLR
%endif

;-----------------------------------------------------------------------------
; void predict_8x8_hu( pixel *src, pixel *edge )
;-----------------------------------------------------------------------------
%macro PREDICT_8x8_HU 2
cglobal predict_8x8_hu, 2,2,8
    add       r0, 4*FDEC_STRIDEB
%if HIGH_BIT_DEPTH
%if cpuflag(ssse3)
    movu      m5, [r1+7*SIZEOF_PIXEL]
    pshufb    m5, [pw_reverse]
%else
    movq      m6, [r1+7*SIZEOF_PIXEL]
    movq      m5, [r1+11*SIZEOF_PIXEL]
    pshuflw   m6, m6, q0123
    pshuflw   m5, m5, q0123
    movlhps   m5, m6
%endif ; cpuflag
    psrldq    m2, m5, 2
    pshufd    m3, m5, q0321
    pshufhw   m2, m2, q2210
    pshufhw   m3, m3, q1110
    pavgw     m4, m5, m2
%else ; !HIGH_BIT_DEPTH
    movu      m1, [r1+7*SIZEOF_PIXEL] ; l0 l1 l2 l3 l4 l5 l6 l7
    pshufw    m0, m1, q0123           ; l6 l7 l4 l5 l2 l3 l0 l1
    psllq     m1, 56                  ; l7 .. .. .. .. .. .. ..
    mova      m2, m0
    psllw     m0, 8
    psrlw     m2, 8
    por       m2, m0
    mova      m3, m2
    mova      m4, m2
    mova      m5, m2                  ; l7 l6 l5 l4 l3 l2 l1 l0
    psrlq     m3, 16
    psrlq     m2, 8
    por       m2, m1                  ; l7 l7 l6 l5 l4 l3 l2 l1
    punpckhbw m1, m1
    por       m3, m1                  ; l7 l7 l7 l6 l5 l4 l3 l2
    pavgb     m4, m2
%endif ; !HIGH_BIT_DEPTH
    PRED8x8_LOWPASS m2, m3, m5, m2, m6
    punpckh%2 m0, m4, m2              ; p8 p7 p6 p5
    punpckl%2 m4, m2                  ; p4 p3 p2 p1
    PALIGNR   m5, m0, m4, 2*SIZEOF_PIXEL, m3
    pshuf%1   m1, m0, q3321
    PALIGNR   m6, m0, m4, 4*SIZEOF_PIXEL, m3
    pshuf%1   m2, m0, q3332
    PALIGNR   m7, m0, m4, 6*SIZEOF_PIXEL, m3
    pshuf%1   m3, m0, q3333
    mova      [r0-4*FDEC_STRIDEB], m4
    mova      [r0-3*FDEC_STRIDEB], m5
    mova      [r0-2*FDEC_STRIDEB], m6
    mova      [r0-1*FDEC_STRIDEB], m7
    mova      [r0+0*FDEC_STRIDEB], m0
    mova      [r0+1*FDEC_STRIDEB], m1
    mova      [r0+2*FDEC_STRIDEB], m2
    mova      [r0+3*FDEC_STRIDEB], m3
    RET
%endmacro

%if HIGH_BIT_DEPTH
INIT_XMM sse2
PREDICT_8x8_HU d, wd
INIT_XMM ssse3
PREDICT_8x8_HU d, wd
INIT_XMM avx
PREDICT_8x8_HU d, wd
%elif ARCH_X86_64 == 0
INIT_MMX mmx2
PREDICT_8x8_HU w, bw
%endif

;-----------------------------------------------------------------------------
; void predict_8x8_vr( pixel *src, pixel *edge )
;-----------------------------------------------------------------------------
%macro PREDICT_8x8_VR 1
cglobal predict_8x8_vr, 2,3
    mova        m2, [r1+16*SIZEOF_PIXEL]
%ifidn cpuname, ssse3
    mova        m0, [r1+8*SIZEOF_PIXEL]
    palignr     m3, m2, m0, 7*SIZEOF_PIXEL
    palignr     m1, m2, m0, 6*SIZEOF_PIXEL
%else
    movu        m3, [r1+15*SIZEOF_PIXEL]
    movu        m1, [r1+14*SIZEOF_PIXEL]
%endif
    pavg%1      m4, m3, m2
    add         r0, FDEC_STRIDEB*4
    PRED8x8_LOWPASS m3, m1, m2, m3, m5
    mova        [r0-4*FDEC_STRIDEB], m4
    mova        [r0-3*FDEC_STRIDEB], m3
    mova        m1, [r1+8*SIZEOF_PIXEL]
    PSLLPIX     m0, m1, 1
    PSLLPIX     m2, m1, 2
    PRED8x8_LOWPASS m0, m1, m2, m0, m6

%assign Y -2
%rep 5
    PALIGNR     m4, m0, 7*SIZEOF_PIXEL, m5
    mova        [r0+Y*FDEC_STRIDEB], m4
    PSLLPIX     m0, m0, 1
    SWAP 3, 4
%assign Y (Y+1)
%endrep
    PALIGNR     m4, m0, 7*SIZEOF_PIXEL, m0
    mova        [r0+Y*FDEC_STRIDEB], m4
    RET
%endmacro

%if HIGH_BIT_DEPTH
INIT_XMM sse2
PREDICT_8x8_VR w
INIT_XMM ssse3
PREDICT_8x8_VR w
INIT_XMM avx
PREDICT_8x8_VR w
%elif ARCH_X86_64 == 0
INIT_MMX mmx2
PREDICT_8x8_VR b
%endif

%macro LOAD_PLANE_ARGS 0
%if cpuflag(avx2) && ARCH_X86_64 == 0
    vpbroadcastw m0, r1m
    vpbroadcastw m2, r2m
    vpbroadcastw m4, r3m
%elif mmsize == 8 ; MMX is only used on x86_32
    SPLATW       m0, r1m
    SPLATW       m2, r2m
    SPLATW       m4, r3m
%else
    movd        xm0, r1m
    movd        xm2, r2m
    movd        xm4, r3m
    SPLATW       m0, xm0
    SPLATW       m2, xm2
    SPLATW       m4, xm4
%endif
%endmacro

;-----------------------------------------------------------------------------
; void predict_8x8c_p_core( uint8_t *src, int i00, int b, int c )
;-----------------------------------------------------------------------------
%if ARCH_X86_64 == 0 && HIGH_BIT_DEPTH == 0
%macro PREDICT_CHROMA_P_MMX 1
cglobal predict_8x%1c_p_core, 1,2
    LOAD_PLANE_ARGS
    movq        m1, m2
    pmullw      m2, [pw_0to15]
    psllw       m1, 2
    paddsw      m0, m2        ; m0 = {i+0*b, i+1*b, i+2*b, i+3*b}
    paddsw      m1, m0        ; m1 = {i+4*b, i+5*b, i+6*b, i+7*b}
    mov         r1d, %1
ALIGN 4
.loop:
    movq        m5, m0
    movq        m6, m1
    psraw       m5, 5
    psraw       m6, 5
    packuswb    m5, m6
    movq        [r0], m5

    paddsw      m0, m4
    paddsw      m1, m4
    add         r0, FDEC_STRIDE
    dec         r1d
    jg .loop
    RET
%endmacro ; PREDICT_CHROMA_P_MMX

INIT_MMX mmx2
PREDICT_CHROMA_P_MMX 8
PREDICT_CHROMA_P_MMX 16
%endif ; !ARCH_X86_64 && !HIGH_BIT_DEPTH

%macro PREDICT_CHROMA_P 1
%if HIGH_BIT_DEPTH
cglobal predict_8x%1c_p_core, 1,2,7
    LOAD_PLANE_ARGS
    mova        m3, [pw_pixel_max]
    pxor        m1, m1
    pmullw      m2, [pw_43210123] ; b
%if %1 == 16
    pmullw      m5, m4, [pw_m7]   ; c
%else
    pmullw      m5, m4, [pw_m3]
%endif
    paddw       m5, [pw_16]
%if mmsize == 32
    mova       xm6, xm4
    paddw       m4, m4
    paddw       m5, m6
%endif
    mov        r1d, %1/(mmsize/16)
.loop:
    paddsw      m6, m2, m5
    paddsw      m6, m0
    psraw       m6, 5
    CLIPW       m6, m1, m3
    paddw       m5, m4
%if mmsize == 32
    vextracti128 [r0], m6, 1
    mova [r0+FDEC_STRIDEB], xm6
    add         r0, 2*FDEC_STRIDEB
%else
    mova      [r0], m6
    add         r0, FDEC_STRIDEB
%endif
    dec        r1d
    jg .loop
    RET
%else ; !HIGH_BIT_DEPTH
cglobal predict_8x%1c_p_core, 1,2
    LOAD_PLANE_ARGS
%if mmsize == 32
    vbroadcasti128 m1, [pw_0to15]   ; 0 1 2 3 4 5 6 7 0 1 2 3 4 5 6 7
    pmullw      m2, m1
    mova       xm1, xm4             ; zero upper half
    paddsw      m4, m4
    paddsw      m0, m1
%else
    pmullw      m2, [pw_0to15]
%endif
    paddsw      m0, m2              ; m0 = {i+0*b, i+1*b, i+2*b, i+3*b, i+4*b, i+5*b, i+6*b, i+7*b}
    paddsw      m1, m0, m4
    paddsw      m4, m4
    mov        r1d, %1/(mmsize/8)
.loop:
    psraw       m2, m0, 5
    psraw       m3, m1, 5
    paddsw      m0, m4
    paddsw      m1, m4
    packuswb    m2, m3
%if mmsize == 32
    movq        [r0+FDEC_STRIDE*1], xm2
    movhps      [r0+FDEC_STRIDE*3], xm2
    vextracti128 xm2, m2, 1
    movq        [r0+FDEC_STRIDE*0], xm2
    movhps      [r0+FDEC_STRIDE*2], xm2
%else
    movq        [r0+FDEC_STRIDE*0], xm2
    movhps      [r0+FDEC_STRIDE*1], xm2
%endif
    add         r0, FDEC_STRIDE*mmsize/8
    dec        r1d
    jg .loop
    RET
%endif ; HIGH_BIT_DEPTH
%endmacro ; PREDICT_CHROMA_P

INIT_XMM sse2
PREDICT_CHROMA_P 8
PREDICT_CHROMA_P 16
INIT_XMM avx
PREDICT_CHROMA_P 8
PREDICT_CHROMA_P 16
INIT_YMM avx2
PREDICT_CHROMA_P 8
PREDICT_CHROMA_P 16

%if ARCH_X86_64
; 8-bit: words of rows 0 4 1 5 | 2 6 3 7 in the lanes of m0 | m1, so one packuswb
; holds 8 rows: pair k (lanes 0|2, bytes 8k..8k+7) goes to row 2k at r0+64k-8k.
; 10-bit: rows y..y+3 in the lanes.
%macro PREDICT_CHROMA_P_ICL 1
cglobal predict_8x%1c_p_core, 4,5
    vpbroadcastw    m0, r1d
    vpbroadcastw    m2, r2d
    vpbroadcastw    m4, r3d
%if HIGH_BIT_DEPTH
    vbroadcasti32x4 m1, [pw_43210123]
    vpmovsxbw       m5, [pb_p8x%1c_rows]
    pmullw          m2, m1            ; b*(x-3)
    pmullw          m5, m4            ; c*(y-3) or c*(y-7)
    vpbroadcastd    m1, [pw_16]
    paddw           m5, m1
    psllw           m4, 2
    pxor            m1, m1
    vpbroadcastd    m3, [pw_pixel_max]
    mov            r4d, %1/4
.loop:
    paddsw          m6, m2, m5
    paddsw          m6, m0
    psraw           m6, 5
    CLIPW           m6, m1, m3
    paddw           m5, m4
    mova            [r0+0*FDEC_STRIDEB], xm6
    vextracti32x4   [r0+1*FDEC_STRIDEB], m6, 1
    vextracti32x4   [r0+2*FDEC_STRIDEB], m6, 2
    vextracti32x4   [r0+3*FDEC_STRIDEB], m6, 3
    add             r0, 4*FDEC_STRIDEB
    dec            r4d
    jg .loop
%else ; !HIGH_BIT_DEPTH
    vbroadcasti32x4 m1, [pw_0to15]
    vpmovzxbw       m3, [pb_p8c_rows]
    pmullw          m1, m2            ; b*x
    pmullw          m3, m4            ; c*y
    paddsw          m0, m3
    paddsw          m0, m1            ; rows 0 4 1 5
    paddsw          m1, m0, m4
    paddsw          m1, m4            ; rows 2 6 3 7
    mov             r4, 0x000000ff000000ff
    kmovq           k1, r4
    kshiftlq        k2, k1, 8
    kshiftlq        k3, k1, 16
    kshiftlq        k4, k1, 24
%if %1 == 16
    psllw           m4, 3
    mov            r4d, 2
.loop:
%endif
    psraw           m2, m0, 5
    psraw           m3, m1, 5
    packuswb        m2, m3
    vmovdqu8 [r0+0*FDEC_STRIDE   ]{k1}, m2
    vmovdqu8 [r0+2*FDEC_STRIDE- 8]{k2}, m2
    vmovdqu8 [r0+4*FDEC_STRIDE-16]{k3}, m2
    vmovdqu8 [r0+6*FDEC_STRIDE-24]{k4}, m2
%if %1 == 16
    paddsw          m0, m4
    paddsw          m1, m4
    add             r0, 8*FDEC_STRIDE
    dec            r4d
    jg .loop
%endif
%endif ; HIGH_BIT_DEPTH
    RET
%endmacro ; PREDICT_CHROMA_P_ICL

INIT_ZMM avx512icl
PREDICT_CHROMA_P_ICL 8
PREDICT_CHROMA_P_ICL 16
%endif ; ARCH_X86_64

;-----------------------------------------------------------------------------
; void predict_16x16_p_core( uint8_t *src, int i00, int b, int c )
;-----------------------------------------------------------------------------
%if HIGH_BIT_DEPTH == 0 && ARCH_X86_64 == 0
INIT_MMX mmx2
cglobal predict_16x16_p_core, 1,2
    LOAD_PLANE_ARGS
    movq        mm5, mm2
    movq        mm1, mm2
    pmullw      mm5, [pw_0to15]
    psllw       mm2, 3
    psllw       mm1, 2
    movq        mm3, mm2
    paddsw      mm0, mm5        ; mm0 = {i+ 0*b, i+ 1*b, i+ 2*b, i+ 3*b}
    paddsw      mm1, mm0        ; mm1 = {i+ 4*b, i+ 5*b, i+ 6*b, i+ 7*b}
    paddsw      mm2, mm0        ; mm2 = {i+ 8*b, i+ 9*b, i+10*b, i+11*b}
    paddsw      mm3, mm1        ; mm3 = {i+12*b, i+13*b, i+14*b, i+15*b}

    mov         r1d, 16
ALIGN 4
.loop:
    movq        mm5, mm0
    movq        mm6, mm1
    psraw       mm5, 5
    psraw       mm6, 5
    packuswb    mm5, mm6
    movq        [r0], mm5

    movq        mm5, mm2
    movq        mm6, mm3
    psraw       mm5, 5
    psraw       mm6, 5
    packuswb    mm5, mm6
    movq        [r0+8], mm5

    paddsw      mm0, mm4
    paddsw      mm1, mm4
    paddsw      mm2, mm4
    paddsw      mm3, mm4
    add         r0, FDEC_STRIDE
    dec         r1d
    jg          .loop
    RET
%endif ; !HIGH_BIT_DEPTH && !ARCH_X86_64

%macro PREDICT_16x16_P 0
cglobal predict_16x16_p_core, 1,2,8
    movd     m0, r1m
    movd     m1, r2m
    movd     m2, r3m
    SPLATW   m0, m0, 0
    SPLATW   m1, m1, 0
    SPLATW   m2, m2, 0
    pmullw   m3, m1, [pw_0to15]
    psllw    m1, 3
%if HIGH_BIT_DEPTH
    pxor     m6, m6
    mov     r1d, 16
.loop:
    mova     m4, m0
    mova     m5, m0
    mova     m7, m3
    paddsw   m7, m6
    paddsw   m4, m7
    paddsw   m7, m1
    paddsw   m5, m7
    psraw    m4, 5
    psraw    m5, 5
    CLIPW    m4, [pb_0], [pw_pixel_max]
    CLIPW    m5, [pb_0], [pw_pixel_max]
    mova   [r0], m4
    mova [r0+16], m5
    add      r0, FDEC_STRIDEB
    paddw    m6, m2
%else ; !HIGH_BIT_DEPTH
    paddsw   m0, m3  ; m0 = {i+ 0*b, i+ 1*b, i+ 2*b, i+ 3*b, i+ 4*b, i+ 5*b, i+ 6*b, i+ 7*b}
    paddsw   m1, m0  ; m1 = {i+ 8*b, i+ 9*b, i+10*b, i+11*b, i+12*b, i+13*b, i+14*b, i+15*b}
    paddsw   m7, m2, m2
    mov     r1d, 8
ALIGN 4
.loop:
    psraw    m3, m0, 5
    psraw    m4, m1, 5
    paddsw   m5, m0, m2
    paddsw   m6, m1, m2
    psraw    m5, 5
    psraw    m6, 5
    packuswb m3, m4
    packuswb m5, m6
    mova [r0+FDEC_STRIDE*0], m3
    mova [r0+FDEC_STRIDE*1], m5
    paddsw   m0, m7
    paddsw   m1, m7
    add      r0, FDEC_STRIDE*2
%endif ; !HIGH_BIT_DEPTH
    dec     r1d
    jg .loop
    RET
%endmacro ; PREDICT_16x16_P

INIT_XMM sse2
PREDICT_16x16_P
%if HIGH_BIT_DEPTH == 0
INIT_XMM avx
PREDICT_16x16_P
%endif

INIT_YMM avx2
cglobal predict_16x16_p_core, 1,2,8*HIGH_BIT_DEPTH
    LOAD_PLANE_ARGS
%if HIGH_BIT_DEPTH
    pmullw       m2, [pw_0to15]
    pxor         m5, m5
    pxor         m6, m6
    mova         m7, [pw_pixel_max]
    mov         r1d, 8
.loop:
    paddsw       m1, m2, m5
    paddw        m5, m4
    paddsw       m1, m0
    paddsw       m3, m2, m5
    psraw        m1, 5
    paddsw       m3, m0
    psraw        m3, 5
    CLIPW        m1, m6, m7
    mova [r0+0*FDEC_STRIDEB], m1
    CLIPW        m3, m6, m7
    mova [r0+1*FDEC_STRIDEB], m3
    paddw        m5, m4
    add          r0, 2*FDEC_STRIDEB
%else ; !HIGH_BIT_DEPTH
    vbroadcasti128 m1, [pw_0to15]
    mova        xm3, xm4    ; zero high bits
    pmullw       m1, m2
    psllw        m2, 3
    paddsw       m0, m3
    paddsw       m0, m1     ; X+1*C X+0*C
    paddsw       m1, m0, m2 ; Y+1*C Y+0*C
    paddsw       m4, m4
    mov         r1d, 4
.loop:
    psraw        m2, m0, 5
    psraw        m3, m1, 5
    paddsw       m0, m4
    paddsw       m1, m4
    packuswb     m2, m3     ; X+1*C Y+1*C X+0*C Y+0*C
    vextracti128 [r0+0*FDEC_STRIDE], m2, 1
    mova         [r0+1*FDEC_STRIDE], xm2
    psraw        m2, m0, 5
    psraw        m3, m1, 5
    paddsw       m0, m4
    paddsw       m1, m4
    packuswb     m2, m3     ; X+3*C Y+3*C X+2*C Y+2*C
    vextracti128 [r0+2*FDEC_STRIDE], m2, 1
    mova         [r0+3*FDEC_STRIDE], xm2
    add          r0, FDEC_STRIDE*4
%endif ; !HIGH_BIT_DEPTH
    dec         r1d
    jg .loop
    RET

%if ARCH_X86_64
; 8-bit: x 0-7 | 8-15 of rows 0 2 1 3 in the lanes of m0 | m1; after packuswb
; lanes 0|2 are rows 0|1 and lanes 1|3 rows 2|3 (stored from r0+48).
; 10-bit: rows y|y+1 in the ymm halves.
INIT_ZMM avx512icl
cglobal predict_16x16_p_core, 4,5
    vpbroadcastw    m0, r1d
    vpbroadcastw    m2, r2d
    vpbroadcastw    m4, r3d
%if HIGH_BIT_DEPTH
    vbroadcasti32x8 m1, [pw_0to15]
    pmullw          m2, m1            ; b*x
    mov            r4d, 0xffff0000
    kmovd           k1, r4d
    vmovdqu16       m5{k1}{z}, m4     ; c*y
    paddw           m4, m4
    pxor            m6, m6
    vpbroadcastd    m3, [pw_pixel_max]
    mov            r4d, 8
.loop:
    paddsw          m1, m2, m5
    paddsw          m1, m0
    psraw           m1, 5
    CLIPW           m1, m6, m3
    paddw           m5, m4
    mova            [r0+0*FDEC_STRIDEB], ym1
    vextracti32x8   [r0+1*FDEC_STRIDEB], m1, 1
    add             r0, 2*FDEC_STRIDEB
%else ; !HIGH_BIT_DEPTH
    vbroadcasti32x4 m1, [pw_0to15]
    vpmovzxbw       m3, [pb_p16_rows]
    pmullw          m1, m2            ; b*x
    pmullw          m3, m4            ; c*y
    psllw           m2, 3
    paddsw          m0, m3
    paddsw          m0, m1            ; x 0-7
    paddsw          m1, m0, m2        ; x 8-15
    psllw           m4, 2
    mov             r4, 0x0000ffff0000ffff
    kmovq           k1, r4
    kshiftlq        k2, k1, 16
    mov            r4d, 4
.loop:
    psraw           m2, m0, 5
    psraw           m3, m1, 5
    packuswb        m2, m3
    vmovdqu8 [r0+0*FDEC_STRIDE   ]{k1}, m2
    vmovdqu8 [r0+2*FDEC_STRIDE-16]{k2}, m2
    paddsw          m0, m4
    paddsw          m1, m4
    add             r0, 4*FDEC_STRIDE
%endif ; !HIGH_BIT_DEPTH
    dec            r4d
    jg .loop
    RET
%endif ; ARCH_X86_64

%if HIGH_BIT_DEPTH == 0
%macro PREDICT_8x8_DDL 0
;-----------------------------------------------------------------------------
; void predict_8x8_ddl( uint8_t *src, uint8_t *edge )
;-----------------------------------------------------------------------------
cglobal predict_8x8_ddl, 2,2
    mova        m0, [r1+16]
%ifidn cpuname, ssse3
    movd        m2, [r1+32]
    palignr     m2, m0, 1
%else
    movu        m2, [r1+17]
%endif
    pslldq      m1, m0, 1
    add        r0, FDEC_STRIDE*4
    PRED8x8_LOWPASS m0, m1, m2, m0, m3

%assign Y -4
%rep 8
    psrldq      m0, 1
    movq        [r0+Y*FDEC_STRIDE], m0
%assign Y (Y+1)
%endrep
    RET
%endmacro

%macro PREDICT_8x8_DDR 0
;-----------------------------------------------------------------------------
; void predict_8x8_ddr( uint8_t *src, uint8_t *edge )
;-----------------------------------------------------------------------------
cglobal predict_8x8_ddr, 2,2
    movu        m0, [r1+8]
    movu        m1, [r1+7]
    psrldq      m2, m0, 1
    add         r0, FDEC_STRIDE*4
    PRED8x8_LOWPASS m0, m1, m2, m0, m3

    psrldq      m1, m0, 1
%assign Y 3
%rep 3
    movq        [r0+Y*FDEC_STRIDE], m0
    movq        [r0+(Y-1)*FDEC_STRIDE], m1
    psrldq      m0, 2
    psrldq      m1, 2
%assign Y (Y-2)
%endrep
    movq        [r0-3*FDEC_STRIDE], m0
    movq        [r0-4*FDEC_STRIDE], m1
    RET
%endmacro

%macro PREDICT_8x8_VL 0
;-----------------------------------------------------------------------------
; void predict_8x8_vl( uint8_t *src, uint8_t *edge )
;-----------------------------------------------------------------------------
cglobal predict_8x8_vl, 2,2
    mova        m0, [r1+16]
    pslldq      m1, m0, 1
    psrldq      m2, m0, 1
    pavgb       m3, m0, m2
    add         r0, FDEC_STRIDE*4
    PRED8x8_LOWPASS m0, m1, m2, m0, m5
; m0: (t0 + 2*t1 + t2 + 2) >> 2
; m3: (t0 + t1 + 1) >> 1

%assign Y -4
%rep 3
    psrldq      m0, 1
    movq        [r0+ Y   *FDEC_STRIDE], m3
    movq        [r0+(Y+1)*FDEC_STRIDE], m0
    psrldq      m3, 1
%assign Y (Y+2)
%endrep
    psrldq      m0, 1
    movq        [r0+ Y   *FDEC_STRIDE], m3
    movq        [r0+(Y+1)*FDEC_STRIDE], m0
    RET
%endmacro

%macro PREDICT_8x8_VR 0
;-----------------------------------------------------------------------------
; void predict_8x8_vr( uint8_t *src, uint8_t *edge )
;-----------------------------------------------------------------------------
cglobal predict_8x8_vr, 2,2
    movu        m2, [r1+8]
    add         r0, 4*FDEC_STRIDE
    pslldq      m1, m2, 2
    pslldq      m0, m2, 1
    pavgb       m3, m2, m0
    PRED8x8_LOWPASS m0, m2, m1, m0, m4
    movhps      [r0-4*FDEC_STRIDE], m3
    movhps      [r0-3*FDEC_STRIDE], m0
%if cpuflag(ssse3)
    movhlps     m3, m3
    pshufb      m0, [shuf_vr]
    palignr     m3, m0, 13
%else
    mova        m2, m0
    mova        m1, [pw_00ff]
    pand        m1, m0
    psrlw       m0, 8
    packuswb    m1, m0
    pslldq      m1, 4
    movhlps     m3, m1
    shufps      m1, m2, q3210
    psrldq      m3, 5
    psrldq      m1, 5
    SWAP         0, 1
%endif
    movq        [r0+3*FDEC_STRIDE], m0
    movq        [r0+2*FDEC_STRIDE], m3
    psrldq      m0, 1
    psrldq      m3, 1
    movq        [r0+1*FDEC_STRIDE], m0
    movq        [r0+0*FDEC_STRIDE], m3
    psrldq      m0, 1
    psrldq      m3, 1
    movq        [r0-1*FDEC_STRIDE], m0
    movq        [r0-2*FDEC_STRIDE], m3
    RET
%endmacro

%macro PREDICT_8x8 0
    PREDICT_8x8_DDL
%ifnidn cpuname, ssse3
    PREDICT_8x8_DDR
    PREDICT_8x8_VL
%endif
    PREDICT_8x8_VR
%endmacro

INIT_XMM sse2
PREDICT_8x8
INIT_XMM ssse3
PREDICT_8x8
INIT_XMM avx
PREDICT_8x8
%if ARCH_X86_64
INIT_XMM avx512icl
PREDICT_8x8_DDL
PREDICT_8x8_DDR
PREDICT_8x8_VL
PREDICT_8x8_VR
%endif

%endif ; !HIGH_BIT_DEPTH

;-----------------------------------------------------------------------------
; void predict_8x8_vl( pixel *src, pixel *edge )
;-----------------------------------------------------------------------------
%macro PREDICT_8x8_VL_10 1
cglobal predict_8x8_vl, 2,2,8
    mova         m0, [r1+16*SIZEOF_PIXEL]
    mova         m1, [r1+24*SIZEOF_PIXEL]
    PALIGNR      m2, m1, m0, SIZEOF_PIXEL*1, m4
    PSRLPIX      m4, m1, 1
    pavg%1       m6, m0, m2
    pavg%1       m7, m1, m4
    add          r0, FDEC_STRIDEB*4
    mova         [r0-4*FDEC_STRIDEB], m6
    PALIGNR      m3, m7, m6, SIZEOF_PIXEL*1, m5
    mova         [r0-2*FDEC_STRIDEB], m3
    PALIGNR      m3, m7, m6, SIZEOF_PIXEL*2, m5
    mova         [r0+0*FDEC_STRIDEB], m3
    PALIGNR      m7, m7, m6, SIZEOF_PIXEL*3, m5
    mova         [r0+2*FDEC_STRIDEB], m7
    PALIGNR      m3, m1, m0, SIZEOF_PIXEL*7, m6
    PSLLPIX      m5, m0, 1
    PRED8x8_LOWPASS m0, m5, m2, m0, m7
    PRED8x8_LOWPASS m1, m3, m4, m1, m7
    PALIGNR      m4, m1, m0, SIZEOF_PIXEL*1, m2
    mova         [r0-3*FDEC_STRIDEB], m4
    PALIGNR      m4, m1, m0, SIZEOF_PIXEL*2, m2
    mova         [r0-1*FDEC_STRIDEB], m4
    PALIGNR      m4, m1, m0, SIZEOF_PIXEL*3, m2
    mova         [r0+1*FDEC_STRIDEB], m4
    PALIGNR      m1, m1, m0, SIZEOF_PIXEL*4, m2
    mova         [r0+3*FDEC_STRIDEB], m1
    RET
%endmacro
%if HIGH_BIT_DEPTH
INIT_XMM sse2
PREDICT_8x8_VL_10 w
INIT_XMM ssse3
PREDICT_8x8_VL_10 w
INIT_XMM avx
PREDICT_8x8_VL_10 w
%else
INIT_MMX mmx2
PREDICT_8x8_VL_10 b
%endif

;-----------------------------------------------------------------------------
; void predict_8x8_hd( pixel *src, pixel *edge )
;-----------------------------------------------------------------------------
%macro PREDICT_8x8_HD 2
cglobal predict_8x8_hd, 2,2
    add       r0, 4*FDEC_STRIDEB
    mova      m0, [r1+ 8*SIZEOF_PIXEL]     ; lt l0 l1 l2 l3 l4 l5 l6
    movu      m1, [r1+ 7*SIZEOF_PIXEL]     ; l0 l1 l2 l3 l4 l5 l6 l7
%ifidn cpuname, ssse3
    mova      m2, [r1+16*SIZEOF_PIXEL]     ; t7 t6 t5 t4 t3 t2 t1 t0
    mova      m4, m2                       ; t7 t6 t5 t4 t3 t2 t1 t0
    palignr   m2, m0, 7*SIZEOF_PIXEL       ; t6 t5 t4 t3 t2 t1 t0 lt
    palignr   m4, m0, 1*SIZEOF_PIXEL       ; t0 lt l0 l1 l2 l3 l4 l5
%else
    movu      m2, [r1+15*SIZEOF_PIXEL]
    movu      m4, [r1+ 9*SIZEOF_PIXEL]
%endif ; cpuflag
    pavg%1    m3, m0, m1
    PRED8x8_LOWPASS m0, m4, m1, m0, m5
    PSRLPIX   m4, m2, 2                    ; .. .. t6 t5 t4 t3 t2 t1
    PSRLPIX   m1, m2, 1                    ; .. t6 t5 t4 t3 t2 t1 t0
    PRED8x8_LOWPASS m1, m4, m2, m1, m5
                                           ; .. p11 p10 p9
    punpckh%2 m2, m3, m0                   ; p8 p7 p6 p5
    punpckl%2 m3, m0                       ; p4 p3 p2 p1
    mova      [r0+3*FDEC_STRIDEB], m3
    PALIGNR   m0, m2, m3, 2*SIZEOF_PIXEL, m5
    mova      [r0+2*FDEC_STRIDEB], m0
    PALIGNR   m0, m2, m3, 4*SIZEOF_PIXEL, m5
    mova      [r0+1*FDEC_STRIDEB], m0
    PALIGNR   m0, m2, m3, 6*SIZEOF_PIXEL, m3
    mova      [r0+0*FDEC_STRIDEB], m0
    mova      [r0-1*FDEC_STRIDEB], m2
    PALIGNR   m0, m1, m2, 2*SIZEOF_PIXEL, m5
    mova      [r0-2*FDEC_STRIDEB], m0
    PALIGNR   m0, m1, m2, 4*SIZEOF_PIXEL, m5
    mova      [r0-3*FDEC_STRIDEB], m0
    PALIGNR   m1, m1, m2, 6*SIZEOF_PIXEL, m2
    mova      [r0-4*FDEC_STRIDEB], m1
    RET
%endmacro

%if HIGH_BIT_DEPTH
INIT_XMM sse2
PREDICT_8x8_HD w, wd
INIT_XMM ssse3
PREDICT_8x8_HD w, wd
INIT_XMM avx
PREDICT_8x8_HD w, wd
%else
INIT_MMX mmx2
PREDICT_8x8_HD b, bw

;-----------------------------------------------------------------------------
; void predict_8x8_hd( uint8_t *src, uint8_t *edge )
;-----------------------------------------------------------------------------
%macro PREDICT_8x8_HD 0
cglobal predict_8x8_hd, 2,2
    add     r0, 4*FDEC_STRIDE
    movu    m1, [r1+7]
    movu    m3, [r1+8]
    movu    m2, [r1+9]
    pavgb   m4, m1, m3
    PRED8x8_LOWPASS m0, m1, m2, m3, m5
    punpcklbw m4, m0
    movhlps m0, m4

%assign Y 3
%rep 3
    movq   [r0+(Y)*FDEC_STRIDE], m4
    movq   [r0+(Y-4)*FDEC_STRIDE], m0
    psrldq m4, 2
    psrldq m0, 2
%assign Y (Y-1)
%endrep
    movq   [r0+(Y)*FDEC_STRIDE], m4
    movq   [r0+(Y-4)*FDEC_STRIDE], m0
    RET
%endmacro

INIT_XMM sse2
PREDICT_8x8_HD
INIT_XMM avx
PREDICT_8x8_HD
%endif ; HIGH_BIT_DEPTH

%if HIGH_BIT_DEPTH == 0
;-----------------------------------------------------------------------------
; void predict_8x8_hu( uint8_t *src, uint8_t *edge )
;-----------------------------------------------------------------------------
INIT_MMX
cglobal predict_8x8_hu_sse2, 2,2
    add        r0, 4*FDEC_STRIDE
    movq      mm1, [r1+7]           ; l0 l1 l2 l3 l4 l5 l6 l7
    pshufw    mm0, mm1, q0123       ; l6 l7 l4 l5 l2 l3 l0 l1
    movq      mm2, mm0
    psllw     mm0, 8
    psrlw     mm2, 8
    por       mm2, mm0              ; l7 l6 l5 l4 l3 l2 l1 l0
    psllq     mm1, 56               ; l7 .. .. .. .. .. .. ..
    movq      mm3, mm2
    movq      mm4, mm2
    movq      mm5, mm2
    psrlq     mm2, 8
    psrlq     mm3, 16
    por       mm2, mm1              ; l7 l7 l6 l5 l4 l3 l2 l1
    punpckhbw mm1, mm1
    por       mm3, mm1              ; l7 l7 l7 l6 l5 l4 l3 l2
    pavgb     mm4, mm2
    PRED8x8_LOWPASS mm1, mm3, mm5, mm2, mm6

    movq2dq   xmm0, mm4
    movq2dq   xmm1, mm1
    punpcklbw xmm0, xmm1
    punpckhbw  mm4, mm1
%assign Y -4
%rep 3
    movq     [r0+Y*FDEC_STRIDE], xmm0
    psrldq    xmm0, 2
%assign Y (Y+1)
%endrep
    pshufw     mm5, mm4, q3321
    pshufw     mm6, mm4, q3332
    pshufw     mm7, mm4, q3333
    movq     [r0+Y*FDEC_STRIDE], xmm0
    movq     [r0+0*FDEC_STRIDE], mm4
    movq     [r0+1*FDEC_STRIDE], mm5
    movq     [r0+2*FDEC_STRIDE], mm6
    movq     [r0+3*FDEC_STRIDE], mm7
    RET

INIT_XMM
cglobal predict_8x8_hu_ssse3, 2,2
    add       r0, 4*FDEC_STRIDE
    movq      m3, [r1+7]
    pshufb    m3, [shuf_hu]
    psrldq    m1, m3, 1
    psrldq    m2, m3, 2
    pavgb     m0, m1, m3
    PRED8x8_LOWPASS m1, m3, m2, m1, m4
    punpcklbw m0, m1
%assign Y -4
%rep 3
    movq   [r0+ Y   *FDEC_STRIDE], m0
    movhps [r0+(Y+4)*FDEC_STRIDE], m0
    psrldq    m0, 2
    pshufhw   m0, m0, q2210
%assign Y (Y+1)
%endrep
    movq   [r0+ Y   *FDEC_STRIDE], m0
    movhps [r0+(Y+4)*FDEC_STRIDE], m0
    RET
%endif ; !HIGH_BIT_DEPTH

%if ARCH_X86_64
;-----------------------------------------------------------------------------
; avx512icl 8x8 directional modes: the rows come from the filtered edge by
; vpermb/vpermw. 8-bit: one zmm holds a row pair (row y in bytes 0-7, row y+1
; in bytes 32-39) for a masked store, valignd steps two rows. 10-bit: one zmm
; holds 4 rows, one per lane.
;-----------------------------------------------------------------------------
%macro STORE4_ICL 2 ; zmm number, first row
    mova          [r0+(%2+0)*FDEC_STRIDEB], xm%1
    vextracti32x4 [r0+(%2+1)*FDEC_STRIDEB], m%1, 1
    vextracti32x4 [r0+(%2+2)*FDEC_STRIDEB], m%1, 2
    vextracti32x4 [r0+(%2+3)*FDEC_STRIDEB], m%1, 3
%endmacro

; rows %2, %2+2*%3, ... of the row pairs in %1, valignd between
%macro STORE_PAIRS_ICL 3 ; zmm, first row, row step
    vmovdqu8 [r0+(%2+0*%3)*FDEC_STRIDE]{k1}, %1
    valignd       %1, %1, %1, 1
    vmovdqu8 [r0+(%2+1*%3)*FDEC_STRIDE]{k1}, %1
    valignd       %1, %1, %1, 1
    vmovdqu8 [r0+(%2+2*%3)*FDEC_STRIDE]{k1}, %1
    valignd       %1, %1, %1, 1
    vmovdqu8 [r0+(%2+3*%3)*FDEC_STRIDE]{k1}, %1
%endmacro

INIT_ZMM avx512icl
%if HIGH_BIT_DEPTH == 0
;-----------------------------------------------------------------------------
; void predict_8x8_hd( uint8_t *src, uint8_t *edge )
;-----------------------------------------------------------------------------
cglobal predict_8x8_hd, 2,3
    movu        xm1, [r1+7]
    movu        xm3, [r1+8]
    movu        xm2, [r1+9]
    pavgb       xm4, xm1, xm3
    PRED8x8_LOWPASS xm0, xm1, xm2, xm3, xm5
    movu         m1, [pb_hd_icl]
    vpermi2b     m1, m4, m0
    mov          r2, 0x000000ff000000ff
    kmovq        k1, r2
    STORE_PAIRS_ICL m1, 6, -2
    RET

;-----------------------------------------------------------------------------
; void predict_8x8_hu( uint8_t *src, uint8_t *edge )
;-----------------------------------------------------------------------------
cglobal predict_8x8_hu, 2,3
    movq        xm3, [r1+7]
    pshufb      xm3, [shuf_hu]
    psrldq      xm1, xm3, 1
    psrldq      xm2, xm3, 2
    pavgb       xm0, xm1, xm3
    PRED8x8_LOWPASS xm1, xm3, xm2, xm1, xm4
    movu         m2, [pb_hu_icl]
    vpermi2b     m2, m0, m1
    mov          r2, 0x000000ff000000ff
    kmovq        k1, r2
    STORE_PAIRS_ICL m2, 0, 2
    RET

%else ; HIGH_BIT_DEPTH
;-----------------------------------------------------------------------------
; void predict_8x8_ddl( uint16_t *src, uint16_t *edge )
;-----------------------------------------------------------------------------
cglobal predict_8x8_ddl, 2,2
    movu        ym0, [r1+16*SIZEOF_PIXEL]
    movu        ym1, [r1+15*SIZEOF_PIXEL]
    movu        ym2, [r1+17*SIZEOF_PIXEL]
    PRED8x8_LOWPASS ym0, ym1, ym2, ym0
    movu         m3, [pw_ddl_icl]
    vpermw       m1, m3, m0
    vpbroadcastd m2, [pw_4]
    paddw        m3, m2
    vpermw       m2, m3, m0
    STORE4_ICL   1, 0
    STORE4_ICL   2, 4
    RET

;-----------------------------------------------------------------------------
; void predict_8x8_ddr( uint16_t *src, uint16_t *edge )
;-----------------------------------------------------------------------------
cglobal predict_8x8_ddr, 2,2
    movu        ym0, [r1+8*SIZEOF_PIXEL]
    movu        ym1, [r1+7*SIZEOF_PIXEL]
    movu        ym2, [r1+9*SIZEOF_PIXEL]
    PRED8x8_LOWPASS ym0, ym1, ym2, ym0
    movu         m3, [pw_ddr_icl]
    vpermw       m1, m3, m0
    vpbroadcastd m2, [pw_4]
    psubw        m3, m2
    vpermw       m2, m3, m0
    STORE4_ICL   1, 0
    STORE4_ICL   2, 4
    RET

;-----------------------------------------------------------------------------
; void predict_8x8_vl( uint16_t *src, uint16_t *edge )
;-----------------------------------------------------------------------------
cglobal predict_8x8_vl, 2,2
    movu        ym0, [r1+16*SIZEOF_PIXEL]
    movu        ym1, [r1+15*SIZEOF_PIXEL]
    movu        ym2, [r1+17*SIZEOF_PIXEL]
    pavgw       ym3, ym0, ym2
    PRED8x8_LOWPASS ym0, ym1, ym2, ym0
    movu         m4, [pw_vl_icl]
    vpbroadcastd m5, [pw_2]
    paddw        m5, m4
    vpermi2w     m4, m3, m0
    vpermi2w     m5, m3, m0
    STORE4_ICL   4, 0
    STORE4_ICL   5, 4
    RET

;-----------------------------------------------------------------------------
; void predict_8x8_vr( uint16_t *src, uint16_t *edge )
;-----------------------------------------------------------------------------
cglobal predict_8x8_vr, 2,2
    movu        ym0, [r1+8*SIZEOF_PIXEL]
    movu        ym1, [r1+7*SIZEOF_PIXEL]
    movu        ym2, [r1+9*SIZEOF_PIXEL]
    pavgw       ym3, ym0, ym2
    PRED8x8_LOWPASS ym0, ym1, ym2, ym0
    movu         m4, [pw_vr_icl]
    movu         m5, [pw_vr4_icl]
    vpermi2w     m4, m3, m0
    vpermi2w     m5, m3, m0
    STORE4_ICL   4, 0
    STORE4_ICL   5, 4
    RET

;-----------------------------------------------------------------------------
; void predict_8x8_hd( uint16_t *src, uint16_t *edge )
;-----------------------------------------------------------------------------
cglobal predict_8x8_hd, 2,2
    movu        ym1, [r1+7*SIZEOF_PIXEL]
    movu        ym0, [r1+8*SIZEOF_PIXEL]
    movu        ym2, [r1+9*SIZEOF_PIXEL]
    pavgw       ym3, ym1, ym0
    PRED8x8_LOWPASS ym0, ym1, ym2, ym0
    movu         m4, [pw_hd_icl]
    movu         m5, [pw_hd4_icl]
    vpermi2w     m4, m3, m0
    vpermi2w     m5, m3, m0
    STORE4_ICL   4, 0
    STORE4_ICL   5, 4
    RET

;-----------------------------------------------------------------------------
; void predict_8x8_hu( uint16_t *src, uint16_t *edge )
;-----------------------------------------------------------------------------
cglobal predict_8x8_hu, 2,2
    movu        ym3, [pw_hu_left]
    vpbroadcastd ym4, [pw_1]
    vpermw      ym0, ym3, [r1+7*SIZEOF_PIXEL] ; l0 .. l7 l7 ..
    psubusw     ym3, ym4
    vpermw      ym1, ym3, [r1+7*SIZEOF_PIXEL] ; l1 .. l7 l7 ..
    psubusw     ym3, ym4
    vpermw      ym2, ym3, [r1+7*SIZEOF_PIXEL] ; l2 .. l7 l7 ..
    pavgw       ym5, ym0, ym1
    PRED8x8_LOWPASS ym1, ym0, ym2, ym1
    movu         m3, [pw_hu_icl]
    vpbroadcastd m4, [pw_4]
    paddw        m4, m3
    vpermi2w     m3, m5, m1
    vpermi2w     m4, m5, m1
    STORE4_ICL   3, 0
    STORE4_ICL   4, 4
    RET
%endif ; HIGH_BIT_DEPTH
%endif ; ARCH_X86_64

;-----------------------------------------------------------------------------
; void predict_8x8c_v( uint8_t *src )
;-----------------------------------------------------------------------------

%macro PREDICT_8x8C_V 0
cglobal predict_8x8c_v, 1,1
    mova        m0, [r0 - FDEC_STRIDEB]
    STORE8      m0
    RET
%endmacro

%if HIGH_BIT_DEPTH
INIT_XMM sse
PREDICT_8x8C_V
%else
INIT_MMX mmx
PREDICT_8x8C_V
%endif

%if HIGH_BIT_DEPTH

INIT_MMX
cglobal predict_8x8c_v_mmx, 1,1
    mova        m0, [r0 - FDEC_STRIDEB]
    mova        m1, [r0 - FDEC_STRIDEB + 8]
%assign Y 0
%rep 8
    mova        [r0 + (Y&1)*FDEC_STRIDEB], m0
    mova        [r0 + (Y&1)*FDEC_STRIDEB + 8], m1
%if (Y&1) && (Y!=7)
    add         r0, FDEC_STRIDEB*2
%endif
%assign Y Y+1
%endrep
    RET

%endif

%macro PREDICT_8x16C_V 0
cglobal predict_8x16c_v, 1,1
    mova        m0, [r0 - FDEC_STRIDEB]
    STORE16     m0
    RET
%endmacro

%if HIGH_BIT_DEPTH
INIT_XMM sse
PREDICT_8x16C_V
%else
INIT_MMX mmx
PREDICT_8x16C_V
%endif

;-----------------------------------------------------------------------------
; void predict_8x8c_h( uint8_t *src )
;-----------------------------------------------------------------------------
%macro PREDICT_C_H 0
cglobal predict_8x8c_h, 1,1
%if cpuflag(ssse3) && notcpuflag(avx2)
    mova  m2, [pb_3]
%endif
    PRED_H_4ROWS 8, 1
    PRED_H_4ROWS 8, 0
    RET

cglobal predict_8x16c_h, 1,2
%if cpuflag(ssse3) && notcpuflag(avx2)
    mova  m2, [pb_3]
%endif
    mov  r1d, 4
.loop:
    PRED_H_4ROWS 8, 1
    dec  r1d
    jg .loop
    RET
%endmacro

INIT_MMX mmx2
PREDICT_C_H
%if HIGH_BIT_DEPTH
INIT_XMM sse2
PREDICT_C_H
INIT_XMM avx2
PREDICT_C_H
%else
INIT_MMX ssse3
PREDICT_C_H
%endif

;-----------------------------------------------------------------------------
; void predict_8x8c_dc( pixel *src )
;-----------------------------------------------------------------------------
%macro LOAD_LEFT 1
    movzx    r1d, pixel [r0+FDEC_STRIDEB*(%1-4)-SIZEOF_PIXEL]
    movzx    r2d, pixel [r0+FDEC_STRIDEB*(%1-3)-SIZEOF_PIXEL]
    add      r1d, r2d
    movzx    r2d, pixel [r0+FDEC_STRIDEB*(%1-2)-SIZEOF_PIXEL]
    add      r1d, r2d
    movzx    r2d, pixel [r0+FDEC_STRIDEB*(%1-1)-SIZEOF_PIXEL]
    add      r1d, r2d
%endmacro

%macro PREDICT_8x8C_DC 0
cglobal predict_8x8c_dc, 1,3
    pxor      m7, m7
%if HIGH_BIT_DEPTH
    movq      m0, [r0-FDEC_STRIDEB+0]
    movq      m1, [r0-FDEC_STRIDEB+8]
    HADDW     m0, m2
    HADDW     m1, m2
%else ; !HIGH_BIT_DEPTH
    movd      m0, [r0-FDEC_STRIDEB+0]
    movd      m1, [r0-FDEC_STRIDEB+4]
    psadbw    m0, m7            ; s0
    psadbw    m1, m7            ; s1
%endif
    add       r0, FDEC_STRIDEB*4

    LOAD_LEFT 0                 ; s2
    movd      m2, r1d
    LOAD_LEFT 4                 ; s3
    movd      m3, r1d

    punpcklwd m0, m1
    punpcklwd m2, m3
    punpckldq m0, m2            ; s0, s1, s2, s3
    pshufw    m3, m0, q3312     ; s2, s1, s3, s3
    pshufw    m0, m0, q1310     ; s0, s1, s3, s1
    paddw     m0, m3
    psrlw     m0, 2
    pavgw     m0, m7            ; s0+s2, s1, s3, s1+s3
%if HIGH_BIT_DEPTH
%if cpuflag(sse2)
    movq2dq   xmm0, m0
    punpcklwd xmm0, xmm0
    pshufd    xmm1, xmm0, q3322
    punpckldq xmm0, xmm0
%assign Y 0
%rep 8
%assign i (0 + (Y/4))
    movdqa [r0+FDEC_STRIDEB*(Y-4)+0], xmm %+ i
%assign Y Y+1
%endrep
%else ; !sse2
    pshufw    m1, m0, q0000
    pshufw    m2, m0, q1111
    pshufw    m3, m0, q2222
    pshufw    m4, m0, q3333
%assign Y 0
%rep 8
%assign i (1 + (Y/4)*2)
%assign j (2 + (Y/4)*2)
    movq [r0+FDEC_STRIDEB*(Y-4)+0], m %+ i
    movq [r0+FDEC_STRIDEB*(Y-4)+8], m %+ j
%assign Y Y+1
%endrep
%endif
%else ; !HIGH_BIT_DEPTH
    packuswb  m0, m0
    punpcklbw m0, m0
    movq      m1, m0
    punpcklbw m0, m0
    punpckhbw m1, m1
%assign Y 0
%rep 8
%assign i (0 + (Y/4))
    movq [r0+FDEC_STRIDEB*(Y-4)], m %+ i
%assign Y Y+1
%endrep
%endif
    RET
%endmacro

INIT_MMX mmx2
PREDICT_8x8C_DC
%if HIGH_BIT_DEPTH
INIT_MMX sse2
PREDICT_8x8C_DC
%endif

%if HIGH_BIT_DEPTH
%macro STORE_4LINES 3
%if cpuflag(sse2)
    movdqa [r0+FDEC_STRIDEB*(%3-4)], %1
    movdqa [r0+FDEC_STRIDEB*(%3-3)], %1
    movdqa [r0+FDEC_STRIDEB*(%3-2)], %1
    movdqa [r0+FDEC_STRIDEB*(%3-1)], %1
%else
    movq [r0+FDEC_STRIDEB*(%3-4)+0], %1
    movq [r0+FDEC_STRIDEB*(%3-4)+8], %2
    movq [r0+FDEC_STRIDEB*(%3-3)+0], %1
    movq [r0+FDEC_STRIDEB*(%3-3)+8], %2
    movq [r0+FDEC_STRIDEB*(%3-2)+0], %1
    movq [r0+FDEC_STRIDEB*(%3-2)+8], %2
    movq [r0+FDEC_STRIDEB*(%3-1)+0], %1
    movq [r0+FDEC_STRIDEB*(%3-1)+8], %2
%endif
%endmacro
%else
%macro STORE_4LINES 2
    movq [r0+FDEC_STRIDEB*(%2-4)], %1
    movq [r0+FDEC_STRIDEB*(%2-3)], %1
    movq [r0+FDEC_STRIDEB*(%2-2)], %1
    movq [r0+FDEC_STRIDEB*(%2-1)], %1
%endmacro
%endif

%macro PREDICT_8x16C_DC 0
cglobal predict_8x16c_dc, 1,3
    pxor      m7, m7
%if HIGH_BIT_DEPTH
    movq      m0, [r0-FDEC_STRIDEB+0]
    movq      m1, [r0-FDEC_STRIDEB+8]
    HADDW     m0, m2
    HADDW     m1, m2
%else
    movd      m0, [r0-FDEC_STRIDEB+0]
    movd      m1, [r0-FDEC_STRIDEB+4]
    psadbw    m0, m7            ; s0
    psadbw    m1, m7            ; s1
%endif
    punpcklwd m0, m1            ; s0, s1

    add       r0, FDEC_STRIDEB*4
    LOAD_LEFT 0                 ; s2
    pinsrw    m0, r1d, 2
    LOAD_LEFT 4                 ; s3
    pinsrw    m0, r1d, 3        ; s0, s1, s2, s3
    add       r0, FDEC_STRIDEB*8
    LOAD_LEFT 0                 ; s4
    pinsrw    m1, r1d, 2
    LOAD_LEFT 4                 ; s5
    pinsrw    m1, r1d, 3        ; s1, __, s4, s5
    sub       r0, FDEC_STRIDEB*8

    pshufw    m2, m0, q1310     ; s0, s1, s3, s1
    pshufw    m0, m0, q3312     ; s2, s1, s3, s3
    pshufw    m3, m1, q0302     ; s4, s1, s5, s1
    pshufw    m1, m1, q3322     ; s4, s4, s5, s5
    paddw     m0, m2
    paddw     m1, m3
    psrlw     m0, 2
    psrlw     m1, 2
    pavgw     m0, m7
    pavgw     m1, m7
%if HIGH_BIT_DEPTH
%if cpuflag(sse2)
    movq2dq xmm0, m0
    movq2dq xmm1, m1
    punpcklwd xmm0, xmm0
    punpcklwd xmm1, xmm1
    pshufd    xmm2, xmm0, q3322
    pshufd    xmm3, xmm1, q3322
    punpckldq xmm0, xmm0
    punpckldq xmm1, xmm1
    STORE_4LINES xmm0, xmm0, 0
    STORE_4LINES xmm2, xmm2, 4
    STORE_4LINES xmm1, xmm1, 8
    STORE_4LINES xmm3, xmm3, 12
%else
    pshufw    m2, m0, q0000
    pshufw    m3, m0, q1111
    pshufw    m4, m0, q2222
    pshufw    m5, m0, q3333
    STORE_4LINES m2, m3, 0
    STORE_4LINES m4, m5, 4
    pshufw    m2, m1, q0000
    pshufw    m3, m1, q1111
    pshufw    m4, m1, q2222
    pshufw    m5, m1, q3333
    STORE_4LINES m2, m3, 8
    STORE_4LINES m4, m5, 12
%endif
%else
    packuswb  m0, m0            ; dc0, dc1, dc2, dc3
    packuswb  m1, m1            ; dc4, dc5, dc6, dc7
    punpcklbw m0, m0
    punpcklbw m1, m1
    pshufw    m2, m0, q1100
    pshufw    m3, m0, q3322
    pshufw    m4, m1, q1100
    pshufw    m5, m1, q3322
    STORE_4LINES m2, 0
    STORE_4LINES m3, 4
    add       r0, FDEC_STRIDEB*8
    STORE_4LINES m4, 0
    STORE_4LINES m5, 4
%endif
    RET
%endmacro

INIT_MMX mmx2
PREDICT_8x16C_DC
%if HIGH_BIT_DEPTH
INIT_MMX sse2
PREDICT_8x16C_DC
%endif

%macro PREDICT_C_DC_TOP 1
%if HIGH_BIT_DEPTH
INIT_XMM
cglobal predict_8x%1c_dc_top_sse2, 1,1
    pxor        m2, m2
    mova        m0, [r0 - FDEC_STRIDEB]
    pshufd      m1, m0, q2301
    paddw       m0, m1
    pshuflw     m1, m0, q2301
    pshufhw     m1, m1, q2301
    paddw       m0, m1
    psrlw       m0, 1
    pavgw       m0, m2
    STORE%1     m0
    RET
%else ; !HIGH_BIT_DEPTH
INIT_MMX
cglobal predict_8x%1c_dc_top_mmx2, 1,1
    movq        mm0, [r0 - FDEC_STRIDE]
    pxor        mm1, mm1
    pxor        mm2, mm2
    punpckhbw   mm1, mm0
    punpcklbw   mm0, mm2
    psadbw      mm1, mm2        ; s1
    psadbw      mm0, mm2        ; s0
    psrlw       mm1, 1
    psrlw       mm0, 1
    pavgw       mm1, mm2
    pavgw       mm0, mm2
    pshufw      mm1, mm1, 0
    pshufw      mm0, mm0, 0     ; dc0 (w)
    packuswb    mm0, mm1        ; dc0,dc1 (b)
    STORE%1     mm0
    RET
%endif
%endmacro

PREDICT_C_DC_TOP 8
PREDICT_C_DC_TOP 16

;-----------------------------------------------------------------------------
; void predict_16x16_v( pixel *src )
;-----------------------------------------------------------------------------

%macro PREDICT_16x16_V 0
cglobal predict_16x16_v, 1,2
%assign %%i 0
%rep 16*SIZEOF_PIXEL/mmsize
    mova m %+ %%i, [r0-FDEC_STRIDEB+%%i*mmsize]
%assign %%i %%i+1
%endrep
%if 16*SIZEOF_PIXEL/mmsize == 4
    STORE16 m0, m1, m2, m3
%elif 16*SIZEOF_PIXEL/mmsize == 2
    STORE16 m0, m1
%else
    STORE16 m0
%endif
    RET
%endmacro

INIT_MMX mmx2
PREDICT_16x16_V
INIT_XMM sse
PREDICT_16x16_V
%if HIGH_BIT_DEPTH
INIT_YMM avx
PREDICT_16x16_V
%endif

;-----------------------------------------------------------------------------
; void predict_16x16_h( pixel *src )
;-----------------------------------------------------------------------------
%macro PREDICT_16x16_H 0
cglobal predict_16x16_h, 1,2
%if cpuflag(ssse3) && notcpuflag(avx2)
    mova  m2, [pb_3]
%endif
    mov  r1d, 4
.loop:
    PRED_H_4ROWS 16, 1
    dec  r1d
    jg .loop
    RET
%endmacro

INIT_MMX mmx2
PREDICT_16x16_H
%if HIGH_BIT_DEPTH
INIT_XMM sse2
PREDICT_16x16_H
INIT_YMM avx2
PREDICT_16x16_H
%else
;no SSE2 for 8-bit, it's slower than MMX on all systems that don't support SSSE3
INIT_XMM ssse3
PREDICT_16x16_H
%endif

;-----------------------------------------------------------------------------
; void predict_16x16_dc_core( pixel *src, int i_dc_left )
;-----------------------------------------------------------------------------
%macro PRED16x16_DC_MMX 2
%if HIGH_BIT_DEPTH
    mova       m0, [r0 - FDEC_STRIDEB+ 0]
    paddw      m0, [r0 - FDEC_STRIDEB+ 8]
    paddw      m0, [r0 - FDEC_STRIDEB+16]
    paddw      m0, [r0 - FDEC_STRIDEB+24]
    HADDW      m0, m1
    paddw      m0, %1
    psrlw      m0, %2
    SPLATW     m0, m0
    STORE16    m0, m0, m0, m0
%else ; !HIGH_BIT_DEPTH
    pxor        m0, m0
    pxor        m1, m1
    psadbw      m0, [r0 - FDEC_STRIDE]
    psadbw      m1, [r0 - FDEC_STRIDE + 8]
    paddusw     m0, m1
    paddusw     m0, %1
    psrlw       m0, %2                      ; dc
    pshufw      m0, m0, 0
    packuswb    m0, m0                      ; dc in bytes
    STORE16     m0, m0
%endif
%endmacro

INIT_MMX mmx2
cglobal predict_16x16_dc_core, 1,2
%if ARCH_X86_64
    movd         m6, r1d
    PRED16x16_DC_MMX m6, 5
%else
    PRED16x16_DC_MMX r1m, 5
%endif
    RET

INIT_MMX mmx2
cglobal predict_16x16_dc_top, 1,2
    PRED16x16_DC_MMX [pw_8], 4
    RET

INIT_MMX mmx2
%if HIGH_BIT_DEPTH
cglobal predict_16x16_dc_left_core, 1,2
    movd       m0, r1m
    SPLATW     m0, m0
    STORE16    m0, m0, m0, m0
    RET
%else ; !HIGH_BIT_DEPTH
cglobal predict_16x16_dc_left_core, 1,1
    movd       m0, r1m
    pshufw     m0, m0, 0
    packuswb   m0, m0
    STORE16    m0, m0
    RET
%endif

%macro PRED16x16_DC 2
%if HIGH_BIT_DEPTH
    mova      xm0, [r0 - FDEC_STRIDEB+ 0]
    paddw     xm0, [r0 - FDEC_STRIDEB+16]
    HADDW     xm0, xm2
    paddw     xm0, %1
    psrlw     xm0, %2
    SPLATW     m0, xm0
%if mmsize == 32
    STORE16    m0
%else
    STORE16    m0, m0
%endif
%else ; !HIGH_BIT_DEPTH
    pxor        m0, m0
    psadbw      m0, [r0 - FDEC_STRIDE]
    movhlps     m1, m0
    paddw       m0, m1
    paddusw     m0, %1
    psrlw       m0, %2              ; dc
    SPLATW      m0, m0
    packuswb    m0, m0              ; dc in bytes
    STORE16     m0
%endif
%endmacro

%macro PREDICT_16x16_DC_CORE 0
cglobal predict_16x16_dc_core, 2,2,4
    movd         xm3, r1m
    PRED16x16_DC xm3, 5
    RET

cglobal predict_16x16_dc_top, 1,2
    PRED16x16_DC [pw_8], 4
    RET

cglobal predict_16x16_dc_left_core, 1,2
    movd      xm0, r1m
    SPLATW     m0, xm0
%if HIGH_BIT_DEPTH && mmsize == 16
    STORE16    m0, m0
%else
%if HIGH_BIT_DEPTH == 0
    packuswb   m0, m0
%endif
    STORE16    m0
%endif
    RET
%endmacro

INIT_XMM sse2
PREDICT_16x16_DC_CORE
%if HIGH_BIT_DEPTH
INIT_YMM avx2
PREDICT_16x16_DC_CORE
%else
INIT_XMM avx2
PREDICT_16x16_DC_CORE
%endif

; %1 rows of %3 at FDEC_STRIDE, using %2. More than 4 rows moves r0.
%macro STORE_ROWS 3
%if %1 == 4
    %2 [r0+0*FDEC_STRIDEB], %3
    %2 [r0+1*FDEC_STRIDEB], %3
    %2 [r0+2*FDEC_STRIDEB], %3
    %2 [r0+3*FDEC_STRIDEB], %3
%else
    add  r0, 4*FDEC_STRIDEB
%assign %%i 0
%rep %1/8
%if %%i
    add  r0, 8*FDEC_STRIDEB
%endif
    %2 [r0-4*FDEC_STRIDEB], %3
    %2 [r0-3*FDEC_STRIDEB], %3
    %2 [r0-2*FDEC_STRIDEB], %3
    %2 [r0-1*FDEC_STRIDEB], %3
    %2 [r0+0*FDEC_STRIDEB], %3
    %2 [r0+1*FDEC_STRIDEB], %3
    %2 [r0+2*FDEC_STRIDEB], %3
    %2 [r0+3*FDEC_STRIDEB], %3
%assign %%i %%i+1
%endrep
%endif
%endmacro

; r1d = (left neighbours of rows %1..%1+3 + 2) >> 2
%macro PRED_LEFT4 1
    movzx      r1d, pixel [r0+(%1+0)*FDEC_STRIDEB-SIZEOF_PIXEL]
    movzx      r2d, pixel [r0+(%1+1)*FDEC_STRIDEB-SIZEOF_PIXEL]
    add        r1d, r2d
    movzx      r2d, pixel [r0+(%1+2)*FDEC_STRIDEB-SIZEOF_PIXEL]
    add        r1d, r2d
    movzx      r2d, pixel [r0+(%1+3)*FDEC_STRIDEB-SIZEOF_PIXEL]
    lea        r1d, [r1+r2+2]
    shr        r1d, 2
%endmacro

%if HIGH_BIT_DEPTH
    %define MOVPIX4 movq ; one 4-pixel row
%else
    %define MOVPIX4 movd
%endif

; 4x4 block of r1d
%macro PRED4x4_DC_STORE 0
%if HIGH_BIT_DEPTH
    movd        m0, r1d
    pshuflw     m0, m0, q0000
    STORE_ROWS   4, movq, m0
%else
    imul       r1d, 0x01010101
    STORE_ROWS   4, mov, r1d
%endif
%endmacro

;-----------------------------------------------------------------------------
; void predict_4x4_v( pixel *src )
;-----------------------------------------------------------------------------
INIT_XMM sse2
cglobal predict_4x4_v, 1,1
    MOVPIX4     m0, [r0-FDEC_STRIDEB]
    STORE_ROWS   4, MOVPIX4, m0
    RET

%if HIGH_BIT_DEPTH == 0
;-----------------------------------------------------------------------------
; void predict_4x4_h( uint8_t *src )
;-----------------------------------------------------------------------------
%macro PRED4x4_H_ROW 1
    movzx      r1d, byte [r0+%1*FDEC_STRIDE-1]
    imul       r1d, 0x01010101
    mov [r0+%1*FDEC_STRIDE], r1d
%endmacro

cglobal predict_4x4_h, 1,2
    PRED4x4_H_ROW 0
    PRED4x4_H_ROW 1
    PRED4x4_H_ROW 2
    PRED4x4_H_ROW 3
    RET
%endif

;-----------------------------------------------------------------------------
; void predict_4x4_dc_left( pixel *src )
;-----------------------------------------------------------------------------
cglobal predict_4x4_dc_left, 1,3
    PRED_LEFT4   0
    PRED4x4_DC_STORE
    RET

;-----------------------------------------------------------------------------
; void predict_4x4_dc_top( pixel *src )
;-----------------------------------------------------------------------------
cglobal predict_4x4_dc_top, 1,2
%if HIGH_BIT_DEPTH
    movq        m0, [r0-FDEC_STRIDEB]
    pmaddwd     m0, [pw_1]
    pshuflw     m1, m0, q1032
    paddd       m0, m1
    paddw       m0, [pw_2]
    psrlw       m0, 2
    pshuflw     m0, m0, q0000
    STORE_ROWS   4, movq, m0
%else
    pxor        m1, m1
    movd        m0, [r0-FDEC_STRIDE]
    psadbw      m0, m1
    movd       r1d, m0
    add        r1d, 2
    shr        r1d, 2
    PRED4x4_DC_STORE
%endif
    RET

;-----------------------------------------------------------------------------
; void predict_4x4_dc_128( pixel *src )
;-----------------------------------------------------------------------------
cglobal predict_4x4_dc_128, 1,1
%if HIGH_BIT_DEPTH
    movq        m0, [pw_512]
    STORE_ROWS   4, movq, m0
%else
    STORE_ROWS   4, mov dword, 0x80808080
%endif
    RET

%if HIGH_BIT_DEPTH
    %define pix_128 pw_512
    %define MOVPIX8 mova ; one 8-pixel row
%else
    %define pix_128 pb_128
    %define MOVPIX8 movq
%endif

;-----------------------------------------------------------------------------
; void predict_8x8_dc_128( pixel *src, pixel edge[36] )
; void predict_8x8c_dc_128( pixel *src )
; void predict_8x16c_dc_128( pixel *src )
;-----------------------------------------------------------------------------
%macro PREDICT_DC_128 2 ; name, rows
cglobal %1, 1,1
    mova         m0, [pix_128]
    STORE_ROWS   %2, MOVPIX8, m0
    RET
%endmacro

INIT_XMM sse2
PREDICT_DC_128 predict_8x8_dc_128, 8
PREDICT_DC_128 predict_8x8c_dc_128, 8
PREDICT_DC_128 predict_8x16c_dc_128, 16

;-----------------------------------------------------------------------------
; void predict_16x16_dc_128( pixel *src )
;-----------------------------------------------------------------------------
%macro PREDICT_16x16_DC_128 0
cglobal predict_16x16_dc_128, 1,2
    mova         m0, [pix_128]
%if HIGH_BIT_DEPTH && mmsize == 16
    STORE16      m0, m0
%else
    STORE16      m0
%endif
    RET
%endmacro

INIT_XMM sse2
PREDICT_16x16_DC_128
%if HIGH_BIT_DEPTH
INIT_YMM avx
PREDICT_16x16_DC_128
%endif

%if ARCH_X86_64
;-----------------------------------------------------------------------------
; avx512icl 16x16 v, h, dc: 8-bit rows y|y+1 in bytes 0-15|32-47 of one zmm,
; one masked store per row pair. 10-bit rows are 64 bytes apart: dc sums by
; vpdpwssd (rounding in the accumulator) and ymm row stores; v, h and dc_128
; as vpscatterqq of two rows (8 qwords) at a time.
;-----------------------------------------------------------------------------
INIT_ZMM avx512icl
%if HIGH_BIT_DEPTH == 0
%macro STORE16_PAIRS_ICL 1 ; zmm with a row in bytes 0-15 and 32-47
    mov          r1, 0x0000ffff0000ffff
    kmovq        k1, r1
%assign %%y 0
%rep 8
    vmovdqu8 [r0+%%y*FDEC_STRIDE]{k1}, %1
%assign %%y %%y+2
%endrep
%endmacro

; xm0 = sum of the top row (dword 0)
%macro SUM16_TOP_ICL 0
    pxor        xm1, xm1
    psadbw      xm0, xm1, [r0-FDEC_STRIDE]
    punpckhqdq  xm1, xm0, xm0
    paddd       xm0, xm1
%endmacro

;-----------------------------------------------------------------------------
; void predict_16x16_v( uint8_t *src )
;-----------------------------------------------------------------------------
cglobal predict_16x16_v, 1,2
    vbroadcasti32x4 m0, [r0-FDEC_STRIDE]
    STORE16_PAIRS_ICL m0
    RET

;-----------------------------------------------------------------------------
; void predict_16x16_h( uint8_t *src )
;-----------------------------------------------------------------------------
cglobal predict_16x16_h, 1,2
    mov          r1, 0xffffffff00000000
    kmovq        k2, r1
    mov          r1, 0x0000ffff0000ffff
    kmovq        k1, r1
%assign Y 0
%rep 8
    vpbroadcastb ym %+ Y, [r0+(Y*2+0)*FDEC_STRIDE-1]
    vpbroadcastb  m %+ Y{k2}, [r0+(Y*2+1)*FDEC_STRIDE-1]
%assign Y Y+1
%endrep
%assign Y 0
%rep 8
    vmovdqu8 [r0+Y*2*FDEC_STRIDE]{k1}, m %+ Y
%assign Y Y+1
%endrep
    RET

;-----------------------------------------------------------------------------
; void predict_16x16_dc_core( uint8_t *src, int i_dc_left )
;-----------------------------------------------------------------------------
cglobal predict_16x16_dc_core, 2,2
    SUM16_TOP_ICL
    movd        xm1, r1d
    paddd       xm0, xm1
    psrld       xm0, 5
    vpbroadcastb m0, xm0
    STORE16_PAIRS_ICL m0
    RET

;-----------------------------------------------------------------------------
; void predict_16x16_dc_top( uint8_t *src )
;-----------------------------------------------------------------------------
cglobal predict_16x16_dc_top, 1,2
    SUM16_TOP_ICL
    paddw       xm0, [pw_8]
    psrlw       xm0, 4
    vpbroadcastb m0, xm0
    STORE16_PAIRS_ICL m0
    RET

;-----------------------------------------------------------------------------
; void predict_16x16_dc_left_core( uint8_t *src, int i_dc_left )
;-----------------------------------------------------------------------------
cglobal predict_16x16_dc_left_core, 2,2
    vpbroadcastb m0, r1d
    STORE16_PAIRS_ICL m0
    RET

;-----------------------------------------------------------------------------
; void predict_16x16_dc_128( uint8_t *src )
;-----------------------------------------------------------------------------
cglobal predict_16x16_dc_128, 1,2
    mov         r1d, 0x80808080
    vpbroadcastd m0, r1d
    STORE16_PAIRS_ICL m0
    RET

%else ; HIGH_BIT_DEPTH
%macro STORE16_ROWS_ICL 1 ; ymm
%assign %%y 0
%rep 16
    mova [r0+%%y*FDEC_STRIDEB], %1
%assign %%y %%y+1
%endrep
%endmacro

; ym0 = (sum of the top row + xm2) >> %1, broadcast
%macro DC16_TOP_ICL 1 ; shift, xm2 = rounding
    movu        ym0, [r0-FDEC_STRIDEB]
    vextracti128 xm1, ym0, 1
    paddw       xm0, xm1
    vpdpwssd    xm2, xm0, [pw_1]{1to4}
    pshufd      xm1, xm2, q1032
    paddd       xm2, xm1
    pshufd      xm1, xm2, q2301
    paddd       xm2, xm1
    psrld       xm2, %1
    vpbroadcastw ym0, xm2
%endmacro

;-----------------------------------------------------------------------------
; void predict_16x16_v( uint16_t *src )
;-----------------------------------------------------------------------------
cglobal predict_16x16_v, 1,1
    vbroadcasti64x4 m0, [r0-FDEC_STRIDEB]
    movu         m7, [pq_rowpair_icl]
%assign Y 0
%rep 8
    kxnorb       k1, k1, k1
    vpscatterqq [r0+m7+Y*2*FDEC_STRIDEB]{k1}, m0
%assign Y Y+1
%endrep
    RET

;-----------------------------------------------------------------------------
; void predict_16x16_h( uint16_t *src )
;-----------------------------------------------------------------------------
cglobal predict_16x16_h, 1,2
    mov         r1d, 0xffff0000
    kmovd        k2, r1d
    movu         m7, [pq_rowpair_icl]
%assign Y 0
%rep 8
    vpbroadcastw ym0, [r0+(Y*2+0)*FDEC_STRIDEB-SIZEOF_PIXEL]
    vpbroadcastw  m0{k2}, [r0+(Y*2+1)*FDEC_STRIDEB-SIZEOF_PIXEL]
    kxnorb       k1, k1, k1
    vpscatterqq [r0+m7+Y*2*FDEC_STRIDEB]{k1}, m0
%assign Y Y+1
%endrep
    RET

;-----------------------------------------------------------------------------
; void predict_16x16_dc_core( uint16_t *src, int i_dc_left )
;-----------------------------------------------------------------------------
cglobal predict_16x16_dc_core, 2,2
    movd        xm2, r1d
    DC16_TOP_ICL 5
    STORE16_ROWS_ICL ym0
    RET

;-----------------------------------------------------------------------------
; void predict_16x16_dc_top( uint16_t *src )
;-----------------------------------------------------------------------------
cglobal predict_16x16_dc_top, 1,2
    mov         r1d, 8
    movd        xm2, r1d
    DC16_TOP_ICL 4
    STORE16_ROWS_ICL ym0
    RET

;-----------------------------------------------------------------------------
; void predict_16x16_dc_left_core( uint16_t *src, int i_dc_left )
;-----------------------------------------------------------------------------
cglobal predict_16x16_dc_left_core, 2,2
    vpbroadcastw ym0, r1d
    STORE16_ROWS_ICL ym0
    RET

;-----------------------------------------------------------------------------
; void predict_16x16_dc_128( uint16_t *src )
;-----------------------------------------------------------------------------
cglobal predict_16x16_dc_128, 1,2
    mov         r1d, 1 << (BIT_DEPTH-1)
    vpbroadcastw m0, r1d
    movu         m7, [pq_rowpair_icl]
%assign Y 0
%rep 8
    kxnorb       k1, k1, k1
    vpscatterqq [r0+m7+Y*2*FDEC_STRIDEB]{k1}, m0
%assign Y Y+1
%endrep
    RET
%endif ; HIGH_BIT_DEPTH
%endif ; ARCH_X86_64

%if ARCH_X86_64
;-----------------------------------------------------------------------------
; avx512icl 8x8 v, h, dc (pixel *src, pixel edge[36]): 8-bit rows y|y+1 in
; bytes 0-7|32-39, one masked store per row pair. 10-bit rows are 64 bytes
; apart: h as vpermw rows (4 per zmm), dc sums by vpdpwssd, v and dc_128 as
; vpscatterqq of four rows (8 qwords).
;-----------------------------------------------------------------------------
INIT_ZMM avx512icl
%if HIGH_BIT_DEPTH == 0
%macro STORE8_PAIRS_ICL 1 ; zmm with a row in bytes 0-7 and 32-39
    mov          r1, 0x000000ff000000ff
    kmovq        k1, r1
    vmovdqu8 [r0+0*FDEC_STRIDE]{k1}, %1
    vmovdqu8 [r0+2*FDEC_STRIDE]{k1}, %1
    vmovdqu8 [r0+4*FDEC_STRIDE]{k1}, %1
    vmovdqu8 [r0+6*FDEC_STRIDE]{k1}, %1
%endmacro

; m0 = broadcast (psadbw(xm0) + %1) >> %2
%macro DC8_ICL 2
    pxor        xm1, xm1
    psadbw      xm0, xm1
    punpckhqdq  xm1, xm0, xm0
    paddw       xm0, xm1
    paddw       xm0, [%1]
    psrlw       xm0, %2
    vpbroadcastb m0, xm0
%endmacro

;-----------------------------------------------------------------------------
; void predict_8x8_v( uint8_t *src, uint8_t edge[36] )
;-----------------------------------------------------------------------------
cglobal predict_8x8_v, 2,2
    vpbroadcastq m0, [r1+16]
    STORE8_PAIRS_ICL m0
    RET

;-----------------------------------------------------------------------------
; void predict_8x8_h( uint8_t *src, uint8_t edge[36] )
;-----------------------------------------------------------------------------
cglobal predict_8x8_h, 2,3
    movq        xm5, [r1+7]             ; l7 .. l0
    movu         m3, [pb_8x8h_icl]
    mov         r2d, 0x02020202
    vpbroadcastd m4, r2d
    vpermb       m0, m3, m5
    psubb        m3, m4
    vpermb       m1, m3, m5
    psubb        m3, m4
    vpermb       m2, m3, m5
    psubb        m3, m4
    vpermb       m3, m3, m5
    mov          r1, 0x000000ff000000ff
    kmovq        k1, r1
    vmovdqu8 [r0+0*FDEC_STRIDE]{k1}, m0
    vmovdqu8 [r0+2*FDEC_STRIDE]{k1}, m1
    vmovdqu8 [r0+4*FDEC_STRIDE]{k1}, m2
    vmovdqu8 [r0+6*FDEC_STRIDE]{k1}, m3
    RET

;-----------------------------------------------------------------------------
; void predict_8x8_dc( uint8_t *src, uint8_t edge[36] )
;-----------------------------------------------------------------------------
cglobal predict_8x8_dc, 2,2
    movq        xm0, [r1+7]
    movhps      xm0, [r1+16]
    DC8_ICL pw_8, 4
    STORE8_PAIRS_ICL m0
    RET

;-----------------------------------------------------------------------------
; void predict_8x8_dc_top( uint8_t *src, uint8_t edge[36] )
;-----------------------------------------------------------------------------
cglobal predict_8x8_dc_top, 2,2
    movq        xm0, [r1+16]
    DC8_ICL pw_4, 3
    STORE8_PAIRS_ICL m0
    RET

;-----------------------------------------------------------------------------
; void predict_8x8_dc_left( uint8_t *src, uint8_t edge[36] )
;-----------------------------------------------------------------------------
cglobal predict_8x8_dc_left, 2,2
    movq        xm0, [r1+7]
    DC8_ICL pw_4, 3
    STORE8_PAIRS_ICL m0
    RET

;-----------------------------------------------------------------------------
; void predict_8x8_dc_128( uint8_t *src, uint8_t edge[36] )
;-----------------------------------------------------------------------------
cglobal predict_8x8_dc_128, 1,2
    mov         r1d, 0x80808080
    vpbroadcastd m0, r1d
    STORE8_PAIRS_ICL m0
    RET

%else ; HIGH_BIT_DEPTH
%macro STORE8_ROWS_ICL 1 ; xmm
%assign %%y 0
%rep 8
    mova [r0+%%y*FDEC_STRIDEB], %1
%assign %%y %%y+1
%endrep
%endmacro

; rows 0-3 and 4-7 of %1 (one row per 128-bit lane) by vpscatterqq
%macro SCATTER8_ICL 1
    movu         m7, [pq_rowquad_icl]
    kxnorb       k1, k1, k1
    vpscatterqq [r0+m7+0*FDEC_STRIDEB]{k1}, %1
    kxnorb       k1, k1, k1
    vpscatterqq [r0+m7+4*FDEC_STRIDEB]{k1}, %1
%endmacro

; xm0 = broadcast (sum of the words of xm0 + xm2) >> %1
%macro DC8W_ICL 1
    vpdpwssd    xm2, xm0, [pw_1]{1to4}
    pshufd      xm1, xm2, q1032
    paddd       xm2, xm1
    pshufd      xm1, xm2, q2301
    paddd       xm2, xm1
    psrld       xm2, %1
    vpbroadcastw xm0, xm2
%endmacro

;-----------------------------------------------------------------------------
; void predict_8x8_v( uint16_t *src, uint16_t edge[36] )
;-----------------------------------------------------------------------------
cglobal predict_8x8_v, 2,2
    vbroadcasti32x4 m0, [r1+16*SIZEOF_PIXEL]
    SCATTER8_ICL m0
    RET

;-----------------------------------------------------------------------------
; void predict_8x8_h( uint16_t *src, uint16_t edge[36] )
;-----------------------------------------------------------------------------
cglobal predict_8x8_h, 2,2
    movu         m2, [pw_8x8h_icl]
    vpbroadcastd m3, [pw_4]
    movu        xm4, [r1+7*SIZEOF_PIXEL]  ; l7 .. l0
    vpermw       m0, m2, m4
    psubw        m2, m3
    vpermw       m1, m2, m4
    STORE4_ICL    0, 0
    STORE4_ICL    1, 4
    RET

;-----------------------------------------------------------------------------
; void predict_8x8_dc( uint16_t *src, uint16_t edge[36] )
;-----------------------------------------------------------------------------
cglobal predict_8x8_dc, 2,2
    movu        xm0, [r1+7*SIZEOF_PIXEL]
    paddw       xm0, [r1+16*SIZEOF_PIXEL]
    mov         r1d, 8
    movd        xm2, r1d
    DC8W_ICL 4
    STORE8_ROWS_ICL xm0
    RET

;-----------------------------------------------------------------------------
; void predict_8x8_dc_top( uint16_t *src, uint16_t edge[36] )
;-----------------------------------------------------------------------------
cglobal predict_8x8_dc_top, 2,2
    movu        xm0, [r1+16*SIZEOF_PIXEL]
    mov         r1d, 4
    movd        xm2, r1d
    DC8W_ICL 3
    STORE8_ROWS_ICL xm0
    RET

;-----------------------------------------------------------------------------
; void predict_8x8_dc_left( uint16_t *src, uint16_t edge[36] )
;-----------------------------------------------------------------------------
cglobal predict_8x8_dc_left, 2,2
    movu        xm0, [r1+7*SIZEOF_PIXEL]
    mov         r1d, 4
    movd        xm2, r1d
    DC8W_ICL 3
    STORE8_ROWS_ICL xm0
    RET

;-----------------------------------------------------------------------------
; void predict_8x8_dc_128( uint16_t *src, uint16_t edge[36] )
;-----------------------------------------------------------------------------
cglobal predict_8x8_dc_128, 1,2
    mov         r1d, 1 << (BIT_DEPTH-1)
    vpbroadcastw m0, r1d
    SCATTER8_ICL m0
    RET
%endif ; HIGH_BIT_DEPTH
%endif ; ARCH_X86_64

%if ARCH_X86_64
;-----------------------------------------------------------------------------
; avx512icl 8x8c/8x16c v, h, dc: 8-bit rows y|y+1 in bytes 0-7|32-39, one
; masked store per row pair; the left column by merge-masked vpbroadcastq
; (row y in qword lane y) and vpermb; dc sums by vpdpbusd. 10-bit rows are
; 64 bytes apart: dc sums by vpdpwssd, h rows by vpermw, v and dc_128 as
; vpscatterqq of four rows.
;-----------------------------------------------------------------------------
INIT_ZMM avx512icl
; %1 = the 8 qwords ending at the left pixels of rows %2..%2+7, one per lane
%macro LEFT8_ICL 2
    mov         r2d, 1
    kmovb        k1, r2d
%assign %%y 0
%rep 8
    vpbroadcastq %1{k1}, [r0+(%2+%%y)*FDEC_STRIDEB-8]
%if %%y < 7
    kshiftlb     k1, k1, 1
%endif
%assign %%y %%y+1
%endrep
%endmacro

%if HIGH_BIT_DEPTH == 0
%macro CSTORE_PAIRS_ICL 2-3 0 ; zmm, rows, first row
    mov          r1, 0x000000ff000000ff
    kmovq        k2, r1
%assign %%y 0
%rep %2/2
    vmovdqu8 [r0+(%3+%%y)*FDEC_STRIDE]{k2}, %1
%assign %%y %%y+2
%endrep
%endmacro

%macro PREDICT_C_ICL 1 ; height
;-----------------------------------------------------------------------------
; void predict_8x%1c_v( uint8_t *src )
;-----------------------------------------------------------------------------
cglobal predict_8x%1c_v, 1,2
    vpbroadcastq m0, [r0-FDEC_STRIDE]
    CSTORE_PAIRS_ICL m0, %1
    RET

;-----------------------------------------------------------------------------
; void predict_8x%1c_h( uint8_t *src )
;-----------------------------------------------------------------------------
cglobal predict_8x%1c_h, 1,2
    mov          r1, 0xffffffff00000000
    kmovq        k1, r1
    mov          r1, 0x000000ff000000ff
    kmovq        k2, r1
%assign %%y 0
%rep %1/2
    vpbroadcastb ym0, [r0+(%%y+0)*FDEC_STRIDE-1]
    vpbroadcastb  m0{k1}, [r0+(%%y+1)*FDEC_STRIDE-1]
    vmovdqu8 [r0+%%y*FDEC_STRIDE]{k2}, m0
%assign %%y %%y+2
%endrep
    RET

;-----------------------------------------------------------------------------
; void predict_8x%1c_dc_128( uint8_t *src )
;-----------------------------------------------------------------------------
cglobal predict_8x%1c_dc_128, 1,2
    mov         r1d, 0x80808080
    vpbroadcastd m0, r1d
    CSTORE_PAIRS_ICL m0, %1
    RET

;-----------------------------------------------------------------------------
; void predict_8x%1c_dc_top( uint8_t *src )
;-----------------------------------------------------------------------------
cglobal predict_8x%1c_dc_top, 1,2
    movq        xm0, [r0-FDEC_STRIDE]
    pxor        xm1, xm1
    vpdpbusd    xm1, xm0, [pb_1]{1to4}  ; s0 s1
    pxor        xm2, xm2
    psrld       xm1, 1
    pavgw       xm1, xm2                ; (s+2)>>2
    movu         m2, [pb_c_dc_icl]
    vpermb       m0, m2, m1
    CSTORE_PAIRS_ICL m0, %1
    RET

;-----------------------------------------------------------------------------
; void predict_8x%1c_dc_left( uint8_t *src )
;-----------------------------------------------------------------------------
cglobal predict_8x%1c_dc_left, 1,3
    LEFT8_ICL    m0, 0
%if %1 == 16
    LEFT8_ICL    m1, 8
    movu        xm2, [pb_c_left16_icl]
    vpermi2b     m2, m0, m1             ; l0 .. l15
%else
    movu        xm2, [pb_c_left16_icl]
    vpermb       m2, m2, m0             ; l0 .. l7
%endif
    pxor        xm1, xm1
    vpdpbusd    xm1, xm2, [pb_1]{1to4}  ; one sum per 4 rows
    pxor        xm2, xm2
    psrld       xm1, 1
    pavgw       xm1, xm2
%assign %%g 0
%rep %1/4
    vpbroadcastb m0, xm1
    CSTORE_PAIRS_ICL m0, 4, %%g*4
%if %%g < %1/4-1
    psrldq      xm1, 4
%endif
%assign %%g %%g+1
%endrep
    RET

;-----------------------------------------------------------------------------
; void predict_8x%1c_dc( uint8_t *src )
;-----------------------------------------------------------------------------
cglobal predict_8x%1c_dc, 1,3
    LEFT8_ICL    m0, 0
    movq        xm1, [r0-FDEC_STRIDE]
    movu        xm2, [pb_c_dc8_icl]
    vpermi2b     m2, m0, m1             ; t0 .. t7 l0 .. l7
    pxor        xm3, xm3
    vpdpbusd    xm3, xm2, [pb_1]{1to4}  ; s0 s1 s2 s3
%if %1 == 16
    LEFT8_ICL    m0, 8
    movu        xm2, [pb_c_left16_icl]
    vpermb       m2, m2, m0             ; l8 .. l15
    pxor        xm4, xm4
    vpdpbusd    xm4, xm2, [pb_1]{1to4}  ; s4 s5
    vinserti32x4 ym3, ym3, xm4, 1
    movu        ym1, [pd_c_dc16a_icl]
    movu        ym2, [pd_c_dc16b_icl]
    vpermd      ym1, ym1, ym3           ; s0 s1 s3 s1 s4 s1 s5 s1
    vpermd      ym3, ym2, ym3           ; s2 s1 s3 s3 s4 s4 s5 s5
%else
    pshufd      xm1, xm3, q1310         ; s0 s1 s3 s1
    pshufd      xm3, xm3, q3312         ; s2 s1 s3 s3
%endif
    paddd       ym3, ym1
    pxor        xm2, xm2
    psrld       ym3, 2
    pavgw       ym3, ym2                ; dc0 .. dc%1/2-1 in dwords
    movu         m1, [pb_c_dc_icl]
    mov         r2d, 0x08080808
    vpbroadcastd m2, r2d
%assign %%g 0
%rep %1/4
    vpermb       m0, m1, m3
    CSTORE_PAIRS_ICL m0, 4, %%g*4
%if %%g < %1/4-1
    paddb        m1, m2
%endif
%assign %%g %%g+1
%endrep
    RET
%endmacro ; PREDICT_C_ICL

PREDICT_C_ICL 8
PREDICT_C_ICL 16
%else ; HIGH_BIT_DEPTH
%macro CSTORE_ROWS_ICL 3 ; xmm, rows, first row
%assign %%y 0
%rep %2
    mova [r0+(%3+%%y)*FDEC_STRIDEB], %1
%assign %%y %%y+1
%endrep
%endmacro

%macro PREDICT_C_ICL 1 ; height
;-----------------------------------------------------------------------------
; void predict_8x%1c_v( uint16_t *src )
;-----------------------------------------------------------------------------
cglobal predict_8x%1c_v, 1,1
    vbroadcasti32x4 m0, [r0-FDEC_STRIDEB]
    movu         m7, [pq_rowquad_icl]
%assign %%y 0
%rep %1/4
    kxnorb       k1, k1, k1
    vpscatterqq [r0+m7+%%y*FDEC_STRIDEB]{k1}, m0
%assign %%y %%y+4
%endrep
    RET

;-----------------------------------------------------------------------------
; void predict_8x%1c_h( uint16_t *src )
;-----------------------------------------------------------------------------
cglobal predict_8x%1c_h, 1,3
    vpbroadcastd m4, [pw_16]
%assign %%y 0
%rep %1/8
    LEFT8_ICL    m1, %%y
    movu         m2, [pw_c_h_icl]
    vpermw       m0, m2, m1
    paddw        m2, m4
    vpermw       m3, m2, m1
    STORE4_ICL    0, %%y
    STORE4_ICL    3, %%y+4
%assign %%y %%y+8
%endrep
    RET

;-----------------------------------------------------------------------------
; void predict_8x%1c_dc_128( uint16_t *src )
;-----------------------------------------------------------------------------
cglobal predict_8x%1c_dc_128, 1,2
    mov         r1d, 1 << (BIT_DEPTH-1)
    vpbroadcastw m0, r1d
    movu         m7, [pq_rowquad_icl]
%assign %%y 0
%rep %1/4
    kxnorb       k1, k1, k1
    vpscatterqq [r0+m7+%%y*FDEC_STRIDEB]{k1}, m0
%assign %%y %%y+4
%endrep
    RET

;-----------------------------------------------------------------------------
; void predict_8x%1c_dc_top( uint16_t *src )
;-----------------------------------------------------------------------------
cglobal predict_8x%1c_dc_top, 1,1
    movu        xm0, [r0-FDEC_STRIDEB]
    pxor        xm1, xm1
    vpdpwssd    xm1, xm0, [pw_1]{1to4}
    pshufd      xm2, xm1, q2301
    paddd       xm1, xm2                ; s0 . s1 .
    pxor        xm2, xm2
    psrld       xm1, 1
    pavgw       xm1, xm2                ; (s+2)>>2
    movu        xm2, [pw_c_dctop_icl]
    vpermw      xm0, xm2, xm1
    CSTORE_ROWS_ICL xm0, %1, 0
    RET

;-----------------------------------------------------------------------------
; void predict_8x%1c_dc_left( uint16_t *src )
;-----------------------------------------------------------------------------
cglobal predict_8x%1c_dc_left, 1,3
    LEFT8_ICL    m0, 0
    movu        ym2, [pw_c_left16_icl]
%if %1 == 16
    LEFT8_ICL    m1, 8
    vpermi2w     m2, m0, m1             ; l0 .. l15
%else
    vpermw       m2, m2, m0             ; l0 .. l7
%endif
    pxor        xm1, xm1
    vpdpwssd    ym1, ym2, [pw_1]{1to8}
    pshufd      ym2, ym1, q2301
    paddd       ym1, ym2                ; one sum per 4 rows: dwords 0 2 4 6
    pxor        xm2, xm2
    psrld       ym1, 1
    pavgw       ym1, ym2
%assign %%g 0
%rep %1/4
    mov         r2d, %%g*4
    vpbroadcastw m2, r2d
    vpermw       m0, m2, m1
    CSTORE_ROWS_ICL xm0, 4, %%g*4
%assign %%g %%g+1
%endrep
    RET

;-----------------------------------------------------------------------------
; void predict_8x%1c_dc( uint16_t *src )
;-----------------------------------------------------------------------------
cglobal predict_8x%1c_dc, 1,3
    LEFT8_ICL    m0, 0
    movu        xm1, [r0-FDEC_STRIDEB]
    movu        ym2, [pw_c_dc8_icl]
    vpermi2w     m2, m0, m1             ; t0 .. t7 l0 .. l7
    pxor        xm3, xm3
    vpdpwssd    ym3, ym2, [pw_1]{1to8}
    pshufd      ym1, ym3, q2301
    paddd       ym3, ym1                ; s0 . s1 . s2 . s3 .
%if %1 == 16
    LEFT8_ICL    m0, 8
    movu        xm2, [pw_c_left16_icl]
    vpermw       m2, m2, m0             ; l8 .. l15
    pxor        xm4, xm4
    vpdpwssd    xm4, xm2, [pw_1]{1to4}
    pshufd      xm2, xm4, q2301
    paddd       xm4, xm2                ; s4 . s5 .
    vinserti32x4 m3, m3, xm4, 2
    movu        ym1, [pd_c_dc16a_icl]
    movu        ym2, [pd_c_dc16b_icl]
%else
    movu        ym1, [pd_c_dc8a_icl]
    movu        ym2, [pd_c_dc8b_icl]
%endif
    vpermd       m1, m1, m3             ; s0 s1 s3 s1 (s4 s1 s5 s1)
    vpermd       m3, m2, m3             ; s2 s1 s3 s3 (s4 s4 s5 s5)
    paddd       ym3, ym1
    pxor        xm2, xm2
    psrld       ym3, 2
    pavgw       ym3, ym2                ; dc0 .. dc%1/2-1 in dwords
    movu        xm1, [pw_c_dc_icl]
    vpbroadcastd m2, [pw_4]
%assign %%g 0
%rep %1/4
    vpermw       m0, m1, m3
    CSTORE_ROWS_ICL xm0, 4, %%g*4
%if %%g < %1/4-1
    paddw       xm1, xm2
%endif
%assign %%g %%g+1
%endrep
    RET
%endmacro ; PREDICT_C_ICL

PREDICT_C_ICL 8
PREDICT_C_ICL 16
%endif ; HIGH_BIT_DEPTH
%endif ; ARCH_X86_64

%if ARCH_X86_64
;-----------------------------------------------------------------------------
; avx512icl 4x4: the left column by merge-masked vpbroadcastd/q (row y in lane
; y), packed with the top row by vpermi2b/w into E = l3 l3 l2 l1 l0 lt t0 .. t7
; t7; F1/F2 of E, then one vpermi2b/w per block picks every output pixel.
; 8-bit: rows 0|1 in bytes 0-3|32-35 and rows 2|3 in bytes 8-11|40-43, two
; masked stores. 10-bit: the 4 rows in one ymm.
;-----------------------------------------------------------------------------
INIT_ZMM avx512icl
%if HIGH_BIT_DEPTH == 0
; xm0 = left pixel of row y in byte 4*y+3
%macro LEFT4_ICL 0
    mov         r1d, 1
    kmovb        k1, r1d
    vpbroadcastd xm0{k1}, [r0+0*FDEC_STRIDE-4]
    kshiftlb     k1, k1, 1
    vpbroadcastd xm0{k1}, [r0+1*FDEC_STRIDE-4]
    kshiftlb     k1, k1, 1
    vpbroadcastd xm0{k1}, [r0+2*FDEC_STRIDE-4]
    kshiftlb     k1, k1, 1
    vpbroadcastd xm0{k1}, [r0+3*FDEC_STRIDE-4]
%endmacro

; rows 0|1 (bytes 0-3|32-35) and 2|3 (bytes 8-11|40-43) of %1
%macro STORE4x4_ICL 1
    mov          r1, 0x0000000f0000000f
    kmovq        k1, r1
    vmovdqu8 [r0+0*FDEC_STRIDE  ]{k1}, %1
    kshiftlq     k1, k1, 8
    vmovdqu8 [r0+2*FDEC_STRIDE-8]{k1}, %1
%endmacro

; the same row (bytes 0-3 and 32-35 of %1) in all 4 rows
%macro STORE4x4_SPLAT_ICL 1
    mov          r1, 0x0000000f0000000f
    kmovq        k1, r1
    vmovdqu8 [r0+0*FDEC_STRIDE]{k1}, %1
    vmovdqu8 [r0+2*FDEC_STRIDE]{k1}, %1
%endmacro

%macro PREDICT_4x4_DIR_ICL 1 ; mode
;-----------------------------------------------------------------------------
; void predict_4x4_%1( uint8_t *src )
;-----------------------------------------------------------------------------
cglobal predict_4x4_%1, 1,2
    LEFT4_ICL
    movu        xm1, [r0-FDEC_STRIDE-8]
    movu        xm2, [pb_e4_icl]
    vpermi2b    xm2, xm0, xm1           ; E
    psrldq      xm3, xm2, 1
    psrldq      xm4, xm2, 2
    pavgb       xm0, xm2, xm3
    PRED8x8_LOWPASS xm1, xm2, xm4, xm3, xm5
    movu         m2, [pb_4x4_%1_icl]
    vpermi2b     m2, m0, m1
    STORE4x4_ICL m2
    RET
%endmacro

PREDICT_4x4_DIR_ICL ddl
PREDICT_4x4_DIR_ICL ddr
PREDICT_4x4_DIR_ICL vr
PREDICT_4x4_DIR_ICL hd
PREDICT_4x4_DIR_ICL vl
PREDICT_4x4_DIR_ICL hu

;-----------------------------------------------------------------------------
; void predict_4x4_v( uint8_t *src )
;-----------------------------------------------------------------------------
cglobal predict_4x4_v, 1,2
    vpbroadcastd m0, [r0-FDEC_STRIDE]
    STORE4x4_SPLAT_ICL m0
    RET

;-----------------------------------------------------------------------------
; void predict_4x4_h( uint8_t *src )
;-----------------------------------------------------------------------------
cglobal predict_4x4_h, 1,2
    LEFT4_ICL
    movu         m1, [pb_h4_icl]
    vpermb       m1, m1, m0
    STORE4x4_ICL m1
    RET

;-----------------------------------------------------------------------------
; void predict_4x4_dc( uint8_t *src )
;-----------------------------------------------------------------------------
cglobal predict_4x4_dc, 1,2
    LEFT4_ICL
    movd        xm1, [r0-FDEC_STRIDE]
    movu        xm2, [pb_dc4_icl]
    vpermi2b    xm2, xm0, xm1           ; t0 .. t3 l0 .. l3
    pxor        xm1, xm1
    psadbw      xm2, xm1
    paddw       xm2, [pw_4]
    psrlw       xm2, 3
    vpbroadcastb m0, xm2
    STORE4x4_SPLAT_ICL m0
    RET

;-----------------------------------------------------------------------------
; void predict_4x4_dc_top( uint8_t *src )
;-----------------------------------------------------------------------------
cglobal predict_4x4_dc_top, 1,2
    movd        xm0, [r0-FDEC_STRIDE]
    pxor        xm1, xm1
    psadbw      xm0, xm1
    paddw       xm0, [pw_2]
    psrlw       xm0, 2
    vpbroadcastb m0, xm0
    STORE4x4_SPLAT_ICL m0
    RET

;-----------------------------------------------------------------------------
; void predict_4x4_dc_left( uint8_t *src )
;-----------------------------------------------------------------------------
cglobal predict_4x4_dc_left, 1,2
    LEFT4_ICL
    movu        xm1, [pb_dc4_icl+4]     ; l0 .. l3
    mov         r1d, 0xf
    kmovb        k1, r1d
    vpermb      xm1{k1}{z}, xm1, xm0
    pxor        xm0, xm0
    psadbw      xm1, xm0
    paddw       xm1, [pw_2]
    psrlw       xm1, 2
    vpbroadcastb m0, xm1
    STORE4x4_SPLAT_ICL m0
    RET

%else ; HIGH_BIT_DEPTH
; ym0 = left pixel of row y in word 4*y+3
%macro LEFT4W_ICL 0
    mov         r1d, 1
    kmovb        k1, r1d
    vpbroadcastq ym0{k1}, [r0+0*FDEC_STRIDEB-8]
    kshiftlb     k1, k1, 1
    vpbroadcastq ym0{k1}, [r0+1*FDEC_STRIDEB-8]
    kshiftlb     k1, k1, 1
    vpbroadcastq ym0{k1}, [r0+2*FDEC_STRIDEB-8]
    kshiftlb     k1, k1, 1
    vpbroadcastq ym0{k1}, [r0+3*FDEC_STRIDEB-8]
%endmacro

; rows 0-3 of ym%1 (4 words each)
%macro STORE4x4W_ICL 1
    movq   [r0+0*FDEC_STRIDEB], xm%1
    movhps [r0+1*FDEC_STRIDEB], xm%1
    vextracti32x4 xm%1, ym%1, 1
    movq   [r0+2*FDEC_STRIDEB], xm%1
    movhps [r0+3*FDEC_STRIDEB], xm%1
%endmacro

; the low qword of xm%1 in all 4 rows
%macro STORE4x4W_SPLAT_ICL 1
    movq   [r0+0*FDEC_STRIDEB], xm%1
    movq   [r0+1*FDEC_STRIDEB], xm%1
    movq   [r0+2*FDEC_STRIDEB], xm%1
    movq   [r0+3*FDEC_STRIDEB], xm%1
%endmacro

; 4 qwords of ym%1 to rows 0-3 by vpscatterqq
%macro SCATTER4x4W_ICL 1
    movu        ym7, [pq_rows4_icl]
    kxnorb       k1, k1, k1
    vpscatterqq [r0+ym7]{k1}, ym%1
%endmacro

; xm%1 = broadcast word (sum of the words of xm%2 + dword 0 of xm3) >> %3
%macro DC4W_ICL 3
    vpdpwssd    xm3, xm%2, [pw_1]{1to4}
    pshufd      xm%2, xm3, q1032
    paddd       xm3, xm%2
    pshufd      xm%2, xm3, q2301
    paddd       xm3, xm%2
    psrld       xm3, %3
    vpbroadcastw xm%1, xm3
%endmacro

%macro PREDICT_4x4_DIR_ICL 1 ; mode
;-----------------------------------------------------------------------------
; void predict_4x4_%1( uint16_t *src )
;-----------------------------------------------------------------------------
cglobal predict_4x4_%1, 1,2
    LEFT4W_ICL
    movu        ym1, [r0-FDEC_STRIDEB-16]
    movu        ym2, [pw_e4_icl]
    movu        ym3, [pw_e4_icl+32]
    movu        ym4, [pw_e4_icl+64]
    vpermi2w    ym2, ym0, ym1           ; E
    vpermi2w    ym3, ym0, ym1           ; E >> 1
    vpermi2w    ym4, ym0, ym1           ; E >> 2
    pavgw       ym0, ym2, ym3
    PRED8x8_LOWPASS ym1, ym2, ym4, ym3
    movu        ym2, [pw_4x4_%1_icl]
    vpermi2w    ym2, ym0, ym1
    STORE4x4W_ICL 2
    RET
%endmacro

PREDICT_4x4_DIR_ICL ddl
PREDICT_4x4_DIR_ICL ddr
PREDICT_4x4_DIR_ICL vr
PREDICT_4x4_DIR_ICL hd
PREDICT_4x4_DIR_ICL vl
PREDICT_4x4_DIR_ICL hu

;-----------------------------------------------------------------------------
; void predict_4x4_v( uint16_t *src )
;-----------------------------------------------------------------------------
cglobal predict_4x4_v, 1,1
    vpbroadcastq ym0, [r0-FDEC_STRIDEB]
    SCATTER4x4W_ICL 0
    RET

;-----------------------------------------------------------------------------
; void predict_4x4_h( uint16_t *src )
;-----------------------------------------------------------------------------
cglobal predict_4x4_h, 1,2
    LEFT4W_ICL
    movu        ym1, [pw_h4_icl]
    vpermw      ym1, ym1, ym0
    STORE4x4W_ICL 1
    RET

;-----------------------------------------------------------------------------
; void predict_4x4_dc( uint16_t *src )
;-----------------------------------------------------------------------------
cglobal predict_4x4_dc, 1,2
    LEFT4W_ICL
    movq        xm1, [r0-FDEC_STRIDEB]
    movu        ym2, [pw_dc4_icl]
    vpermi2w    ym2, ym0, ym1           ; t0 .. t3 l0 .. l3
    mov         r1d, 4
    movd        xm3, r1d
    DC4W_ICL     0, 2, 3
    STORE4x4W_SPLAT_ICL 0
    RET

;-----------------------------------------------------------------------------
; void predict_4x4_dc_top( uint16_t *src )
;-----------------------------------------------------------------------------
cglobal predict_4x4_dc_top, 1,2
    movq        xm2, [r0-FDEC_STRIDEB]
    mov         r1d, 2
    movd        xm3, r1d
    DC4W_ICL     0, 2, 2
    STORE4x4W_SPLAT_ICL 0
    RET

;-----------------------------------------------------------------------------
; void predict_4x4_dc_left( uint16_t *src )
;-----------------------------------------------------------------------------
cglobal predict_4x4_dc_left, 1,2
    LEFT4W_ICL
    movu        ym1, [pw_dc4_icl+8]     ; l0 .. l3
    mov         r1d, 0xf
    kmovb        k1, r1d
    vpermw      ym2{k1}{z}, ym1, ym0
    mov         r1d, 2
    movd        xm3, r1d
    DC4W_ICL     0, 2, 2
    STORE4x4W_SPLAT_ICL 0
    RET

%endif ; HIGH_BIT_DEPTH
%endif ; ARCH_X86_64

;-----------------------------------------------------------------------------
; void predict_8x8c_dc_left( pixel *src )
; void predict_8x16c_dc_left( pixel *src )
;-----------------------------------------------------------------------------
; rows %1..%1+3 of r1d; 8-bit splats with r3 = 0x0101010101010101
%macro PRED_C_DC_LEFT_STORE 1
%if HIGH_BIT_DEPTH
    movd         m0, r1d
%if cpuflag(avx2)
    vpbroadcastw m0, m0
%else
    pshuflw      m0, m0, q0000
    punpcklqdq   m0, m0
%endif
    mova [r0+(%1+0)*FDEC_STRIDEB], m0
    mova [r0+(%1+1)*FDEC_STRIDEB], m0
    mova [r0+(%1+2)*FDEC_STRIDEB], m0
    mova [r0+(%1+3)*FDEC_STRIDEB], m0
%else
    imul         r1, r3
    mov  [r0+(%1+0)*FDEC_STRIDE], r1
    mov  [r0+(%1+1)*FDEC_STRIDE], r1
    mov  [r0+(%1+2)*FDEC_STRIDE], r1
    mov  [r0+(%1+3)*FDEC_STRIDE], r1
%endif
%endmacro

; each 4-row group is the rounded mean of its own 4 left neighbours
%macro PREDICT_C_DC_LEFT 1 ; height
cglobal predict_8x%1c_dc_left, 1,4
%if HIGH_BIT_DEPTH == 0
    mov          r3, 0x0101010101010101
%endif
%assign %%y 0
%rep %1/4
    PRED_LEFT4   %%y
    PRED_C_DC_LEFT_STORE %%y
%assign %%y %%y+4
%endrep
    RET
%endmacro

%if HIGH_BIT_DEPTH
INIT_XMM sse2
PREDICT_C_DC_LEFT 8
PREDICT_C_DC_LEFT 16
INIT_XMM avx2
PREDICT_C_DC_LEFT 8
PREDICT_C_DC_LEFT 16
%elif ARCH_X86_64
INIT_XMM sse2
PREDICT_C_DC_LEFT 16
%endif
