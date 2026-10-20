;*****************************************************************************
;* pixel.asm: x86 pixel metrics
;*****************************************************************************
;* Copyright (C) 2003-2014 x264 project
;*
;* Authors: Loren Merritt <lorenm@u.washington.edu>
;*          Holger Lubitz <holger@lubitz.org>
;*          Laurent Aimar <fenrir@via.ecp.fr>
;*          Alex Izvorski <aizvorksi@gmail.com>
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

SECTION_RODATA 32
var_shuf_avx512: db 0,-1, 1,-1, 2,-1, 3,-1, 4,-1, 5,-1, 6,-1, 7,-1
                 db 8,-1, 9,-1,10,-1,11,-1,12,-1,13,-1,14,-1,15,-1
hmul_16p:  times 16 db 1
           times 8 db 1, -1
hmul_8p:   times 8 db 1
           times 4 db 1, -1
           times 8 db 1
           times 4 db 1, -1
mask_ff:   times 16 db 0xff
           times 16 db 0
mask_ac4:  times 2 dw 0, -1, -1, -1, 0, -1, -1, -1
mask_ac4b: times 2 dw 0, -1, 0, -1, -1, -1, -1, -1
mask_ac8:  times 2 dw 0, -1, -1, -1, -1, -1, -1, -1
intra_8x8c_dc_shuf: db 0,1,0,1,0,1,0,1,2,3,2,3,2,3,2,3, 4,5,4,5,4,5,4,5,6,7,6,7,6,7,6,7
intra_8x8c_dc_shufb: db 0,0,0,0,1,1,1,1,0,0,0,0,1,1,1,1, 2,2,2,2,3,3,3,3,2,2,2,2,3,3,3,3
%if BIT_DEPTH == 10
ssim_c1:   times 4 dd 6697.7856    ; .01*.01*1023*1023*64
ssim_c2:   times 4 dd 3797644.4352 ; .03*.03*1023*1023*64*63
pf_64:     times 4 dd 64.0
pf_128:    times 4 dd 128.0
%elif BIT_DEPTH == 9
ssim_c1:   times 4 dd 1671         ; .01*.01*511*511*64
ssim_c2:   times 4 dd 947556       ; .03*.03*511*511*64*63
%else ; 8-bit
ssim_c1:   times 4 dd 416          ; .01*.01*255*255*64
ssim_c2:   times 4 dd 235963       ; .03*.03*255*255*64*63
%endif
hmul_4p:   times 2 db 1, 1, 1, 1, 1, -1, 1, -1
mask_10:   times 4 dw 0, -1
mask_1100: times 2 dd 0, -1
pb_pppm:   times 4 db 1,1,1,-1
deinterleave_shuf: db 0, 2, 4, 6, 8, 10, 12, 14, 1, 3, 5, 7, 9, 11, 13, 15
intrax3_shuf: db 7,6,7,6,5,4,5,4,3,2,3,2,1,0,1,0

intrax9a_ddlr1: db  6, 7, 8, 9, 7, 8, 9,10, 4, 5, 6, 7, 3, 4, 5, 6
intrax9a_ddlr2: db  8, 9,10,11, 9,10,11,12, 2, 3, 4, 5, 1, 2, 3, 4
intrax9a_hdu1:  db 15, 4, 5, 6,14, 3,15, 4,14, 2,13, 1,13, 1,12, 0
intrax9a_hdu2:  db 13, 2,14, 3,12, 1,13, 2,12, 0,11,11,11,11,11,11
intrax9a_vrl1:  db 10,11,12,13, 3, 4, 5, 6,11,12,13,14, 5, 6, 7, 8
intrax9a_vrl2:  db  2,10,11,12, 1, 3, 4, 5,12,13,14,15, 6, 7, 8, 9
intrax9a_vh1:   db  6, 7, 8, 9, 6, 7, 8, 9, 4, 4, 4, 4, 3, 3, 3, 3
intrax9a_vh2:   db  6, 7, 8, 9, 6, 7, 8, 9, 2, 2, 2, 2, 1, 1, 1, 1
intrax9a_dc:    db  1, 2, 3, 4, 6, 7, 8, 9,-1,-1,-1,-1,-1,-1,-1,-1
intrax9a_lut:   db 0x60,0x68,0x80,0x00,0x08,0x20,0x40,0x28,0x48,0,0,0,0,0,0,0
pw_s01234567:   dw 0x8000,0x8001,0x8002,0x8003,0x8004,0x8005,0x8006,0x8007
pw_s01234657:   dw 0x8000,0x8001,0x8002,0x8003,0x8004,0x8006,0x8005,0x8007
intrax9_edge:   db  0, 0, 1, 2, 3, 7, 8, 9,10,11,12,13,14,15,15,15

intrax9b_ddlr1: db  6, 7, 8, 9, 4, 5, 6, 7, 7, 8, 9,10, 3, 4, 5, 6
intrax9b_ddlr2: db  8, 9,10,11, 2, 3, 4, 5, 9,10,11,12, 1, 2, 3, 4
intrax9b_hdu1:  db 15, 4, 5, 6,14, 2,13, 1,14, 3,15, 4,13, 1,12, 0
intrax9b_hdu2:  db 13, 2,14, 3,12, 0,11,11,12, 1,13, 2,11,11,11,11
intrax9b_vrl1:  db 10,11,12,13,11,12,13,14, 3, 4, 5, 6, 5, 6, 7, 8
intrax9b_vrl2:  db  2,10,11,12,12,13,14,15, 1, 3, 4, 5, 6, 7, 8, 9
intrax9b_vh1:   db  6, 7, 8, 9, 4, 4, 4, 4, 6, 7, 8, 9, 3, 3, 3, 3
intrax9b_vh2:   db  6, 7, 8, 9, 2, 2, 2, 2, 6, 7, 8, 9, 1, 1, 1, 1
intrax9b_edge2: db  6, 7, 8, 9, 6, 7, 8, 9, 4, 3, 2, 1, 4, 3, 2, 1
intrax9b_v1:    db  0, 1,-1,-1,-1,-1,-1,-1, 4, 5,-1,-1,-1,-1,-1,-1
intrax9b_v2:    db  2, 3,-1,-1,-1,-1,-1,-1, 6, 7,-1,-1,-1,-1,-1,-1
intrax9b_lut:   db 0x60,0x64,0x80,0x00,0x04,0x20,0x40,0x24,0x44,0,0,0,0,0,0,0

ALIGN 32
intra8x9_h1:   db  7, 7, 7, 7, 7, 7, 7, 7, 5, 5, 5, 5, 5, 5, 5, 5
intra8x9_h2:   db  6, 6, 6, 6, 6, 6, 6, 6, 4, 4, 4, 4, 4, 4, 4, 4
intra8x9_h3:   db  3, 3, 3, 3, 3, 3, 3, 3, 1, 1, 1, 1, 1, 1, 1, 1
intra8x9_h4:   db  2, 2, 2, 2, 2, 2, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0
intra8x9_ddl1: db  1, 2, 3, 4, 5, 6, 7, 8, 3, 4, 5, 6, 7, 8, 9,10
intra8x9_ddl2: db  2, 3, 4, 5, 6, 7, 8, 9, 4, 5, 6, 7, 8, 9,10,11
intra8x9_ddl3: db  5, 6, 7, 8, 9,10,11,12, 7, 8, 9,10,11,12,13,14
intra8x9_ddl4: db  6, 7, 8, 9,10,11,12,13, 8, 9,10,11,12,13,14,15
intra8x9_vl1:  db  0, 1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7, 8
intra8x9_vl2:  db  1, 2, 3, 4, 5, 6, 7, 8, 2, 3, 4, 5, 6, 7, 8, 9
intra8x9_vl3:  db  2, 3, 4, 5, 6, 7, 8, 9, 3, 4, 5, 6, 7, 8, 9,10
intra8x9_vl4:  db  3, 4, 5, 6, 7, 8, 9,10, 4, 5, 6, 7, 8, 9,10,11
intra8x9_ddr1: db  8, 9,10,11,12,13,14,15, 6, 7, 8, 9,10,11,12,13
intra8x9_ddr2: db  7, 8, 9,10,11,12,13,14, 5, 6, 7, 8, 9,10,11,12
intra8x9_ddr3: db  4, 5, 6, 7, 8, 9,10,11, 2, 3, 4, 5, 6, 7, 8, 9
intra8x9_ddr4: db  3, 4, 5, 6, 7, 8, 9,10, 1, 2, 3, 4, 5, 6, 7, 8
intra8x9_vr1:  db  8, 9,10,11,12,13,14,15, 7, 8, 9,10,11,12,13,14
intra8x9_vr2:  db  8, 9,10,11,12,13,14,15, 6, 8, 9,10,11,12,13,14
intra8x9_vr3:  db  5, 7, 8, 9,10,11,12,13, 3, 5, 7, 8, 9,10,11,12
intra8x9_vr4:  db  4, 6, 8, 9,10,11,12,13, 2, 4, 6, 8, 9,10,11,12
intra8x9_hd1:  db  3, 8, 9,10,11,12,13,14, 1, 6, 2, 7, 3, 8, 9,10
intra8x9_hd2:  db  2, 7, 3, 8, 9,10,11,12, 0, 5, 1, 6, 2, 7, 3, 8
intra8x9_hd3:  db  7, 8, 9,10,11,12,13,14, 3, 4, 5, 6, 7, 8, 9,10
intra8x9_hd4:  db  5, 6, 7, 8, 9,10,11,12, 1, 2, 3, 4, 5, 6, 7, 8
intra8x9_hu1:  db 13,12,11,10, 9, 8, 7, 6, 9, 8, 7, 6, 5, 4, 3, 2
intra8x9_hu2:  db 11,10, 9, 8, 7, 6, 5, 4, 7, 6, 5, 4, 3, 2, 1, 0
intra8x9_hu3:  db  5, 4, 3, 2, 1, 0,15,15, 1, 0,15,15,15,15,15,15
intra8x9_hu4:  db  3, 2, 1, 0,15,15,15,15,15,15,15,15,15,15,15,15
pw_s00112233:  dw 0x8000,0x8000,0x8001,0x8001,0x8002,0x8002,0x8003,0x8003
pw_s00001111:  dw 0x8000,0x8000,0x8000,0x8000,0x8001,0x8001,0x8001,0x8001

transd_shuf1: SHUFFLE_MASK_W 0, 8, 2, 10, 4, 12, 6, 14
transd_shuf2: SHUFFLE_MASK_W 1, 9, 3, 11, 5, 13, 7, 15

sw_f0:     dq 0xfff0, 0
pd_f0:     times 4 dd 0xffff0000
pd_2:      times 4 dd 2

pw_76543210: dw 0, 1, 2, 3, 4, 5, 6, 7

ads_mvs_shuffle:
%macro ADS_MVS_SHUFFLE 8
    %assign y x
    %rep 8
        %rep 7
            %rotate (~y)&1
            %assign y y>>((~y)&1)
        %endrep
        db %1*2, %1*2+1
        %rotate 1
        %assign y y>>1
    %endrep
%endmacro
%assign x 0
%rep 256
    ADS_MVS_SHUFFLE 0, 1, 2, 3, 4, 5, 6, 7
%assign x x+1
%endrep

%if HIGH_BIT_DEPTH == 0
; satd_mcc 4x4: byte pairs (i, i+2) of an interleaved uv row
mcc_ch_shuf: db 0, 2, 1, 3, 2, 4, 3, 5, 4, 6, 5, 7, 6, 8, 7, 9
%endif

%if HIGH_BIT_DEPTH
; 10-bit intra_satd_x9_4x4 / intra_sa8d_x9_8x8 (avx2), per-lane word shuffles
ALIGN 32
x9h_swapw: SHUFFLE_MASK_W 1, 0, 3, 2, 5, 4, 7, 6
           SHUFFLE_MASK_W 1, 0, 3, 2, 5, 4, 7, 6
x9h_top0:  SHUFFLE_MASK_W 0, 1, 2, 3, 4, 5, 6, 7
           SHUFFLE_MASK_W 1, 2, 3, 4, 5, 6, 7, 7
x9h_top1:  SHUFFLE_MASK_W 1, 2, 3, 4, 5, 6, 7, 7
           SHUFFLE_MASK_W 2, 3, 4, 5, 6, 7, 7, 7
x9h_top2:  SHUFFLE_MASK_W 2, 3, 4, 5, 6, 7, 7, 7
           SHUFFLE_MASK_W 3, 4, 5, 6, 7, 7, 7, 7
x9h_ddl:   SHUFFLE_MASK_W 0, 1, 2, 3, 1, 2, 3, 4
           SHUFFLE_MASK_W 1, 2, 3, 4, 2, 3, 4, 5
x9h_ldup:  SHUFFLE_MASK_W 0, 0, 1, 2, 3, 4, 5, 6
           SHUFFLE_MASK_W 0, 0, 1, 2, 3, 4, 5, 6
x9h_h:     SHUFFLE_MASK_W 3, 3, 3, 3, 2, 2, 2, 2
           SHUFFLE_MASK_W 1, 1, 1, 1, 0, 0, 0, 0
x9h_ddr:   SHUFFLE_MASK_W 4, 5, 6, 7, 3, 4, 5, 6
           SHUFFLE_MASK_W 2, 3, 4, 5, 1, 2, 3, 4
x9h_vrf:   SHUFFLE_MASK_W 0x80, 0x80, 0x80, 0x80, 4, 5, 6, 7
           SHUFFLE_MASK_W 3, 0x80, 0x80, 0x80, 2, 4, 5, 6
x9h_vrg:   SHUFFLE_MASK_W 4, 5, 6, 7, 0x80, 0x80, 0x80, 0x80
           SHUFFLE_MASK_W 0x80, 4, 5, 6, 0x80, 0x80, 0x80, 0x80
x9h_hdf:   SHUFFLE_MASK_W 0x80, 4, 5, 6, 0x80, 3, 0x80, 4
           SHUFFLE_MASK_W 0x80, 2, 0x80, 3, 0x80, 1, 0x80, 2
x9h_hdg:   SHUFFLE_MASK_W 3, 0x80, 0x80, 0x80, 2, 0x80, 3, 0x80
           SHUFFLE_MASK_W 1, 0x80, 2, 0x80, 0, 0x80, 1, 0x80
x9h_hu:    SHUFFLE_MASK_W 4, 5, 2, 3, 2, 3, 0, 1
           SHUFFLE_MASK_W 0, 1, 0, 1, 0, 1, 0, 1
x9h_deint: SHUFFLE_MASK_W 0, 2, 4, 6, 1, 3, 5, 7
x9h_rev:   SHUFFLE_MASK_W 7, 6, 5, 4, 3, 2, 1, 0
%endif

%if HIGH_BIT_DEPTH == 0
; 8-bit intra_satd_x9_4x4 / intra_sa8d_x9_8x8 (avx2): pshufb masks that give
; each prediction row twice within its lane, for the pmaddubsw hadamard stage
%macro X9B_MASK4 16 ; 4x4 rows 0-3: lane 0 = r0 r0 r1 r1, lane 1 = r2 r2 r3 r3
    db  %1, %2, %3, %4, %1, %2, %3, %4, %5, %6, %7, %8, %5, %6, %7, %8
    db  %9,%10,%11,%12, %9,%10,%11,%12,%13,%14,%15,%16,%13,%14,%15,%16
%endmacro
%macro X9B_MASK8 16 ; one 8x8 row of two modes: lane 0 = a a, lane 1 = b b
    db  %1, %2, %3, %4, %5, %6, %7, %8, %1, %2, %3, %4, %5, %6, %7, %8
    db  %9,%10,%11,%12,%13,%14,%15,%16, %9,%10,%11,%12,%13,%14,%15,%16
%endmacro
ALIGN 32
; 4x4, from e = l3 l3 l2 l1 l0 lt t0 .. t7 t7 t7, F = F2(e), P and Q as in INTRA_X9_PRED
x9b4_v:   X9B_MASK4  6, 7, 8, 9,  6, 7, 8, 9,  6, 7, 8, 9,  6, 7, 8, 9
x9b4_h:   X9B_MASK4  4, 4, 4, 4,  3, 3, 3, 3,  2, 2, 2, 2,  1, 1, 1, 1
x9b4_ddl: X9B_MASK4  6, 7, 8, 9,  7, 8, 9,10,  8, 9,10,11,  9,10,11,12
x9b4_ddr: X9B_MASK4  4, 5, 6, 7,  3, 4, 5, 6,  2, 3, 4, 5,  1, 2, 3, 4
x9b4_vr:  X9B_MASK4 10,11,12,13,  3, 4, 5, 6,  2,10,11,12,  1, 3, 4, 5
x9b4_hd:  X9B_MASK4 15, 4, 5, 6, 14, 3,15, 4, 13, 2,14, 3, 12, 1,13, 2
x9b4_vl:  X9B_MASK4 11,12,13,14,  5, 6, 7, 8, 12,13,14,15,  6, 7, 8, 9
x9b4_hu:  X9B_MASK4 14, 2,13, 1, 13, 1,12, 0, 12, 0,11,11, 11,11,11,11
; 8x8, rows 0-7 of each mode pair. Sources (lane 0 | lane 1):
; v | h: edge[16..31] | edge[7..22]
x9b8_vh:   X9B_MASK8  0, 1, 2, 3, 4, 5, 6, 7,  7, 7, 7, 7, 7, 7, 7, 7
           X9B_MASK8  0, 1, 2, 3, 4, 5, 6, 7,  6, 6, 6, 6, 6, 6, 6, 6
           X9B_MASK8  0, 1, 2, 3, 4, 5, 6, 7,  5, 5, 5, 5, 5, 5, 5, 5
           X9B_MASK8  0, 1, 2, 3, 4, 5, 6, 7,  4, 4, 4, 4, 4, 4, 4, 4
           X9B_MASK8  0, 1, 2, 3, 4, 5, 6, 7,  3, 3, 3, 3, 3, 3, 3, 3
           X9B_MASK8  0, 1, 2, 3, 4, 5, 6, 7,  2, 2, 2, 2, 2, 2, 2, 2
           X9B_MASK8  0, 1, 2, 3, 4, 5, 6, 7,  1, 1, 1, 1, 1, 1, 1, 1
           X9B_MASK8  0, 1, 2, 3, 4, 5, 6, 7,  0, 0, 0, 0, 0, 0, 0, 0
; dc | ddl: dc splat | FT
x9b8_dcddl: X9B_MASK8 0, 0, 0, 0, 0, 0, 0, 0,  1, 2, 3, 4, 5, 6, 7, 8
           X9B_MASK8  0, 0, 0, 0, 0, 0, 0, 0,  2, 3, 4, 5, 6, 7, 8, 9
           X9B_MASK8  0, 0, 0, 0, 0, 0, 0, 0,  3, 4, 5, 6, 7, 8, 9,10
           X9B_MASK8  0, 0, 0, 0, 0, 0, 0, 0,  4, 5, 6, 7, 8, 9,10,11
           X9B_MASK8  0, 0, 0, 0, 0, 0, 0, 0,  5, 6, 7, 8, 9,10,11,12
           X9B_MASK8  0, 0, 0, 0, 0, 0, 0, 0,  6, 7, 8, 9,10,11,12,13
           X9B_MASK8  0, 0, 0, 0, 0, 0, 0, 0,  7, 8, 9,10,11,12,13,14
           X9B_MASK8  0, 0, 0, 0, 0, 0, 0, 0,  8, 9,10,11,12,13,14,15
; ddr | vr: FL | FL (odd rows), FL | FL[0..7] GL[8..15] (even rows)
x9b8_ddrvr: X9B_MASK8 8, 9,10,11,12,13,14,15,  8, 9,10,11,12,13,14,15
           X9B_MASK8  7, 8, 9,10,11,12,13,14,  8, 9,10,11,12,13,14,15
           X9B_MASK8  6, 7, 8, 9,10,11,12,13,  7, 8, 9,10,11,12,13,14
           X9B_MASK8  5, 6, 7, 8, 9,10,11,12,  6, 8, 9,10,11,12,13,14
           X9B_MASK8  4, 5, 6, 7, 8, 9,10,11,  5, 7, 8, 9,10,11,12,13
           X9B_MASK8  3, 4, 5, 6, 7, 8, 9,10,  4, 6, 8, 9,10,11,12,13
           X9B_MASK8  2, 3, 4, 5, 6, 7, 8, 9,  3, 5, 7, 8, 9,10,11,12
           X9B_MASK8  1, 2, 3, 4, 5, 6, 7, 8,  2, 4, 6, 8, 9,10,11,12
; hd | vl: HDT[6..21] | GT, FT (rows 0-4), HDT[0..15] | GT, FT (rows 5-7)
x9b8_hdvl: X9B_MASK8  8, 9,10,11,12,13,14,15,  0, 1, 2, 3, 4, 5, 6, 7
           X9B_MASK8  6, 7, 8, 9,10,11,12,13,  1, 2, 3, 4, 5, 6, 7, 8
           X9B_MASK8  4, 5, 6, 7, 8, 9,10,11,  1, 2, 3, 4, 5, 6, 7, 8
           X9B_MASK8  2, 3, 4, 5, 6, 7, 8, 9,  2, 3, 4, 5, 6, 7, 8, 9
           X9B_MASK8  0, 1, 2, 3, 4, 5, 6, 7,  2, 3, 4, 5, 6, 7, 8, 9
           X9B_MASK8  4, 5, 6, 7, 8, 9,10,11,  3, 4, 5, 6, 7, 8, 9,10
           X9B_MASK8  2, 3, 4, 5, 6, 7, 8, 9,  3, 4, 5, 6, 7, 8, 9,10
           X9B_MASK8  0, 1, 2, 3, 4, 5, 6, 7,  4, 5, 6, 7, 8, 9,10,11
; hu: GL[0] FL[0] .. GL[6] FL[6] l7 l7 in both lanes (lane 1 unused)
x9b8_hu:   X9B_MASK8 12,13,10,11, 8, 9, 6, 7, 12,13,10,11, 8, 9, 6, 7
           X9B_MASK8 10,11, 8, 9, 6, 7, 4, 5, 10,11, 8, 9, 6, 7, 4, 5
           X9B_MASK8  8, 9, 6, 7, 4, 5, 2, 3,  8, 9, 6, 7, 4, 5, 2, 3
           X9B_MASK8  6, 7, 4, 5, 2, 3, 0, 1,  6, 7, 4, 5, 2, 3, 0, 1
           X9B_MASK8  4, 5, 2, 3, 0, 1,15,15,  4, 5, 2, 3, 0, 1,15,15
           X9B_MASK8  2, 3, 0, 1,15,15,15,15,  2, 3, 0, 1,15,15,15,15
           X9B_MASK8  0, 1,15,15,15,15,15,15,  0, 1,15,15,15,15,15,15
           X9B_MASK8 15,15,15,15,15,15,15,15, 15,15,15,15,15,15,15,15
x9b_swapw: SHUFFLE_MASK_W 1, 0, 3, 2, 5, 4, 7, 6
%endif

; intra_satd_lowres
ALIGN 32
pw_17408:      times 16 dw 17408 ; pmulhrsw: (17*x+16)>>5
lowres_p_x:    times 2 dw -3, -2, -1, 0, 1, 2, 3, 4
lowres_p_y:    times 8 dw -3
               times 8 dw 1
%if HIGH_BIT_DEPTH
lowres_p_w1:   dw -4, -3, -2, -1, 0, 1, 2, 3, 4, 3, 2, 1, 0, -1, -2, -3
lowres_p_w2:   dw  4,  0,  0,  0, 0, 0, 0, 0, -4, 0, 0, 0, 0, 0, 0, 0
lowres_h0:     times 8 db 14, 15
               times 8 db  6,  7
lowres_h1:     times 8 db 12, 13
               times 8 db  4,  5
lowres_h2:     times 8 db 10, 11
               times 8 db  2,  3
lowres_h3:     times 8 db  8,  9
               times 8 db  0,  1
%else
lowres_shuf_ul: times 2 db 0, 1, 2, 3, 4, 8, 7, 7, 8, 9,10,11,12,13,14,15
lowres_shuf_t2: times 2 db 1, 2, 3, 4, 5, 6, 7, 8, 9,10,11,12,13,14,15,15
lowres_p_wh:   db -4,-3,-2,-1, 0, 1, 2, 3, 4, 0, 0, 0, 0, 0, 0, 0
lowres_p_wv:   db  0, 0, 0, 0, 0, 0, 0, 4, 3, 2, 1, 0,-1,-2,-3,-4
lowres_p_wa:   db  0, 0, 0, 0, 0, 0, 0,16,16, 0, 0, 0, 0, 0, 0, 0
ALIGN 32
lowres_h0:     times 16 db 15
               times 16 db 11
lowres_h1:     times 16 db 14
               times 16 db 10
lowres_h2:     times 16 db 13
               times 16 db  9
lowres_h3:     times 16 db 12
               times 16 db  8
; rows (k, k+4) of the x9 predictions, each row twice
lowres_ddl0:   db  1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8
               db  5, 6, 7, 8, 9,10,11,12, 5, 6, 7, 8, 9,10,11,12
lowres_ddl1:   db  2, 3, 4, 5, 6, 7, 8, 9, 2, 3, 4, 5, 6, 7, 8, 9
               db  6, 7, 8, 9,10,11,12,13, 6, 7, 8, 9,10,11,12,13
lowres_ddl2:   db  3, 4, 5, 6, 7, 8, 9,10, 3, 4, 5, 6, 7, 8, 9,10
               db  7, 8, 9,10,11,12,13,14, 7, 8, 9,10,11,12,13,14
lowres_ddl3:   db  4, 5, 6, 7, 8, 9,10,11, 4, 5, 6, 7, 8, 9,10,11
               db  8, 9,10,11,12,13,14,15, 8, 9,10,11,12,13,14,15
lowres_vl0:    db  0, 1, 2, 3, 4, 5, 6, 7, 0, 1, 2, 3, 4, 5, 6, 7
               db  2, 3, 4, 5, 6, 7, 8, 9, 2, 3, 4, 5, 6, 7, 8, 9
lowres_vl1:    db  1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8
               db  3, 4, 5, 6, 7, 8, 9,10, 3, 4, 5, 6, 7, 8, 9,10
lowres_vl2:    db  1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8
               db  3, 4, 5, 6, 7, 8, 9,10, 3, 4, 5, 6, 7, 8, 9,10
lowres_vl3:    db  2, 3, 4, 5, 6, 7, 8, 9, 2, 3, 4, 5, 6, 7, 8, 9
               db  4, 5, 6, 7, 8, 9,10,11, 4, 5, 6, 7, 8, 9,10,11
lowres_ddr0:   db  8, 9,10,11,12,13,14,15, 8, 9,10,11,12,13,14,15
               db  4, 5, 6, 7, 8, 9,10,11, 4, 5, 6, 7, 8, 9,10,11
lowres_ddr1:   db  7, 8, 9,10,11,12,13,14, 7, 8, 9,10,11,12,13,14
               db  3, 4, 5, 6, 7, 8, 9,10, 3, 4, 5, 6, 7, 8, 9,10
lowres_ddr2:   db  6, 7, 8, 9,10,11,12,13, 6, 7, 8, 9,10,11,12,13
               db  2, 3, 4, 5, 6, 7, 8, 9, 2, 3, 4, 5, 6, 7, 8, 9
lowres_ddr3:   db  5, 6, 7, 8, 9,10,11,12, 5, 6, 7, 8, 9,10,11,12
               db  1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8
lowres_vr0:    db  8, 9,10,11,12,13,14,15, 8, 9,10,11,12,13,14,15
               db  5, 7, 8, 9,10,11,12,13, 5, 7, 8, 9,10,11,12,13
lowres_vr1:    db  8, 9,10,11,12,13,14,15, 8, 9,10,11,12,13,14,15
               db  4, 6, 8, 9,10,11,12,13, 4, 6, 8, 9,10,11,12,13
lowres_vr2:    db  7, 8, 9,10,11,12,13,14, 7, 8, 9,10,11,12,13,14
               db  3, 5, 7, 8, 9,10,11,12, 3, 5, 7, 8, 9,10,11,12
lowres_vr3:    db  6, 8, 9,10,11,12,13,14, 6, 8, 9,10,11,12,13,14
               db  2, 4, 6, 8, 9,10,11,12, 2, 4, 6, 8, 9,10,11,12
lowres_hd0:    db  3, 8, 9,10,11,12,13,14, 3, 8, 9,10,11,12,13,14
               db  7, 8, 9,10,11,12,13,14, 7, 8, 9,10,11,12,13,14
lowres_hd1:    db  2, 7, 3, 8, 9,10,11,12, 2, 7, 3, 8, 9,10,11,12
               db  5, 6, 7, 8, 9,10,11,12, 5, 6, 7, 8, 9,10,11,12
lowres_hd2:    db  1, 6, 2, 7, 3, 8, 9,10, 1, 6, 2, 7, 3, 8, 9,10
               db  3, 4, 5, 6, 7, 8, 9,10, 3, 4, 5, 6, 7, 8, 9,10
lowres_hd3:    db  0, 5, 1, 6, 2, 7, 3, 8, 0, 5, 1, 6, 2, 7, 3, 8
               db  1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8
lowres_hu0:    db 13,12,11,10, 9, 8, 7, 6,13,12,11,10, 9, 8, 7, 6
               db  5, 4, 3, 2, 1, 0,15,15, 5, 4, 3, 2, 1, 0,15,15
lowres_hu1:    db 11,10, 9, 8, 7, 6, 5, 4,11,10, 9, 8, 7, 6, 5, 4
               db  3, 2, 1, 0,15,15,15,15, 3, 2, 1, 0,15,15,15,15
lowres_hu2:    db  9, 8, 7, 6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2
               db  1, 0,15,15,15,15,15,15, 1, 0,15,15,15,15,15,15
lowres_hu3:    db  7, 6, 5, 4, 3, 2, 1, 0, 7, 6, 5, 4, 3, 2, 1, 0
               db 15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15
%endif
; weightp: vpermd orders of 2 and 4 blocks a register, byte loads, last so nothing moves
weightp_perm8:  db 0,4,1,5,2,6,3,7
weightp_perm16: db 0,4,8,12,1,5,9,13,2,6,10,14,3,7,11,15
weightp_perm_nv16: db 0,4,1,5,2,6,3,7,8,12,9,13,10,14,11,15
; ads avx512icl: candidate indices
ads_idx_w: dw  0, 1, 2, 3, 4, 5, 6, 7, 8, 9,10,11,12,13,14,15
           dw 16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
; 8-bit weightp_stats8 avx512icl: vpermt2b of the min (bytes 0-31) and max (32-63) dwords of
; blocks 0 1 4 5 | 2 3 6 7 to min | max << 16 in block order; vpermt2d of the qword sums
weightp_mm_perm:  db  0,0,32,0,  4,0,36,0, 16,0,48,0, 20,0,52,0
                  db  8,0,40,0, 12,0,44,0, 24,0,56,0, 28,0,60,0
weightp_sum_perm: dd  0, 2, 4, 6, 8,10,12,14

SECTION .text

cextern pb_0
cextern pb_1
cextern pw_1
cextern pw_4
cextern pw_8
cextern pw_16
cextern pw_32
cextern pw_00ff
cextern pw_ppppmmmm
cextern pw_ppmmppmm
cextern pw_pmpmpmpm
cextern pw_pmmpzzzz
cextern pw_512
cextern pw_pixel_max
cextern pd_1
cextern pd_ffff
cextern hsub_mul
cextern popcnt_table

;=============================================================================
; SSD
;=============================================================================

%if HIGH_BIT_DEPTH
;-----------------------------------------------------------------------------
; int pixel_ssd_WxH( uint16_t *, intptr_t, uint16_t *, intptr_t )
;-----------------------------------------------------------------------------
%macro SSD_ONE 2
cglobal pixel_ssd_%1x%2, 4,7,6
    FIX_STRIDES r1, r3
%if mmsize == %1*2
    %define offset0_1 r1
    %define offset0_2 r1*2
    %define offset0_3 r5
    %define offset1_1 r3
    %define offset1_2 r3*2
    %define offset1_3 r6
    lea     r5, [3*r1]
    lea     r6, [3*r3]
%elif mmsize == %1
    %define offset0_1 mmsize
    %define offset0_2 r1
    %define offset0_3 r1+mmsize
    %define offset1_1 mmsize
    %define offset1_2 r3
    %define offset1_3 r3+mmsize
%elif mmsize == %1/2
    %define offset0_1 mmsize
    %define offset0_2 mmsize*2
    %define offset0_3 mmsize*3
    %define offset1_1 mmsize
    %define offset1_2 mmsize*2
    %define offset1_3 mmsize*3
%endif
    %assign %%n %2/(2*mmsize/%1)
%if %%n > 1
    mov    r4d, %%n
%endif
    pxor    m0, m0
.loop:
    mova    m1, [r0]
    mova    m2, [r0+offset0_1]
    mova    m3, [r0+offset0_2]
    mova    m4, [r0+offset0_3]
    psubw   m1, [r2]
    psubw   m2, [r2+offset1_1]
    psubw   m3, [r2+offset1_2]
    psubw   m4, [r2+offset1_3]
%if %%n > 1
    lea     r0, [r0+r1*(%2/%%n)]
    lea     r2, [r2+r3*(%2/%%n)]
%endif
    pmaddwd m1, m1
    pmaddwd m2, m2
    pmaddwd m3, m3
    pmaddwd m4, m4
    paddd   m1, m2
    paddd   m3, m4
    paddd   m0, m1
    paddd   m0, m3
%if %%n > 1
    dec    r4d
    jg .loop
%endif
    HADDD   m0, m5
    movd   eax, xm0
    RET
%endmacro

INIT_MMX mmx2
SSD_ONE     4,  4
SSD_ONE     4,  8
SSD_ONE     4, 16
SSD_ONE     8,  4
SSD_ONE     8,  8
SSD_ONE     8, 16
SSD_ONE    16,  8
SSD_ONE    16, 16
INIT_XMM sse2
SSD_ONE     8,  4
SSD_ONE     8,  8
SSD_ONE     8, 16
SSD_ONE    16,  8
SSD_ONE    16, 16
INIT_YMM avx2
SSD_ONE    16,  8
SSD_ONE    16, 16

; 8 wide: two rows a ymm
%macro SSD_W8_HBD 1 ; height
cglobal pixel_ssd_8x%1, 4,7,5
    FIX_STRIDES r1, r3
    lea     r5, [3*r1]
    lea     r6, [3*r3]
    pxor    m0, m0
%rep %1/4
    mova   xm1, [r0]
    vinserti128 m1, m1, [r0+r1], 1
    mova   xm2, [r0+2*r1]
    vinserti128 m2, m2, [r0+r5], 1
    mova   xm3, [r2]
    vinserti128 m3, m3, [r2+r3], 1
    mova   xm4, [r2+2*r3]
    vinserti128 m4, m4, [r2+r6], 1
    psubw   m1, m3
    psubw   m2, m4
    pmaddwd m1, m1
    pmaddwd m2, m2
    paddd   m0, m1
    paddd   m0, m2
    lea     r0, [r0+4*r1]
    lea     r2, [r2+4*r3]
%endrep
    HADDD   m0, m1
    movd   eax, xm0
    RET
%endmacro

SSD_W8_HBD  8
SSD_W8_HBD 16
%endif ; HIGH_BIT_DEPTH

%if HIGH_BIT_DEPTH == 0
%macro SSD_LOAD_FULL 5
    mova      m1, [t0+%1]
    mova      m2, [t2+%2]
    mova      m3, [t0+%3]
    mova      m4, [t2+%4]
%if %5==1
    add       t0, t1
    add       t2, t3
%elif %5==2
    lea       t0, [t0+2*t1]
    lea       t2, [t2+2*t3]
%endif
%endmacro

%macro LOAD 5
    movh      m%1, %3
    movh      m%2, %4
%if %5
    lea       t0, [t0+2*t1]
%endif
%endmacro

%macro JOIN 7
    movh      m%3, %5
    movh      m%4, %6
%if %7
    lea       t2, [t2+2*t3]
%endif
    punpcklbw m%1, m7
    punpcklbw m%3, m7
    psubw     m%1, m%3
    punpcklbw m%2, m7
    punpcklbw m%4, m7
    psubw     m%2, m%4
%endmacro

%macro JOIN_SSE2 7
    movh      m%3, %5
    movh      m%4, %6
%if %7
    lea       t2, [t2+2*t3]
%endif
    punpcklqdq m%1, m%2
    punpcklqdq m%3, m%4
    DEINTB %2, %1, %4, %3, 7
    psubw m%2, m%4
    psubw m%1, m%3
%endmacro

%macro JOIN_SSSE3 7
    movh      m%3, %5
    movh      m%4, %6
%if %7
    lea       t2, [t2+2*t3]
%endif
    punpcklbw m%1, m%3
    punpcklbw m%2, m%4
%endmacro

%macro LOAD_AVX2 5
    mova     xm%1, %3
    vinserti128 m%1, m%1, %4, 1
%if %5
    lea       t0, [t0+2*t1]
%endif
%endmacro

%macro JOIN_AVX2 7
    mova     xm%2, %5
    vinserti128 m%2, m%2, %6, 1
%if %7
    lea       t2, [t2+2*t3]
%endif
    SBUTTERFLY bw, %1, %2, %3
%endmacro

%macro SSD_LOAD_HALF 5
    LOAD      1, 2, [t0+%1], [t0+%3], 1
    JOIN      1, 2, 3, 4, [t2+%2], [t2+%4], 1
    LOAD      3, 4, [t0+%1], [t0+%3], %5
    JOIN      3, 4, 5, 6, [t2+%2], [t2+%4], %5
%endmacro

%macro SSD_CORE 7-8
%ifidn %8, FULL
    mova      m%6, m%2
    mova      m%7, m%4
    psubusb   m%2, m%1
    psubusb   m%4, m%3
    psubusb   m%1, m%6
    psubusb   m%3, m%7
    por       m%1, m%2
    por       m%3, m%4
    punpcklbw m%2, m%1, m%5
    punpckhbw m%1, m%5
    punpcklbw m%4, m%3, m%5
    punpckhbw m%3, m%5
%endif
    pmaddwd   m%1, m%1
    pmaddwd   m%2, m%2
    pmaddwd   m%3, m%3
    pmaddwd   m%4, m%4
%endmacro

%macro SSD_CORE_SSE2 7-8
%ifidn %8, FULL
    DEINTB %6, %1, %7, %2, %5
    psubw m%6, m%7
    psubw m%1, m%2
    SWAP %6, %2, %1
    DEINTB %6, %3, %7, %4, %5
    psubw m%6, m%7
    psubw m%3, m%4
    SWAP %6, %4, %3
%endif
    pmaddwd   m%1, m%1
    pmaddwd   m%2, m%2
    pmaddwd   m%3, m%3
    pmaddwd   m%4, m%4
%endmacro

%macro SSD_CORE_SSSE3 7-8
%ifidn %8, FULL
    punpckhbw m%6, m%1, m%2
    punpckhbw m%7, m%3, m%4
    punpcklbw m%1, m%2
    punpcklbw m%3, m%4
    SWAP %6, %2, %3
    SWAP %7, %4
%endif
    pmaddubsw m%1, m%5
    pmaddubsw m%2, m%5
    pmaddubsw m%3, m%5
    pmaddubsw m%4, m%5
    pmaddwd   m%1, m%1
    pmaddwd   m%2, m%2
    pmaddwd   m%3, m%3
    pmaddwd   m%4, m%4
%endmacro

%macro SSD_ITER 6
    SSD_LOAD_%1 %2,%3,%4,%5,%6
    SSD_CORE  1, 2, 3, 4, 7, 5, 6, %1
    paddd     m1, m2
    paddd     m3, m4
    paddd     m0, m1
    paddd     m0, m3
%endmacro

;-----------------------------------------------------------------------------
; int pixel_ssd_16x16( uint8_t *, intptr_t, uint8_t *, intptr_t )
;-----------------------------------------------------------------------------
%macro SSD 2
%if %1 != %2
    %assign function_align 8
%else
    %assign function_align 16
%endif
cglobal pixel_ssd_%1x%2, 0,0,0
    mov     al, %1*%2/mmsize/2

%if %1 != %2
    jmp mangle(private_prefix %+ _pixel_ssd_%1x%1 %+ SUFFIX %+ .startloop)
%else

.startloop:
%if ARCH_X86_64
    DECLARE_REG_TMP 0,1,2,3
    PROLOGUE 0,0,8
%else
    PROLOGUE 0,5
    DECLARE_REG_TMP 1,2,3,4
    mov t0, r0m
    mov t1, r1m
    mov t2, r2m
    mov t3, r3m
%endif

%if cpuflag(ssse3)
    mova    m7, [hsub_mul]
%elifidn cpuname, sse2
    mova    m7, [pw_00ff]
%elif %1 >= mmsize
    pxor    m7, m7
%endif
    pxor    m0, m0

ALIGN 16
.loop:
%if %1 > mmsize
    SSD_ITER FULL, 0, 0, mmsize, mmsize, 1
%elif %1 == mmsize
    SSD_ITER FULL, 0, 0, t1, t3, 2
%else
    SSD_ITER HALF, 0, 0, t1, t3, 2
%endif
    dec     al
    jg .loop
%if mmsize==32
    vextracti128 xm1, m0, 1
    paddd  xm0, xm1
    HADDD  xm0, xm1
    movd   eax, xm0
%else
    HADDD   m0, m1
    movd   eax, m0
%endif
    RET
%endif
%endmacro

INIT_MMX mmx
SSD 16, 16
SSD 16,  8
SSD  8,  8
SSD  8, 16
SSD  4,  4
SSD  8,  4
SSD  4,  8
SSD  4, 16
INIT_XMM sse2slow
SSD 16, 16
SSD  8,  8
SSD 16,  8
SSD  8, 16
SSD  8,  4
INIT_XMM sse2
%define SSD_CORE SSD_CORE_SSE2
%define JOIN JOIN_SSE2
SSD 16, 16
SSD  8,  8
SSD 16,  8
SSD  8, 16
SSD  8,  4
INIT_XMM ssse3
%define SSD_CORE SSD_CORE_SSSE3
%define JOIN JOIN_SSSE3
SSD 16, 16
SSD  8,  8
SSD 16,  8
SSD  8, 16
SSD  8,  4
INIT_XMM avx
SSD 16, 16
SSD  8,  8
SSD 16,  8
SSD  8, 16
SSD  8,  4
INIT_MMX ssse3
SSD  4,  4
SSD  4,  8
SSD  4, 16
INIT_XMM xop
SSD 16, 16
SSD  8,  8
SSD 16,  8
SSD  8, 16
SSD  8,  4
%define LOAD LOAD_AVX2
%define JOIN JOIN_AVX2
INIT_YMM avx2
SSD 16, 16
SSD 16,  8
%assign function_align 16
%endif ; !HIGH_BIT_DEPTH

;-----------------------------------------------------------------------------
; void pixel_ssd_nv12_core( uint16_t *pixuv1, intptr_t stride1, uint16_t *pixuv2, intptr_t stride2,
;                           int width, int height, uint64_t *ssd_u, uint64_t *ssd_v )
;
; The maximum width this function can handle without risk of overflow is given
; in the following equation: (mmsize in bits)
;
;   2 * mmsize/32 * (2^32 - 1) / (2^BIT_DEPTH - 1)^2
;
; For 10-bit MMX this means width >= 16416 and for XMM >= 32832. At sane
; distortion levels it will take much more than that though.
;-----------------------------------------------------------------------------
%if HIGH_BIT_DEPTH
%macro SSD_NV12 0
cglobal pixel_ssd_nv12_core, 6,7,7
    shl        r4d, 2
    FIX_STRIDES r1, r3
    add         r0, r4
    add         r2, r4
    xor         r6, r6
    pxor        m4, m4
    pxor        m5, m5
    pxor        m6, m6
.loopy:
    mov         r6, r4
    neg         r6
    pxor        m2, m2
    pxor        m3, m3
.loopx:
    mova        m0, [r0+r6]
    mova        m1, [r0+r6+mmsize]
    psubw       m0, [r2+r6]
    psubw       m1, [r2+r6+mmsize]
    PSHUFLW     m0, m0, q3120
    PSHUFLW     m1, m1, q3120
%if mmsize >= 16
    pshufhw     m0, m0, q3120
    pshufhw     m1, m1, q3120
%endif
    pmaddwd     m0, m0
    pmaddwd     m1, m1
    paddd       m2, m0
    paddd       m3, m1
    add         r6, 2*mmsize
    jl .loopx
%if mmsize == 32 ; avx2 may overread by 32 bytes, that has to be handled
    jz .no_overread
    psubd       m3, m1
.no_overread:
%endif
%if mmsize >= 16 ; using HADDD would remove the mmsize/32 part from the
                 ; equation above, putting the width limit at 8208
    punpckhdq   m0, m2, m6
    punpckhdq   m1, m3, m6
    punpckldq   m2, m6
    punpckldq   m3, m6
    paddq       m3, m2
    paddq       m1, m0
    paddq       m4, m3
    paddq       m4, m1
%else ; unfortunately paddq is sse2
      ; emulate 48 bit precision for mmx2 instead
    mova        m0, m2
    mova        m1, m3
    punpcklwd   m2, m6
    punpcklwd   m3, m6
    punpckhwd   m0, m6
    punpckhwd   m1, m6
    paddd       m3, m2
    paddd       m1, m0
    paddd       m4, m3
    paddd       m5, m1
%endif
    add         r0, r1
    add         r2, r3
    dec        r5d
    jg .loopy
    mov         r3, r6m
    mov         r4, r7m
%if mmsize == 32
    vextracti128 xm0, m4, 1
    paddq      xm4, xm0
%endif
%if mmsize >= 16
    movq      [r3], xm4
    movhps    [r4], xm4
%else ; fixup for mmx2
    SBUTTERFLY dq, 4, 5, 0
    mova        m0, m4
    psrld       m4, 16
    paddd       m5, m4
    pslld       m0, 16
    SBUTTERFLY dq, 0, 5, 4
    psrlq       m0, 16
    psrlq       m5, 16
    movq      [r3], m0
    movq      [r4], m5
%endif
    RET
%endmacro ; SSD_NV12
%endif ; HIGH_BIT_DEPTH

%if HIGH_BIT_DEPTH == 0
;-----------------------------------------------------------------------------
; void pixel_ssd_nv12_core( uint8_t *pixuv1, intptr_t stride1, uint8_t *pixuv2, intptr_t stride2,
;                           int width, int height, uint64_t *ssd_u, uint64_t *ssd_v )
;
; This implementation can potentially overflow on image widths >= 11008 (or
; 6604 if interlaced), since it is called on blocks of height up to 12 (resp
; 20). At sane distortion levels it will take much more than that though.
;-----------------------------------------------------------------------------
%macro SSD_NV12 0
cglobal pixel_ssd_nv12_core, 6,7
    add    r4d, r4d
    add     r0, r4
    add     r2, r4
    pxor    m3, m3
    pxor    m4, m4
    mova    m5, [pw_00ff]
.loopy:
    mov     r6, r4
    neg     r6
.loopx:
%if mmsize == 32 ; only 16-byte alignment is guaranteed
    movu    m2, [r0+r6]
    movu    m1, [r2+r6]
%else
    mova    m2, [r0+r6]
    mova    m1, [r2+r6]
%endif
    psubusb m0, m2, m1
    psubusb m1, m2
    por     m0, m1
    psrlw   m2, m0, 8
    pand    m0, m5
    pmaddwd m2, m2
    pmaddwd m0, m0
    paddd   m3, m0
    paddd   m4, m2
    add     r6, mmsize
    jl .loopx
%if mmsize == 32 ; avx2 may overread by 16 bytes, that has to be handled
    jz .no_overread
    pcmpeqb xm1, xm1
    pandn   m0, m1, m0 ; zero the lower half
    pandn   m2, m1, m2
    psubd   m3, m0
    psubd   m4, m2
.no_overread:
%endif
    add     r0, r1
    add     r2, r3
    dec    r5d
    jg .loopy
    mov     r3, r6m
    mov     r4, r7m
    HADDD   m3, m0
    HADDD   m4, m0
    pxor   xm0, xm0
    punpckldq xm3, xm0
    punpckldq xm4, xm0
    movq  [r3], xm3
    movq  [r4], xm4
    RET
%endmacro ; SSD_NV12
%endif ; !HIGH_BIT_DEPTH

INIT_MMX mmx2
SSD_NV12
INIT_XMM sse2
SSD_NV12
INIT_XMM avx
SSD_NV12
INIT_YMM avx2
SSD_NV12

;-----------------------------------------------------------------------------
; int pixel_ssd_WxH( pixel *, intptr_t, pixel *, intptr_t ), avx512icl: VNNI
;-----------------------------------------------------------------------------
%if ARCH_X86_64
%if HIGH_BIT_DEPTH
; vpdpwssd of the differences into m0 m5
%macro SSD_ICL 2-3 ; width, height, name suffix
cglobal pixel_ssd_%1x%2%3, 4,7,6
    FIX_STRIDES r1, r3
    lea         r5, [r1*3]
    lea         r6, [r3*3]
    pxor        m0, m0
    pxor        m5, m5
%rep %2/4
%if %1 == 16 && mmsize == 64
    movu       ym1, [r0]
    vinserti64x4 m1, m1, [r0+r1], 1
    movu       ym2, [r0+r1*2]
    vinserti64x4 m2, m2, [r0+r5], 1
    movu       ym3, [r2]
    vinserti64x4 m3, m3, [r2+r3], 1
    movu       ym4, [r2+r3*2]
    vinserti64x4 m4, m4, [r2+r6], 1
    psubw       m1, m3
    psubw       m2, m4
    vpdpwssd    m0, m1, m1
    vpdpwssd    m5, m2, m2
%elif %1 == 16
    movu        m1, [r0]
    movu        m2, [r0+r1]
    movu        m3, [r0+r1*2]
    movu        m4, [r0+r5]
    psubw       m1, [r2]
    psubw       m2, [r2+r3]
    psubw       m3, [r2+r3*2]
    psubw       m4, [r2+r6]
    vpdpwssd    m0, m1, m1
    vpdpwssd    m5, m2, m2
    vpdpwssd    m0, m3, m3
    vpdpwssd    m5, m4, m4
%else
    movu       xm1, [r0]
    vinserti128 m1, m1, [r0+r1], 1
    movu       xm2, [r0+r1*2]
    vinserti128 m2, m2, [r0+r5], 1
    movu       xm3, [r2]
    vinserti128 m3, m3, [r2+r3], 1
    movu       xm4, [r2+r3*2]
    vinserti128 m4, m4, [r2+r6], 1
    psubw       m1, m3
    psubw       m2, m4
    vpdpwssd    m0, m1, m1
    vpdpwssd    m5, m2, m2
%endif
    lea         r0, [r0+r1*4]
    lea         r2, [r2+r3*4]
%endrep
    paddd       m0, m5
    HADDD       m0, m1
    movd       eax, xm0
    RET
%endmacro
%else ; !HIGH_BIT_DEPTH
; |a - b| bytes; vpdpbusd |d| * (|d| ^ 0x80) = d*d - 128*|d| into m0 m5 and |d| into m4 m8
; m6 = 1, m7 = 0x80
%macro SSD_ICL_ABS 4 ; a (|d| out), b, square, sum
    pminub      m3, m%1, m%2
    pmaxub     m%1, m%2
    psubb      m%1, m3
    pxor        m3, m%1, m7
    vpdpbusd   m%3, m%1, m3
    vpdpbusd   m%4, m%1, m6
%endmacro

; four rows of 8 a ymm
%macro SSD_ICL_W8 4 ; dst, src, stride, 3*stride
    movq      xm%1, [%2]
    movhps    xm%1, [%2+%3]
    movq       xm3, [%2+%3*2]
    movhps     xm3, [%2+%4]
    vinserti128 m%1, m%1, xm3, 1
%endmacro

; four rows of 16 a zmm
%macro SSD_ICL_W16Z 4 ; dst, src, stride, 3*stride
    movu      xm%1, [%2]
    vinserti32x4 m%1, m%1, [%2+%3], 1
    vinserti32x4 m%1, m%1, [%2+%3*2], 2
    vinserti32x4 m%1, m%1, [%2+%4], 3
%endmacro

%macro SSD_ICL 2-3 ; width, height, name suffix
cglobal pixel_ssd_%1x%2%3, 4,7,9
    lea         r5, [r1*3]
    lea         r6, [r3*3]
    vpbroadcastd m6, [pb_1]
    mov        r4d, 0x80808080
    vpbroadcastd m7, r4d
    pxor        m0, m0
    pxor        m5, m5
    pxor        m4, m4
    pxor        m8, m8
%rep %2/4
%if %1 == 16 && mmsize == 64
    SSD_ICL_W16Z 1, r0, r1, r5
    SSD_ICL_W16Z 2, r2, r3, r6
    SSD_ICL_ABS 1, 2, 0, 4
    SWAP 0, 5
    SWAP 4, 8
%elif %1 == 16
    movu       xm1, [r0]
    vinserti128 m1, m1, [r0+r1], 1
    movu       xm2, [r2]
    vinserti128 m2, m2, [r2+r3], 1
    SSD_ICL_ABS 1, 2, 0, 4
    movu       xm1, [r0+r1*2]
    vinserti128 m1, m1, [r0+r5], 1
    movu       xm2, [r2+r3*2]
    vinserti128 m2, m2, [r2+r6], 1
    SSD_ICL_ABS 1, 2, 5, 8
%else
    SSD_ICL_W8 1, r0, r1, r5
    SSD_ICL_W8 2, r2, r3, r6
    SSD_ICL_ABS 1, 2, 0, 4
    SWAP 0, 5
    SWAP 4, 8
%endif
    lea         r0, [r0+r1*4]
    lea         r2, [r2+r3*4]
%endrep
    paddd       m0, m5
    paddd       m4, m8
    pslld       m4, 7
    paddd       m0, m4
    HADDD       m0, m1
    movd       eax, xm0
    RET
%endmacro
%endif ; HIGH_BIT_DEPTH

INIT_YMM avx512icl
SSD_ICL 16, 16
SSD_ICL 16,  8
SSD_ICL  8, 16
SSD_ICL  8,  8
; zmm: assembled, not dispatched (for full width zmm)
INIT_ZMM avx512icl
SSD_ICL 16, 16, _zmm
SSD_ICL 16,  8, _zmm
%endif ; ARCH_X86_64

;=============================================================================
; variance
;=============================================================================

%macro VAR_START 1
    pxor  m5, m5    ; sum
    pxor  m6, m6    ; sum squared
%if HIGH_BIT_DEPTH == 0
%if %1
    mova  m7, [pw_00ff]
%elif mmsize < 32
    pxor  m7, m7    ; zero
%endif
%endif ; !HIGH_BIT_DEPTH
%endmacro

%macro VAR_END 2
%if HIGH_BIT_DEPTH
%if mmsize == 8 && %1*%2 == 256
    HADDUW  m5, m2
%else
    HADDW   m5, m2
%endif
%else ; !HIGH_BIT_DEPTH
    HADDW   m5, m2
%endif ; HIGH_BIT_DEPTH
    HADDD   m6, m1
%if ARCH_X86_64
    punpckldq m5, m6
    movq   rax, m5
%else
    movd   eax, m5
    movd   edx, m6
%endif
    RET
%endmacro

%macro VAR_CORE 0
    paddw     m5, m0
    paddw     m5, m3
    paddw     m5, m1
    paddw     m5, m4
    pmaddwd   m0, m0
    pmaddwd   m3, m3
    pmaddwd   m1, m1
    pmaddwd   m4, m4
    paddd     m6, m0
    paddd     m6, m3
    paddd     m6, m1
    paddd     m6, m4
%endmacro

%macro VAR_2ROW 2
    mov      r2d, %2
.loop:
%if HIGH_BIT_DEPTH
    mova      m0, [r0]
    mova      m1, [r0+mmsize]
    mova      m3, [r0+%1]
    mova      m4, [r0+%1+mmsize]
%else ; !HIGH_BIT_DEPTH
    mova      m0, [r0]
    punpckhbw m1, m0, m7
    mova      m3, [r0+%1]
    mova      m4, m3
    punpcklbw m0, m7
%endif ; HIGH_BIT_DEPTH
%ifidn %1, r1
    lea       r0, [r0+%1*2]
%else
    add       r0, r1
%endif
%if HIGH_BIT_DEPTH == 0
    punpcklbw m3, m7
    punpckhbw m4, m7
%endif ; !HIGH_BIT_DEPTH
    VAR_CORE
    dec r2d
    jg .loop
%endmacro

;-----------------------------------------------------------------------------
; int pixel_var_wxh( uint8_t *, intptr_t )
;-----------------------------------------------------------------------------
INIT_MMX mmx2
cglobal pixel_var_16x16, 2,3
    FIX_STRIDES r1
    VAR_START 0
    VAR_2ROW 8*SIZEOF_PIXEL, 16
    VAR_END 16, 16

cglobal pixel_var_8x16, 2,3
    FIX_STRIDES r1
    VAR_START 0
    VAR_2ROW r1, 8
    VAR_END 8, 16

cglobal pixel_var_8x8, 2,3
    FIX_STRIDES r1
    VAR_START 0
    VAR_2ROW r1, 4
    VAR_END 8, 8

%if HIGH_BIT_DEPTH
%macro VAR 0
cglobal pixel_var_16x16, 2,3,8
    FIX_STRIDES r1
    VAR_START 0
    VAR_2ROW r1, 8
    VAR_END 16, 16

cglobal pixel_var_8x8, 2,3,8
    lea       r2, [r1*3]
    VAR_START 0
    mova      m0, [r0]
    mova      m1, [r0+r1*2]
    mova      m3, [r0+r1*4]
    mova      m4, [r0+r2*2]
    lea       r0, [r0+r1*8]
    VAR_CORE
    mova      m0, [r0]
    mova      m1, [r0+r1*2]
    mova      m3, [r0+r1*4]
    mova      m4, [r0+r2*2]
    VAR_CORE
    VAR_END 8, 8

cglobal pixel_var_8x16, 2,3,8
    lea       r2, [r1*3]
    VAR_START 0
%rep 3
    mova      m0, [r0]
    mova      m1, [r0+r1*2]
    mova      m3, [r0+r1*4]
    mova      m4, [r0+r2*2]
    lea       r0, [r0+r1*8]
    VAR_CORE
%endrep
    mova      m0, [r0]
    mova      m1, [r0+r1*2]
    mova      m3, [r0+r1*4]
    mova      m4, [r0+r2*2]
    VAR_CORE
    VAR_END 8, 16
%endmacro ; VAR

INIT_XMM sse2
VAR
INIT_XMM avx
VAR
INIT_XMM xop
VAR

; rows only need 16 byte alignment: without AVX-512 frame strides are 16 byte aligned
%macro VAR_END_YMM 0
    HADDW     m5, m2
    HADDD     m6, m1
%if ARCH_X86_64
    punpckldq xm5, xm6
    movq     rax, xm5
%else
    movd     eax, xm5
    movd     edx, xm6
%endif
    RET
%endmacro

; four rows a ymm pair: lane 0 rows from %1, lane 1 rows from %2
%macro VAR_LOAD4_YMM 2
    mova         xm0, [%1]
    vinserti128   m0, m0, [%2], 1
    mova         xm3, [%1+r1]
    vinserti128   m3, m3, [%2+r1], 1
    mova         xm1, [%1+r1*2]
    vinserti128   m1, m1, [%2+r1*2], 1
    mova         xm4, [%1+r3]
    vinserti128   m4, m4, [%2+r3], 1
%endmacro

INIT_YMM avx2
cglobal pixel_var_16x16, 2,4,7
    FIX_STRIDES r1
    lea       r3, [r1*3]
    VAR_START 0
%rep 4
    VAR_LOAD4_YMM r0, r0+16
    lea       r0, [r0+r1*4]
    VAR_CORE
%endrep
    VAR_END_YMM

cglobal pixel_var_8x16, 2,4,7
    FIX_STRIDES r1
    lea       r3, [r1*3]
    lea       r2, [r0+r1*4]
    VAR_START 0
    VAR_LOAD4_YMM r0, r2
    lea       r0, [r0+r1*8]
    lea       r2, [r2+r1*8]
    VAR_CORE
    VAR_LOAD4_YMM r0, r2
    VAR_CORE
    VAR_END_YMM
%endif ; HIGH_BIT_DEPTH

%if HIGH_BIT_DEPTH == 0
%macro VAR 0
cglobal pixel_var_16x16, 2,3,8
    VAR_START 1
    mov      r2d, 8
.loop:
    mova      m0, [r0]
    mova      m3, [r0+r1]
    DEINTB    1, 0, 4, 3, 7
    lea       r0, [r0+r1*2]
    VAR_CORE
    dec r2d
    jg .loop
    VAR_END 16, 16

cglobal pixel_var_8x8, 2,4,8
    VAR_START 1
    mov      r2d, 2
    lea       r3, [r1*3]
.loop:
    movh      m0, [r0]
    movh      m3, [r0+r1]
    movhps    m0, [r0+r1*2]
    movhps    m3, [r0+r3]
    DEINTB    1, 0, 4, 3, 7
    lea       r0, [r0+r1*4]
    VAR_CORE
    dec r2d
    jg .loop
    VAR_END 8, 8

cglobal pixel_var_8x16, 2,4,8
    VAR_START 1
    mov      r2d, 4
    lea       r3, [r1*3]
.loop:
    movh      m0, [r0]
    movh      m3, [r0+r1]
    movhps    m0, [r0+r1*2]
    movhps    m3, [r0+r3]
    DEINTB    1, 0, 4, 3, 7
    lea       r0, [r0+r1*4]
    VAR_CORE
    dec r2d
    jg .loop
    VAR_END 8, 16
%endmacro ; VAR

INIT_XMM sse2
VAR
INIT_XMM avx
VAR
INIT_XMM xop
VAR

INIT_YMM avx2
cglobal pixel_var_16x16, 2,4,7
    VAR_START 0
    mov      r2d, 4
    lea       r3, [r1*3]
.loop:
    pmovzxbw  m0, [r0]
    pmovzxbw  m3, [r0+r1]
    pmovzxbw  m1, [r0+r1*2]
    pmovzxbw  m4, [r0+r3]
    lea       r0, [r0+r1*4]
    VAR_CORE
    dec r2d
    jg .loop
    vextracti128 xm0, m5, 1
    vextracti128 xm1, m6, 1
    paddw  xm5, xm0
    paddd  xm6, xm1
    HADDW  xm5, xm2
    HADDD  xm6, xm1
%if ARCH_X86_64
    punpckldq xm5, xm6
    movq   rax, xm5
%else
    movd   eax, xm5
    movd   edx, xm6
%endif
    RET
%endif ; !HIGH_BIT_DEPTH

%macro VAR_AVX512_CORE 1 ; accum
%if %1
    paddw    m0, m2
    pmaddwd  m2, m2
    paddw    m0, m3
    pmaddwd  m3, m3
    paddd    m1, m2
    paddd    m1, m3
%else
    paddw    m0, m2, m3
    pmaddwd  m2, m2
    pmaddwd  m3, m3
    paddd    m1, m2, m3
%endif
%endmacro

%macro VAR_AVX512_CORE_16x16 1 ; accum
%if HIGH_BIT_DEPTH
    mova            ym2, [r0]
    vinserti64x4     m2, [r0+r1], 1
    mova            ym3, [r0+2*r1]
    vinserti64x4     m3, [r0+r3], 1
%else
    vbroadcasti64x2 ym2, [r0]
    vbroadcasti64x2  m2 {k1}, [r0+r1]
    vbroadcasti64x2 ym3, [r0+2*r1]
    vbroadcasti64x2  m3 {k1}, [r0+r3]
    pshufb           m2, m4
    pshufb           m3, m4
%endif
    VAR_AVX512_CORE %1
%endmacro

%macro VAR_AVX512_CORE_8x8 1 ; accum
%if HIGH_BIT_DEPTH
    mova            xm2, [r0]
    mova            xm3, [r0+r1]
%else
    movq            xm2, [r0]
    movq            xm3, [r0+r1]
%endif
    vinserti128     ym2, [r0+2*r1], 1
    vinserti128     ym3, [r0+r2], 1
    lea              r0, [r0+4*r1]
    vinserti32x4     m2, [r0], 2
    vinserti32x4     m3, [r0+r1], 2
    vinserti32x4     m2, [r0+2*r1], 3
    vinserti32x4     m3, [r0+r2], 3
%if HIGH_BIT_DEPTH == 0
    punpcklbw        m2, m4
    punpcklbw        m3, m4
%endif
    VAR_AVX512_CORE %1
%endmacro

INIT_ZMM avx512
cglobal pixel_var_16x16, 2,4
    FIX_STRIDES     r1
    mov            r2d, 0xf0
    lea             r3, [3*r1]
%if HIGH_BIT_DEPTH == 0
    vbroadcasti64x4 m4, [var_shuf_avx512]
    kmovb           k1, r2d
%endif
    VAR_AVX512_CORE_16x16 0
.loop:
    lea             r0, [r0+4*r1]
    VAR_AVX512_CORE_16x16 1
    sub            r2d, 0x50
    jg .loop
%if ARCH_X86_64 == 0
    pop            r3d
    %assign regs_used 3
%endif
var_avx512_end:
    vbroadcasti32x4 m2, [pw_1]
    pmaddwd         m0, m2
    SBUTTERFLY      dq, 0, 1, 2
    paddd           m0, m1
    vextracti32x8  ym1, m0, 1
    paddd          ym0, ym1
    vextracti128   xm1, ym0, 1
    paddd         xmm0, xm0, xm1
    punpckhqdq    xmm1, xmm0, xmm0
    paddd         xmm0, xmm1
%if ARCH_X86_64
    movq           rax, xmm0
%else
    movd           eax, xmm0
    pextrd         edx, xmm0, 1
%endif
    RET

%if HIGH_BIT_DEPTH == 0 ; 8x8 doesn't benefit from AVX-512 in high bit-depth
cglobal pixel_var_8x8, 2,3
    lea             r2, [3*r1]
    pxor           xm4, xm4
    VAR_AVX512_CORE_8x8 0
    jmp var_avx512_end
%endif

cglobal pixel_var_8x16, 2,3
    FIX_STRIDES     r1
    lea             r2, [3*r1]
%if HIGH_BIT_DEPTH == 0
    pxor           xm4, xm4
%endif
    VAR_AVX512_CORE_8x8 0
    lea             r0, [r0+4*r1]
    VAR_AVX512_CORE_8x8 1
    jmp var_avx512_end

;-----------------------------------------------------------------------------
; uint64_t pixel_var_wxh( pixel *, intptr_t ), avx512icl: VNNI
;-----------------------------------------------------------------------------
%if ARCH_X86_64
%if HIGH_BIT_DEPTH
; vpdpwssd squares, two accumulators m6 m2; word sums m5
%macro VAR_ICL_CORE 0
    paddw       m5, m0
    paddw       m5, m3
    paddw       m5, m1
    paddw       m5, m4
    vpdpwssd    m6, m0, m0
    vpdpwssd    m2, m3, m3
    vpdpwssd    m6, m1, m1
    vpdpwssd    m2, m4, m4
%endmacro

%macro VAR_ICL_START 0
    FIX_STRIDES r1
    lea         r3, [r1*3]
    pxor        m5, m5
    pxor        m6, m6
    pxor        m2, m2
%endmacro

INIT_YMM avx512icl
cglobal pixel_var_16x16, 2,4,7
    VAR_ICL_START
%rep 4
    VAR_LOAD4_YMM r0, r0+16
    lea         r0, [r0+r1*4]
    VAR_ICL_CORE
%endrep
    paddd       m6, m2
    VAR_END_YMM

cglobal pixel_var_8x16, 2,4,7
    VAR_ICL_START
    lea         r2, [r0+r1*4]
    VAR_LOAD4_YMM r0, r2
    lea         r0, [r0+r1*8]
    lea         r2, [r2+r1*8]
    VAR_ICL_CORE
    VAR_LOAD4_YMM r0, r2
    VAR_ICL_CORE
    paddd       m6, m2
    VAR_END_YMM

cglobal pixel_var_8x8, 2,4,7
    VAR_ICL_START
    lea         r2, [r0+r1*4]
    VAR_LOAD4_YMM r0, r2
    VAR_ICL_CORE
    paddd       m6, m2
    VAR_END_YMM

; zmm, two rows a register: assembled, not dispatched (for full width zmm)
INIT_ZMM avx512icl
cglobal pixel_var_16x16_zmm, 2,4,7
    VAR_ICL_START
%rep 2
    movu       ym0, [r0]
    vinserti64x4 m0, m0, [r0+r1], 1
    movu       ym3, [r0+r1*2]
    vinserti64x4 m3, m3, [r0+r3], 1
    lea         r0, [r0+r1*4]
    movu       ym1, [r0]
    vinserti64x4 m1, m1, [r0+r1], 1
    movu       ym4, [r0+r1*2]
    vinserti64x4 m4, m4, [r0+r3], 1
    lea         r0, [r0+r1*4]
    VAR_ICL_CORE
%endrep
    paddd       m6, m2
    vextracti32x8 ym0, m5, 1
    paddw      ym5, ym0
    vextracti32x8 ym0, m6, 1
    paddd      ym6, ym0
    vpbroadcastd ym0, [pw_1]
    pmaddwd    ym5, ym0
    vextracti128 xm0, ym5, 1
    paddd      xm5, xm0
    vextracti128 xm0, ym6, 1
    paddd      xm6, xm0
    punpckldq  xm0, xm5, xm6
    punpckhdq  xm5, xm6
    paddd      xm5, xm0
    punpckhqdq xm0, xm5, xm5
    paddd      xm5, xm0
    movq       rax, xm5
    RET
%else ; !HIGH_BIT_DEPTH
; vpdpbusd: x * 1 and x * (x ^ 0x80) = x*x - 128*x; m6 = 1, m7 = 0x80 bytes
; sums m0 m1, squares - 128 * sums m2 m3
%macro VAR_ICL_ACC 4 ; pixels, tmp, sum, square
    pxor        m%2, m%1, m7
    vpdpbusd    m%3, m%1, m6
    vpdpbusd    m%4, m%1, m%2
%endmacro

%macro VAR_ICL_START 0
    vpbroadcastd m6, [pb_1]
    mov        r2d, 0x80808080
    vpbroadcastd m7, r2d
    lea         r3, [r1*3]
    pxor        m0, m0
    pxor        m1, m1
    pxor        m2, m2
    pxor        m3, m3
%endmacro

%macro VAR_ICL_END 0
    paddd       m0, m1
    paddd       m2, m3
    pslld       m1, m0, 7
    paddd       m2, m1
    punpckldq   m1, m0, m2
    punpckhdq   m0, m2
    paddd       m0, m1
%if mmsize == 64
    vextracti32x8 ym1, m0, 1
    paddd      ym0, ym1
%endif
    vextracti128 xm1, ym0, 1
    paddd      xm0, xm1
    punpckhqdq xm1, xm0, xm0
    paddd      xm0, xm1
    movq       rax, xm0
    RET
%endmacro

; four rows of 8 a ymm
%macro VAR_ICL_W8 2 ; sum, square
    movq       xm4, [r0]
    movhps     xm4, [r0+r1]
    movq       xm5, [r0+r1*2]
    movhps     xm5, [r0+r3]
    vinserti128 m4, m4, xm5, 1
    VAR_ICL_ACC 4, 5, %1, %2
%endmacro

INIT_YMM avx512icl
cglobal pixel_var_16x16, 2,4,10
    VAR_ICL_START
%rep 4
    movu       xm4, [r0]
    vinserti128 m4, m4, [r0+r1], 1
    movu       xm5, [r0+r1*2]
    vinserti128 m5, m5, [r0+r3], 1
    lea         r0, [r0+r1*4]
    VAR_ICL_ACC 4, 8, 0, 2
    VAR_ICL_ACC 5, 9, 1, 3
%endrep
    VAR_ICL_END

cglobal pixel_var_8x16, 2,4,8
    VAR_ICL_START
%rep 2
    VAR_ICL_W8 0, 2
    lea         r0, [r0+r1*4]
    VAR_ICL_W8 1, 3
    lea         r0, [r0+r1*4]
%endrep
    VAR_ICL_END

cglobal pixel_var_8x8, 2,4,8
    VAR_ICL_START
    VAR_ICL_W8 0, 2
    lea         r0, [r0+r1*4]
    VAR_ICL_W8 1, 3
    VAR_ICL_END

; zmm, four rows a register: assembled, not dispatched (for full width zmm)
INIT_ZMM avx512icl
cglobal pixel_var_16x16_zmm, 2,4,10
    VAR_ICL_START
%rep 2
    movu       xm4, [r0]
    vinserti32x4 m4, m4, [r0+r1], 1
    vinserti32x4 m4, m4, [r0+r1*2], 2
    vinserti32x4 m4, m4, [r0+r3], 3
    lea         r0, [r0+r1*4]
    movu       xm5, [r0]
    vinserti32x4 m5, m5, [r0+r1], 1
    vinserti32x4 m5, m5, [r0+r1*2], 2
    vinserti32x4 m5, m5, [r0+r3], 3
    lea         r0, [r0+r1*4]
    VAR_ICL_ACC 4, 8, 0, 2
    VAR_ICL_ACC 5, 9, 1, 3
%endrep
    VAR_ICL_END
%endif ; HIGH_BIT_DEPTH
%endif ; ARCH_X86_64

%macro VAR2_END 3
    HADDW   %2, xm1
    movd   r1d, %2
%if HIGH_BIT_DEPTH && ARCH_X86_64 ; 8x16: |sum| up to 128*1023, sum*sum above 2^32
    movsxd  r1, r1d
    imul    r1, r1
    HADDD   %3, xm1
    shr     r1, %1
%else
    imul   r1d, r1d
    HADDD   %3, xm1
    shr    r1d, %1
%endif
    movd   eax, %3
    movd  [r4], %3
    sub    eax, r1d  ; sqr - (sum * sum >> shift)
    RET
%endmacro

;-----------------------------------------------------------------------------
; int pixel_var2_8x8( pixel *, intptr_t, pixel *, intptr_t, int * )
;-----------------------------------------------------------------------------
%macro VAR2_8x8_MMX 2
cglobal pixel_var2_8x%1, 5,6
    FIX_STRIDES r1, r3
    VAR_START 0
    mov      r5d, %1
.loop:
%if HIGH_BIT_DEPTH
    mova      m0, [r0]
    mova      m1, [r0+mmsize]
    psubw     m0, [r2]
    psubw     m1, [r2+mmsize]
%else ; !HIGH_BIT_DEPTH
    movq      m0, [r0]
    movq      m1, m0
    movq      m2, [r2]
    movq      m3, m2
    punpcklbw m0, m7
    punpckhbw m1, m7
    punpcklbw m2, m7
    punpckhbw m3, m7
    psubw     m0, m2
    psubw     m1, m3
%endif ; HIGH_BIT_DEPTH
    paddw     m5, m0
    paddw     m5, m1
    pmaddwd   m0, m0
    pmaddwd   m1, m1
    paddd     m6, m0
    paddd     m6, m1
    add       r0, r1
    add       r2, r3
    dec       r5d
    jg .loop
    VAR2_END %2, m5, m6
%endmacro

%if ARCH_X86_64 == 0
INIT_MMX mmx2
VAR2_8x8_MMX  8, 6
VAR2_8x8_MMX 16, 7
%endif

%macro VAR2_8x8_SSE2 2
cglobal pixel_var2_8x%1, 5,6,8
    VAR_START 1
    mov      r5d, %1/2
.loop:
%if HIGH_BIT_DEPTH
    mova      m0, [r0]
    mova      m1, [r0+r1*2]
    mova      m2, [r2]
    mova      m3, [r2+r3*2]
%else ; !HIGH_BIT_DEPTH
    movq      m1, [r0]
    movhps    m1, [r0+r1]
    movq      m3, [r2]
    movhps    m3, [r2+r3]
    DEINTB    0, 1, 2, 3, 7
%endif ; HIGH_BIT_DEPTH
    psubw     m0, m2
    psubw     m1, m3
    paddw     m5, m0
    paddw     m5, m1
    pmaddwd   m0, m0
    pmaddwd   m1, m1
    paddd     m6, m0
    paddd     m6, m1
    lea       r0, [r0+r1*2*SIZEOF_PIXEL]
    lea       r2, [r2+r3*2*SIZEOF_PIXEL]
    dec      r5d
    jg .loop
    VAR2_END %2, m5, m6
%endmacro

INIT_XMM sse2
VAR2_8x8_SSE2  8, 6
VAR2_8x8_SSE2 16, 7

%if HIGH_BIT_DEPTH
; AVX2: four rows a pass, two a ymm; lane sums fold to xmm for VAR2_END
%macro VAR2_8x8_AVX2_HBD 2
cglobal pixel_var2_8x%1, 5,6,7
    FIX_STRIDES r1, r3
    VAR_START 0
    mov      r5d, %1/4
.loop:
    mova     xm0, [r0]
    vinserti128 m0, m0, [r0+r1], 1
    mova     xm2, [r2]
    vinserti128 m2, m2, [r2+r3], 1
    lea       r0, [r0+r1*2]
    lea       r2, [r2+r3*2]
    mova     xm1, [r0]
    vinserti128 m1, m1, [r0+r1], 1
    mova     xm3, [r2]
    vinserti128 m3, m3, [r2+r3], 1
    lea       r0, [r0+r1*2]
    lea       r2, [r2+r3*2]
    psubw     m0, m2
    psubw     m1, m3
    paddw     m5, m0
    paddw     m5, m1
    pmaddwd   m0, m0
    pmaddwd   m1, m1
    paddd     m6, m0
    paddd     m6, m1
    dec      r5d
    jg .loop
    vextracti128 xm0, m5, 1
    paddw    xm5, xm0
    vextracti128 xm0, m6, 1
    paddd    xm6, xm0
    VAR2_END %2, xm5, xm6
%endmacro

INIT_YMM avx2
VAR2_8x8_AVX2_HBD  8, 6
VAR2_8x8_AVX2_HBD 16, 7

; avx512icl: vpdpwssd squares, two accumulators m6 m2
%macro VAR2_8x8_ICL_HBD 2
cglobal pixel_var2_8x%1, 5,6,7
    FIX_STRIDES r1, r3
    pxor      m5, m5
    pxor      m6, m6
    pxor      m2, m2
    mov      r5d, %1/4
.loop:
    mova     xm0, [r0]
    vinserti128 m0, m0, [r0+r1], 1
    mova     xm3, [r2]
    vinserti128 m3, m3, [r2+r3], 1
    lea       r0, [r0+r1*2]
    lea       r2, [r2+r3*2]
    mova     xm1, [r0]
    vinserti128 m1, m1, [r0+r1], 1
    mova     xm4, [r2]
    vinserti128 m4, m4, [r2+r3], 1
    lea       r0, [r0+r1*2]
    lea       r2, [r2+r3*2]
    psubw     m0, m3
    psubw     m1, m4
    paddw     m5, m0
    paddw     m5, m1
    vpdpwssd  m6, m0, m0
    vpdpwssd  m2, m1, m1
    dec      r5d
    jg .loop
    paddd     m6, m2
    vextracti128 xm0, m5, 1
    paddw    xm5, xm0
    vextracti128 xm0, m6, 1
    paddd    xm6, xm0
    VAR2_END %2, xm5, xm6
%endmacro

%if ARCH_X86_64
INIT_YMM avx512icl
VAR2_8x8_ICL_HBD  8, 6
VAR2_8x8_ICL_HBD 16, 7
%endif
%endif

%if HIGH_BIT_DEPTH == 0
%macro VAR2_8x8_SSSE3 2
cglobal pixel_var2_8x%1, 5,6,8
    pxor      m5, m5    ; sum
    pxor      m6, m6    ; sum squared
    mova      m7, [hsub_mul]
    mov      r5d, %1/4
.loop:
    movq      m0, [r0]
    movq      m2, [r2]
    movq      m1, [r0+r1]
    movq      m3, [r2+r3]
    lea       r0, [r0+r1*2]
    lea       r2, [r2+r3*2]
    punpcklbw m0, m2
    punpcklbw m1, m3
    movq      m2, [r0]
    movq      m3, [r2]
    punpcklbw m2, m3
    movq      m3, [r0+r1]
    movq      m4, [r2+r3]
    punpcklbw m3, m4
    pmaddubsw m0, m7
    pmaddubsw m1, m7
    pmaddubsw m2, m7
    pmaddubsw m3, m7
    paddw     m5, m0
    paddw     m5, m1
    paddw     m5, m2
    paddw     m5, m3
    pmaddwd   m0, m0
    pmaddwd   m1, m1
    pmaddwd   m2, m2
    pmaddwd   m3, m3
    paddd     m6, m0
    paddd     m6, m1
    paddd     m6, m2
    paddd     m6, m3
    lea       r0, [r0+r1*2]
    lea       r2, [r2+r3*2]
    dec      r5d
    jg .loop
    VAR2_END %2, m5, m6
%endmacro

INIT_XMM ssse3
VAR2_8x8_SSSE3  8, 6
VAR2_8x8_SSSE3 16, 7
INIT_XMM xop
VAR2_8x8_SSSE3  8, 6
VAR2_8x8_SSSE3 16, 7

%macro VAR2_8x8_AVX2 2
cglobal pixel_var2_8x%1, 5,6,6
    pxor      m3, m3    ; sum
    pxor      m4, m4    ; sum squared
    mova      m5, [hsub_mul]
    mov      r5d, %1/4
.loop:
    movq     xm0, [r0]
    movq     xm1, [r2]
    vinserti128 m0, m0, [r0+r1], 1
    vinserti128 m1, m1, [r2+r3], 1
    lea       r0, [r0+r1*2]
    lea       r2, [r2+r3*2]
    punpcklbw m0, m1
    movq     xm1, [r0]
    movq     xm2, [r2]
    vinserti128 m1, m1, [r0+r1], 1
    vinserti128 m2, m2, [r2+r3], 1
    lea       r0, [r0+r1*2]
    lea       r2, [r2+r3*2]
    punpcklbw m1, m2
    pmaddubsw m0, m5
    pmaddubsw m1, m5
    paddw     m3, m0
    paddw     m3, m1
    pmaddwd   m0, m0
    pmaddwd   m1, m1
    paddd     m4, m0
    paddd     m4, m1
    dec      r5d
    jg .loop
    vextracti128 xm0, m3, 1
    vextracti128 xm1, m4, 1
    paddw    xm3, xm0
    paddd    xm4, xm1
    VAR2_END %2, xm3, xm4
%endmacro

INIT_YMM avx2
VAR2_8x8_AVX2  8, 6
VAR2_8x8_AVX2 16, 7

; avx512icl: vpdpwssd squares, two accumulators m4 m6
%macro VAR2_8x8_ICL 2
cglobal pixel_var2_8x%1, 5,6,7
    pxor      m3, m3
    pxor      m4, m4
    pxor      m6, m6
    mova      m5, [hsub_mul]
    mov      r5d, %1/4
.loop:
    movq     xm0, [r0]
    movq     xm1, [r2]
    vinserti128 m0, m0, [r0+r1], 1
    vinserti128 m1, m1, [r2+r3], 1
    lea       r0, [r0+r1*2]
    lea       r2, [r2+r3*2]
    punpcklbw m0, m1
    movq     xm1, [r0]
    movq     xm2, [r2]
    vinserti128 m1, m1, [r0+r1], 1
    vinserti128 m2, m2, [r2+r3], 1
    lea       r0, [r0+r1*2]
    lea       r2, [r2+r3*2]
    punpcklbw m1, m2
    pmaddubsw m0, m5
    pmaddubsw m1, m5
    paddw     m3, m0
    paddw     m3, m1
    vpdpwssd  m4, m0, m0
    vpdpwssd  m6, m1, m1
    dec      r5d
    jg .loop
    paddd     m4, m6
    vextracti128 xm0, m3, 1
    vextracti128 xm1, m4, 1
    paddw    xm3, xm0
    paddd    xm4, xm1
    VAR2_END %2, xm3, xm4
%endmacro

%if ARCH_X86_64
INIT_YMM avx512icl
VAR2_8x8_ICL  8, 6
VAR2_8x8_ICL 16, 7
%endif

%endif ; !HIGH_BIT_DEPTH

;=============================================================================
; SATD
;=============================================================================

; avx512icl functions between ICL_LOW_BEGIN and ICL_LOW_END keep m0-m15 on
; ymm0-15 (x86inc's avx512 permutation undone): only the opmask/VBMI2/VNNI
; instructions need EVEX, the rest keep their shorter VEX encodings and the
; VEX-only ones (phaddw, phminposuw, ...) still assemble. vzeroupper on return
; and WIN64 xmm6-15 saves as for avx2. VNNI needs {evex}: on ymm0-15 nasm
; picks the VEX AVX-VNNI encoding, which avx512icl does not imply.
%macro ICL_LOW_RESET 0
    INIT_YMM avx512icl
    AVX512_MM_PERMUTATION
    %define RESET_MM_PERMUTATION ICL_LOW_RESET
%endmacro

%macro ICL_LOW_BEGIN 0
    %define vzeroupper_required (mmsize > 16)
    %define high_mm_regs 0
    ICL_LOW_RESET
%endmacro

%macro ICL_LOW_END 0
    %define vzeroupper_required (mmsize > 16 && (ARCH_X86_64 == 0 || xmm_regs_used > 16 || notcpuflag(avx512)))
    %define high_mm_regs (16*cpuflag(avx512))
    INIT_YMM avx512icl
%endmacro

%macro JDUP 2
%if cpuflag(sse4)
    ; just use shufps on anything post conroe
    shufps %1, %2, 0
%elif cpuflag(ssse3) && notcpuflag(atom)
    ; join 2x 32 bit and duplicate them
    ; emulating shufps is faster on conroe
    punpcklqdq %1, %2
    movsldup %1, %1
%else
    ; doesn't need to dup. sse2 does things by zero extending to words and full h_2d
    punpckldq %1, %2
%endif
%endmacro

%macro HSUMSUB 5
    pmaddubsw m%2, m%5
    pmaddubsw m%1, m%5
    pmaddubsw m%4, m%5
    pmaddubsw m%3, m%5
%endmacro

%macro DIFF_UNPACK_SSE2 5
    punpcklbw m%1, m%5
    punpcklbw m%2, m%5
    punpcklbw m%3, m%5
    punpcklbw m%4, m%5
    psubw m%1, m%2
    psubw m%3, m%4
%endmacro

%macro DIFF_SUMSUB_SSSE3 5
    HSUMSUB %1, %2, %3, %4, %5
    psubw m%1, m%2
    psubw m%3, m%4
%endmacro

%macro LOAD_DUP_2x4P 4 ; dst, tmp, 2* pointer
    movd %1, %3
    movd %2, %4
    JDUP %1, %2
%endmacro

%macro LOAD_DUP_4x8P_CONROE 8 ; 4*dst, 4*pointer
    movddup m%3, %6
    movddup m%4, %8
    movddup m%1, %5
    movddup m%2, %7
%endmacro

%macro LOAD_DUP_4x8P_PENRYN 8
    ; penryn and nehalem run punpcklqdq and movddup in different units
    movh m%3, %6
    movh m%4, %8
    punpcklqdq m%3, m%3
    movddup m%1, %5
    punpcklqdq m%4, m%4
    movddup m%2, %7
%endmacro

%macro LOAD_SUMSUB_8x2P 9
    LOAD_DUP_4x8P %1, %2, %3, %4, %6, %7, %8, %9
    DIFF_SUMSUB_SSSE3 %1, %3, %2, %4, %5
%endmacro

%macro LOAD_SUMSUB_8x4P_SSSE3 7-11 r0, r2, 0, 0
; 4x dest, 2x tmp, 1x mul, [2* ptr], [increment?]
    LOAD_SUMSUB_8x2P %1, %2, %5, %6, %7, [%8], [%9], [%8+r1], [%9+r3]
    LOAD_SUMSUB_8x2P %3, %4, %5, %6, %7, [%8+2*r1], [%9+2*r3], [%8+r4], [%9+r5]
%if %10
    lea %8, [%8+4*r1]
    lea %9, [%9+4*r3]
%endif
%endmacro

%macro LOAD_SUMSUB_16P_SSSE3 7 ; 2*dst, 2*tmp, mul, 2*ptr
    movddup m%1, [%7]
    movddup m%2, [%7+8]
    mova m%4, [%6]
    movddup m%3, m%4
    punpckhqdq m%4, m%4
    DIFF_SUMSUB_SSSE3 %1, %3, %2, %4, %5
%endmacro

%macro LOAD_SUMSUB_16P_SSE2 7 ; 2*dst, 2*tmp, mask, 2*ptr
    movu  m%4, [%7]
    mova  m%2, [%6]
    DEINTB %1, %2, %3, %4, %5
    psubw m%1, m%3
    psubw m%2, m%4
    SUMSUB_BA w, %1, %2, %3
%endmacro

%macro LOAD_SUMSUB_16x4P 10-13 r0, r2, none
; 8x dest, 1x tmp, 1x mul, [2* ptr] [2nd tmp]
    LOAD_SUMSUB_16P %1, %5, %2, %3, %10, %11, %12
    LOAD_SUMSUB_16P %2, %6, %3, %4, %10, %11+r1, %12+r3
    LOAD_SUMSUB_16P %3, %7, %4, %9, %10, %11+2*r1, %12+2*r3
    LOAD_SUMSUB_16P %4, %8, %13, %9, %10, %11+r4, %12+r5
%endmacro

%macro LOAD_SUMSUB_16x2P_AVX2 9
; 2*dst, 2*tmp, mul, 4*ptr
    vbroadcasti128 m%1, [%6]
    vbroadcasti128 m%3, [%7]
    vbroadcasti128 m%2, [%8]
    vbroadcasti128 m%4, [%9]
    DIFF_SUMSUB_SSSE3 %1, %3, %2, %4, %5
%endmacro

%macro LOAD_SUMSUB_16x4P_AVX2 7-11 r0, r2, 0, 0
; 4x dest, 2x tmp, 1x mul, [2* ptr], [increment?]
    LOAD_SUMSUB_16x2P_AVX2 %1, %2, %5, %6, %7, %8, %9, %8+r1, %9+r3
    LOAD_SUMSUB_16x2P_AVX2 %3, %4, %5, %6, %7, %8+2*r1, %9+2*r3, %8+r4, %9+r5
%if %10
    lea  %8, [%8+4*r1]
    lea  %9, [%9+4*r3]
%endif
%endmacro

%macro LOAD_DUP_4x16P_AVX2 8 ; 4*dst, 4*pointer
    mova  xm%3, %6
    mova  xm%4, %8
    mova  xm%1, %5
    mova  xm%2, %7
    vpermq m%3, m%3, q0011
    vpermq m%4, m%4, q0011
    vpermq m%1, m%1, q0011
    vpermq m%2, m%2, q0011
%endmacro

%macro LOAD_SUMSUB8_16x2P_AVX2 9
; 2*dst, 2*tmp, mul, 4*ptr
    LOAD_DUP_4x16P_AVX2 %1, %2, %3, %4, %6, %7, %8, %9
    DIFF_SUMSUB_SSSE3 %1, %3, %2, %4, %5
%endmacro

%macro LOAD_SUMSUB8_16x4P_AVX2 7-11 r0, r2, 0, 0
; 4x dest, 2x tmp, 1x mul, [2* ptr], [increment?]
    LOAD_SUMSUB8_16x2P_AVX2 %1, %2, %5, %6, %7, [%8], [%9], [%8+r1], [%9+r3]
    LOAD_SUMSUB8_16x2P_AVX2 %3, %4, %5, %6, %7, [%8+2*r1], [%9+2*r3], [%8+r4], [%9+r5]
%if %10
    lea  %8, [%8+4*r1]
    lea  %9, [%9+4*r3]
%endif
%endmacro

; in: r4=3*stride1, r5=3*stride2
; in: %2 = horizontal offset
; in: %3 = whether we need to increment pix1 and pix2
; clobber: m3..m7
; out: %1 = satd
%macro SATD_4x4_MMX 3
    %xdefine %%n nn%1
    %assign offset %2*SIZEOF_PIXEL
    LOAD_DIFF m4, m3, none, [r0+     offset], [r2+     offset]
    LOAD_DIFF m5, m3, none, [r0+  r1+offset], [r2+  r3+offset]
    LOAD_DIFF m6, m3, none, [r0+2*r1+offset], [r2+2*r3+offset]
    LOAD_DIFF m7, m3, none, [r0+  r4+offset], [r2+  r5+offset]
%if %3
    lea  r0, [r0+4*r1]
    lea  r2, [r2+4*r3]
%endif
    HADAMARD4_2D 4, 5, 6, 7, 3, %%n
    paddw m4, m6
    SWAP %%n, 4
%endmacro

; in: %1 = horizontal if 0, vertical if 1
%macro SATD_8x4_SSE 8-9
%if %1
    HADAMARD4_2D_SSE %2, %3, %4, %5, %6, amax
%else
    HADAMARD4_V %2, %3, %4, %5, %6
    ; doing the abs first is a slight advantage
    ABSW2 m%2, m%4, m%2, m%4, m%6, m%7
    ABSW2 m%3, m%5, m%3, m%5, m%6, m%7
    HADAMARD 1, max, %2, %4, %6, %7
%endif
%ifnidn %9, swap
    paddw m%8, m%2
%else
    SWAP %8, %2
%endif
%if %1
    paddw m%8, m%4
%else
    HADAMARD 1, max, %3, %5, %6, %7
    paddw m%8, m%3
%endif
%endmacro

%macro SATD_START_MMX 0
    FIX_STRIDES r1, r3
    lea  r4, [3*r1] ; 3*stride1
    lea  r5, [3*r3] ; 3*stride2
%endmacro

%macro SATD_END_MMX 0
%if HIGH_BIT_DEPTH
    HADDUW      m0, m1
    movd       eax, m0
%else ; !HIGH_BIT_DEPTH
    pshufw      m1, m0, q1032
    paddw       m0, m1
    pshufw      m1, m0, q2301
    paddw       m0, m1
    movd       eax, m0
    and        eax, 0xffff
%endif ; HIGH_BIT_DEPTH
    RET
%endmacro

; FIXME avoid the spilling of regs to hold 3*stride.
; for small blocks on x86_32, modify pixel pointer instead.

;-----------------------------------------------------------------------------
; int pixel_satd_16x16( uint8_t *, intptr_t, uint8_t *, intptr_t )
;-----------------------------------------------------------------------------
INIT_MMX mmx2
cglobal pixel_satd_16x4_internal
    SATD_4x4_MMX m2,  0, 0
    SATD_4x4_MMX m1,  4, 0
    paddw        m0, m2
    SATD_4x4_MMX m2,  8, 0
    paddw        m0, m1
    SATD_4x4_MMX m1, 12, 0
    paddw        m0, m2
    paddw        m0, m1
    ret

cglobal pixel_satd_8x8_internal
    SATD_4x4_MMX m2,  0, 0
    SATD_4x4_MMX m1,  4, 1
    paddw        m0, m2
    paddw        m0, m1
pixel_satd_8x4_internal_mmx2:
    SATD_4x4_MMX m2,  0, 0
    SATD_4x4_MMX m1,  4, 0
    paddw        m0, m2
    paddw        m0, m1
    ret

%if HIGH_BIT_DEPTH
%macro SATD_MxN_MMX 3
cglobal pixel_satd_%1x%2, 4,7
    SATD_START_MMX
    pxor   m0, m0
    call pixel_satd_%1x%3_internal_mmx2
    HADDUW m0, m1
    movd  r6d, m0
%rep %2/%3-1
    pxor   m0, m0
    lea    r0, [r0+4*r1]
    lea    r2, [r2+4*r3]
    call pixel_satd_%1x%3_internal_mmx2
    movd   m2, r4
    HADDUW m0, m1
    movd   r4, m0
    add    r6, r4
    movd   r4, m2
%endrep
    movifnidn eax, r6d
    RET
%endmacro

SATD_MxN_MMX 16, 16, 4
SATD_MxN_MMX 16,  8, 4
SATD_MxN_MMX  8, 16, 8
%endif ; HIGH_BIT_DEPTH

%if HIGH_BIT_DEPTH == 0
cglobal pixel_satd_16x16, 4,6
    SATD_START_MMX
    pxor   m0, m0
%rep 3
    call pixel_satd_16x4_internal_mmx2
    lea  r0, [r0+4*r1]
    lea  r2, [r2+4*r3]
%endrep
    call pixel_satd_16x4_internal_mmx2
    HADDUW m0, m1
    movd  eax, m0
    RET

cglobal pixel_satd_16x8, 4,6
    SATD_START_MMX
    pxor   m0, m0
    call pixel_satd_16x4_internal_mmx2
    lea  r0, [r0+4*r1]
    lea  r2, [r2+4*r3]
    call pixel_satd_16x4_internal_mmx2
    SATD_END_MMX

cglobal pixel_satd_8x16, 4,6
    SATD_START_MMX
    pxor   m0, m0
    call pixel_satd_8x8_internal_mmx2
    lea  r0, [r0+4*r1]
    lea  r2, [r2+4*r3]
    call pixel_satd_8x8_internal_mmx2
    SATD_END_MMX
%endif ; !HIGH_BIT_DEPTH

cglobal pixel_satd_8x8, 4,6
    SATD_START_MMX
    pxor   m0, m0
    call pixel_satd_8x8_internal_mmx2
    SATD_END_MMX

cglobal pixel_satd_8x4, 4,6
    SATD_START_MMX
    pxor   m0, m0
    call pixel_satd_8x4_internal_mmx2
    SATD_END_MMX

cglobal pixel_satd_4x16, 4,6
    SATD_START_MMX
    SATD_4x4_MMX m0, 0, 1
    SATD_4x4_MMX m1, 0, 1
    paddw  m0, m1
    SATD_4x4_MMX m1, 0, 1
    paddw  m0, m1
    SATD_4x4_MMX m1, 0, 0
    paddw  m0, m1
    SATD_END_MMX

cglobal pixel_satd_4x8, 4,6
    SATD_START_MMX
    SATD_4x4_MMX m0, 0, 1
    SATD_4x4_MMX m1, 0, 0
    paddw  m0, m1
    SATD_END_MMX

cglobal pixel_satd_4x4, 4,6
    SATD_START_MMX
    SATD_4x4_MMX m0, 0, 0
    SATD_END_MMX

%macro SATD_START_SSE2 2-3 0
    FIX_STRIDES r1, r3
%if HIGH_BIT_DEPTH && %3
    pxor    %2, %2
%elif cpuflag(ssse3) && notcpuflag(atom)
%if mmsize==32
    mova    %2, [hmul_16p]
%else
    mova    %2, [hmul_8p]
%endif
%endif
    lea     r4, [3*r1]
    lea     r5, [3*r3]
    pxor    %1, %1
%endmacro

%macro SATD_END_SSE2 1-2
%if HIGH_BIT_DEPTH
    HADDUW  %1, xm0
%if %0 == 2
    paddd   %1, %2
%endif
%else
    HADDW   %1, xm7
%endif
    movd   eax, %1
    RET
%endmacro

%macro SATD_ACCUM 3
%if HIGH_BIT_DEPTH
    HADDUW %1, %2
    paddd  %3, %1
    pxor   %1, %1
%endif
%endmacro

%macro BACKUP_POINTERS 0
%if ARCH_X86_64
%if WIN64
    PUSH r7
%endif
    mov     r6, r0
    mov     r7, r2
%endif
%endmacro

%macro RESTORE_AND_INC_POINTERS 0
%if ARCH_X86_64
    lea     r0, [r6+8*SIZEOF_PIXEL]
    lea     r2, [r7+8*SIZEOF_PIXEL]
%if WIN64
    POP r7
%endif
%else
    mov     r0, r0mp
    mov     r2, r2mp
    add     r0, 8*SIZEOF_PIXEL
    add     r2, 8*SIZEOF_PIXEL
%endif
%endmacro

%macro SATD_4x8_SSE 3
%if HIGH_BIT_DEPTH
    movh    m0, [r0+0*r1]
    movh    m4, [r2+0*r3]
    movh    m1, [r0+1*r1]
    movh    m5, [r2+1*r3]
    movhps  m0, [r0+4*r1]
    movhps  m4, [r2+4*r3]
    movh    m2, [r0+2*r1]
    movh    m6, [r2+2*r3]
    psubw   m0, m4
    movh    m3, [r0+r4]
    movh    m4, [r2+r5]
    lea     r0, [r0+4*r1]
    lea     r2, [r2+4*r3]
    movhps  m1, [r0+1*r1]
    movhps  m5, [r2+1*r3]
    movhps  m2, [r0+2*r1]
    movhps  m6, [r2+2*r3]
    psubw   m1, m5
    movhps  m3, [r0+r4]
    movhps  m4, [r2+r5]
    psubw   m2, m6
    psubw   m3, m4
%else ; !HIGH_BIT_DEPTH
    movd m4, [r2]
    movd m5, [r2+r3]
    movd m6, [r2+2*r3]
    add r2, r5
    movd m0, [r0]
    movd m1, [r0+r1]
    movd m2, [r0+2*r1]
    add r0, r4
    movd m3, [r2+r3]
    JDUP m4, m3
    movd m3, [r0+r1]
    JDUP m0, m3
    movd m3, [r2+2*r3]
    JDUP m5, m3
    movd m3, [r0+2*r1]
    JDUP m1, m3
%if %1==0 && %2==1
    mova m3, [hmul_4p]
    DIFFOP 0, 4, 1, 5, 3
%else
    DIFFOP 0, 4, 1, 5, 7
%endif
    movd m5, [r2]
    add r2, r5
    movd m3, [r0]
    add r0, r4
    movd m4, [r2]
    JDUP m6, m4
    movd m4, [r0]
    JDUP m2, m4
    movd m4, [r2+r3]
    JDUP m5, m4
    movd m4, [r0+r1]
    JDUP m3, m4
%if %1==0 && %2==1
    mova m4, [hmul_4p]
    DIFFOP 2, 6, 3, 5, 4
%else
    DIFFOP 2, 6, 3, 5, 7
%endif
%endif ; HIGH_BIT_DEPTH
    SATD_8x4_SSE %1, 0, 1, 2, 3, 4, 5, 7, %3
%endmacro

;-----------------------------------------------------------------------------
; int pixel_satd_8x4( uint8_t *, intptr_t, uint8_t *, intptr_t )
;-----------------------------------------------------------------------------
%macro SATDS_SSE2 0
%define vertical ((notcpuflag(ssse3) || cpuflag(atom)) || HIGH_BIT_DEPTH)

%if cpuflag(ssse3) && (vertical==0 || HIGH_BIT_DEPTH)
cglobal pixel_satd_4x4, 4, 6, 6
    SATD_START_MMX
    mova m4, [hmul_4p]
    LOAD_DUP_2x4P m2, m5, [r2], [r2+r3]
    LOAD_DUP_2x4P m3, m5, [r2+2*r3], [r2+r5]
    LOAD_DUP_2x4P m0, m5, [r0], [r0+r1]
    LOAD_DUP_2x4P m1, m5, [r0+2*r1], [r0+r4]
    DIFF_SUMSUB_SSSE3 0, 2, 1, 3, 4
    HADAMARD 0, sumsub, 0, 1, 2, 3
    HADAMARD 4, sumsub, 0, 1, 2, 3
    HADAMARD 1, amax, 0, 1, 2, 3
    HADDW m0, m1
    movd eax, m0
    RET
%endif

cglobal pixel_satd_4x8, 4, 6, 8
    SATD_START_MMX
%if vertical==0
    mova m7, [hmul_4p]
%endif
    SATD_4x8_SSE vertical, 0, swap
    HADDW m7, m1
    movd eax, m7
    RET

cglobal pixel_satd_4x16, 4, 6, 8
    SATD_START_MMX
%if vertical==0
    mova m7, [hmul_4p]
%endif
    SATD_4x8_SSE vertical, 0, swap
    lea r0, [r0+r1*2*SIZEOF_PIXEL]
    lea r2, [r2+r3*2*SIZEOF_PIXEL]
    SATD_4x8_SSE vertical, 1, add
    HADDW m7, m1
    movd eax, m7
    RET

cglobal pixel_satd_8x8_internal
    LOAD_SUMSUB_8x4P 0, 1, 2, 3, 4, 5, 7, r0, r2, 1, 0
    SATD_8x4_SSE vertical, 0, 1, 2, 3, 4, 5, 6
%%pixel_satd_8x4_internal:
    LOAD_SUMSUB_8x4P 0, 1, 2, 3, 4, 5, 7, r0, r2, 1, 0
    SATD_8x4_SSE vertical, 0, 1, 2, 3, 4, 5, 6
    ret

; 16x8 regresses on phenom win64, 16x16 is almost the same (too many spilled registers)
; These aren't any faster on AVX systems with fast movddup (Bulldozer, Sandy Bridge)
%if HIGH_BIT_DEPTH == 0 && UNIX64 && notcpuflag(avx)
cglobal pixel_satd_16x4_internal
    LOAD_SUMSUB_16x4P 0, 1, 2, 3, 4, 8, 5, 9, 6, 7, r0, r2, 11
    lea  r2, [r2+4*r3]
    lea  r0, [r0+4*r1]
    ; always use horizontal mode here
    SATD_8x4_SSE 0, 0, 1, 2, 3, 6, 11, 10
    SATD_8x4_SSE 0, 4, 8, 5, 9, 6, 3, 10
    ret

cglobal pixel_satd_16x8, 4,6,12
    SATD_START_SSE2 m10, m7
%if vertical
    mova m7, [pw_00ff]
%endif
    jmp %%pixel_satd_16x8_internal

cglobal pixel_satd_16x16, 4,6,12
    SATD_START_SSE2 m10, m7
%if vertical
    mova m7, [pw_00ff]
%endif
    call pixel_satd_16x4_internal
    call pixel_satd_16x4_internal
%%pixel_satd_16x8_internal:
    call pixel_satd_16x4_internal
    call pixel_satd_16x4_internal
    SATD_END_SSE2 m10
%else
cglobal pixel_satd_16x8, 4,6,8
    SATD_START_SSE2 m6, m7
    BACKUP_POINTERS
    call pixel_satd_8x8_internal
    RESTORE_AND_INC_POINTERS
    call pixel_satd_8x8_internal
    SATD_END_SSE2 m6

cglobal pixel_satd_16x16, 4,6,8
    SATD_START_SSE2 m6, m7, 1
    BACKUP_POINTERS
    call pixel_satd_8x8_internal
    call pixel_satd_8x8_internal
    SATD_ACCUM m6, m0, m7
    RESTORE_AND_INC_POINTERS
    call pixel_satd_8x8_internal
    call pixel_satd_8x8_internal
    SATD_END_SSE2 m6, m7
%endif

cglobal pixel_satd_8x16, 4,6,8
    SATD_START_SSE2 m6, m7
    call pixel_satd_8x8_internal
    call pixel_satd_8x8_internal
    SATD_END_SSE2 m6

cglobal pixel_satd_8x8, 4,6,8
    SATD_START_SSE2 m6, m7
    call pixel_satd_8x8_internal
    SATD_END_SSE2 m6

cglobal pixel_satd_8x4, 4,6,8
    SATD_START_SSE2 m6, m7
    call %%pixel_satd_8x4_internal
    SATD_END_SSE2 m6
%endmacro ; SATDS_SSE2

%macro SA8D_INTER 0
%if ARCH_X86_64
    %define lh m10
    %define rh m0
%else
    %define lh m0
    %define rh [esp+48]
%endif
%if HIGH_BIT_DEPTH || ARCH_X86_64
    paddd   lh, rh
%else
    paddusw lh, rh
%endif ; HIGH_BIT_DEPTH
%endmacro

; 8-bit x86_64: an 8x8's words are <= 80*255, four 8x8s overflow 16 bits
%macro SA8D_WIDEN 0
%if HIGH_BIT_DEPTH == 0
    pmaddwd m0, [pw_1]
%endif
%endmacro

; high bit depth: max() words are <= 32*PIXEL_MAX, four of them overflow 16 bits
%macro SA8D_SUM_HBD 4
    pmaddwd m%1, [pw_1]
    pmaddwd m%2, [pw_1]
    pmaddwd m%3, [pw_1]
    pmaddwd m%4, [pw_1]
    paddd   m%1, m%2
    paddd   m%3, m%4
    paddd   m%1, m%3
%endmacro

%macro SA8D 0
; sse2 doesn't seem to like the horizontal way of doing things
%define vertical ((notcpuflag(ssse3) || cpuflag(atom)) || HIGH_BIT_DEPTH)

%if ARCH_X86_64
;-----------------------------------------------------------------------------
; int pixel_sa8d_8x8( uint8_t *, intptr_t, uint8_t *, intptr_t )
;-----------------------------------------------------------------------------
cglobal pixel_sa8d_8x8_internal
    lea  r6, [r0+4*r1]
    lea  r7, [r2+4*r3]
    LOAD_SUMSUB_8x4P 0, 1, 2, 8, 5, 6, 7, r0, r2
    LOAD_SUMSUB_8x4P 4, 5, 3, 9, 11, 6, 7, r6, r7
%if vertical
    HADAMARD8_2D 0, 1, 2, 8, 4, 5, 3, 9, 6, amax
%else ; non-sse2
    HADAMARD8_2D_HMUL 0, 1, 2, 8, 4, 5, 3, 9, 6, 11
%endif
%if HIGH_BIT_DEPTH
    SA8D_SUM_HBD 0, 1, 2, 8
%else
    paddw m0, m1
    paddw m0, m2
    paddw m0, m8
%endif
    SAVE_MM_PERMUTATION
    ret

cglobal pixel_sa8d_8x8, 4,8,12
    FIX_STRIDES r1, r3
    lea  r4, [3*r1]
    lea  r5, [3*r3]
%if vertical == 0
    mova m7, [hmul_8p]
%endif
    call pixel_sa8d_8x8_internal
%if HIGH_BIT_DEPTH
    HADDD  m0, m1
%else
    HADDW m0, m1
%endif ; HIGH_BIT_DEPTH
    movd eax, m0
    add eax, 1
    shr eax, 1
    RET

cglobal pixel_sa8d_16x16, 4,8,12
    FIX_STRIDES r1, r3
    lea  r4, [3*r1]
    lea  r5, [3*r3]
%if vertical == 0
    mova m7, [hmul_8p]
%endif
    call pixel_sa8d_8x8_internal ; pix[0]
    SA8D_WIDEN
    add  r2, 8*SIZEOF_PIXEL
    add  r0, 8*SIZEOF_PIXEL
    mova m10, m0
    call pixel_sa8d_8x8_internal ; pix[8]
    SA8D_WIDEN
    lea  r2, [r2+8*r3]
    lea  r0, [r0+8*r1]
    SA8D_INTER
    call pixel_sa8d_8x8_internal ; pix[8*stride+8]
    SA8D_WIDEN
    sub  r2, 8*SIZEOF_PIXEL
    sub  r0, 8*SIZEOF_PIXEL
    SA8D_INTER
    call pixel_sa8d_8x8_internal ; pix[8*stride]
    SA8D_WIDEN
    SA8D_INTER
    SWAP 0, 10
    HADDD  m0, m1
    movd eax, m0
    add  eax, 1
    shr  eax, 1
    RET

%else ; ARCH_X86_32
%if mmsize == 16
cglobal pixel_sa8d_8x8_internal
    %define spill0 [esp+4]
    %define spill1 [esp+20]
    %define spill2 [esp+36]
%if vertical
    LOAD_DIFF_8x4P 0, 1, 2, 3, 4, 5, 6, r0, r2, 1
    HADAMARD4_2D 0, 1, 2, 3, 4
    movdqa spill0, m3
    LOAD_DIFF_8x4P 4, 5, 6, 7, 3, 3, 2, r0, r2, 1
    HADAMARD4_2D 4, 5, 6, 7, 3
    HADAMARD2_2D 0, 4, 1, 5, 3, qdq, amax
    movdqa m3, spill0
%if HIGH_BIT_DEPTH
    pmaddwd m0, [pw_1]
    pmaddwd m1, [pw_1]
    paddd m0, m1
%else
    paddw m0, m1
%endif
    HADAMARD2_2D 2, 6, 3, 7, 5, qdq, amax
%else ; mmsize == 8
    mova m7, [hmul_8p]
    LOAD_SUMSUB_8x4P 0, 1, 2, 3, 5, 6, 7, r0, r2, 1
    ; could do first HADAMARD4_V here to save spilling later
    ; surprisingly, not a win on conroe or even p4
    mova spill0, m2
    mova spill1, m3
    mova spill2, m1
    SWAP 1, 7
    LOAD_SUMSUB_8x4P 4, 5, 6, 7, 2, 3, 1, r0, r2, 1
    HADAMARD4_V 4, 5, 6, 7, 3
    mova m1, spill2
    mova m2, spill0
    mova m3, spill1
    mova spill0, m6
    mova spill1, m7
    HADAMARD4_V 0, 1, 2, 3, 7
    SUMSUB_BADC w, 0, 4, 1, 5, 7
    HADAMARD 2, sumsub, 0, 4, 7, 6
    HADAMARD 2, sumsub, 1, 5, 7, 6
    HADAMARD 1, amax, 0, 4, 7, 6
    HADAMARD 1, amax, 1, 5, 7, 6
    mova m6, spill0
    mova m7, spill1
    paddw m0, m1
    SUMSUB_BADC w, 2, 6, 3, 7, 4
    HADAMARD 2, sumsub, 2, 6, 4, 5
    HADAMARD 2, sumsub, 3, 7, 4, 5
    HADAMARD 1, amax, 2, 6, 4, 5
    HADAMARD 1, amax, 3, 7, 4, 5
%endif ; sse2/non-sse2
%if HIGH_BIT_DEPTH
    pmaddwd m2, [pw_1]
    pmaddwd m3, [pw_1]
    paddd m0, m2
    paddd m0, m3
%else
    paddw m0, m2
    paddw m0, m3
%endif
    SAVE_MM_PERMUTATION
    ret
%endif ; ifndef mmx2

cglobal pixel_sa8d_8x8, 4,7
    FIX_STRIDES r1, r3
    mov    r6, esp
    and   esp, ~15
    sub   esp, 48
    lea    r4, [3*r1]
    lea    r5, [3*r3]
    call pixel_sa8d_8x8_internal
%if HIGH_BIT_DEPTH
    HADDD  m0, m1
%else
    HADDW  m0, m1
%endif ; HIGH_BIT_DEPTH
    movd  eax, m0
    add   eax, 1
    shr   eax, 1
    mov   esp, r6
    RET

cglobal pixel_sa8d_16x16, 4,7
    FIX_STRIDES r1, r3
    mov  r6, esp
    and  esp, ~15
    sub  esp, 64
    lea  r4, [3*r1]
    lea  r5, [3*r3]
    call pixel_sa8d_8x8_internal
%if mmsize == 8
    lea  r0, [r0+4*r1]
    lea  r2, [r2+4*r3]
%endif
    mova [esp+48], m0
    call pixel_sa8d_8x8_internal
    mov  r0, [r6+20]
    mov  r2, [r6+28]
    add  r0, 8*SIZEOF_PIXEL
    add  r2, 8*SIZEOF_PIXEL
    SA8D_INTER
    mova [esp+48], m0
    call pixel_sa8d_8x8_internal
%if mmsize == 8
    lea  r0, [r0+4*r1]
    lea  r2, [r2+4*r3]
%else
    SA8D_INTER
%endif
    mova [esp+64-mmsize], m0
    call pixel_sa8d_8x8_internal
%if HIGH_BIT_DEPTH
    SA8D_INTER
    HADDD m0, m1
%else ; !HIGH_BIT_DEPTH
    paddusw m0, [esp+64-mmsize]
%if mmsize == 16
    HADDUW m0, m1
%else
    mova m2, [esp+48]
    pxor m7, m7
    mova m1, m0
    mova m3, m2
    punpcklwd m0, m7
    punpckhwd m1, m7
    punpcklwd m2, m7
    punpckhwd m3, m7
    paddd m0, m1
    paddd m2, m3
    paddd m0, m2
    HADDD m0, m1
%endif
%endif ; HIGH_BIT_DEPTH
    movd eax, m0
    add  eax, 1
    shr  eax, 1
    mov  esp, r6
    RET
%endif ; !ARCH_X86_64
%endmacro ; SA8D

;=============================================================================
; SA8D_SATD
;=============================================================================

; %1: vertical/horizontal mode
; %2-%5: sa8d output regs (m0,m1,m2,m3,m4,m5,m8,m9)
; m10: satd result
; m6, m11-15: tmp regs
%macro SA8D_SATD_8x4 5
%if %1
    LOAD_DIFF_8x4P %2, %3, %4, %5, 6, 11, 7, r0, r2, 1, mmsize < 32
    HADAMARD   0, sumsub, %2, %3, 6
    HADAMARD   0, sumsub, %4, %5, 6
    SBUTTERFLY        wd, %2, %3, 6
    SBUTTERFLY        wd, %4, %5, 6
    HADAMARD2_2D  %2, %4, %3, %5, 6, dq

    mova   m12, m%2
    mova   m13, m%3
    mova   m14, m%4
    mova   m15, m%5
    HADAMARD 0, sumsub, %2, %3, 6
    HADAMARD 0, sumsub, %4, %5, 6
    SBUTTERFLY     qdq, 12, 13, 6
    HADAMARD   0, amax, 12, 13, 6
    SBUTTERFLY     qdq, 14, 15, 6
    paddw m10, m12
    HADAMARD   0, amax, 14, 15, 6
    paddw m10, m14
%else
    LOAD_SUMSUB_8x4P %2, %3, %4, %5, 6, 11, 7, r0, r2, 1
    HADAMARD4_V %2, %3, %4, %5, 6

    pabsw    m12, m%2 ; doing the abs first is a slight advantage
    pabsw    m14, m%4
    pabsw    m13, m%3
    pabsw    m15, m%5
%if cpuflag(avx512icl)
    SATD_ICL_HMAX 12, 14, 6
    paddw    m10, m12
    SATD_ICL_HMAX 13, 15, 6
    paddw    m10, m13
%else
    HADAMARD 1, max, 12, 14, 6, 11
    paddw    m10, m12
    HADAMARD 1, max, 13, 15, 6, 11
    paddw    m10, m13
%endif
%endif
%endmacro ; SA8D_SATD_8x4

; %1: add spilled regs?
; %2: spill regs?
%macro SA8D_SATD_ACCUM 2
%if HIGH_BIT_DEPTH
    pmaddwd m10, [pw_1]
%if %1
    paddd   m10, temp1
    paddd    m0, temp0
%endif
%if %2
    mova  temp1, m10
    pxor    m10, m10
%endif
%else
    ; an 8x8's sa8d words are <= 80*255, four 8x8s overflow 16 bits
    pmaddwd  m0, [pw_1]
%if %1
    paddd    m0, temp0
%endif
%endif
%if %2
    mova  temp0, m0
%endif
%endmacro

%macro SA8D_SATD 0
%define vertical ((notcpuflag(ssse3) || cpuflag(atom)) || HIGH_BIT_DEPTH)
cglobal pixel_sa8d_satd_8x8_internal
    SA8D_SATD_8x4 vertical, 0, 1, 2, 3
    SA8D_SATD_8x4 vertical, 4, 5, 8, 9

%if vertical ; sse2-style
    HADAMARD2_2D 0, 4, 2, 8, 6, qdq, amax
    HADAMARD2_2D 1, 5, 3, 9, 6, qdq, amax
%else        ; complete sa8d
    SUMSUB_BADC w, 0, 4, 1, 5, 12
    HADAMARD 2, sumsub, 0, 4, 12, 11
    HADAMARD 2, sumsub, 1, 5, 12, 11
    SUMSUB_BADC w, 2, 8, 3, 9, 12
    HADAMARD 2, sumsub, 2, 8, 12, 11
    HADAMARD 2, sumsub, 3, 9, 12, 11
%if cpuflag(avx512icl)
    ABSW2 m0, m4, m0, m4, m12, m11
    ABSW2 m1, m5, m1, m5, m12, m11
    ABSW2 m2, m8, m2, m8, m12, m11
    ABSW2 m3, m9, m3, m9, m12, m11
    SATD_ICL_HMAX 0, 4, 12
    SATD_ICL_HMAX 1, 5, 12
    SATD_ICL_HMAX 2, 8, 12
    SATD_ICL_HMAX 3, 9, 12
%else
    HADAMARD 1, amax, 0, 4, 12, 11
    HADAMARD 1, amax, 1, 5, 12, 4
    HADAMARD 1, amax, 2, 8, 12, 4
    HADAMARD 1, amax, 3, 9, 12, 4
%endif
%endif

    ; create sa8d sub results
%if HIGH_BIT_DEPTH
    SA8D_SUM_HBD 0, 1, 2, 3
%else
    paddw    m1, m2
    paddw    m0, m3
    paddw    m0, m1
%endif

    SAVE_MM_PERMUTATION
    ret

;-------------------------------------------------------------------------------
; uint64_t pixel_sa8d_satd_16x16( pixel *, intptr_t, pixel *, intptr_t )
;-------------------------------------------------------------------------------
cglobal pixel_sa8d_satd_16x16, 4,8-(mmsize/32),16,SIZEOF_PIXEL*mmsize
    %define temp0 [rsp+0*mmsize]
    %define temp1 [rsp+1*mmsize]
    FIX_STRIDES r1, r3
%if vertical==0
    mova     m7, [hmul_8p]
%endif
%if cpuflag(avx512icl)
    mov     r4d, 0x5555
    kmovd    k1, r4d
%endif
    lea      r4, [3*r1]
    lea      r5, [3*r3]
    pxor    m10, m10

%if mmsize==32
    call pixel_sa8d_satd_8x8_internal
    SA8D_SATD_ACCUM 0, 1
    call pixel_sa8d_satd_8x8_internal
    SA8D_SATD_ACCUM 1, 0
    vextracti128 xm1, m0, 1
    vextracti128 xm2, m10, 1
    paddd   xm0, xm1
%if HIGH_BIT_DEPTH
    paddd  xm10, xm2
%else
    paddw  xm10, xm2
%endif
%else
    lea      r6, [r2+8*SIZEOF_PIXEL]
    lea      r7, [r0+8*SIZEOF_PIXEL]

    call pixel_sa8d_satd_8x8_internal
    SA8D_SATD_ACCUM 0, 1
    call pixel_sa8d_satd_8x8_internal
    SA8D_SATD_ACCUM 1, 1

    mov      r0, r7
    mov      r2, r6

    call pixel_sa8d_satd_8x8_internal
    SA8D_SATD_ACCUM 1, 1
    call pixel_sa8d_satd_8x8_internal
    SA8D_SATD_ACCUM 1, 0
%endif

; xop already has fast horizontal sums
%if cpuflag(avx512icl) && HIGH_BIT_DEPTH==0
    pmaddwd    xm10, [pw_1]
    punpcklqdq  xm1, xm0, xm10
    punpckhqdq  xm0, xm10
    paddd       xm0, xm1    ;  sa8d1  sa8d2  satd1  satd2
    pshufd      xm1, xm0, q2301
    paddd       xm0, xm1    ;   sa8d   sa8d   satd   satd
    movd        r0d, xm0
    pextrd      eax, xm0, 2
%elif cpuflag(sse4) && notcpuflag(xop) && HIGH_BIT_DEPTH==0
    pmaddwd xm10, [pw_1]
    phaddd  xm0, xm10       ;  sa8d1  sa8d2  satd1  satd2
    pshufd  xm1, xm0, q2301 ;  sa8d2  sa8d1  satd2  satd1
    paddd   xm0, xm1        ;   sa8d   sa8d   satd   satd
    movd    r0d, xm0
    pextrd  eax, xm0, 2
%else
    HADDD   xm0, xm1
%if HIGH_BIT_DEPTH
    HADDD  xm10, xm2
%else
    HADDW  xm10, xm2
%endif
    movd    r0d, xm0
    movd    eax, xm10
%endif
    add     r0d, 1
    shl     rax, 32
    shr     r0d, 1
    or      rax, r0
    RET
%endmacro ; SA8D_SATD

;=============================================================================
; INTRA SATD
;=============================================================================

%macro HSUMSUB2 8
    pshufd %4, %2, %7
    pshufd %5, %3, %7
    %1     %2, %8
    %1     %6, %8
    paddw  %2, %4
    paddw  %3, %5
%endmacro

; intra_sa8d_x3_8x8 and intra_satd_x3_4x4 are obsoleted by x9 on ssse3+,
; and are only retained for old cpus.
%macro INTRA_SA8D_SSE2 0
%if ARCH_X86_64
;-----------------------------------------------------------------------------
; void intra_sa8d_x3_8x8( uint8_t *fenc, uint8_t edge[36], int *res )
;-----------------------------------------------------------------------------
cglobal intra_sa8d_x3_8x8, 3,3,13
    ; 8x8 hadamard
    pxor        m8, m8
    movq        m0, [r0+0*FENC_STRIDE]
    movq        m1, [r0+1*FENC_STRIDE]
    movq        m2, [r0+2*FENC_STRIDE]
    movq        m3, [r0+3*FENC_STRIDE]
    movq        m4, [r0+4*FENC_STRIDE]
    movq        m5, [r0+5*FENC_STRIDE]
    movq        m6, [r0+6*FENC_STRIDE]
    movq        m7, [r0+7*FENC_STRIDE]
    punpcklbw   m0, m8
    punpcklbw   m1, m8
    punpcklbw   m2, m8
    punpcklbw   m3, m8
    punpcklbw   m4, m8
    punpcklbw   m5, m8
    punpcklbw   m6, m8
    punpcklbw   m7, m8

    HADAMARD8_2D 0, 1, 2, 3, 4, 5, 6, 7, 8

    ABSW2       m8, m9, m2, m3, m2, m3
    ABSW2      m10, m11, m4, m5, m4, m5
    paddw       m8, m10
    paddw       m9, m11
    ABSW2      m10, m11, m6, m7, m6, m7
    ABSW       m12, m1, m1
    paddw      m10, m11
    paddw       m8, m9
    paddw      m12, m10
    paddw      m12, m8

    ; 1D hadamard of edges
    movq        m8, [r1+7]
    movq        m9, [r1+16]
    pxor       m10, m10
    punpcklbw   m8, m10
    punpcklbw   m9, m10
    HSUMSUB2 pmullw, m8, m9, m10, m11, m11, q1032, [pw_ppppmmmm]
    HSUMSUB2 pmullw, m8, m9, m10, m11, m11, q2301, [pw_ppmmppmm]
    pshuflw    m10, m8, q2301
    pshuflw    m11, m9, q2301
    pshufhw    m10, m10, q2301
    pshufhw    m11, m11, q2301
    pmullw      m8, [pw_pmpmpmpm]
    pmullw     m11, [pw_pmpmpmpm]
    paddw       m8, m10
    paddw       m9, m11

    ; differences
    paddw      m10, m8, m9
    paddw      m10, [pw_8]
    pand       m10, [sw_f0]
    psllw       m8, 3 ; left edge
    psllw      m10, 2 ; dc
    psubw       m8, m0
    psubw      m10, m0
    punpcklwd   m0, m1
    punpcklwd   m2, m3
    punpcklwd   m4, m5
    punpcklwd   m6, m7
    ABSW       m10, m10, m1
    paddw      m10, m12
    punpckldq   m0, m2
    punpckldq   m4, m6
    punpcklqdq  m0, m4 ; transpose
    psllw       m9, 3 ; top edge
    psrldq      m2, m10, 2 ; 8x7 sum
    psubw       m0, m9  ; 8x1 sum
    ABSW2       m8, m0, m8, m0, m1, m3 ; 1x8 sum
    paddw       m8, m12
    paddusw     m2, m0

    ; 3x HADDW
    mova        m7, [pd_f0]
    pandn       m0, m7, m10
    psrld      m10, 16
    pandn       m1, m7, m8
    psrld       m8, 16
    pandn       m7, m2
    psrld       m2, 16
    paddd       m0, m10
    paddd       m1, m8
    paddd       m2, m7
    pshufd      m3, m0, q2301
    punpckhdq   m4, m2, m1
    punpckldq   m2, m1
    paddd       m3, m0
    paddd       m2, m4
    punpckhqdq  m0, m2, m3
    punpcklqdq  m2, m3
    paddd       m0, [pd_2]
    paddd       m0, m2
    psrld       m0, 2
    mova      [r2], m0
    RET
%endif ; ARCH_X86_64
%endmacro ; INTRA_SA8D_SSE2

; in: r0 = fenc
; out: m0..m3 = hadamard coefs
INIT_MMX
cglobal hadamard_load
; not really a global, but otherwise cycles get attributed to the wrong function in profiling
%if HIGH_BIT_DEPTH
    mova        m0, [r0+0*FENC_STRIDEB]
    mova        m1, [r0+1*FENC_STRIDEB]
    mova        m2, [r0+2*FENC_STRIDEB]
    mova        m3, [r0+3*FENC_STRIDEB]
%else
    pxor        m7, m7
    movd        m0, [r0+0*FENC_STRIDE]
    movd        m1, [r0+1*FENC_STRIDE]
    movd        m2, [r0+2*FENC_STRIDE]
    movd        m3, [r0+3*FENC_STRIDE]
    punpcklbw   m0, m7
    punpcklbw   m1, m7
    punpcklbw   m2, m7
    punpcklbw   m3, m7
%endif
    HADAMARD4_2D 0, 1, 2, 3, 4
    SAVE_MM_PERMUTATION
    ret

%macro SCALAR_HADAMARD 4-5 ; direction, offset, 3x tmp
%ifidn %1, top
%if HIGH_BIT_DEPTH
    mova        %3, [r1+%2*SIZEOF_PIXEL-FDEC_STRIDEB]
%else
    movd        %3, [r1+%2*SIZEOF_PIXEL-FDEC_STRIDEB]
    pxor        %5, %5
    punpcklbw   %3, %5
%endif
%else ; left
%ifnidn %2, 0
    shl         %2d, 5 ; log(FDEC_STRIDEB)
%endif
    movd        %3, [r1+%2*SIZEOF_PIXEL-4+1*FDEC_STRIDEB]
    pinsrw      %3, [r1+%2*SIZEOF_PIXEL-2+0*FDEC_STRIDEB], 0
    pinsrw      %3, [r1+%2*SIZEOF_PIXEL-2+2*FDEC_STRIDEB], 2
    pinsrw      %3, [r1+%2*SIZEOF_PIXEL-2+3*FDEC_STRIDEB], 3
%if HIGH_BIT_DEPTH == 0
    psrlw       %3, 8
%endif
%ifnidn %2, 0
    shr         %2d, 5
%endif
%endif ; direction
%if cpuflag(ssse3)
    %define %%sign psignw
%else
    %define %%sign pmullw
%endif
    pshufw      %4, %3, q1032
    %%sign      %4, [pw_ppmmppmm]
    paddw       %3, %4
    pshufw      %4, %3, q2301
    %%sign      %4, [pw_pmpmpmpm]
    paddw       %3, %4
    psllw       %3, 2
    mova        [%1_1d+2*%2], %3
%endmacro

%macro SUM_MM_X3 8 ; 3x sum, 4x tmp, op
    pxor        %7, %7
    pshufw      %4, %1, q1032
    pshufw      %5, %2, q1032
    pshufw      %6, %3, q1032
    paddw       %1, %4
    paddw       %2, %5
    paddw       %3, %6
    punpcklwd   %1, %7
    punpcklwd   %2, %7
    punpcklwd   %3, %7
    pshufw      %4, %1, q1032
    pshufw      %5, %2, q1032
    pshufw      %6, %3, q1032
    %8          %1, %4
    %8          %2, %5
    %8          %3, %6
%endmacro

; in: m1..m3
; out: m7
; clobber: m4..m6
%macro SUM3x4 0
    ABSW2       m4, m5, m1, m2, m1, m2
    ABSW        m7, m3, m3
    paddw       m4, m5
    paddw       m7, m4
%endmacro

; in: m0..m3 (4x4)
; out: m0 v, m4 h, m5 dc
; clobber: m1..m3
%macro SUM4x3 3 ; dc, left, top
    movq        m4, %2
%ifid %1
    movq        m5, %1
%else
    movd        m5, %1
%endif
    psubw       m4, m0
    psubw       m5, m0
    punpcklwd   m0, m1
    punpcklwd   m2, m3
    punpckldq   m0, m2 ; transpose
    psubw       m0, %3
    ABSW2       m4, m5, m4, m5, m2, m3 ; 1x4 sum
    ABSW        m0, m0, m1 ; 4x1 sum
%endmacro

%macro INTRA_X3_MMX 0
;-----------------------------------------------------------------------------
; void intra_satd_x3_4x4( uint8_t *fenc, uint8_t *fdec, int *res )
;-----------------------------------------------------------------------------
cglobal intra_satd_x3_4x4, 3,3
%if UNIX64
    ; stack is 16 byte aligned because abi says so
    %define  top_1d  rsp-8  ; size 8
    %define  left_1d rsp-16 ; size 8
%else
    ; WIN64:  stack is 16 byte aligned because abi says so
    ; X86_32: stack is 16 byte aligned at least in gcc, and we've pushed 3 regs + return address, so it's still aligned
    SUB         rsp, 16
    %define  top_1d  rsp+8
    %define  left_1d rsp
%endif

    call hadamard_load
    SCALAR_HADAMARD left, 0, m4, m5
    SCALAR_HADAMARD top,  0, m6, m5, m7
    paddw       m6, m4
    pavgw       m6, [pw_16]
    pand        m6, [sw_f0] ; dc

    SUM3x4
    SUM4x3 m6, [left_1d], [top_1d]
    paddw       m4, m7
    paddw       m5, m7
    movq        m1, m5
    psrlq       m1, 16  ; 4x3 sum
    paddw       m0, m1

    SUM_MM_X3   m0, m4, m5, m1, m2, m3, m6, pavgw
    movd        [r2+0], m0 ; i4x4_v satd
    movd        [r2+4], m4 ; i4x4_h satd
    movd        [r2+8], m5 ; i4x4_dc satd
%if UNIX64 == 0
    ADD         rsp, 16
%endif
    RET

;-----------------------------------------------------------------------------
; void intra_satd_x3_16x16( uint8_t *fenc, uint8_t *fdec, int *res )
;-----------------------------------------------------------------------------
cglobal intra_satd_x3_16x16, 0,5
    %assign  stack_pad  120 + ((stack_offset+120+gprsize)&15)
    ; not really needed on x86_64, just shuts up valgrind about storing data below the stack across a function call
    SUB         rsp, stack_pad
%define sums    rsp+64 ; size 56
%define top_1d  rsp+32 ; size 32
%define left_1d rsp    ; size 32
    movifnidn   r1,  r1mp

    pxor        m7, m7
    mova [sums+ 0], m7
    mova [sums+ 8], m7
    mova [sums+16], m7
%if HIGH_BIT_DEPTH
    mova [sums+24], m7
    mova [sums+32], m7
    mova [sums+40], m7
    mova [sums+48], m7
%endif

    ; 1D hadamards
    mov        r3d, 12
    movd        m6, [pw_32]
.loop_edge:
    SCALAR_HADAMARD left, r3, m0, m1
    SCALAR_HADAMARD top,  r3, m1, m2, m3
    pavgw       m0, m1
    paddw       m6, m0
    sub        r3d, 4
    jge .loop_edge
    psrlw       m6, 2
    pand        m6, [sw_f0] ; dc

    ; 2D hadamards
    movifnidn   r0, r0mp
    mov         r3, -4
.loop_y:
    mov         r4, -4
.loop_x:
    call hadamard_load

    SUM3x4
    SUM4x3 m6, [left_1d+8*(r3+4)], [top_1d+8*(r4+4)]
    pavgw       m4, m7
    pavgw       m5, m7
    paddw       m0, [sums+ 0] ; i16x16_v satd
    paddw       m4, [sums+ 8] ; i16x16_h satd
    paddw       m5, [sums+16] ; i16x16_dc satd
    mova [sums+ 0], m0
    mova [sums+ 8], m4
    mova [sums+16], m5

    add         r0, 4*SIZEOF_PIXEL
    inc         r4
    jl  .loop_x
%if HIGH_BIT_DEPTH
    psrld       m7, m4, 16
    pslld       m4, 16
    psrld       m4, 16
    paddd       m4, m7
    psrld       m7, m0, 16
    pslld       m0, 16
    psrld       m0, 16
    paddd       m0, m7
    paddd       m4, [sums+32]
    paddd       m0, [sums+24]
    mova [sums+32], m4
    mova [sums+24], m0
    pxor        m7, m7
    punpckhwd   m3, m5, m7
    punpcklwd   m5, m7
    paddd       m3, [sums+48]
    paddd       m5, [sums+40]
    mova [sums+48], m3
    mova [sums+40], m5
    mova [sums+ 0], m7
    mova [sums+ 8], m7
    mova [sums+16], m7
%endif
    add         r0, 4*FENC_STRIDEB-16*SIZEOF_PIXEL
    inc         r3
    jl  .loop_y

; horizontal sum
    movifnidn   r2, r2mp
%if HIGH_BIT_DEPTH
    mova        m1, m5
    paddd       m5, m3
    HADDD       m5, m7 ; DC satd
    HADDD       m4, m7 ; H satd
    HADDD       m0, m7 ; the part of V satd that doesn't overlap with DC
    psrld       m0, 1
    psrlq       m1, 32 ; DC[1]
    paddd       m0, m3 ; DC[2]
    psrlq       m3, 32 ; DC[3]
    paddd       m0, m1
    paddd       m0, m3
%else
    mova        m7, m5
    SUM_MM_X3   m0, m4, m5, m3, m1, m2, m6, paddd
    psrld       m0, 1
    pslld       m7, 16
    psrld       m7, 16
    paddd       m0, m5
    psubd       m0, m7
%endif
    movd    [r2+8], m5 ; i16x16_dc satd
    movd    [r2+4], m4 ; i16x16_h satd
    movd    [r2+0], m0 ; i16x16_v satd
    ADD        rsp, stack_pad
    RET

%if ARCH_X86_64
    %define  t0 r6
%else
    %define  t0 r2
%endif

;-----------------------------------------------------------------------------
; void intra_satd_x3_8x8c( uint8_t *fenc, uint8_t *fdec, int *res )
;-----------------------------------------------------------------------------
cglobal intra_satd_x3_8x8c, 0,6
    ; not really needed on x86_64, just shuts up valgrind about storing data below the stack across a function call
    SUB          rsp, 72
%define  sums    rsp+48 ; size 24
%define  dc_1d   rsp+32 ; size 16
%define  top_1d  rsp+16 ; size 16
%define  left_1d rsp    ; size 16
    movifnidn   r1,  r1mp
    pxor        m7, m7
    mova [sums+ 0], m7
    mova [sums+ 8], m7
    mova [sums+16], m7

    ; 1D hadamards
    mov         r3d, 4
.loop_edge:
    SCALAR_HADAMARD left, r3, m0, m1
    SCALAR_HADAMARD top,  r3, m0, m1, m2
    sub         r3d, 4
    jge .loop_edge

    ; dc
    movzx       t0d, word [left_1d+0]
    movzx       r3d, word [top_1d+0]
    movzx       r4d, word [left_1d+8]
    movzx       r5d, word [top_1d+8]
    lea         t0d, [t0 + r3 + 16]
    lea         r3d, [r4 + r5 + 16]
    shr         t0d, 1
    shr         r3d, 1
    add         r4d, 8
    add         r5d, 8
    and         t0d, -16 ; tl
    and         r3d, -16 ; br
    and         r4d, -16 ; bl
    and         r5d, -16 ; tr
    mov         [dc_1d+ 0], t0d ; tl
    mov         [dc_1d+ 4], r5d ; tr
    mov         [dc_1d+ 8], r4d ; bl
    mov         [dc_1d+12], r3d ; br
    lea         r5, [dc_1d]

    ; 2D hadamards
    movifnidn   r0,  r0mp
    movifnidn   r2,  r2mp
    mov         r3,  -2
.loop_y:
    mov         r4,  -2
.loop_x:
    call hadamard_load

    SUM3x4
    SUM4x3 [r5+4*(r4+2)], [left_1d+8*(r3+2)], [top_1d+8*(r4+2)]
    pavgw       m4, m7
    pavgw       m5, m7
    paddw       m0, [sums+16] ; i4x4_v satd
    paddw       m4, [sums+8]  ; i4x4_h satd
    paddw       m5, [sums+0]  ; i4x4_dc satd
    movq        [sums+16], m0
    movq        [sums+8], m4
    movq        [sums+0], m5

    add         r0, 4*SIZEOF_PIXEL
    inc         r4
    jl  .loop_x
    add         r0, 4*FENC_STRIDEB-8*SIZEOF_PIXEL
    add         r5, 8
    inc         r3
    jl  .loop_y

; horizontal sum
    movq        m0, [sums+0]
    movq        m1, [sums+8]
    movq        m2, [sums+16]
    movq        m7, m0
%if HIGH_BIT_DEPTH
    psrlq       m7, 16
    HADDW       m7, m3
    SUM_MM_X3   m0, m1, m2, m3, m4, m5, m6, paddd
    psrld       m2, 1
    paddd       m2, m7
%else
    psrlq       m7, 15
    paddw       m2, m7
    SUM_MM_X3   m0, m1, m2, m3, m4, m5, m6, paddd
    psrld       m2, 1
%endif
    movd        [r2+0], m0 ; i8x8c_dc satd
    movd        [r2+4], m1 ; i8x8c_h satd
    movd        [r2+8], m2 ; i8x8c_v satd
    ADD         rsp, 72
    RET
%endmacro ; INTRA_X3_MMX



%macro PRED4x4_LOWPASS 5
%ifid %5
    pavgb       %5, %2, %3
    pxor        %3, %2
    pand        %3, [pb_1]
    psubusb     %5, %3
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

%macro INTRA_X9_PRED 2
%if cpuflag(sse4)
    movu       m1, [r1-1*FDEC_STRIDE-8]
    pinsrb     m1, [r1+3*FDEC_STRIDE-1], 0
    pinsrb     m1, [r1+2*FDEC_STRIDE-1], 1
    pinsrb     m1, [r1+1*FDEC_STRIDE-1], 2
    pinsrb     m1, [r1+0*FDEC_STRIDE-1], 3
%else
    movd      mm0, [r1+3*FDEC_STRIDE-4]
    punpcklbw mm0, [r1+2*FDEC_STRIDE-4]
    movd      mm1, [r1+1*FDEC_STRIDE-4]
    punpcklbw mm1, [r1+0*FDEC_STRIDE-4]
    punpckhwd mm0, mm1
    psrlq     mm0, 32
    movq2dq    m0, mm0
    movu       m1, [r1-1*FDEC_STRIDE-8]
    movss      m1, m0                  ; l3 l2 l1 l0 __ __ __ lt t0 t1 t2 t3 t4 t5 t6 t7
%endif ; cpuflag
    pshufb     m1, [intrax9_edge]      ; l3 l3 l2 l1 l0 lt t0 t1 t2 t3 t4 t5 t6 t7 t7 __
    psrldq     m0, m1, 1               ; l3 l2 l1 l0 lt t0 t1 t2 t3 t4 t5 t6 t7 t7 __ __
    psrldq     m2, m1, 2               ; l2 l1 l0 lt t0 t1 t2 t3 t4 t5 t6 t7 t7 __ __ __
    pavgb      m5, m0, m1              ; Gl3 Gl2 Gl1 Gl0 Glt Gt0 Gt1 Gt2 Gt3 Gt4 Gt5  __  __ __ __ __
    mova       %2, m1
    PRED4x4_LOWPASS m0, m1, m2, m0, m4 ; Fl3 Fl2 Fl1 Fl0 Flt Ft0 Ft1 Ft2 Ft3 Ft4 Ft5 Ft6 Ft7 __ __ __
    ; ddl               ddr
    ; Ft1 Ft2 Ft3 Ft4   Flt Ft0 Ft1 Ft2
    ; Ft2 Ft3 Ft4 Ft5   Fl0 Flt Ft0 Ft1
    ; Ft3 Ft4 Ft5 Ft6   Fl1 Fl0 Flt Ft0
    ; Ft4 Ft5 Ft6 Ft7   Fl2 Fl1 Fl0 Flt
    pshufb     m2, m0, [%1_ddlr1] ; a: ddl row0, ddl row1, ddr row0, ddr row1 / b: ddl row0, ddr row0, ddl row1, ddr row1
    pshufb     m3, m0, [%1_ddlr2] ; rows 2,3
    ; hd                hu
    ; Glt Flt Ft0 Ft1   Gl0 Fl1 Gl1 Fl2
    ; Gl0 Fl0 Glt Flt   Gl1 Fl2 Gl2 Fl3
    ; Gl1 Fl1 Gl0 Fl0   Gl2 Fl3 Gl3 Gl3
    ; Gl2 Fl2 Gl1 Fl1   Gl3 Gl3 Gl3 Gl3
    pslldq     m0, 5                   ; ___ ___ ___ ___ ___ Fl3 Fl2 Fl1 Fl0 Flt Ft0 Ft1 Ft2 Ft3 Ft4 Ft5
    palignr    m7, m5, m0, 5           ; Fl3 Fl2 Fl1 Fl0 Flt Ft0 Ft1 Ft2 Ft3 Ft4 Ft5 Gl3 Gl2 Gl1 Gl0 Glt
    pshufb     m6, m7, [%1_hdu1]
    pshufb     m7, m7, [%1_hdu2]
    ; vr                vl
    ; Gt0 Gt1 Gt2 Gt3   Gt1 Gt2 Gt3 Gt4
    ; Flt Ft0 Ft1 Ft2   Ft1 Ft2 Ft3 Ft4
    ; Fl0 Gt0 Gt1 Gt2   Gt2 Gt3 Gt4 Gt5
    ; Fl1 Flt Ft0 Ft1   Ft2 Ft3 Ft4 Ft5
    psrldq     m5, 5                   ; Gt0 Gt1 Gt2 Gt3 Gt4 Gt5 ...
    palignr    m5, m0, 6               ; ___ Fl1 Fl0 Flt Ft0 Ft1 Ft2 Ft3 Ft4 Ft5 Gt0 Gt1 Gt2 Gt3 Gt4 Gt5
    pshufb     m4, m5, [%1_vrl1]
    pshufb     m5, m5, [%1_vrl2]
%endmacro ; INTRA_X9_PRED

%macro INTRA_X9_VHDC 5 ; edge, fenc01, fenc23, tmp, tmp
    pshufb     m2, m%1, [intrax9b_vh1]
    pshufb     m3, m%1, [intrax9b_vh2]
    mova      [pred_buf+0x60], m2
    mova      [pred_buf+0x70], m3
    pshufb    m%1, [intrax9b_edge2] ; t0 t1 t2 t3 t0 t1 t2 t3 l0 l1 l2 l3 l0 l1 l2 l3
    pmaddubsw m%1, [hmul_4p]
    pshufhw    m0, m%1, q2301
    pshuflw    m0, m0,  q2301
    psignw    m%1, [pw_pmpmpmpm]
    paddw      m0, m%1
    psllw      m0, 2 ; hadamard(top), hadamard(left)
    movhlps    m3, m0
    pshufb     m1, m0, [intrax9b_v1]
    pshufb     m2, m0, [intrax9b_v2]
    paddw      m0, m3
    psignw     m3, [pw_pmmpzzzz] ; FIXME could this be eliminated?
    pavgw      m0, [pw_16]
    pand       m0, [sw_f0] ; dc
    ; This (as well as one of the steps in intra_satd_x9_4x4.satd_8x4) could be
    ; changed from a wd transpose to a qdq, with appropriate rearrangement of inputs.
    ; Which would be faster on conroe, but slower on penryn and sandybridge, and too invasive to ifdef.
    HADAMARD 0, sumsub, %2, %3, %4, %5
    HADAMARD 1, sumsub, %2, %3, %4, %5
    movd      r3d, m0
    shr       r3d, 4
    imul      r3d, 0x01010101
    mov       [pred_buf+0x80], r3d
    mov       [pred_buf+0x88], r3d
    mov       [pred_buf+0x90], r3d
    mov       [pred_buf+0x98], r3d
    psubw      m3, m%2
    psubw      m0, m%2
    psubw      m1, m%2
    psubw      m2, m%3
    pabsw     m%3, m%3
    pabsw      m3, m3
    pabsw      m0, m0
    pabsw      m1, m1
    pabsw      m2, m2
    pavgw      m3, m%3
    pavgw      m0, m%3
    pavgw      m1, m2
%if cpuflag(sse4)
    phaddw     m3, m0
%else
    SBUTTERFLY qdq, 3, 0, 2
    paddw      m3, m0
%endif
    movhlps    m2, m1
    paddw      m1, m2
%if cpuflag(xop)
    vphaddwq   m3, m3
    vphaddwq   m1, m1
    packssdw   m1, m3
%else
    phaddw     m1, m3
    pmaddwd    m1, [pw_1] ; v, _, h, dc
%endif
%endmacro ; INTRA_X9_VHDC

%macro INTRA_X9_END 2
%if cpuflag(sse4)
    phminposuw m0, m0 ; h,dc,ddl,ddr,vr,hd,vl,hu
    movd      eax, m0
    add       eax, 1<<16
    cmp        ax, r3w
    cmovge    eax, r3d
%else
%if %1
    ; 4x4 sad is up to 12 bits; +bitcosts -> 13 bits; pack with 3 bit index
    psllw      m0, 3
    paddw      m0, [pw_s01234567] ; h,dc,ddl,ddr,vr,hd,vl,hu
%else
    ; 4x4 satd is up to 13 bits; +bitcosts and saturate -> 13 bits; pack with 3 bit index
    psllw      m0, 2
    paddusw    m0, m0
    paddw      m0, [pw_s01234657] ; h,dc,ddl,ddr,vr,vl,hd,hu
%endif
    movhlps    m1, m0
    pminsw     m0, m1
    pshuflw    m1, m0, q0032
    pminsw     m0, m1
    pshuflw    m1, m0, q0001
    pminsw     m0, m1
    movd      eax, m0
    movsx     r2d, ax
    and       eax, 7
    sar       r2d, 3
    shl       eax, 16
    ; 1<<16: increment index to match intra4x4_pred_e. couldn't do this before because it had to fit in 3 bits
    ; 1<<12: undo sign manipulation
    lea       eax, [rax+r2+(1<<16)+(1<<12)]
    cmp        ax, r3w
    cmovge    eax, r3d
%endif ; cpuflag

    ; output the predicted samples
    mov       r3d, eax
    shr       r3d, 16
%ifdef PIC
    lea        r2, [%2_lut]
    movzx     r2d, byte [r2+r3]
%else
    movzx     r2d, byte [%2_lut+r3]
%endif
%if %1 ; sad
    movq      mm0, [pred_buf+r2]
    movq      mm1, [pred_buf+r2+16]
    movd     [r1+0*FDEC_STRIDE], mm0
    movd     [r1+2*FDEC_STRIDE], mm1
    psrlq     mm0, 32
    psrlq     mm1, 32
    movd     [r1+1*FDEC_STRIDE], mm0
    movd     [r1+3*FDEC_STRIDE], mm1
%else ; satd
%assign i 0
%rep 4
    mov       r3d, [pred_buf+r2+8*i]
    mov      [r1+i*FDEC_STRIDE], r3d
%assign i i+1
%endrep
%endif
%endmacro ; INTRA_X9_END

%macro INTRA_X9 0
;-----------------------------------------------------------------------------
; int intra_sad_x9_4x4( uint8_t *fenc, uint8_t *fdec, uint16_t *bitcosts )
;-----------------------------------------------------------------------------
%if notcpuflag(xop)
cglobal intra_sad_x9_4x4, 3,4,9
    %assign pad 0xc0-gprsize-(stack_offset&15)
    %define pred_buf rsp
    sub       rsp, pad
%if ARCH_X86_64
    INTRA_X9_PRED intrax9a, m8
%else
    INTRA_X9_PRED intrax9a, [rsp+0xa0]
%endif
    mova [rsp+0x00], m2
    mova [rsp+0x10], m3
    mova [rsp+0x20], m4
    mova [rsp+0x30], m5
    mova [rsp+0x40], m6
    mova [rsp+0x50], m7
%if cpuflag(sse4)
    movd       m0, [r0+0*FENC_STRIDE]
    pinsrd     m0, [r0+1*FENC_STRIDE], 1
    movd       m1, [r0+2*FENC_STRIDE]
    pinsrd     m1, [r0+3*FENC_STRIDE], 1
%else
    movd      mm0, [r0+0*FENC_STRIDE]
    punpckldq mm0, [r0+1*FENC_STRIDE]
    movd      mm1, [r0+2*FENC_STRIDE]
    punpckldq mm1, [r0+3*FENC_STRIDE]
    movq2dq    m0, mm0
    movq2dq    m1, mm1
%endif
    punpcklqdq m0, m0
    punpcklqdq m1, m1
    psadbw     m2, m0
    psadbw     m3, m1
    psadbw     m4, m0
    psadbw     m5, m1
    psadbw     m6, m0
    psadbw     m7, m1
    paddd      m2, m3
    paddd      m4, m5
    paddd      m6, m7
%if ARCH_X86_64
    SWAP        7, 8
    pxor       m8, m8
    %define %%zero m8
%else
    mova       m7, [rsp+0xa0]
    %define %%zero [pb_0]
%endif
    pshufb     m3, m7, [intrax9a_vh1]
    pshufb     m5, m7, [intrax9a_vh2]
    pshufb     m7, [intrax9a_dc]
    psadbw     m7, %%zero
    psrlw      m7, 2
    mova [rsp+0x60], m3
    mova [rsp+0x70], m5
    psadbw     m3, m0
    pavgw      m7, %%zero
    pshufb     m7, %%zero
    psadbw     m5, m1
    movq [rsp+0x80], m7
    movq [rsp+0x90], m7
    psadbw     m0, m7
    paddd      m3, m5
    psadbw     m1, m7
    paddd      m0, m1
    movzx     r3d, word [r2]
    movd      r0d, m3 ; v
    add       r3d, r0d
    punpckhqdq m3, m0 ; h, dc
    shufps     m3, m2, q2020
    psllq      m6, 32
    por        m4, m6
    movu       m0, [r2+2]
    packssdw   m3, m4
    paddw      m0, m3
    INTRA_X9_END 1, intrax9a
    add       rsp, pad
    RET
%endif ; cpuflag

%if ARCH_X86_64
;-----------------------------------------------------------------------------
; int intra_satd_x9_4x4( uint8_t *fenc, uint8_t *fdec, uint16_t *bitcosts )
;-----------------------------------------------------------------------------
cglobal intra_satd_x9_4x4, 3,4,16
    %assign pad 0xb0-gprsize-(stack_offset&15)
    %define pred_buf rsp
    sub       rsp, pad
    INTRA_X9_PRED intrax9b, m15
    mova [rsp+0x00], m2
    mova [rsp+0x10], m3
    mova [rsp+0x20], m4
    mova [rsp+0x30], m5
    mova [rsp+0x40], m6
    mova [rsp+0x50], m7
    movd       m8, [r0+0*FENC_STRIDE]
    movd       m9, [r0+1*FENC_STRIDE]
    movd      m10, [r0+2*FENC_STRIDE]
    movd      m11, [r0+3*FENC_STRIDE]
    mova      m12, [hmul_8p]
    pshufd     m8, m8, 0
    pshufd     m9, m9, 0
    pshufd    m10, m10, 0
    pshufd    m11, m11, 0
    pmaddubsw  m8, m12
    pmaddubsw  m9, m12
    pmaddubsw m10, m12
    pmaddubsw m11, m12
    movddup    m0, m2
    pshufd     m1, m2, q3232
    movddup    m2, m3
    movhlps    m3, m3
    call .satd_8x4 ; ddr, ddl
    movddup    m2, m5
    pshufd     m3, m5, q3232
    mova       m5, m0
    movddup    m0, m4
    pshufd     m1, m4, q3232
    call .satd_8x4 ; vr, vl
    movddup    m2, m7
    pshufd     m3, m7, q3232
    mova       m4, m0
    movddup    m0, m6
    pshufd     m1, m6, q3232
    call .satd_8x4 ; hd, hu
%if cpuflag(sse4)
    punpckldq  m4, m0
%else
    punpcklqdq m4, m0 ; conroe dislikes punpckldq, and ssse3 INTRA_X9_END can handle arbitrary orders whereas phminposuw can't
%endif
    mova       m1, [pw_ppmmppmm]
    psignw     m8, m1
    psignw    m10, m1
    paddw      m8, m9
    paddw     m10, m11
    INTRA_X9_VHDC 15, 8, 10, 6, 7
    ; find minimum
    movu       m0, [r2+2]
    movd      r3d, m1
    palignr    m5, m1, 8
%if notcpuflag(sse4)
    pshufhw    m0, m0, q3120 ; compensate for different order in unpack
%endif
    packssdw   m5, m4
    paddw      m0, m5
    movzx     r0d, word [r2]
    add       r3d, r0d
    INTRA_X9_END 0, intrax9b
    add       rsp, pad
    RET
RESET_MM_PERMUTATION
ALIGN 16
.satd_8x4:
    pmaddubsw  m0, m12
    pmaddubsw  m1, m12
    pmaddubsw  m2, m12
    pmaddubsw  m3, m12
    psubw      m0, m8
    psubw      m1, m9
    psubw      m2, m10
    psubw      m3, m11
    SATD_8x4_SSE 0, 0, 1, 2, 3, 13, 14, 0, swap
    pmaddwd    m0, [pw_1]
%if cpuflag(sse4)
    pshufd     m1, m0, q0032
%else
    movhlps    m1, m0
%endif
    paddd    xmm0, m0, m1 ; consistent location of return value. only the avx version of hadamard permutes m0, so 3arg is free
    ret

%else ; !ARCH_X86_64
cglobal intra_satd_x9_4x4, 3,4,8
    %assign pad 0x120-gprsize-(stack_offset&15)
    %define fenc_buf rsp
    %define pred_buf rsp+0x40
    %define spill    rsp+0xe0
    sub       rsp, pad
    INTRA_X9_PRED intrax9b, [spill+0x20]
    mova [pred_buf+0x00], m2
    mova [pred_buf+0x10], m3
    mova [pred_buf+0x20], m4
    mova [pred_buf+0x30], m5
    mova [pred_buf+0x40], m6
    mova [pred_buf+0x50], m7
    movd       m4, [r0+0*FENC_STRIDE]
    movd       m5, [r0+1*FENC_STRIDE]
    movd       m6, [r0+2*FENC_STRIDE]
    movd       m0, [r0+3*FENC_STRIDE]
    mova       m7, [hmul_8p]
    pshufd     m4, m4, 0
    pshufd     m5, m5, 0
    pshufd     m6, m6, 0
    pshufd     m0, m0, 0
    pmaddubsw  m4, m7
    pmaddubsw  m5, m7
    pmaddubsw  m6, m7
    pmaddubsw  m0, m7
    mova [fenc_buf+0x00], m4
    mova [fenc_buf+0x10], m5
    mova [fenc_buf+0x20], m6
    mova [fenc_buf+0x30], m0
    movddup    m0, m2
    pshufd     m1, m2, q3232
    movddup    m2, m3
    movhlps    m3, m3
    pmaddubsw  m0, m7
    pmaddubsw  m1, m7
    pmaddubsw  m2, m7
    pmaddubsw  m3, m7
    psubw      m0, m4
    psubw      m1, m5
    psubw      m2, m6
    call .satd_8x4b ; ddr, ddl
    mova       m3, [pred_buf+0x30]
    mova       m1, [pred_buf+0x20]
    movddup    m2, m3
    movhlps    m3, m3
    movq [spill+0x08], m0
    movddup    m0, m1
    movhlps    m1, m1
    call .satd_8x4 ; vr, vl
    mova       m3, [pred_buf+0x50]
    mova       m1, [pred_buf+0x40]
    movddup    m2, m3
    movhlps    m3, m3
    movq [spill+0x10], m0
    movddup    m0, m1
    movhlps    m1, m1
    call .satd_8x4 ; hd, hu
    movq [spill+0x18], m0
    mova       m1, [spill+0x20]
    mova       m4, [fenc_buf+0x00]
    mova       m5, [fenc_buf+0x20]
    mova       m2, [pw_ppmmppmm]
    psignw     m4, m2
    psignw     m5, m2
    paddw      m4, [fenc_buf+0x10]
    paddw      m5, [fenc_buf+0x30]
    INTRA_X9_VHDC 1, 4, 5, 6, 7
    ; find minimum
    movu       m0, [r2+2]
    movd      r3d, m1
    punpckhqdq m1, [spill+0x00]
    packssdw   m1, [spill+0x10]
%if cpuflag(sse4)
    pshufhw    m1, m1, q3120
%else
    pshufhw    m0, m0, q3120
%endif
    paddw      m0, m1
    movzx     r0d, word [r2]
    add       r3d, r0d
    INTRA_X9_END 0, intrax9b
    add       rsp, pad
    RET
RESET_MM_PERMUTATION
ALIGN 16
.satd_8x4:
    pmaddubsw  m0, m7
    pmaddubsw  m1, m7
    pmaddubsw  m2, m7
    pmaddubsw  m3, m7
    %xdefine fenc_buf fenc_buf+gprsize
    psubw      m0, [fenc_buf+0x00]
    psubw      m1, [fenc_buf+0x10]
    psubw      m2, [fenc_buf+0x20]
.satd_8x4b:
    psubw      m3, [fenc_buf+0x30]
    SATD_8x4_SSE 0, 0, 1, 2, 3, 4, 5, 0, swap
    pmaddwd    m0, [pw_1]
%if cpuflag(sse4)
    pshufd     m1, m0, q0032
%else
    movhlps    m1, m0
%endif
    paddd    xmm0, m0, m1
    ret
%endif ; ARCH
%endmacro ; INTRA_X9



%macro INTRA8_X9 0
;-----------------------------------------------------------------------------
; int intra_sad_x9_8x8( uint8_t *fenc, uint8_t *fdec, uint8_t edge[36], uint16_t *bitcosts, uint16_t *satds )
;-----------------------------------------------------------------------------
cglobal intra_sad_x9_8x8, 5,6,9
    %define fenc02 m4
    %define fenc13 m5
    %define fenc46 m6
    %define fenc57 m7
%if ARCH_X86_64
    %define tmp m8
    %assign padbase 0x0
%else
    %define tmp [rsp]
    %assign padbase 0x10
%endif
    %assign pad 0x240+0x10+padbase-gprsize-(stack_offset&15)
    %define pred(i,j) [rsp+i*0x40+j*0x10+padbase]

    SUB        rsp, pad
    movq    fenc02, [r0+FENC_STRIDE* 0]
    movq    fenc13, [r0+FENC_STRIDE* 1]
    movq    fenc46, [r0+FENC_STRIDE* 4]
    movq    fenc57, [r0+FENC_STRIDE* 5]
    movhps  fenc02, [r0+FENC_STRIDE* 2]
    movhps  fenc13, [r0+FENC_STRIDE* 3]
    movhps  fenc46, [r0+FENC_STRIDE* 6]
    movhps  fenc57, [r0+FENC_STRIDE* 7]

    ; save instruction size: avoid 4-byte memory offsets
    lea         r0, [intra8x9_h1+128]
    %define off(m) (r0+m-(intra8x9_h1+128))

; v
    movddup     m0, [r2+16]
    mova pred(0,0), m0
    psadbw      m1, m0, fenc02
    mova pred(0,1), m0
    psadbw      m2, m0, fenc13
    mova pred(0,2), m0
    psadbw      m3, m0, fenc46
    mova pred(0,3), m0
    psadbw      m0, m0, fenc57
    paddw       m1, m2
    paddw       m0, m3
    paddw       m0, m1
    movhlps     m1, m0
    paddw       m0, m1
    movd    [r4+0], m0

; h
    movq        m0, [r2+7]
    pshufb      m1, m0, [off(intra8x9_h1)]
    pshufb      m2, m0, [off(intra8x9_h2)]
    mova pred(1,0), m1
    psadbw      m1, fenc02
    mova pred(1,1), m2
    psadbw      m2, fenc13
    paddw       m1, m2
    pshufb      m3, m0, [off(intra8x9_h3)]
    pshufb      m2, m0, [off(intra8x9_h4)]
    mova pred(1,2), m3
    psadbw      m3, fenc46
    mova pred(1,3), m2
    psadbw      m2, fenc57
    paddw       m1, m3
    paddw       m1, m2
    movhlps     m2, m1
    paddw       m1, m2
    movd    [r4+2], m1

    lea         r5, [rsp+padbase+0x100]
    %define pred(i,j) [r5+i*0x40+j*0x10-0x100]

; dc
    movhps      m0, [r2+16]
    pxor        m2, m2
    psadbw      m0, m2
    movhlps     m1, m0
    paddw       m0, m1
    psrlw       m0, 3
    pavgw       m0, m2
    pshufb      m0, m2
    mova pred(2,0), m0
    psadbw      m1, m0, fenc02
    mova pred(2,1), m0
    psadbw      m2, m0, fenc13
    mova pred(2,2), m0
    psadbw      m3, m0, fenc46
    mova pred(2,3), m0
    psadbw      m0, m0, fenc57
    paddw       m1, m2
    paddw       m0, m3
    paddw       m0, m1
    movhlps     m1, m0
    paddw       m0, m1
    movd    [r4+4], m0

; ddl
; Ft1 Ft2 Ft3 Ft4 Ft5 Ft6 Ft7 Ft8
; Ft2 Ft3 Ft4 Ft5 Ft6 Ft7 Ft8 Ft9
; Ft3 Ft4 Ft5 Ft6 Ft7 Ft8 Ft9 FtA
; Ft4 Ft5 Ft6 Ft7 Ft8 Ft9 FtA FtB
; Ft5 Ft6 Ft7 Ft8 Ft9 FtA FtB FtC
; Ft6 Ft7 Ft8 Ft9 FtA FtB FtC FtD
; Ft7 Ft8 Ft9 FtA FtB FtC FtD FtE
; Ft8 Ft9 FtA FtB FtC FtD FtE FtF
    mova        m0, [r2+16]
    movu        m2, [r2+17]
    pslldq      m1, m0, 1
    pavgb       m3, m0, m2              ; Gt1 Gt2 Gt3 Gt4 Gt5 Gt6 Gt7 Gt8 Gt9 GtA GtB ___ ___ ___ ___ ___
    PRED4x4_LOWPASS m0, m1, m2, m0, tmp ; ___ Ft1 Ft2 Ft3 Ft4 Ft5 Ft6 Ft7 Ft8 Ft9 FtA FtB FtC FtD FtE FtF
    pshufb      m1, m0, [off(intra8x9_ddl1)]
    pshufb      m2, m0, [off(intra8x9_ddl2)]
    mova pred(3,0), m1
    psadbw      m1, fenc02
    mova pred(3,1), m2
    psadbw      m2, fenc13
    paddw       m1, m2
    pshufb      m2, m0, [off(intra8x9_ddl3)]
    mova pred(3,2), m2
    psadbw      m2, fenc46
    paddw       m1, m2
    pshufb      m2, m0, [off(intra8x9_ddl4)]
    mova pred(3,3), m2
    psadbw      m2, fenc57
    paddw       m1, m2
    movhlps     m2, m1
    paddw       m1, m2
    movd    [r4+6], m1

; vl
; Gt1 Gt2 Gt3 Gt4 Gt5 Gt6 Gt7 Gt8
; Ft1 Ft2 Ft3 Ft4 Ft5 Ft6 Ft7 Ft8
; Gt2 Gt3 Gt4 Gt5 Gt6 Gt7 Gt8 Gt9
; Ft2 Ft3 Ft4 Ft5 Ft6 Ft7 Ft8 Ft9
; Gt3 Gt4 Gt5 Gt6 Gt7 Gt8 Gt9 GtA
; Ft3 Ft4 Ft5 Ft6 Ft7 Ft8 Ft9 FtA
; Gt4 Gt5 Gt6 Gt7 Gt8 Gt9 GtA GtB
; Ft4 Ft5 Ft6 Ft7 Ft8 Ft9 FtA FtB
    pshufb      m1, m3, [off(intra8x9_vl1)]
    pshufb      m2, m0, [off(intra8x9_vl2)]
    pshufb      m3, m3, [off(intra8x9_vl3)]
    pshufb      m0, m0, [off(intra8x9_vl4)]
    mova pred(7,0), m1
    psadbw      m1, fenc02
    mova pred(7,1), m2
    psadbw      m2, fenc13
    mova pred(7,2), m3
    psadbw      m3, fenc46
    mova pred(7,3), m0
    psadbw      m0, fenc57
    paddw       m1, m2
    paddw       m0, m3
    paddw       m0, m1
    movhlps     m1, m0
    paddw       m0, m1
%if cpuflag(sse4)
    pextrw [r4+14], m0, 0
%else
    movd       r5d, m0
    mov    [r4+14], r5w
    lea         r5, [rsp+padbase+0x100]
%endif

; ddr
; Flt Ft0 Ft1 Ft2 Ft3 Ft4 Ft5 Ft6
; Fl0 Flt Ft0 Ft1 Ft2 Ft3 Ft4 Ft5
; Fl1 Fl0 Flt Ft0 Ft1 Ft2 Ft3 Ft4
; Fl2 Fl1 Fl0 Flt Ft0 Ft1 Ft2 Ft3
; Fl3 Fl2 Fl1 Fl0 Flt Ft0 Ft1 Ft2
; Fl4 Fl3 Fl2 Fl1 Fl0 Flt Ft0 Ft1
; Fl5 Fl4 Fl3 Fl2 Fl1 Fl0 Flt Ft0
; Fl6 Fl5 Fl4 Fl3 Fl2 Fl1 Fl0 Flt
    movu        m2, [r2+8]
    movu        m0, [r2+7]
    movu        m1, [r2+6]
    pavgb       m3, m2, m0              ; Gl6 Gl5 Gl4 Gl3 Gl2 Gl1 Gl0 Glt Gt0 Gt1 Gt2 Gt3 Gt4 Gt5 Gt6 Gt7
    PRED4x4_LOWPASS m0, m1, m2, m0, tmp ; Fl7 Fl6 Fl5 Fl4 Fl3 Fl2 Fl1 Fl0 Flt Ft0 Ft1 Ft2 Ft3 Ft4 Ft5 Ft6
    pshufb      m1, m0, [off(intra8x9_ddr1)]
    pshufb      m2, m0, [off(intra8x9_ddr2)]
    mova pred(4,0), m1
    psadbw      m1, fenc02
    mova pred(4,1), m2
    psadbw      m2, fenc13
    paddw       m1, m2
    pshufb      m2, m0, [off(intra8x9_ddr3)]
    mova pred(4,2), m2
    psadbw      m2, fenc46
    paddw       m1, m2
    pshufb      m2, m0, [off(intra8x9_ddr4)]
    mova pred(4,3), m2
    psadbw      m2, fenc57
    paddw       m1, m2
    movhlps     m2, m1
    paddw       m1, m2
    movd    [r4+8], m1

    add         r0, 256
    add         r5, 0xC0
    %define off(m) (r0+m-(intra8x9_h1+256+128))
    %define pred(i,j) [r5+i*0x40+j*0x10-0x1C0]

; vr
; Gt0 Gt1 Gt2 Gt3 Gt4 Gt5 Gt6 Gt7
; Flt Ft0 Ft1 Ft2 Ft3 Ft4 Ft5 Ft6
; Fl0 Gt0 Gt1 Gt2 Gt3 Gt4 Gt5 Gt6
; Fl1 Flt Ft0 Ft1 Ft2 Ft3 Ft4 Ft5
; Fl2 Fl0 Gt0 Gt1 Gt2 Gt3 Gt4 Gt5
; Fl3 Fl1 Flt Ft0 Ft1 Ft2 Ft3 Ft4
; Fl4 Fl2 Fl0 Gt0 Gt1 Gt2 Gt3 Gt4
; Fl5 Fl3 Fl1 Flt Ft0 Ft1 Ft2 Ft3
    movsd       m2, m3, m0 ; Fl7 Fl6 Fl5 Fl4 Fl3 Fl2 Fl1 Fl0 Gt0 Gt1 Gt2 Gt3 Gt4 Gt5 Gt6 Gt7
    pshufb      m1, m2, [off(intra8x9_vr1)]
    pshufb      m2, m2, [off(intra8x9_vr3)]
    mova pred(5,0), m1
    psadbw      m1, fenc02
    mova pred(5,2), m2
    psadbw      m2, fenc46
    paddw       m1, m2
    pshufb      m2, m0, [off(intra8x9_vr2)]
    mova pred(5,1), m2
    psadbw      m2, fenc13
    paddw       m1, m2
    pshufb      m2, m0, [off(intra8x9_vr4)]
    mova pred(5,3), m2
    psadbw      m2, fenc57
    paddw       m1, m2
    movhlps     m2, m1
    paddw       m1, m2
    movd   [r4+10], m1

; hd
; Glt Flt Ft0 Ft1 Ft2 Ft3 Ft4 Ft5
; Gl0 Fl0 Glt Flt Ft0 Ft1 Ft2 Ft3
; Gl1 Fl1 Gl0 Fl0 Glt Flt Ft0 Ft1
; Gl2 Fl2 Gl1 Fl1 Gl0 Fl0 Glt Flt
; Gl3 Fl3 Gl2 Fl2 Gl1 Fl1 Gl0 Fl0
; Gl4 Fl4 Gl3 Fl3 Gl2 Fl2 Gl1 Fl1
; Gl5 Fl5 Gl4 Fl4 Gl3 Fl3 Gl2 Fl2
; Gl6 Fl6 Gl5 Fl5 Gl4 Fl4 Gl3 Fl3
    pshufd      m2, m3, q0001
%if cpuflag(sse4)
    pblendw     m2, m0, q3330 ; Gl2 Gl1 Gl0 Glt ___ Fl2 Fl1 Fl0 Flt Ft0 Ft1 Ft2 Ft3 Ft4 Ft5 ___
%else
    movss       m1, m0, m2
    SWAP        1, 2
%endif
    punpcklbw   m0, m3        ; Fl7 Gl6 Fl6 Gl5 Fl5 Gl4 Fl4 Gl3 Fl3 Gl2 Fl2 Gl1 Fl1 Gl0 Fl0 ___
    pshufb      m1, m2, [off(intra8x9_hd1)]
    pshufb      m2, m2, [off(intra8x9_hd2)]
    mova pred(6,0), m1
    psadbw      m1, fenc02
    mova pred(6,1), m2
    psadbw      m2, fenc13
    paddw       m1, m2
    pshufb      m2, m0, [off(intra8x9_hd3)]
    pshufb      m3, m0, [off(intra8x9_hd4)]
    mova pred(6,2), m2
    psadbw      m2, fenc46
    mova pred(6,3), m3
    psadbw      m3, fenc57
    paddw       m1, m2
    paddw       m1, m3
    movhlps     m2, m1
    paddw       m1, m2
    ; don't just store to [r4+12]. this is too close to the load of dqword [r4] and would cause a forwarding stall
    pslldq      m1, 12
    SWAP        3, 1

; hu
; Gl0 Fl1 Gl1 Fl2 Gl2 Fl3 Gl3 Fl4
; Gl1 Fl2 Gl2 Fl3 Gl3 Fl4 Gl4 Fl5
; Gl2 Fl3 Gl3 Gl3 Gl4 Fl5 Gl5 Fl6
; Gl3 Gl3 Gl4 Fl5 Gl5 Fl6 Gl6 Fl7
; Gl4 Fl5 Gl5 Fl6 Gl6 Fl7 Gl7 Gl7
; Gl5 Fl6 Gl6 Fl7 Gl7 Gl7 Gl7 Gl7
; Gl6 Fl7 Gl7 Gl7 Gl7 Gl7 Gl7 Gl7
; Gl7 Gl7 Gl7 Gl7 Gl7 Gl7 Gl7 Gl7
%if cpuflag(sse4)
    pinsrb      m0, [r2+7], 15 ; Gl7
%else
    movd        m1, [r2+7]
    pslldq      m0, 1
    palignr     m1, m0, 1
    SWAP        0, 1
%endif
    pshufb      m1, m0, [off(intra8x9_hu1)]
    pshufb      m2, m0, [off(intra8x9_hu2)]
    mova pred(8,0), m1
    psadbw      m1, fenc02
    mova pred(8,1), m2
    psadbw      m2, fenc13
    paddw       m1, m2
    pshufb      m2, m0, [off(intra8x9_hu3)]
    pshufb      m0, m0, [off(intra8x9_hu4)]
    mova pred(8,2), m2
    psadbw      m2, fenc46
    mova pred(8,3), m0
    psadbw      m0, fenc57
    paddw       m1, m2
    paddw       m1, m0
    movhlps     m2, m1
    paddw       m1, m2
    movd       r2d, m1

    movu        m0, [r3]
    por         m3, [r4]
    paddw       m0, m3
    mova      [r4], m0
    movzx      r5d, word [r3+16]
    add        r2d, r5d
    mov    [r4+16], r2w

%if cpuflag(sse4)
    phminposuw m0, m0 ; v,h,dc,ddl,ddr,vr,hd,vl
    movd      eax, m0
%else
    ; 8x8 sad is up to 14 bits; +bitcosts and saturate -> 14 bits; pack with 2 bit index
    paddusw    m0, m0
    paddusw    m0, m0
    paddw      m0, [off(pw_s00112233)]
    movhlps    m1, m0
    pminsw     m0, m1
    pshuflw    m1, m0, q0032
    pminsw     m0, m1
    movd      eax, m0
    ; repack with 3 bit index
    xor       eax, 0x80008000
    movzx     r3d, ax
    shr       eax, 15
    add       r3d, r3d
    or        eax, 1
    cmp       eax, r3d
    cmovg     eax, r3d
    ; reverse to phminposuw order
    mov       r3d, eax
    and       eax, 7
    shr       r3d, 3
    shl       eax, 16
    or        eax, r3d
%endif
    add       r2d, 8<<16
    cmp        ax, r2w
    cmovg     eax, r2d

    mov       r2d, eax
    shr       r2d, 16
    shl       r2d, 6
    add        r1, 4*FDEC_STRIDE
    mova       m0, [rsp+padbase+r2+0x00]
    mova       m1, [rsp+padbase+r2+0x10]
    mova       m2, [rsp+padbase+r2+0x20]
    mova       m3, [rsp+padbase+r2+0x30]
    movq   [r1+FDEC_STRIDE*-4], m0
    movhps [r1+FDEC_STRIDE*-2], m0
    movq   [r1+FDEC_STRIDE*-3], m1
    movhps [r1+FDEC_STRIDE*-1], m1
    movq   [r1+FDEC_STRIDE* 0], m2
    movhps [r1+FDEC_STRIDE* 2], m2
    movq   [r1+FDEC_STRIDE* 1], m3
    movhps [r1+FDEC_STRIDE* 3], m3
    ADD       rsp, pad
    RET

%if ARCH_X86_64
;-----------------------------------------------------------------------------
; int intra_sa8d_x9_8x8( uint8_t *fenc, uint8_t *fdec, uint8_t edge[36], uint16_t *bitcosts, uint16_t *satds )
;-----------------------------------------------------------------------------
cglobal intra_sa8d_x9_8x8, 5,6,16
    %assign pad 0x2c0+0x10-gprsize-(stack_offset&15)
    %define fenc_buf rsp
    %define pred_buf rsp+0x80
    SUB        rsp, pad
    mova       m15, [hmul_8p]
    pxor        m8, m8
%assign %%i 0
%rep 8
    movddup     m %+ %%i, [r0+%%i*FENC_STRIDE]
    pmaddubsw   m9, m %+ %%i, m15
    punpcklbw   m %+ %%i, m8
    mova [fenc_buf+%%i*0x10], m9
%assign %%i %%i+1
%endrep

    ; save instruction size: avoid 4-byte memory offsets
    lea         r0, [intra8x9_h1+0x80]
    %define off(m) (r0+m-(intra8x9_h1+0x80))
    lea         r5, [pred_buf+0x80]

; v, h, dc
    HADAMARD8_2D 0, 1, 2, 3, 4, 5, 6, 7, 8
    pabsw      m11, m1
%assign %%i 2
%rep 6
    pabsw       m8, m %+ %%i
    paddw      m11, m8
%assign %%i %%i+1
%endrep

    ; 1D hadamard of edges
    movq        m8, [r2+7]
    movddup     m9, [r2+16]
    mova [r5-0x80], m9
    mova [r5-0x70], m9
    mova [r5-0x60], m9
    mova [r5-0x50], m9
    punpcklwd   m8, m8
    pshufb      m9, [intrax3_shuf]
    pmaddubsw   m8, [pb_pppm]
    pmaddubsw   m9, [pb_pppm]
    HSUMSUB2 psignw, m8, m9, m12, m13, m9, q1032, [pw_ppppmmmm]
    HSUMSUB2 psignw, m8, m9, m12, m13, m9, q2301, [pw_ppmmppmm]

    ; dc
    paddw      m10, m8, m9
    paddw      m10, [pw_8]
    pand       m10, [sw_f0]
    psrlw      m12, m10, 4
    psllw      m10, 2
    pxor       m13, m13
    pshufb     m12, m13
    mova [r5+0x00], m12
    mova [r5+0x10], m12
    mova [r5+0x20], m12
    mova [r5+0x30], m12

    ; differences
    psllw       m8, 3 ; left edge
    psubw       m8, m0
    psubw      m10, m0
    pabsw       m8, m8 ; 1x8 sum
    pabsw      m10, m10
    paddw       m8, m11
    paddw      m11, m10
    punpcklwd   m0, m1
    punpcklwd   m2, m3
    punpcklwd   m4, m5
    punpcklwd   m6, m7
    punpckldq   m0, m2
    punpckldq   m4, m6
    punpcklqdq  m0, m4 ; transpose
    psllw       m9, 3  ; top edge
    psrldq     m10, m11, 2 ; 8x7 sum
    psubw       m0, m9 ; 8x1 sum
    pabsw       m0, m0
    paddw      m10, m0

    phaddd     m10, m8 ; logically phaddw, but this is faster and it won't overflow
    psrlw      m11, 1
    psrlw      m10, 1

; store h
    movq        m3, [r2+7]
    pshufb      m0, m3, [off(intra8x9_h1)]
    pshufb      m1, m3, [off(intra8x9_h2)]
    pshufb      m2, m3, [off(intra8x9_h3)]
    pshufb      m3, m3, [off(intra8x9_h4)]
    mova [r5-0x40], m0
    mova [r5-0x30], m1
    mova [r5-0x20], m2
    mova [r5-0x10], m3

; ddl
    mova        m8, [r2+16]
    movu        m2, [r2+17]
    pslldq      m1, m8, 1
    pavgb       m9, m8, m2
    PRED4x4_LOWPASS m8, m1, m2, m8, m3
    pshufb      m0, m8, [off(intra8x9_ddl1)]
    pshufb      m1, m8, [off(intra8x9_ddl2)]
    pshufb      m2, m8, [off(intra8x9_ddl3)]
    pshufb      m3, m8, [off(intra8x9_ddl4)]
    add         r5, 0x40
    call .sa8d
    phaddd     m11, m0

; vl
    pshufb      m0, m9, [off(intra8x9_vl1)]
    pshufb      m1, m8, [off(intra8x9_vl2)]
    pshufb      m2, m9, [off(intra8x9_vl3)]
    pshufb      m3, m8, [off(intra8x9_vl4)]
    add         r5, 0x100
    call .sa8d
    phaddd     m10, m11
    mova       m12, m0

; ddr
    movu        m2, [r2+8]
    movu        m8, [r2+7]
    movu        m1, [r2+6]
    pavgb       m9, m2, m8
    PRED4x4_LOWPASS m8, m1, m2, m8, m3
    pshufb      m0, m8, [off(intra8x9_ddr1)]
    pshufb      m1, m8, [off(intra8x9_ddr2)]
    pshufb      m2, m8, [off(intra8x9_ddr3)]
    pshufb      m3, m8, [off(intra8x9_ddr4)]
    sub         r5, 0xc0
    call .sa8d
    mova       m11, m0

    add         r0, 0x100
    %define off(m) (r0+m-(intra8x9_h1+0x180))

; vr
    movsd       m2, m9, m8
    pshufb      m0, m2, [off(intra8x9_vr1)]
    pshufb      m1, m8, [off(intra8x9_vr2)]
    pshufb      m2, m2, [off(intra8x9_vr3)]
    pshufb      m3, m8, [off(intra8x9_vr4)]
    add         r5, 0x40
    call .sa8d
    phaddd     m11, m0

; hd
%if cpuflag(sse4)
    pshufd      m1, m9, q0001
    pblendw     m1, m8, q3330
%else
    pshufd      m2, m9, q0001
    movss       m1, m8, m2
%endif
    punpcklbw   m8, m9
    pshufb      m0, m1, [off(intra8x9_hd1)]
    pshufb      m1, m1, [off(intra8x9_hd2)]
    pshufb      m2, m8, [off(intra8x9_hd3)]
    pshufb      m3, m8, [off(intra8x9_hd4)]
    add         r5, 0x40
    call .sa8d
    phaddd      m0, m12
    phaddd     m11, m0

; hu
%if cpuflag(sse4)
    pinsrb      m8, [r2+7], 15
%else
    movd        m9, [r2+7]
    pslldq      m8, 1
    palignr     m9, m8, 1
    SWAP        8, 9
%endif
    pshufb      m0, m8, [off(intra8x9_hu1)]
    pshufb      m1, m8, [off(intra8x9_hu2)]
    pshufb      m2, m8, [off(intra8x9_hu3)]
    pshufb      m3, m8, [off(intra8x9_hu4)]
    add         r5, 0x80
    call .sa8d

    pmaddwd     m0, [pw_1]
    phaddw     m10, m11
    movhlps     m1, m0
    paddw       m0, m1
    pshuflw     m1, m0, q0032
    pavgw       m0, m1
    pxor        m2, m2
    pavgw      m10, m2
    movd       r2d, m0

    movu        m0, [r3]
    paddw       m0, m10
    mova      [r4], m0
    movzx      r5d, word [r3+16]
    add        r2d, r5d
    mov    [r4+16], r2w

%if cpuflag(sse4)
    phminposuw m0, m0
    movd      eax, m0
%else
    ; 8x8 sa8d is up to 15 bits; +bitcosts and saturate -> 15 bits; pack with 1 bit index
    paddusw    m0, m0
    paddw      m0, [off(pw_s00001111)]
    movhlps    m1, m0
    pminsw     m0, m1
    pshuflw    m1, m0, q0032
    mova       m2, m0
    pminsw     m0, m1
    pcmpgtw    m2, m1 ; 2nd index bit
    movd      r3d, m0
    movd      r4d, m2
    ; repack with 3 bit index
    xor       r3d, 0x80008000
    and       r4d, 0x00020002
    movzx     eax, r3w
    movzx     r5d, r4w
    shr       r3d, 16
    shr       r4d, 16
    lea       eax, [rax*4+r5]
    lea       r3d, [ r3*4+r4+1]
    cmp       eax, r3d
    cmovg     eax, r3d
    ; reverse to phminposuw order
    mov       r3d, eax
    and       eax, 7
    shr       r3d, 3
    shl       eax, 16
    or        eax, r3d
%endif
    add       r2d, 8<<16
    cmp        ax, r2w
    cmovg     eax, r2d

    mov       r2d, eax
    shr       r2d, 16
    shl       r2d, 6
    add        r1, 4*FDEC_STRIDE
    mova       m0, [pred_buf+r2+0x00]
    mova       m1, [pred_buf+r2+0x10]
    mova       m2, [pred_buf+r2+0x20]
    mova       m3, [pred_buf+r2+0x30]
    movq   [r1+FDEC_STRIDE*-4], m0
    movhps [r1+FDEC_STRIDE*-2], m0
    movq   [r1+FDEC_STRIDE*-3], m1
    movhps [r1+FDEC_STRIDE*-1], m1
    movq   [r1+FDEC_STRIDE* 0], m2
    movhps [r1+FDEC_STRIDE* 2], m2
    movq   [r1+FDEC_STRIDE* 1], m3
    movhps [r1+FDEC_STRIDE* 3], m3
    ADD       rsp, pad
    RET

ALIGN 16
.sa8d:
    %xdefine mret m0
    %xdefine fenc_buf fenc_buf+gprsize
    mova [r5+0x00], m0
    mova [r5+0x10], m1
    mova [r5+0x20], m2
    mova [r5+0x30], m3
    movddup     m4, m0
    movddup     m5, m1
    movddup     m6, m2
    movddup     m7, m3
    punpckhqdq  m0, m0
    punpckhqdq  m1, m1
    punpckhqdq  m2, m2
    punpckhqdq  m3, m3
    PERMUTE 0,4, 1,5, 2,0, 3,1, 4,6, 5,7, 6,2, 7,3
    pmaddubsw   m0, m15
    pmaddubsw   m1, m15
    psubw       m0, [fenc_buf+0x00]
    psubw       m1, [fenc_buf+0x10]
    pmaddubsw   m2, m15
    pmaddubsw   m3, m15
    psubw       m2, [fenc_buf+0x20]
    psubw       m3, [fenc_buf+0x30]
    pmaddubsw   m4, m15
    pmaddubsw   m5, m15
    psubw       m4, [fenc_buf+0x40]
    psubw       m5, [fenc_buf+0x50]
    pmaddubsw   m6, m15
    pmaddubsw   m7, m15
    psubw       m6, [fenc_buf+0x60]
    psubw       m7, [fenc_buf+0x70]
    HADAMARD8_2D_HMUL 0, 1, 2, 3, 4, 5, 6, 7, 13, 14
    paddw       m0, m1
    paddw       m0, m2
    paddw mret, m0, m3
    ret
%endif ; ARCH_X86_64
%endmacro ; INTRA8_X9

; in:  r0=pix, r1=stride, r2=stride*3, r3=tmp, m6=mask_ac4, m7=0
; out: [tmp]=hadamard4, m0=satd
INIT_MMX mmx2
cglobal hadamard_ac_4x4
%if HIGH_BIT_DEPTH
    mova      m0, [r0]
    mova      m1, [r0+r1]
    mova      m2, [r0+r1*2]
    mova      m3, [r0+r2]
%else ; !HIGH_BIT_DEPTH
    movh      m0, [r0]
    movh      m1, [r0+r1]
    movh      m2, [r0+r1*2]
    movh      m3, [r0+r2]
    punpcklbw m0, m7
    punpcklbw m1, m7
    punpcklbw m2, m7
    punpcklbw m3, m7
%endif ; HIGH_BIT_DEPTH
    HADAMARD4_2D 0, 1, 2, 3, 4
    mova [r3],    m0
    mova [r3+8],  m1
    mova [r3+16], m2
    mova [r3+24], m3
    ABSW      m0, m0, m4
    ABSW      m1, m1, m4
    pand      m0, m6
    ABSW      m2, m2, m4
    ABSW      m3, m3, m4
    paddw     m0, m1
    paddw     m2, m3
    paddw     m0, m2
    SAVE_MM_PERMUTATION
    ret

cglobal hadamard_ac_2x2max
    mova      m0, [r3+0x00]
    mova      m1, [r3+0x20]
    mova      m2, [r3+0x40]
    mova      m3, [r3+0x60]
    sub       r3, 8
    SUMSUB_BADC w, 0, 1, 2, 3, 4
    ABSW2 m0, m2, m0, m2, m4, m5
    ABSW2 m1, m3, m1, m3, m4, m5
    HADAMARD 0, max, 0, 2, 4, 5
    HADAMARD 0, max, 1, 3, 4, 5
%if HIGH_BIT_DEPTH
    pmaddwd   m0, m7
    pmaddwd   m1, m7
    paddd     m6, m0
    paddd     m6, m1
%else ; !HIGH_BIT_DEPTH
    paddw     m7, m0
    paddw     m7, m1
%endif ; HIGH_BIT_DEPTH
    SAVE_MM_PERMUTATION
    ret

%macro AC_PREP 2
%if HIGH_BIT_DEPTH
    pmaddwd %1, %2
%endif
%endmacro

%macro AC_PADD 3
%if HIGH_BIT_DEPTH
    AC_PREP %2, %3
    paddd   %1, %2
%else
    paddw   %1, %2
%endif ; HIGH_BIT_DEPTH
%endmacro

cglobal hadamard_ac_8x8
    mova      m6, [mask_ac4]
%if HIGH_BIT_DEPTH
    mova      m7, [pw_1]
%else
    pxor      m7, m7
%endif ; HIGH_BIT_DEPTH
    call hadamard_ac_4x4_mmx2
    add       r0, 4*SIZEOF_PIXEL
    add       r3, 32
    mova      m5, m0
    AC_PREP   m5, m7
    call hadamard_ac_4x4_mmx2
    lea       r0, [r0+4*r1]
    add       r3, 64
    AC_PADD   m5, m0, m7
    call hadamard_ac_4x4_mmx2
    sub       r0, 4*SIZEOF_PIXEL
    sub       r3, 32
    AC_PADD   m5, m0, m7
    call hadamard_ac_4x4_mmx2
    AC_PADD   m5, m0, m7
    sub       r3, 40
    mova [rsp+gprsize+8], m5 ; save satd
%if HIGH_BIT_DEPTH
    pxor      m6, m6
%endif
%rep 3
    call hadamard_ac_2x2max_mmx2
%endrep
    mova      m0, [r3+0x00]
    mova      m1, [r3+0x20]
    mova      m2, [r3+0x40]
    mova      m3, [r3+0x60]
    SUMSUB_BADC w, 0, 1, 2, 3, 4
    HADAMARD 0, sumsub, 0, 2, 4, 5
    ABSW2 m1, m3, m1, m3, m4, m5
    ABSW2 m0, m2, m0, m2, m4, m5
    HADAMARD 0, max, 1, 3, 4, 5
%if HIGH_BIT_DEPTH
    pand      m0, [mask_ac4]
    pmaddwd   m1, m7
    pmaddwd   m0, m7
    pmaddwd   m2, m7
    paddd     m6, m1
    paddd     m0, m2
    paddd     m6, m6
    paddd     m0, m6
    SWAP       0,  6
%else ; !HIGH_BIT_DEPTH
    pand      m6, m0
    paddw     m7, m1
    paddw     m6, m2
    paddw     m7, m7
    paddw     m6, m7
%endif ; HIGH_BIT_DEPTH
    mova [rsp+gprsize], m6 ; save sa8d
    SWAP       0,  6
    SAVE_MM_PERMUTATION
    ret

%macro HADAMARD_AC_WXH_SUM_MMX 2
    mova    m1, [rsp+1*mmsize]
%if HIGH_BIT_DEPTH
%if %1*%2 >= 128
    paddd   m0, [rsp+2*mmsize]
    paddd   m1, [rsp+3*mmsize]
%endif
%if %1*%2 == 256
    mova    m2, [rsp+4*mmsize]
    paddd   m1, [rsp+5*mmsize]
    paddd   m2, [rsp+6*mmsize]
    mova    m3, m0
    paddd   m1, [rsp+7*mmsize]
    paddd   m0, m2
%endif
    psrld   m0, 1
    HADDD   m0, m2
    psrld   m1, 1
    HADDD   m1, m3
%else ; !HIGH_BIT_DEPTH
%if %1*%2 >= 128
    paddusw m0, [rsp+2*mmsize]
    paddusw m1, [rsp+3*mmsize]
%endif
%if %1*%2 == 256
    mova    m2, [rsp+4*mmsize]
    paddusw m1, [rsp+5*mmsize]
    paddusw m2, [rsp+6*mmsize]
    mova    m3, m0
    paddusw m1, [rsp+7*mmsize]
    pxor    m3, m2
    pand    m3, [pw_1]
    pavgw   m0, m2
    psubusw m0, m3
    HADDUW  m0, m2
%else
    psrlw   m0, 1
    HADDW   m0, m2
%endif
    psrlw   m1, 1
    HADDW   m1, m3
%endif ; HIGH_BIT_DEPTH
%endmacro

%macro HADAMARD_AC_WXH_MMX 2
cglobal pixel_hadamard_ac_%1x%2, 2,4
    %assign pad 16-gprsize-(stack_offset&15)
    %define ysub r1
    FIX_STRIDES r1
    sub  rsp, 16+128+pad
    lea  r2, [r1*3]
    lea  r3, [rsp+16]
    call hadamard_ac_8x8_mmx2
%if %2==16
    %define ysub r2
    lea  r0, [r0+r1*4]
    sub  rsp, 16
    call hadamard_ac_8x8_mmx2
%endif
%if %1==16
    neg  ysub
    sub  rsp, 16
    lea  r0, [r0+ysub*4+8*SIZEOF_PIXEL]
    neg  ysub
    call hadamard_ac_8x8_mmx2
%if %2==16
    lea  r0, [r0+r1*4]
    sub  rsp, 16
    call hadamard_ac_8x8_mmx2
%endif
%endif
    HADAMARD_AC_WXH_SUM_MMX %1, %2
    movd edx, m0
    movd eax, m1
    shr  edx, 1
%if ARCH_X86_64
    shl  rdx, 32
    add  rax, rdx
%endif
    add  rsp, 128+%1*%2/4+pad
    RET
%endmacro ; HADAMARD_AC_WXH_MMX

HADAMARD_AC_WXH_MMX 16, 16
HADAMARD_AC_WXH_MMX  8, 16
HADAMARD_AC_WXH_MMX 16,  8
HADAMARD_AC_WXH_MMX  8,  8

%assign hadac_vstack 0
%macro LOAD_INC_8x4W_SSE2 5
%if HIGH_BIT_DEPTH && mmsize == 32 && hadac_vstack ; lane 1 = the block 8 rows down, at r4
    movu      xm%1, [r0]
    vinserti128 m%1, m%1, [r4], 1
    movu      xm%2, [r0+r1]
    vinserti128 m%2, m%2, [r4+r1], 1
    movu      xm%3, [r0+r1*2]
    vinserti128 m%3, m%3, [r4+r1*2], 1
    movu      xm%4, [r0+r2]
    vinserti128 m%4, m%4, [r4+r2], 1
%ifidn %1, 0
    lea       r0, [r0+r1*4]
    lea       r4, [r4+r1*4]
%endif
%elif HIGH_BIT_DEPTH
    movu      m%1, [r0]
    movu      m%2, [r0+r1]
    movu      m%3, [r0+r1*2]
    movu      m%4, [r0+r2]
%ifidn %1, 0
    lea       r0, [r0+r1*4]
%endif
%else ; !HIGH_BIT_DEPTH
    movh      m%1, [r0]
    movh      m%2, [r0+r1]
    movh      m%3, [r0+r1*2]
    movh      m%4, [r0+r2]
%ifidn %1, 0
    lea       r0, [r0+r1*4]
%endif
    punpcklbw m%1, m%5
    punpcklbw m%2, m%5
    punpcklbw m%3, m%5
    punpcklbw m%4, m%5
%endif ; HIGH_BIT_DEPTH
%endmacro

%macro LOAD_INC_8x4W_SSSE3 5
    LOAD_DUP_4x8P %3, %4, %1, %2, [r0+r1*2], [r0+r2], [r0], [r0+r1]
%ifidn %1, 0
    lea       r0, [r0+r1*4]
%endif
    HSUMSUB %1, %2, %3, %4, %5
%endmacro

%macro HADAMARD_AC_SSE2 0-1 ; %1: suffix of the internal (v: vertically stacked blocks)
; in:  r0=pix, r1=stride, r2=stride*3
; out: [esp+16]=sa8d, [esp+32]=satd, r0+=stride*4
cglobal hadamard_ac_8x8%1
%if ARCH_X86_64
    %define spill0 m8
    %define spill1 m9
    %define spill2 m10
%else
    %define spill0 [rsp+gprsize]
    %define spill1 [rsp+gprsize+mmsize]
    %define spill2 [rsp+gprsize+mmsize*2]
%endif
%if HIGH_BIT_DEPTH
    %define vertical 1
%elif cpuflag(ssse3) && notcpuflag(atom)
    %define vertical 0
    ;LOAD_INC loads sumsubs
    mova      m7, [hmul_8p]
%else
    %define vertical 1
    ;LOAD_INC only unpacks to words
    pxor      m7, m7
%endif
    LOAD_INC_8x4W 0, 1, 2, 3, 7
%if vertical
    HADAMARD4_2D_SSE 0, 1, 2, 3, 4
%else
    HADAMARD4_V 0, 1, 2, 3, 4
%endif
    mova  spill0, m1
    SWAP 1, 7
    LOAD_INC_8x4W 4, 5, 6, 7, 1
%if vertical
    HADAMARD4_2D_SSE 4, 5, 6, 7, 1
%else
    HADAMARD4_V 4, 5, 6, 7, 1
    ; FIXME SWAP
    mova      m1, spill0
    mova      spill0, m6
    mova      spill1, m7
    HADAMARD 1, sumsub, 0, 1, 6, 7
    HADAMARD 1, sumsub, 2, 3, 6, 7
    mova      m6, spill0
    mova      m7, spill1
    mova      spill0, m1
    mova      spill1, m0
    HADAMARD 1, sumsub, 4, 5, 1, 0
    HADAMARD 1, sumsub, 6, 7, 1, 0
    mova      m0, spill1
%endif
    mova  spill1, m2
    mova  spill2, m3
    ABSW      m1, m0, m0
    ABSW      m2, m4, m4
    ABSW      m3, m5, m5
    paddw     m1, m2
    SUMSUB_BA w, 0, 4
%if vertical
    pand      m1, [mask_ac4]
%else
    pand      m1, [mask_ac4b]
%endif
%if HIGH_BIT_DEPTH && cpuflag(avx512icl)
    ; vpdpwssd for pmaddwd + paddd, two chains; m12 = pw_1, m13 = pw_2
    vpbroadcastd m12, [pw_1]
    pmaddwd   m1, m12
    ABSW      m2, spill0
    pmaddwd  m11, m3, m12
    ABSW      m3, spill1
    {evex} vpdpwssd  m1, m2, m12
    ABSW      m2, spill2
    {evex} vpdpwssd m11, m3, m12
    ABSW      m3, m6, m6
    {evex} vpdpwssd  m1, m2, m12
    ABSW      m2, m7, m7
    {evex} vpdpwssd m11, m3, m12
    {evex} vpdpwssd  m1, m2, m12
    paddd     m1, m11
%else
    AC_PREP   m1, [pw_1]
    ABSW      m2, spill0
    AC_PADD   m1, m3, [pw_1]
    ABSW      m3, spill1
    AC_PADD   m1, m2, [pw_1]
    ABSW      m2, spill2
    AC_PADD   m1, m3, [pw_1]
    ABSW      m3, m6, m6
    AC_PADD   m1, m2, [pw_1]
    ABSW      m2, m7, m7
    AC_PADD   m1, m3, [pw_1]
    AC_PADD   m1, m2, [pw_1]
%endif
    paddw     m3, m7, spill2
    psubw     m7, spill2
    mova  [rsp+gprsize+mmsize*2], m1 ; save satd
    paddw     m2, m6, spill1
    psubw     m6, spill1
    paddw     m1, m5, spill0
    psubw     m5, spill0
    %assign %%x 2
%if vertical
    %assign %%x 4
%endif
    mova  spill1, m4
    HADAMARD %%x, amax, 3, 7, 4
    HADAMARD %%x, amax, 2, 6, 7, 4
    mova      m4, spill1
    HADAMARD %%x, amax, 1, 5, 6, 7
    HADAMARD %%x, sumsub, 0, 4, 5, 6
%if HIGH_BIT_DEPTH && cpuflag(avx512icl)
    paddw    m13, m12, m12
    pmaddwd   m2, m13
    {evex} vpdpwssd  m2, m3, m13
    ABSW      m4, m4, m7
    pand      m0, [mask_ac8]
    ABSW      m0, m0, m7
    pmaddwd   m4, m12
    {evex} vpdpwssd  m4, m0, m12
    {evex} vpdpwssd  m2, m1, m13
    paddd     m2, m4
%else
    AC_PREP   m2, [pw_1]
    AC_PADD   m2, m3, [pw_1]
    AC_PADD   m2, m1, [pw_1]
%if HIGH_BIT_DEPTH
    paddd     m2, m2
%else
    paddw     m2, m2
%endif ; HIGH_BIT_DEPTH
    ABSW      m4, m4, m7
    pand      m0, [mask_ac8]
    ABSW      m0, m0, m7
    AC_PADD   m2, m4, [pw_1]
    AC_PADD   m2, m0, [pw_1]
%endif
    mova [rsp+gprsize+mmsize], m2 ; save sa8d
    SWAP       0, 2
    SAVE_MM_PERMUTATION
    ret

%ifnidn %1, v
HADAMARD_AC_WXH_SSE2 16, 16
HADAMARD_AC_WXH_SSE2 16,  8
%if mmsize <= 16
HADAMARD_AC_WXH_SSE2  8, 16
HADAMARD_AC_WXH_SSE2  8,  8
%endif
%endif
%endmacro ; HADAMARD_AC_SSE2

%macro HADAMARD_AC_WXH_SUM_SSE2 2
    mova    m1, [rsp+2*mmsize]
%if HIGH_BIT_DEPTH
%if %1*%2*16/mmsize >= 128
    paddd   m0, [rsp+3*mmsize]
    paddd   m1, [rsp+4*mmsize]
%endif
%if %1*%2*16/mmsize == 256
    paddd   m0, [rsp+5*mmsize]
    paddd   m1, [rsp+6*mmsize]
    paddd   m0, [rsp+7*mmsize]
    paddd   m1, [rsp+8*mmsize]
    psrld   m0, 1
%endif
%if mmsize==32
    vextracti128 xm2, m0, 1
    vextracti128 xm3, m1, 1
    paddd   xm0, xm2
    paddd   xm1, xm3
%endif
    HADDD  xm0, xm2
    HADDD  xm1, xm3
%else ; !HIGH_BIT_DEPTH
%if %1*%2*16/mmsize >= 128
    paddusw m0, [rsp+3*mmsize]
    paddusw m1, [rsp+4*mmsize]
%endif
%if %1*%2*16/mmsize == 256
    paddusw m0, [rsp+5*mmsize]
    paddusw m1, [rsp+6*mmsize]
    paddusw m0, [rsp+7*mmsize]
    paddusw m1, [rsp+8*mmsize]
    psrlw   m0, 1
%endif
%if mmsize==32
    vextracti128 xm2, m0, 1
    vextracti128 xm3, m1, 1
    paddusw xm0, xm2
    paddusw xm1, xm3
%endif
    HADDUW xm0, xm2
    HADDW  xm1, xm3
%endif ; HIGH_BIT_DEPTH
%endmacro

; struct { int satd, int sa8d; } pixel_hadamard_ac_16x16( uint8_t *pix, int stride )
%macro HADAMARD_AC_WXH_SSE2 2
cglobal pixel_hadamard_ac_%1x%2, 2,4,11+3*cpuflag(avx512icl)
    %define ysub r1
    FIX_STRIDES r1
    mov   r3, rsp
    and  rsp, ~(mmsize-1)
    sub  rsp, mmsize*3
    lea   r2, [r1*3]
    call hadamard_ac_8x8
%if %2==16
    %define ysub r2
    lea   r0, [r0+r1*4]
    sub  rsp, mmsize*2
    call hadamard_ac_8x8
%endif
%if %1==16 && mmsize <= 16
    neg  ysub
    sub  rsp, mmsize*2
    lea   r0, [r0+ysub*4+8*SIZEOF_PIXEL]
    neg  ysub
    call hadamard_ac_8x8
%if %2==16
    lea   r0, [r0+r1*4]
    sub  rsp, mmsize*2
    call hadamard_ac_8x8
%endif
%endif
    HADAMARD_AC_WXH_SUM_SSE2 %1, %2
    movd edx, xm0
    movd eax, xm1
    shr  edx, 2 - (%1*%2*16/mmsize >> 8)
    shr  eax, 1
%if ARCH_X86_64
    shl  rdx, 32
    add  rax, rdx
%endif
    mov  rsp, r3
    RET
%endmacro ; HADAMARD_AC_WXH_SSE2

; instantiate satds

%if ARCH_X86_64 == 0 && HIGH_BIT_DEPTH == 0
cextern pixel_sa8d_8x8_internal_mmx2
INIT_MMX mmx2
SA8D
%endif

%define TRANS TRANS_SSE2
%define DIFFOP DIFF_UNPACK_SSE2
%define LOAD_INC_8x4W LOAD_INC_8x4W_SSE2
%define LOAD_SUMSUB_8x4P LOAD_DIFF_8x4P
%define LOAD_SUMSUB_16P  LOAD_SUMSUB_16P_SSE2
%define movdqa movaps ; doesn't hurt pre-nehalem, might as well save size
%define movdqu movups
%define punpcklqdq movlhps
INIT_XMM sse2
SA8D
SATDS_SSE2
%if ARCH_X86_64
SA8D_SATD
%endif
%if HIGH_BIT_DEPTH == 0
INTRA_SA8D_SSE2
%endif
INIT_MMX mmx2
INTRA_X3_MMX
INIT_XMM sse2
HADAMARD_AC_SSE2

%if HIGH_BIT_DEPTH == 0
INIT_XMM ssse3,atom
SATDS_SSE2
SA8D
HADAMARD_AC_SSE2
%if ARCH_X86_64
SA8D_SATD
%endif
%endif

%define DIFFOP DIFF_SUMSUB_SSSE3
%define LOAD_DUP_4x8P LOAD_DUP_4x8P_CONROE
%if HIGH_BIT_DEPTH == 0
%define LOAD_INC_8x4W LOAD_INC_8x4W_SSSE3
%define LOAD_SUMSUB_8x4P LOAD_SUMSUB_8x4P_SSSE3
%define LOAD_SUMSUB_16P  LOAD_SUMSUB_16P_SSSE3
%endif
INIT_XMM ssse3
SATDS_SSE2
SA8D
HADAMARD_AC_SSE2
%if ARCH_X86_64
SA8D_SATD
%endif
%if HIGH_BIT_DEPTH == 0
INTRA_X9
INTRA8_X9
%endif
%undef movdqa ; nehalem doesn't like movaps
%undef movdqu ; movups
%undef punpcklqdq ; or movlhps
%if HIGH_BIT_DEPTH == 0
INIT_MMX ssse3
INTRA_X3_MMX
%endif

%define TRANS TRANS_SSE4
%define LOAD_DUP_4x8P LOAD_DUP_4x8P_PENRYN
INIT_XMM sse4
SATDS_SSE2
SA8D
HADAMARD_AC_SSE2
%if ARCH_X86_64
SA8D_SATD
%endif
%if HIGH_BIT_DEPTH == 0
INTRA_X9
INTRA8_X9
%endif

; Sandy/Ivy Bridge and Bulldozer do movddup in the load unit, so
; it's effectively free.
%define LOAD_DUP_4x8P LOAD_DUP_4x8P_CONROE
INIT_XMM avx
SATDS_SSE2
SA8D
%if ARCH_X86_64
SA8D_SATD
%endif
%if HIGH_BIT_DEPTH == 0
INTRA_X9
INTRA8_X9
%endif
HADAMARD_AC_SSE2

%define TRANS TRANS_XOP
INIT_XMM xop
SATDS_SSE2
SA8D
%if ARCH_X86_64
SA8D_SATD
%endif
%if HIGH_BIT_DEPTH == 0
INTRA_X9
; no xop INTRA8_X9. it's slower than avx on bulldozer. dunno why.
%endif
HADAMARD_AC_SSE2

;-----------------------------------------------------------------------------
; uint64_t pixel_hadamard_ac_8x8( pixel *pix, intptr_t stride )
; Lane 0 holds rows 0-3, lane 1 rows 4-7: the 4x4 transforms and the column
; half stage are lane-local, the row half stage is across lanes. Pixels are
; non-negative, so every value before that last stage fits 15 bits except
; the (masked) DC. 8-bit rows are zero extended to the same layout.
;-----------------------------------------------------------------------------
%macro HADAMARD_AC_8x8_AVX2 0
cglobal pixel_hadamard_ac_8x8, 2,3,8
    FIX_STRIDES r1
    lea          r2, [r1*3]
%if HIGH_BIT_DEPTH
    movu        xm0, [r0]
    movu        xm1, [r0+r1]
    movu        xm2, [r0+r1*2]
    movu        xm3, [r0+r2]
    lea          r0, [r0+r1*4]
    vinserti128  m0, m0, [r0], 1
    vinserti128  m1, m1, [r0+r1], 1
    vinserti128  m2, m2, [r0+r1*2], 1
    vinserti128  m3, m3, [r0+r2], 1
%else
    movq        xm0, [r0]
    movq        xm1, [r0+r1]
    movq        xm2, [r0+r1*2]
    movq        xm3, [r0+r2]
    lea          r0, [r0+r1*4]
    movhps      xm0, [r0]
    movhps      xm1, [r0+r1]
    movhps      xm2, [r0+r1*2]
    movhps      xm3, [r0+r2]
    pmovzxbw     m0, xm0
    pmovzxbw     m1, xm1
    pmovzxbw     m2, xm2
    pmovzxbw     m3, xm3
%endif
    HADAMARD4_2D_SSE 0, 1, 2, 3, 4
    mova         m7, [pw_1]
    pabsw        m4, m0
    pand         m4, [mask_ac4]
    pabsw        m5, m1
    paddw        m4, m5
    pabsw        m5, m2
    paddw        m4, m5
    pabsw        m5, m3
    paddw        m4, m5            ; 4x4 AC, <= 4*8184
    pmaddwd      m4, m7
    HADAMARD 4, sumsub, 0, 1, 5
    HADAMARD 4, sumsub, 2, 3, 5
    pabsw        m1, m1
    pabsw        m2, m2
    pabsw        m3, m3
    vextracti128 xm5, m1, 1
    vextracti128 xm6, m2, 1
    pmaxsw      xm1, xm5
    pmaxsw      xm2, xm6
    vextracti128 xm5, m3, 1
    vextracti128 xm6, m0, 1
    pmaxsw      xm3, xm5
    paddw       xm5, xm0, xm6      ; DC in word 0
    psubw       xm0, xm6
    pand        xm5, [mask_ac8]
    pabsw       xm5, xm5
    pabsw       xm0, xm0
    pmaddwd     xm1, xm7
    pmaddwd     xm2, xm7
    pmaddwd     xm3, xm7
    pmaddwd     xm5, xm7
    pmaddwd     xm0, xm7
    paddd       xm1, xm2
    paddd       xm1, xm3
    paddd       xm1, xm1           ; max(|a|,|b|) is half of |a+b|+|a-b|
    paddd       xm0, xm5
    paddd       xm0, xm1           ; sa8d
    vextracti128 xm1, m4, 1
    paddd       xm4, xm1           ; satd
    phaddd      xm4, xm0
    pshufd      xm0, xm4, q2301
    paddd       xm0, xm4           ; satd satd sa8d sa8d
    movd        eax, xm0
    pextrd      edx, xm0, 2
    shr         eax, 1
    shr         edx, 2
%if ARCH_X86_64
    shl         rdx, 32
    add         rax, rdx
%endif
    RET
%endmacro


;-----------------------------------------------------------------------------
; int pixel_satd_bi_WxH( fenc, pixel *src0, intptr_t stride0, pixel *src1, intptr_t stride1, int weight )
; int pixel_satd_bi4_WxH( fenc, pixel *src0a, pixel *src0b, pixel *src1a, pixel *src1b,
;                         intptr_t stride, int weight )
; satd of mc.avg( src0, src1, weight ) without storing it: pavg at weight 32, else
; clip( (src0*w + src1*(64-w) + 32) >> 6 ), -64 < w < 128. bi4 averages
; src0 = pavg( src0a, src0b ) and src1 = pavg( src1a, src1b ), get_ref's unweighted
; predictions from the hpel planes. fenc: the fenc (FENC_STRIDE) at high bit depth,
; satd_fenc_pre's fenc_pre at 8-bit.
; Sources: bi_p<list><a|b> at row k, bi_q<list><a|b> at row k+4 (8 wide),
; bi_s<list> the stride, bi_t<list> 3*stride.
;-----------------------------------------------------------------------------
; bi_o = offset of row %2 (0-3) in list %1's sources
%macro BI_ROW_OFF 2
%if %2 == 0
    %define bi_o 0
%elif %2 == 1
    %define bi_o bi_s%1
%elif %2 == 2
    %define bi_o 2*bi_s%1
%else
    %define bi_o bi_t%1
%endif
%endmacro

; advance the sources %1 rows
%macro BI_NEXT 1
    lea      bi_p0a, [bi_p0a+%1*bi_s0]
    lea      bi_p1a, [bi_p1a+%1*bi_s1]
%if bi_four
    lea      bi_p0b, [bi_p0b+%1*bi_s0]
    lea      bi_p1b, [bi_p1b+%1*bi_s1]
%endif
%if bi_wide == 0
    lea      bi_q0a, [bi_q0a+%1*bi_s0]
    lea      bi_q1a, [bi_q1a+%1*bi_s1]
%if bi_four
    lea      bi_q0b, [bi_q0b+%1*bi_s0]
    lea      bi_q1b, [bi_q1b+%1*bi_s1]
%endif
%endif
%endmacro

; the satd pass of rows m0-m3 into m6
%macro BI_SATD_PASS 1 ; 1 for the high bit depth transform
%if cpuflag(avx512icl) && %1 == 0
%if bi_pass
    SATD_ICL_8x4 add
%else
    SATD_ICL_8x4 swap
%endif
%elif bi_pass
    SATD_8x4_SSE %1, 0, 1, 2, 3, 4, 5, 6
%else
    SATD_8x4_SSE %1, 0, 1, 2, 3, 4, 5, 6, swap
%endif
%endmacro

; the function: SATD_BI_BODY height, weighted after the weight dispatch
%macro SATD_BI 3 ; width, height, bi4
%assign bi_four %3
%assign bi_wide 0
%assign bi_big 0
%if %1 == 16
%assign bi_wide 1
%endif
%if %1*%2 == 256
%assign bi_big 1
%endif
%if bi_four
%if bi_wide
cglobal pixel_satd_bi4_%1x%2, 7,8,11
%else
cglobal pixel_satd_bi4_%1x%2, 7,12,11
%endif
    %define bi_p0a r1
    %define bi_p0b r2
    %define bi_p1a r3
    %define bi_p1b r4
    %define bi_s0  r5
    %define bi_s1  r5
    %define bi_t0  r7
    %define bi_t1  r7
    %define bi_q0a r8
    %define bi_q0b r9
    %define bi_q1a r10
    %define bi_q1b r11
    %define bi_wd  r6d
    %define bi_wb  r6b
    FIX_STRIDES r5
%if cpuflag(avx512icl)
    SATD_ICL_KMASK r7d
%endif
    lea       r7, [3*r5]
%if bi_wide == 0
    lea       r8, [r1+4*r5]
    lea       r9, [r2+4*r5]
    lea      r10, [r3+4*r5]
    lea      r11, [r4+4*r5]
%endif
%else
%if bi_wide
cglobal pixel_satd_bi_%1x%2, 6,8,11
%else
cglobal pixel_satd_bi_%1x%2, 6,10,11
%endif
    %define bi_p0a r1
    %define bi_p1a r3
    %define bi_s0  r2
    %define bi_s1  r4
    %define bi_t0  r6
    %define bi_t1  r7
    %define bi_q0a r8
    %define bi_q1a r9
    %define bi_wd  r5d
    %define bi_wb  r5b
    FIX_STRIDES r2, r4
%if cpuflag(avx512icl)
    SATD_ICL_KMASK r6d
%endif
    lea       r6, [3*r2]
    lea       r7, [3*r4]
%if bi_wide == 0
    lea       r8, [r1+4*r2]
    lea       r9, [r3+4*r4]
%endif
%endif
    cmp     bi_wd, 32
    jne .weight
    SATD_BI_BODY %2, 0
.weight:
    SATD_BI_BODY %2, 1
%endmacro

%if HIGH_BIT_DEPTH
;-----------------------------------------------------------------------------
; 10-bit satd, ymm. Each 128-bit lane holds one row of an independent
; 8x4 unit, so the lane-local vertical-mode transform of SATD_8x4_SSE runs on
; 2 units per pass (4 in the zmm intra_satd_x3). Every pass adds at most 2*8184 per word,
; so up to two passes fit signed words and up to four fit unsigned words.
;-----------------------------------------------------------------------------

; m0-m3 = pix1-pix2 rows %1..%1+3 of the units at r0/r2 (lane 0) and r6/r7 (lane 1)
%macro SATD_HBD_LOAD_X 0 ; 8 wide, ymm: lanes = rows i, i+4
    movu         xm0, [r0]
    vinserti128   m0, m0, [r6], 1
    movu         xm4, [r2]
    vinserti128   m4, m4, [r7], 1
    movu         xm1, [r0+r1]
    vinserti128   m1, m1, [r6+r1], 1
    movu         xm5, [r2+r3]
    vinserti128   m5, m5, [r7+r3], 1
    psubw         m0, m4
    psubw         m1, m5
    movu         xm2, [r0+2*r1]
    vinserti128   m2, m2, [r6+2*r1], 1
    movu         xm4, [r2+2*r3]
    vinserti128   m4, m4, [r7+2*r3], 1
    movu         xm3, [r0+r4]
    vinserti128   m3, m3, [r6+r4], 1
    movu         xm5, [r2+r5]
    vinserti128   m5, m5, [r7+r5], 1
    psubw         m2, m4
    psubw         m3, m5
%endmacro

%macro SATD_HBD_LOAD_Y 0 ; 16 wide, ymm: lanes = columns 0-7, 8-15 of one row
    movu          m0, [r0]
    movu          m1, [r0+r1]
    movu          m2, [r0+2*r1]
    movu          m3, [r0+r4]
    psubw         m0, [r2]
    psubw         m1, [r2+r3]
    psubw         m2, [r2+2*r3]
    psubw         m3, [r2+r5]
%endmacro

%macro SATD_HBD_START 0
    FIX_STRIDES r1, r3
    lea       r4, [3*r1]
    lea       r5, [3*r3]
    lea       r6, [r0+4*r1]
    lea       r7, [r2+4*r3]
%endmacro

%macro SATD_HBD_NEXT8 0 ; advance all row pointers by 8 rows
    lea       r0, [r0+8*r1]
    lea       r2, [r2+8*r3]
    lea       r6, [r6+8*r1]
    lea       r7, [r7+8*r3]
%endmacro

%macro SATD_HBD_END 1 ; 1: words may exceed 32767
%if %1
    HADDUWD   m6, m7
%else
    vpbroadcastd m7, [pw_1]
    pmaddwd   m6, m7
%endif
    HADDD     m6, m7
    movd     eax, xm6
    RET
%endmacro

INIT_YMM avx2
cglobal pixel_satd_8x8, 4,8,8
    SATD_HBD_START
    SATD_HBD_LOAD_X
    SATD_8x4_SSE 1, 0, 1, 2, 3, 4, 5, 6, swap
    SATD_HBD_END 0

cglobal pixel_satd_8x16, 4,8,8
    SATD_HBD_START
    SATD_HBD_LOAD_X
    SATD_8x4_SSE 1, 0, 1, 2, 3, 4, 5, 6, swap
    SATD_HBD_NEXT8
    SATD_HBD_LOAD_X
    SATD_8x4_SSE 1, 0, 1, 2, 3, 4, 5, 6
    SATD_HBD_END 0

cglobal pixel_satd_16x8, 4,6,8
    FIX_STRIDES r1, r3
    lea       r4, [3*r1]
    lea       r5, [3*r3]
    SATD_HBD_LOAD_Y
    SATD_8x4_SSE 1, 0, 1, 2, 3, 4, 5, 6, swap
    lea       r0, [r0+4*r1]
    lea       r2, [r2+4*r3]
    SATD_HBD_LOAD_Y
    SATD_8x4_SSE 1, 0, 1, 2, 3, 4, 5, 6
    SATD_HBD_END 0

cglobal pixel_satd_16x16, 4,6,8
    FIX_STRIDES r1, r3
    lea       r4, [3*r1]
    lea       r5, [3*r3]
    SATD_HBD_LOAD_Y
    SATD_8x4_SSE 1, 0, 1, 2, 3, 4, 5, 6, swap
%rep 3
    lea       r0, [r0+4*r1]
    lea       r2, [r2+4*r3]
    SATD_HBD_LOAD_Y
    SATD_8x4_SSE 1, 0, 1, 2, 3, 4, 5, 6
%endrep
    SATD_HBD_END 1


;-----------------------------------------------------------------------------
; int pixel_satd_avg2_WxH( uint16_t *fenc, uint16_t *src1, uint16_t *src2, intptr_t stride )
; satd( fenc, (src1+src2+1)>>1 ): the qpel candidates of subpel refinement
; without storing the average. fenc has FENC_STRIDE, src1/src2 share stride.
;-----------------------------------------------------------------------------
%macro SATD_AVG2_LOAD_Y 0 ; 16 wide: r1/r2 rows, r4 = 3*stride
    movu          m0, [r1]
    movu          m1, [r1+r3]
    movu          m2, [r1+2*r3]
    movu          m3, [r1+r4]
    pavgw         m0, [r2]
    pavgw         m1, [r2+r3]
    pavgw         m2, [r2+2*r3]
    pavgw         m3, [r2+r4]
    psubw         m0, [r0]
    psubw         m1, [r0+1*FENC_STRIDEB]
    psubw         m2, [r0+2*FENC_STRIDEB]
    psubw         m3, [r0+3*FENC_STRIDEB]
%endmacro

; 8 wide, lanes = rows i, i+4: r5/r6 = r1/r2 four rows down
%macro SATD_AVG2_ROW_X 2 ; dst (number), row
%if %2 == 3
    %define satd_avg2_off r4
%elif %2
    %define satd_avg2_off %2*r3
%endif
%if %2
    movu         xm%1, [r1+satd_avg2_off]
    vinserti128   m%1, m%1, [r5+satd_avg2_off], 1
    movu         xm4, [r2+satd_avg2_off]
    vinserti128   m4, m4, [r6+satd_avg2_off], 1
%else
    movu         xm%1, [r1]
    vinserti128   m%1, m%1, [r5], 1
    movu         xm4, [r2]
    vinserti128   m4, m4, [r6], 1
%endif
    movu         xm5, [r0+%2*FENC_STRIDEB]
    vinserti128   m5, m5, [r0+(%2+4)*FENC_STRIDEB], 1
    pavgw         m%1, m4
    psubw         m%1, m5
%endmacro

%macro SATD_AVG2_LOAD_X 0
    SATD_AVG2_ROW_X 0, 0
    SATD_AVG2_ROW_X 1, 1
    SATD_AVG2_ROW_X 2, 2
    SATD_AVG2_ROW_X 3, 3
%endmacro

%macro SATD_AVG2_START 0
    FIX_STRIDES r3
    lea       r4, [3*r3]
%endmacro

%macro SATD_AVG2_START_X 0
    SATD_AVG2_START
    lea       r5, [r1+4*r3]
    lea       r6, [r2+4*r3]
%endmacro

cglobal pixel_satd_avg2_8x8, 4,7,8
    SATD_AVG2_START_X
    SATD_AVG2_LOAD_X
    SATD_8x4_SSE 1, 0, 1, 2, 3, 4, 5, 6, swap
    SATD_HBD_END 0

cglobal pixel_satd_avg2_8x16, 4,7,8
    SATD_AVG2_START_X
    SATD_AVG2_LOAD_X
    SATD_8x4_SSE 1, 0, 1, 2, 3, 4, 5, 6, swap
    lea       r1, [r1+8*r3]
    lea       r2, [r2+8*r3]
    lea       r5, [r5+8*r3]
    lea       r6, [r6+8*r3]
    add       r0, 8*FENC_STRIDEB
    SATD_AVG2_LOAD_X
    SATD_8x4_SSE 1, 0, 1, 2, 3, 4, 5, 6
    SATD_HBD_END 0

cglobal pixel_satd_avg2_16x8, 4,5,8
    SATD_AVG2_START
    SATD_AVG2_LOAD_Y
    SATD_8x4_SSE 1, 0, 1, 2, 3, 4, 5, 6, swap
    lea       r1, [r1+4*r3]
    lea       r2, [r2+4*r3]
    add       r0, 4*FENC_STRIDEB
    SATD_AVG2_LOAD_Y
    SATD_8x4_SSE 1, 0, 1, 2, 3, 4, 5, 6
    SATD_HBD_END 0

cglobal pixel_satd_avg2_16x16, 4,5,8
    SATD_AVG2_START
    SATD_AVG2_LOAD_Y
    SATD_8x4_SSE 1, 0, 1, 2, 3, 4, 5, 6, swap
%rep 3
    lea       r1, [r1+4*r3]
    lea       r2, [r2+4*r3]
    add       r0, 4*FENC_STRIDEB
    SATD_AVG2_LOAD_Y
    SATD_8x4_SSE 1, 0, 1, 2, 3, 4, 5, 6
%endrep
    SATD_HBD_END 1

%if ARCH_X86_64
;-----------------------------------------------------------------------------
; satd_bi/satd_bi4 (see SATD_BI) in the layout of the satd functions above. The
; weighted average is src1 + pmulhrsw( (src0-src1)<<5, w<<4 ) clipped, the same
; as mc.avg's for |src0-src1| < 1024 and -64 < w < 128.
;-----------------------------------------------------------------------------
; m%1 = list %2's source at bi_o: a row (16 wide) or rows k, k+4 (8 wide); m%3 tmp
%macro BI_HBD_SRC 3
%if bi_wide
    movu          m%1, [bi_p%2a+bi_o]
%if bi_four
    pavgw         m%1, [bi_p%2b+bi_o]
%endif
%else
    movu         xm%1, [bi_p%2a+bi_o]
    vinserti128   m%1, m%1, [bi_q%2a+bi_o], 1
%if bi_four
    movu         xm%3, [bi_p%2b+bi_o]
    vinserti128   m%3, m%3, [bi_q%2b+bi_o], 1
    pavgw         m%1, m%3
%endif
%endif
%endmacro

; m%1 = the average less fenc, row %2 (16 wide) or rows %2, %2+4 (8 wide)
%macro BI_HBD_ROW 2
    BI_ROW_OFF 0, %2
    BI_HBD_SRC %1, 0, 5
    BI_ROW_OFF 1, %2
    BI_HBD_SRC 4, 1, 5
%if bi_weight
    psubw         m%1, m4
    psllw         m%1, 5
    pmulhrsw      m%1, m8
    paddw         m%1, m4
    pmaxsw        m%1, m9
    pminsw        m%1, m10
%else
    pavgw         m%1, m4
%endif
%if bi_wide
    psubw         m%1, [r0+%2*FENC_STRIDEB]
%else
    movu          xm5, [r0+%2*FENC_STRIDEB]
    vinserti128    m5, m5, [r0+(%2+4)*FENC_STRIDEB], 1
    psubw         m%1, m5
%endif
%endmacro

%macro SATD_BI_BODY 2 ; height, weighted
%assign bi_weight %2
%if bi_weight
    shl          bi_wd, 4
    movd           xm8, bi_wd
    vpbroadcastw    m8, xm8
    pxor            m9, m9
    vbroadcasti128 m10, [pw_pixel_max]
%endif
%if bi_wide
    %assign bi_rows 4
%else
    %assign bi_rows 8
%endif
%assign bi_pass 0
%rep %1/bi_rows
%if bi_pass
    BI_NEXT bi_rows
    add            r0, bi_rows*FENC_STRIDEB
%endif
    BI_HBD_ROW 0, 0
    BI_HBD_ROW 1, 1
    BI_HBD_ROW 2, 2
    BI_HBD_ROW 3, 3
    BI_SATD_PASS 1
%assign bi_pass bi_pass+1
%endrep
    SATD_HBD_END bi_big
%endmacro

SATD_BI 16, 16, 0
SATD_BI 16,  8, 0
SATD_BI  8, 16, 0
SATD_BI  8,  8, 0
SATD_BI 16, 16, 1
SATD_BI 16,  8, 1
SATD_BI  8, 16, 1
SATD_BI  8,  8, 1
%endif ; ARCH_X86_64

%if ARCH_X86_64
INIT_YMM avx2
SA8D_SATD

%macro HADAMARD_AC_HBD_YMM 0
HADAMARD_AC_SSE2

; 8x16: lane 0 is the top 8x8, lane 1 the bottom one, one pass like 16x8
%assign hadac_vstack 1
HADAMARD_AC_SSE2 v
%assign hadac_vstack 0
cglobal pixel_hadamard_ac_8x16, 2,5,11+3*cpuflag(avx512icl)
    FIX_STRIDES r1
    mov   r3, rsp
    and  rsp, ~(mmsize-1)
    sub  rsp, mmsize*3
    lea   r2, [r1*3]
    lea   r4, [r0+r1*8]
    call hadamard_ac_8x8v
    HADAMARD_AC_WXH_SUM_SSE2 8, 16
    movd edx, xm0
    movd eax, xm1
    shr  edx, 2
    shr  eax, 1
    shl  rdx, 32
    add  rax, rdx
    mov  rsp, r3
    RET
%endmacro

HADAMARD_AC_HBD_YMM
ICL_LOW_BEGIN
HADAMARD_AC_HBD_YMM
ICL_LOW_END
INIT_YMM avx2

; 16 pixel rows: lane 0 is pix[0], lane 1 is pix[8], the 8x8 transform is lane-local
; avx2: m0 = word sums of the four maxes (unsigned); avx512icl: dword sums (vpdpwssd,
; m12 = pw_1 from the caller)
%macro SA8D_16x16_HBD 0
cglobal pixel_sa8d_16x8_internal
    lea  r6, [r0+4*r1]
    lea  r7, [r2+4*r3]
    LOAD_DIFF_8x4P 0, 1, 2, 8, 5, 6, 7, r0, r2, 0, 0
    LOAD_DIFF_8x4P 4, 5, 3, 9, 11, 6, 7, r6, r7, 0, 0
    HADAMARD8_2D 0, 1, 2, 8, 4, 5, 3, 9, 6, amax
%if cpuflag(avx512icl)
    pmaddwd   m0, m12
    {evex} vpdpwssd  m0, m1, m12
    pmaddwd   m2, m12
    {evex} vpdpwssd  m2, m8, m12
    paddd     m0, m2
%else
    SA8D_SUM_HBD 0, 1, 2, 8
%endif
    SAVE_MM_PERMUTATION
    ret

cglobal pixel_sa8d_16x16, 4,8,12+cpuflag(avx512icl)
    FIX_STRIDES r1, r3
    lea  r4, [3*r1]
    lea  r5, [3*r3]
%if cpuflag(avx512icl)
    vpbroadcastd m12, [pw_1]
%endif
    call pixel_sa8d_16x8_internal
    lea  r0, [r0+8*r1]
    lea  r2, [r2+8*r3]
    mova m10, m0
    call pixel_sa8d_16x8_internal
    paddd m0, m10
    HADDD m0, m1
    movd eax, xm0
    add  eax, 1
    shr  eax, 1
    RET
%endmacro

SA8D_16x16_HBD
ICL_LOW_BEGIN
SA8D_16x16_HBD
ICL_LOW_END
INIT_YMM avx2
%endif

INIT_YMM avx2
HADAMARD_AC_8x8_AVX2

;-----------------------------------------------------------------------------
; int pixel_sa8d_8x8( uint16_t *, intptr_t, uint16_t *, intptr_t )
; Same lane split as hadamard_ac_8x8. Differences reach 32*1023 before the
; last stage, so the four max() results are widened before they are added
; (avx512icl: vpdpwssd, two chains).
;-----------------------------------------------------------------------------
%macro SA8D_8x8_HBD 0
cglobal pixel_sa8d_8x8, 4,6,8
    FIX_STRIDES r1, r3
    lea          r4, [r1*3]
    lea          r5, [r3*3]
    movu        xm0, [r0]
    movu        xm4, [r2]
    movu        xm1, [r0+r1]
    movu        xm5, [r2+r3]
    movu        xm2, [r0+r1*2]
    movu        xm6, [r2+r3*2]
    movu        xm3, [r0+r4]
    movu        xm7, [r2+r5]
    lea          r0, [r0+r1*4]
    lea          r2, [r2+r3*4]
    vinserti128  m0, m0, [r0], 1
    vinserti128  m4, m4, [r2], 1
    vinserti128  m1, m1, [r0+r1], 1
    vinserti128  m5, m5, [r2+r3], 1
    vinserti128  m2, m2, [r0+r1*2], 1
    vinserti128  m6, m6, [r2+r3*2], 1
    vinserti128  m3, m3, [r0+r4], 1
    vinserti128  m7, m7, [r2+r5], 1
    psubw        m0, m4
    psubw        m1, m5
    psubw        m2, m6
    psubw        m3, m7
    HADAMARD4_2D_SSE 0, 1, 2, 3, 4
    HADAMARD 4, sumsub, 0, 1, 4
    HADAMARD 4, sumsub, 2, 3, 4
    mova         m7, [pw_1]
    pabsw        m0, m0
    pabsw        m1, m1
    pabsw        m2, m2
    pabsw        m3, m3
    vextracti128 xm4, m0, 1
    vextracti128 xm5, m1, 1
    vextracti128 xm6, m2, 1
    pmaxsw      xm0, xm4
    pmaxsw      xm1, xm5
    pmaxsw      xm2, xm6
    vextracti128 xm4, m3, 1
    pmaxsw      xm3, xm4
%if cpuflag(avx512icl)
    pmaddwd     xm0, xm7
    {evex} vpdpwssd    xm0, xm1, xm7
    pmaddwd     xm2, xm7
    {evex} vpdpwssd    xm2, xm3, xm7
%else
    pmaddwd     xm0, xm7
    pmaddwd     xm1, xm7
    pmaddwd     xm2, xm7
    pmaddwd     xm3, xm7
    paddd       xm0, xm1
    paddd       xm2, xm3
%endif
    paddd       xm0, xm2
    HADDD       xm0, xm1
    movd        eax, xm0
    add         eax, 1
    shr         eax, 1
    RET
%endmacro

SA8D_8x8_HBD
%if ARCH_X86_64
ICL_LOW_BEGIN
SA8D_8x8_HBD
ICL_LOW_END
INIT_YMM avx2
%endif
%if ARCH_X86_64

;-----------------------------------------------------------------------------
; void intra_satd_x3_16x16( uint16_t *fenc, uint16_t *fdec, int res[3] ) (V, H, DC)
; void intra_satd_x3_8x8c( uint16_t *fenc, uint16_t *fdec, int res[3] )  (DC, H, V)
; 10-bit: the three predictions are built in registers and each goes through the
; vertical-mode SATD_8x4_SSE pass of pixel_satd, so the results equal satd() of the
; C predictions. fenc rows are loaded once, into m8-m11.
;-----------------------------------------------------------------------------

; m0-m3 = m8-m11 - m%1
%macro INTRA_HBD_DIFF4 1
    psubw   m0, m8, m%1
    psubw   m1, m9, m%1
    psubw   m2, m10, m%1
    psubw   m3, m11, m%1
%endmacro

; word accumulator m%1 -> 4 dword sums in xm%1 (%2: lanes may exceed 32767)
%macro INTRA_HBD_FOLD 2
%if %2
    HADDUWD m%1, m4
%else
%if mmsize == 64
    vpbroadcastd m4, [pw_1]
    pmaddwd m%1, m4
%else
    pmaddwd m%1, [pw_1]
%endif
%endif
%if mmsize == 64
    vextracti32x8 ym4, m%1, 1
    paddd   ym%1, ym4
%endif
%if mmsize >= 32
    vextracti128 xm4, ym%1, 1
    paddd   xm%1, xm4
%endif
%endmacro

; accumulators m%1, m%2, m%3 -> res[0], res[1], res[2]
%macro INTRA_HBD_X3_END 4
    INTRA_HBD_FOLD %1, %4
    INTRA_HBD_FOLD %2, %4
    INTRA_HBD_FOLD %3, %4
    punpckldq     xm4, xm%1, xm%2
    punpckhdq     xm%1, xm%2
    paddd         xm%1, xm4
    punpckhdq     xm5, xm%3, xm%3
    punpckldq     xm%3, xm%3
    paddd         xm%3, xm5
    punpcklqdq    xm4, xm%1, xm%3
    punpckhqdq    xm%1, xm%3
    paddd         xm%1, xm4
    movq      [r2], xm%1
    pextrd  [r2+8], xm%1, 2
    RET
%endmacro

%macro INTRA_SATD_X3_16x16_HBD 0
cglobal intra_satd_x3_16x16, 3,5,16
    ; DC = (sum of top + sum of left + 16) >> 5
    movzx         r3d, word [r1-2]
%assign intra_hbd_y 1
%rep 15
    movzx         r4d, word [r1+intra_hbd_y*FDEC_STRIDEB-2]
    add           r3d, r4d
%assign intra_hbd_y intra_hbd_y+1
%endrep
    movu          ym4, [r1-FDEC_STRIDEB]
    pmaddwd       ym4, [pw_1]
    vextracti128  xm5, ym4, 1
    paddd         xm4, xm5
    punpckhqdq    xm5, xm4, xm4
    paddd         xm4, xm5
    pshuflw       xm5, xm4, q1032
    paddd         xm4, xm5
    movd          r4d, xm4
    lea           r3d, [r3+r4+16]
    shr           r3d, 5
    movd         xm13, r3d
    vpbroadcastw  m13, xm13                ; DC
%if mmsize == 64
    vbroadcasti32x8 m12, [r1-FDEC_STRIDEB] ; V: the top row in both halves
    mov           r3d, 0xffff0000
    kmovd          k1, r3d
%else
    movu          m12, [r1-FDEC_STRIDEB]
%endif
%assign intra_hbd_pass 0
%rep 128/mmsize
%if mmsize == 64
    %assign intra_hbd_r0 intra_hbd_pass*8   ; lanes: rows r0+i and r0+i+4
%else
    %assign intra_hbd_r0 intra_hbd_pass*4   ; one row per register
%endif
%assign intra_hbd_i 0
%rep 4
    %assign intra_hbd_f 8+intra_hbd_i
%if mmsize == 64
    movu          ym %+ intra_hbd_f, [r0+(intra_hbd_r0+intra_hbd_i)*FENC_STRIDEB]
    vinserti32x8   m %+ intra_hbd_f, m %+ intra_hbd_f, [r0+(intra_hbd_r0+intra_hbd_i+4)*FENC_STRIDEB], 1
%else
    movu           m %+ intra_hbd_f, [r0+(intra_hbd_r0+intra_hbd_i)*FENC_STRIDEB]
%endif
%assign intra_hbd_i intra_hbd_i+1
%endrep
    INTRA_HBD_DIFF4 12                      ; V
%if intra_hbd_pass == 0
    SATD_8x4_SSE 1, 0, 1, 2, 3, 4, 5, 14, swap
%else
    SATD_8x4_SSE 1, 0, 1, 2, 3, 4, 5, 14
%endif
%assign intra_hbd_i 0
%rep 4                                      ; H: each row minus its left neighbour
    %assign intra_hbd_f 8+intra_hbd_i
%if mmsize == 64
    vpbroadcastw   m %+ intra_hbd_i, [r1+(intra_hbd_r0+intra_hbd_i)*FDEC_STRIDEB-2]
    vpbroadcastw   m %+ intra_hbd_i {k1}, [r1+(intra_hbd_r0+intra_hbd_i+4)*FDEC_STRIDEB-2]
%else
    vpbroadcastw   m %+ intra_hbd_i, [r1+(intra_hbd_r0+intra_hbd_i)*FDEC_STRIDEB-2]
%endif
    psubw          m %+ intra_hbd_i, m %+ intra_hbd_f, m %+ intra_hbd_i
%assign intra_hbd_i intra_hbd_i+1
%endrep
%if intra_hbd_pass == 0
    SATD_8x4_SSE 1, 0, 1, 2, 3, 4, 5, 15, swap
%else
    SATD_8x4_SSE 1, 0, 1, 2, 3, 4, 5, 15
%endif
    INTRA_HBD_DIFF4 13                      ; DC
%if intra_hbd_pass == 0
    SATD_8x4_SSE 1, 0, 1, 2, 3, 4, 5, 6, swap
%else
    SATD_8x4_SSE 1, 0, 1, 2, 3, 4, 5, 6
%endif
%assign intra_hbd_pass intra_hbd_pass+1
%endrep
    INTRA_HBD_X3_END 14, 15, 6, mmsize == 32
%endmacro

;-----------------------------------------------------------------------------
; chroma 8x8, ymm: lanes = rows i and i+4; the DC register is
; lane 0 { dc0 x4, dc1 x4 }, lane 1 { dc2 x4, dc3 x4 } for every row.
;-----------------------------------------------------------------------------
%macro INTRA_SATD_X3_8x8C_HBD 0
cglobal intra_satd_x3_8x8c, 3,7,16
    movu          xm4, [r1-FDEC_STRIDEB]
    pmaddwd       xm4, [pw_1]
    pshufd        xm5, xm4, q2301
    paddd         xm4, xm5                  ; s0 s0 s1 s1 (top 0-3, top 4-7)
    movd          r3d, xm4
    pextrd        r5d, xm4, 2
    movzx         r4d, word [r1-2]
%assign intra_hbd_y 1
%rep 3
    movzx         r6d, word [r1+intra_hbd_y*FDEC_STRIDEB-2]
    add           r4d, r6d
%assign intra_hbd_y intra_hbd_y+1
%endrep                                     ; s2 = left 0-3
    lea           r3d, [r3+r4+4]
    shr           r3d, 3
    movd         xm13, r3d                  ; dc0 = (s0 + s2 + 4) >> 3
    lea           r3d, [r5+2]
    shr           r3d, 2
    pinsrw       xm13, r3d, 1               ; dc1 = (s1 + 2) >> 2
    movzx         r4d, word [r1+4*FDEC_STRIDEB-2]
%assign intra_hbd_y 5
%rep 3
    movzx         r6d, word [r1+intra_hbd_y*FDEC_STRIDEB-2]
    add           r4d, r6d
%assign intra_hbd_y intra_hbd_y+1
%endrep                                     ; s3 = left 4-7
    lea           r3d, [r4+2]
    shr           r3d, 2
    pinsrw       xm13, r3d, 2               ; dc2 = (s3 + 2) >> 2
    lea           r3d, [r4+r5+4]
    shr           r3d, 3
    pinsrw       xm13, r3d, 3               ; dc3 = (s1 + s3 + 4) >> 3
    vpbroadcastq  m13, xm13
    pshufb        m13, [intra_8x8c_dc_shuf]
    vbroadcasti128 m12, [r1-FDEC_STRIDEB]  ; V
%assign intra_hbd_i 0
%rep 4
    %assign intra_hbd_f 8+intra_hbd_i
    movu          xm %+ intra_hbd_f, [r0+intra_hbd_i*FENC_STRIDEB]
    vinserti128    m %+ intra_hbd_f, m %+ intra_hbd_f, [r0+(intra_hbd_i+4)*FENC_STRIDEB], 1
%assign intra_hbd_i intra_hbd_i+1
%endrep
    INTRA_HBD_DIFF4 13                      ; DC
    SATD_8x4_SSE 1, 0, 1, 2, 3, 4, 5, 14, swap
%assign intra_hbd_i 0
%rep 4                                      ; H
    %assign intra_hbd_f 8+intra_hbd_i
    vpbroadcastw  xm %+ intra_hbd_i, [r1+intra_hbd_i*FDEC_STRIDEB-2]
    vpbroadcastw  xm6, [r1+(intra_hbd_i+4)*FDEC_STRIDEB-2]
    vinserti128    m %+ intra_hbd_i, m %+ intra_hbd_i, xm6, 1
    psubw          m %+ intra_hbd_i, m %+ intra_hbd_f, m %+ intra_hbd_i
%assign intra_hbd_i intra_hbd_i+1
%endrep
    SATD_8x4_SSE 1, 0, 1, 2, 3, 4, 5, 15, swap
    INTRA_HBD_DIFF4 12                      ; V
    SATD_8x4_SSE 1, 0, 1, 2, 3, 4, 5, 6, swap
    INTRA_HBD_X3_END 14, 15, 6, 0
%endmacro

;-----------------------------------------------------------------------------
; void intra_satd_x3_8x16c( uint16_t *fenc, uint16_t *fdec, int res[3] )  (DC, H, V)
; two 8x8c halves; xm13 holds dc0-dc7, m7 the DC register of the current half
;-----------------------------------------------------------------------------
; %1 = sum of left[%2..%2+3]
%macro INTRA_HBD_LEFT4 2
    movzx         %1, word [r1+%2*FDEC_STRIDEB-2]
%assign intra_hbd_y %2+1
%rep 3
    movzx         r6d, word [r1+intra_hbd_y*FDEC_STRIDEB-2]
    add           %1, r6d
%assign intra_hbd_y intra_hbd_y+1
%endrep
%endmacro

; rows %1..%1+7, %2 = first half
%macro INTRA_HBD_8x16C_HALF 2
%assign intra_hbd_i 0
%rep 4
    %assign intra_hbd_f 8+intra_hbd_i
    movu          xm %+ intra_hbd_f, [r0+(%1+intra_hbd_i)*FENC_STRIDEB]
    vinserti128    m %+ intra_hbd_f, m %+ intra_hbd_f, [r0+(%1+intra_hbd_i+4)*FENC_STRIDEB], 1
%assign intra_hbd_i intra_hbd_i+1
%endrep
    INTRA_HBD_DIFF4 7                       ; DC
%if %2
    SATD_8x4_SSE 1, 0, 1, 2, 3, 4, 5, 14, swap
%else
    SATD_8x4_SSE 1, 0, 1, 2, 3, 4, 5, 14
%endif
%assign intra_hbd_i 0
%rep 4                                      ; H
    %assign intra_hbd_f 8+intra_hbd_i
    vpbroadcastw  xm %+ intra_hbd_i, [r1+(%1+intra_hbd_i)*FDEC_STRIDEB-2]
    vpbroadcastw  xm4, [r1+(%1+intra_hbd_i+4)*FDEC_STRIDEB-2]
    vinserti128    m %+ intra_hbd_i, m %+ intra_hbd_i, xm4, 1
    psubw          m %+ intra_hbd_i, m %+ intra_hbd_f, m %+ intra_hbd_i
%assign intra_hbd_i intra_hbd_i+1
%endrep
%if %2
    SATD_8x4_SSE 1, 0, 1, 2, 3, 4, 5, 15, swap
%else
    SATD_8x4_SSE 1, 0, 1, 2, 3, 4, 5, 15
%endif
    INTRA_HBD_DIFF4 12                      ; V
%if %2
    SATD_8x4_SSE 1, 0, 1, 2, 3, 4, 5, 6, swap
%else
    SATD_8x4_SSE 1, 0, 1, 2, 3, 4, 5, 6
%endif
%endmacro

%macro INTRA_SATD_X3_8x16C_HBD 0
cglobal intra_satd_x3_8x16c, 3,7,16
    movu          xm4, [r1-FDEC_STRIDEB]
    pmaddwd       xm4, [pw_1]
    pshufd        xm5, xm4, q2301
    paddd         xm4, xm5                  ; s0 s0 s1 s1
    movd          r3d, xm4
    pextrd        r5d, xm4, 2
    INTRA_HBD_LEFT4 r4d, 0                  ; s2
    lea           r3d, [r3+r4+4]
    shr           r3d, 3
    movd         xm13, r3d                  ; dc0 = (s0 + s2 + 4) >> 3
    lea           r3d, [r5+2]
    shr           r3d, 2
    pinsrw       xm13, r3d, 1               ; dc1 = (s1 + 2) >> 2
%assign intra_hbd_k 2
%rep 3
    INTRA_HBD_LEFT4 r4d, intra_hbd_k*2      ; s3, s4, s5
    lea           r3d, [r4+2]
    shr           r3d, 2
    pinsrw       xm13, r3d, intra_hbd_k     ; (s + 2) >> 2
    lea           r3d, [r4+r5+4]
    shr           r3d, 3
    pinsrw       xm13, r3d, intra_hbd_k+1   ; (s1 + s + 4) >> 3
%assign intra_hbd_k intra_hbd_k+2
%endrep
    vpbroadcastq  m7, xm13
    pshufb        m7, [intra_8x8c_dc_shuf]
    vbroadcasti128 m12, [r1-FDEC_STRIDEB]  ; V
    INTRA_HBD_8x16C_HALF 0, 1
    vpermq        m7, m13, q1111
    pshufb        m7, [intra_8x8c_dc_shuf]
    INTRA_HBD_8x16C_HALF 8, 0
    INTRA_HBD_X3_END 14, 15, 6, 0
%endmacro

INIT_YMM avx2
INTRA_SATD_X3_16x16_HBD
INTRA_SATD_X3_8x8C_HBD
INTRA_SATD_X3_8x16C_HBD
INIT_ZMM avx512
INTRA_SATD_X3_16x16_HBD

;-----------------------------------------------------------------------------
; avx512icl high bit depth satd 4x4, 4x8, 4x16, 8x4. Each qword holds 4 words
; of one row, m0/m1 rows k and k+2 of a 4x4. Vertical: sumsub, an exchange
; (qdq for 4 wide, the 128-bit lanes for 8 wide), sumsub. Horizontal, distance
; 1: vprold + paddw + psubw {k1 = odd words}; distance 2, the last stage: the
; max of absolutes of both registers into one (vpblendmd {k2 = even dwords} +
; vpshldq + pmaxsw), whose word sum is the satd. |diff| <= PIXEL_MAX, three
; sumsubs: words <= 8*PIXEL_MAX = 8184 (two passes added: 16368).
;-----------------------------------------------------------------------------
%macro SATD4_ICL_KMASK 1 ; gpr (dword) to clobber
    mov          %1, 0xaaaa0055
    kmovd        k2, %1
    kshiftrd     k1, k2, 16
%endmacro

%macro SATD4_ICL_HBD 1 ; qdq/lane: m0, m1 -> m0 = words summing to the satd; m1-m5 tmp
    SUMSUB_BA     w, 0, 1, 2
%ifidn %1, qdq
    SBUTTERFLY  qdq, 0, 1, 2
%else
    vperm2i128   m2, m0, m1, 0x31
    vinserti128  m0, m0, xm1, 1
    SWAP          1, 2
%endif
    SUMSUB_BA     w, 0, 1, 2
    vprold       m2, m0, 16
    vprold       m3, m1, 16
    paddw        m4, m0, m2
    paddw        m5, m1, m3
    vpsubw       m4 {k1}, m2, m0
    vpsubw       m5 {k1}, m3, m1
    pabsw        m4, m4
    pabsw        m5, m5
    vpblendmd    m0 {k2}, m4, m5
    vpshldq      m5, m4, m5, 32
    pmaxsw       m0, m5
%endmacro

%macro SATD4_ICL_END 0
    pmaddwd      m0, [pw_1]
    HADDD        m0, m1
    movd        eax, xm0
    RET
%endmacro

INIT_XMM avx512icl
cglobal pixel_satd_4x4, 4,6,6
    FIX_STRIDES r1, r3
    SATD4_ICL_KMASK r4d
    lea          r4, [r0+2*r1]
    lea          r5, [r2+2*r3]
    movq         m0, [r0]
    movq         m2, [r2]
    movq         m1, [r4]
    movq         m3, [r5]
    movhps       m0, [r0+r1]
    movhps       m2, [r2+r3]
    movhps       m1, [r4+r1]
    movhps       m3, [r5+r3]
    psubw        m0, m2
    psubw        m1, m3
    SATD4_ICL_HBD qdq
    SATD4_ICL_END

ICL_LOW_BEGIN
%macro SATD4x8_ICL_START 0
    FIX_STRIDES r1, r3
    SATD4_ICL_KMASK r4d
    mov         r4d, 0xe
    kmovb        k3, r4d
    kshiftlb     k4, k3, 1
    kshiftlb     k5, k3, 2
    lea          r4, [3*r1]
    lea          r5, [3*r3]
%endmacro

; m0 = rows 0 1 4 5, m1 = rows 2 3 6 7 of pix1-pix2; r0/r2 move down 4 rows
; (merge-masked broadcasts, k3/k4/k5 = qwords 1-3/2-3/3)
%macro SATD4x8_ICL_LOAD 0
    vpbroadcastq m0, [r0]
    vpbroadcastq m2, [r2]
    vpbroadcastq m1, [r0+2*r1]
    vpbroadcastq m3, [r2+2*r3]
    vpbroadcastq m0 {k3}, [r0+r1]
    vpbroadcastq m2 {k3}, [r2+r3]
    vpbroadcastq m1 {k3}, [r0+r4]
    vpbroadcastq m3 {k3}, [r2+r5]
    lea          r0, [r0+4*r1]
    lea          r2, [r2+4*r3]
    vpbroadcastq m0 {k4}, [r0]
    vpbroadcastq m2 {k4}, [r2]
    vpbroadcastq m1 {k4}, [r0+2*r1]
    vpbroadcastq m3 {k4}, [r2+2*r3]
    vpbroadcastq m0 {k5}, [r0+r1]
    vpbroadcastq m2 {k5}, [r2+r3]
    vpbroadcastq m1 {k5}, [r0+r4]
    vpbroadcastq m3 {k5}, [r2+r5]
    psubw        m0, m2
    psubw        m1, m3
%endmacro

cglobal pixel_satd_4x8, 4,6,6
    SATD4x8_ICL_START
    SATD4x8_ICL_LOAD
    SATD4_ICL_HBD qdq
    SATD4_ICL_END

cglobal pixel_satd_4x16, 4,6,7
    SATD4x8_ICL_START
    SATD4x8_ICL_LOAD
    SATD4_ICL_HBD qdq
    SWAP          0, 6
    lea          r0, [r0+4*r1]
    lea          r2, [r2+4*r3]
    SATD4x8_ICL_LOAD
    SATD4_ICL_HBD qdq
    paddw        m0, m6
    SATD4_ICL_END

; lanes: m0 = rows 0, 1, m1 = rows 2, 3; the qwords are the two 4x4s
cglobal pixel_satd_8x4, 4,6,6
    FIX_STRIDES r1, r3
    SATD4_ICL_KMASK r4d
    lea          r4, [r0+r1]
    lea          r5, [r2+r3]
    movu        xm0, [r0]
    movu        xm2, [r2]
    movu        xm1, [r0+2*r1]
    movu        xm3, [r2+2*r3]
    vinserti128  m0, m0, [r4], 1
    vinserti128  m2, m2, [r5], 1
    vinserti128  m1, m1, [r4+2*r1], 1
    vinserti128  m3, m3, [r5+2*r3], 1
    psubw        m0, m2
    psubw        m1, m3
    SATD4_ICL_HBD lane
    SATD4_ICL_END
ICL_LOW_END
%endif
%endif ; HIGH_BIT_DEPTH

;-----------------------------------------------------------------------------
; int intra_satd_lowres( int16_t *fenc_pre, uint8_t *src, intptr_t stride )
; int intra_satd_lowres( uint16_t *fenc, uint16_t *src, intptr_t stride )
; slicetype's lowres intra cost of the 8x8 at src: the minimum satd of the
; 8x8c DC, H, V and P predictions from its neighbours in the plane and the 8x8
; DDL, VL, DDR, VR, HD and HU from their predict_8x8_filter edge. fenc_pre is
; from satd_fenc_pre_8x8. Registers hold rows k (lane 0) and k+4 (lane 1), as
; in satd_pre_8x8 and the 10-bit satd_8x8.
;-----------------------------------------------------------------------------
; m0-m3: the difference, 8-bit after the first (pmaddubsw) stage; m4, m5 tmp.
; %1 = words summing to the satd
%macro LOWRES_SATD 1
%if HIGH_BIT_DEPTH
    HADAMARD4_2D_SSE 0, 1, 2, 3, 4, amax
    paddw        %1, m0, m2
%else
    HADAMARD4_V  0, 1, 2, 3, 4
    ABSW2        m0, m2, m0, m2, m4, m5
    ABSW2        m1, m3, m1, m3, m4, m5
%if cpuflag(avx512icl)
    SATD_ICL_HMAX 0, 2, 4
    SATD_ICL_HMAX 1, 3, 4
%else
    HADAMARD 1, max, 0, 2, 4, 5
    HADAMARD 1, max, 1, 3, 4, 5
%endif
    paddw        %1, m0, m1
%endif
%endmacro

%if HIGH_BIT_DEPTH && ARCH_X86_64
;-----------------------------------------------------------------------------
; 10-bit intra x9: all nine predictions are scored, bitcosts added and the
; best (mode<<16 | cost) returned, its prediction written to fdec. Same
; contract as the 8-bit versions; costs are unsigned and saturate at 0xffff.
;-----------------------------------------------------------------------------

; 4x4 block in one ymm: rows 0,1 in lane 0, rows 2,3 in lane 1.
; m%1: pred in, |three of the four hadamard stages of fenc-pred| out
; (m8 fenc, m12 swapw, m13-m15 signs). The cross-lane stage is the max in X9H_MERGE.
%macro X9H_SATD 2
    psubw       m%1, m8, m%1
    pshufb      m%2, m%1, m12
    psignw      m%1, m13
    paddw       m%1, m%2
    pshufd      m%2, m%1, q2301
    psignw      m%1, m14
    paddw       m%1, m%2
    pshufd      m%2, m%1, q1032
    psignw      m%1, m15
    paddw       m%1, m%2
    pabsw       m%1, m%1
%endmacro

; m%1 = (8 maxes of mode %1 | 8 maxes of mode %2), their sums are the satds
%macro X9H_MERGE 3
    vperm2i128  m%3, m%1, m%2, 0x20
    vperm2i128  m%1, m%1, m%2, 0x31
    pmaxsw      m%1, m%3
%endmacro

INIT_YMM avx2
;-----------------------------------------------------------------------------
; int intra_satd_x9_4x4( uint16_t *fenc, uint16_t *fdec, uint16_t *bitcosts )
;-----------------------------------------------------------------------------
cglobal intra_satd_x9_4x4, 3,4,16, 9*32
    %define pred_buf rsp
    movq        xm8, [r0+0*FENC_STRIDEB]
    movhps      xm8, [r0+1*FENC_STRIDEB]
    movq        xm0, [r0+2*FENC_STRIDEB]
    movhps      xm0, [r0+3*FENC_STRIDEB]
    vinserti128  m8, m8, xm0, 1
    movu        m12, [x9h_swapw]
    vbroadcasti128 m13, [pw_pmpmpmpm]
    vbroadcasti128 m14, [pw_ppmmppmm]
    vbroadcasti128 m15, [pw_ppppmmmm]

    ; v, ddl, vl: lane 1 of the top edge is lane 0 advanced by one sample
    vbroadcasti128 m0, [r1-FDEC_STRIDEB]
    punpcklqdq   m9, m0, m0
    pshufb       m1, m0, [x9h_top0]
    pshufb       m2, m0, [x9h_top1]
    pshufb       m0, m0, [x9h_top2]
    pavgw        m3, m1, m2           ; t0t1 .. | t1t2 ..
    paddw        m1, m0
    paddw        m2, [pw_1]
    paddw        m1, m2
    paddw        m1, m2
    psrlw        m1, 2                ; F(t1) .. | F(t2) ..
    punpcklqdq   m4, m3, m1
    pshufb       m5, m1, [x9h_ddl]
    movu [pred_buf+0*32], m9
    movu [pred_buf+3*32], m5
    movu [pred_buf+7*32], m4
    X9H_SATD      9, 0
    X9H_SATD      5, 0
    X9H_SATD      4, 0
    vperm2i128   m0, m9, m9, 0x01
    pmaxsw       m9, m0

    ; left edge: e = l3 l2 l1 l0 lt t0 t1 t2 (t3)
    movu        xm0, [r1-FDEC_STRIDEB-10]
    pinsrw      xm0, [r1+3*FDEC_STRIDEB-2], 0
    pinsrw      xm0, [r1+2*FDEC_STRIDEB-2], 1
    pinsrw      xm0, [r1+1*FDEC_STRIDEB-2], 2
    pinsrw      xm0, [r1+0*FDEC_STRIDEB-2], 3
    movq        xm1, [r1-FDEC_STRIDEB+6]
    palignr     xm1, xm1, xm0, 2      ; l2 l1 l0 lt t0 t1 t2 t3
    vpblendd    xm2, xm0, xm1, 0x0c   ; l3 l2 l1 l0 t0 t1 t2 t3
    pmaddwd     xm2, [pw_1]
    pshufd      xm3, xm2, q1032
    paddd       xm2, xm3
    pshufd      xm3, xm2, q2301
    paddd       xm2, xm3
    psrlw       xm2, 2
    pxor        xm3, xm3
    pavgw       xm2, xm3
    vpbroadcastw m2, xm2              ; dc
    vinserti128  m0, m0, xm0, 1
    vinserti128  m1, m1, xm1, 1
    pshufb       m3, m0, [x9h_ldup]
    pavgw        m6, m0, m1           ; G(e[i],e[i+1])
    paddw        m3, m1
    paddw        m1, m0, [pw_1]
    paddw        m3, m1
    paddw        m3, m1
    psrlw        m3, 2                ; F(e[i])
    pshufb       m7, m0, [x9h_h]
    movu [pred_buf+1*32], m7
    movu [pred_buf+2*32], m2
    X9H_SATD      7, 0
    X9H_SATD      2, 0
    X9H_MERGE     7, 2, 0             ; h | dc
    pshufb      m10, m3, [x9h_ddr]
    movu [pred_buf+4*32], m10
    X9H_SATD     10, 0
    X9H_MERGE     5, 10, 0            ; ddl | ddr
    pshufb      m10, m3, [x9h_vrf]
    pshufb       m0, m6, [x9h_vrg]
    por         m10, m0
    pshufb      m11, m3, [x9h_hdf]
    pshufb       m0, m6, [x9h_hdg]
    por         m11, m0
    movu [pred_buf+5*32], m10
    movu [pred_buf+6*32], m11
    X9H_SATD     10, 0
    X9H_SATD     11, 0
    X9H_MERGE    10, 11, 0            ; vr | hd
    punpcklwd    m0, m6, m3
    pshufb       m0, [x9h_hu]
    vpbroadcastw m1, [r1+3*FDEC_STRIDEB-2]
    vpblendd     m0, m0, m1, 0xe0
    movu [pred_buf+8*32], m0
    X9H_SATD      0, 1
    X9H_MERGE     4, 0, 1             ; vl | hu

    phaddw       m7, m5
    phaddw      m10, m4
    phaddw       m7, m10
    phaddw       m9, m9
    phaddw       m9, m9
    phaddw       m7, m9               ; h ddl vr vl v v v v | dc ddr hd hu v v v v
    vextracti128 xm0, m7, 1
    pextrw      r3d, xm7, 4
    punpcklwd   xm0, xm7, xm0
    paddw       xm0, [r2+2]
    phminposuw  xm0, xm0
    movzx       r0d, word [r2]
    add         r3d, r0d
    movd        eax, xm0
    add         eax, 1<<16
    cmp          ax, r3w
    cmovae      eax, r3d

    mov         r3d, eax
    shr         r3d, 16
    shl         r3d, 5
    movu        xm0, [pred_buf+r3]
    movu        xm1, [pred_buf+r3+16]
    movq   [r1+0*FDEC_STRIDEB], xm0
    movhps [r1+1*FDEC_STRIDEB], xm0
    movq   [r1+2*FDEC_STRIDEB], xm1
    movhps [r1+3*FDEC_STRIDEB], xm1
    RET

;-----------------------------------------------------------------------------
; int intra_sa8d_x9_8x8( uint16_t *fenc, uint16_t *fdec, uint16_t edge[36], uint16_t *bitcosts, uint16_t *satds )
;-----------------------------------------------------------------------------
; Modes go through .sa8d in pairs, mode 2k in lane 0 and 2k+1 in lane 1.
; Rows of the directional modes are loads from filtered-edge tables:
; F(i) = F2(e[i-1],e[i],e[i+1]), G(i) = F1(e[i],e[i+1]), e = edge.
cglobal intra_sa8d_x9_8x8, 5,7,16, 0x700
    %define fenc_buf rsp
    %define pred_buf rsp+0x100
    %define f_buf    rsp+0x600 ; F7..F31
    %define g_buf    rsp+0x640 ; G16..G31
    %define ce_buf   rsp+0x660 ; vr even rows: F8 F10 F12 F14 G15..G22
    %define co_buf   rsp+0x680 ; vr odd rows:  F9 F11 F13 F15 F16..F23
    %define p_buf    rsp+0x6a0 ; hd: (G7,F8)..(G14,F15) F16..F23
    %define q_buf    rsp+0x6d0 ; hu: (G14,F14)..(G7,F7) l7 x8
    movu        m15, [pw_1]
    lea          r6, [fenc_buf]
%assign x9i 0
%rep 8
    vbroadcasti128 m0, [r0+x9i*FENC_STRIDEB]
    movu [r6+x9i*32], m0
%assign x9i x9i+1
%endrep

    movu         m0, [r2+12]
    movu         m1, [r2+14]
    movu         m2, [r2+16]
    pavgw        m3, m1, m2           ; G7..G22
    paddw        m0, m2
    paddw        m1, m15
    paddw        m0, m1
    paddw        m0, m1
    psrlw        m0, 2                ; F7..F22
    movu         m4, [r2+30]
    movu         m5, [r2+32]
    movu         m6, [r2+34]
    pavgw        m7, m5, m6           ; G16..G31
    paddw        m4, m6
    paddw        m5, m15
    paddw        m4, m5
    paddw        m4, m5
    psrlw        m4, 2                ; F16..F31
    movu [f_buf], m0
    movu [f_buf+18], m4
    movu [g_buf], m7
    vextracti128 [ce_buf+8], m3, 1
    movu [co_buf+8], xm4
    movu [p_buf+32], xm4
    vextracti128 xm5, m0, 1
    palignr     xm6, xm5, xm0, 2      ; F8..F15
    pshufb      xm1, xm6, [x9h_deint]
    movq   [ce_buf], xm1
    movhps [co_buf], xm1
    punpcklwd   xm2, xm3, xm6
    punpckhwd   xm5, xm3, xm6
    movu [p_buf], xm2
    movu [p_buf+16], xm5
    pshufb      xm2, xm3, [x9h_rev]
    pshufb      xm5, xm0, [x9h_rev]
    punpcklwd   xm6, xm2, xm5
    punpckhwd   xm2, xm5
    vpbroadcastw xm5, [r2+14]
    movu [q_buf], xm6
    movu [q_buf+16], xm2
    movu [q_buf+32], xm5

    ; dc
    movu        xm0, [r2+14]
    paddw       xm0, [r2+32]
    pmaddwd     xm0, xm15
    pshufd      xm1, xm0, q1032
    paddd       xm0, xm1
    pshufd      xm1, xm0, q2301
    paddd       xm0, xm1
    psrlw       xm0, 3
    pxor        xm1, xm1
    pavgw       xm0, xm1
    vpbroadcastw m14, xm0

    ; v | h
    vbroadcasti128 m8, [r2+32]
%assign x9i 0
%rep 8
    vpbroadcastw m %+ x9i, [r2+28-2*x9i]
    vpblendd     m %+ x9i, m8, m %+ x9i, 0xf0
%assign x9i x9i+1
%endrep
    lea          r5, [pred_buf]
    call .sa8d
    mova         m9, m0
    ; dc | ddl
%assign x9i 0
%rep 8
    vinserti128  m %+ x9i, m14, [f_buf+20+2*x9i], 1
%assign x9i x9i+1
%endrep
    add          r5, 0x100
    call .sa8d
    mova        m10, m0
    ; ddr | vr
%assign x9i 0
%rep 8
    movu        xm %+ x9i, [f_buf+16-2*x9i]
%if x9i & 1
    vinserti128  m %+ x9i, m %+ x9i, [co_buf+6-x9i+1], 1
%else
    vinserti128  m %+ x9i, m %+ x9i, [ce_buf+8-x9i], 1
%endif
%assign x9i x9i+1
%endrep
    add          r5, 0x100
    call .sa8d
    mova        m11, m0
    ; hd | vl
%assign x9i 0
%rep 8
    movu        xm %+ x9i, [p_buf+28-4*x9i]
%if x9i & 1
    vinserti128  m %+ x9i, m %+ x9i, [f_buf+20+x9i-1], 1
%else
    vinserti128  m %+ x9i, m %+ x9i, [g_buf+x9i], 1
%endif
%assign x9i x9i+1
%endrep
    add          r5, 0x100
    call .sa8d
    mova        m12, m0
    ; hu | hu
%assign x9i 0
%rep 8
    vbroadcasti128 m %+ x9i, [q_buf+4+4*x9i]
%assign x9i x9i+1
%endrep
    add          r5, 0x100
    call .sa8d

    phaddd       m9, m10              ; v v dc dc | h h ddl ddl
    phaddd      m11, m12              ; ddr ddr hd hd | vr vr vl vl
    phaddd       m9, m11              ; v dc ddr hd | h ddl vr vl
    phaddd      xm0, xm0
    phaddd      xm0, xm0              ; hu
    vpbroadcastd m1, [pd_1]
    paddd        m9, m1
    paddd       xm0, xm1
    psrld        m9, 1
    psrld       xm0, 1
    vextracti128 xm1, m9, 1
    punpckldq   xm2, xm9, xm1
    punpckhdq   xm9, xm1
    packusdw    xm2, xm9              ; v h dc ddl ddr vr hd vl
    packusdw    xm0, xm0
    movu        xm1, [r3]
    paddusw     xm2, xm1
    movzx       r5d, word [r3+16]
    movd        xm1, r5d
    paddusw     xm0, xm1
    movu       [r4], xm2
    pextrw      r2d, xm0, 0
    mov     [r4+16], r2w
    phminposuw  xm0, xm2
    movd        eax, xm0
    add         r2d, 8<<16
    cmp          ax, r2w
    cmova       eax, r2d

    mov         r2d, eax
    shr         r2d, 16
    mov         r3d, r2d
    and         r3d, 1
    and         r2d, ~1
    shl         r2d, 7
    shl         r3d, 4
    add         r2d, r3d
%assign x9i 0
%rep 8
    movu        xm0, [pred_buf+r2+32*x9i]
    movu [r1+x9i*FDEC_STRIDEB], xm0
%assign x9i x9i+1
%endrep
    RET

RESET_MM_PERMUTATION
ALIGN 16
.sa8d: ; m0-m7 pred rows (stored to r5), r6 fenc rows -> m0 = 4 dword sums per lane
    %xdefine mret m0
%assign x9i 0
%rep 8
    movu [r5+x9i*32], m %+ x9i
    psubw        m %+ x9i, [r6+x9i*32]
%assign x9i x9i+1
%endrep
    HADAMARD8_2D 0, 1, 2, 3, 4, 5, 6, 7, 8, amax
    pmaddwd      m0, m15
    pmaddwd      m1, m15
    pmaddwd      m2, m15
    pmaddwd      m3, m15
    paddd        m0, m1
    paddd        m2, m3
    paddd      mret, m0, m2
    ret

;-----------------------------------------------------------------------------
; int intra_satd_lowres( uint16_t *fenc, uint16_t *src, intptr_t stride )
;-----------------------------------------------------------------------------
; m12-m15 fenc rows k, k+4, less the prediction
%macro LOWRES_DIFF10 0
    psubw        m0, m12, m0
    psubw        m1, m13, m1
    psubw        m2, m14, m2
    psubw        m3, m15, m3
%endmacro

; directional rows 0-7, loads from the tables of intra_sa8d_x9_8x8
%macro LOWRES_ROWS10 8
    movu        xm0, %1
    vinserti128  m0, m0, %5, 1
    movu        xm1, %2
    vinserti128  m1, m1, %6, 1
    movu        xm2, %3
    vinserti128  m2, m2, %7, 1
    movu        xm3, %4
    vinserti128  m3, m3, %8, 1
    LOWRES_DIFF10
%endmacro

INIT_YMM avx2
cglobal intra_satd_lowres, 3,5,16, 0x160
    %define lr_edge rsp       ; E6..E32 at 12..65, predict_8x8_filter's layout
    %define lr_f    rsp+0x60  ; F7..F31
    %define lr_g    rsp+0xa0  ; G16..G31
    %define lr_ce   rsp+0xc0  ; vr even rows: F8 F10 F12 F14 G15..G22
    %define lr_co   rsp+0xe0  ; vr odd rows:  F9 F11 F13 F15 F16..F23
    %define lr_p    rsp+0x100 ; hd: (G7,F8)..(G14,F15) F16..F23
    %define lr_q    rsp+0x130 ; hu: (G14,F14)..(G7,F7) l7 x8
    FIX_STRIDES  r2
    sub          r1, r2               ; top row, row k at r1+(k+1)*r2
    lea          r3, [3*r2]
    lea          r4, [r1+4*r2]        ; row 3
    movu       xm12, [r0+0*FENC_STRIDEB]
    vinserti128 m12, m12, [r0+4*FENC_STRIDEB], 1
    movu       xm13, [r0+1*FENC_STRIDEB]
    vinserti128 m13, m13, [r0+5*FENC_STRIDEB], 1
    movu       xm14, [r0+2*FENC_STRIDEB]
    vinserti128 m14, m14, [r0+6*FENC_STRIDEB], 1
    movu       xm15, [r0+3*FENC_STRIDEB]
    vinserti128 m15, m15, [r0+7*FENC_STRIDEB], 1

    ; neighbours
    movq        xm0, [r1+2*r2-8]
    punpcklwd   xm0, [r1+r2-8]
    movq        xm1, [r4-8]
    punpcklwd   xm1, [r1+r3-8]
    movq        xm2, [r4+2*r2-8]
    punpcklwd   xm2, [r4+r2-8]
    movq        xm3, [r4+4*r2-8]
    punpcklwd   xm3, [r4+r3-8]
    punpckhdq   xm1, xm0
    punpckhdq   xm3, xm2
    punpckhqdq  xm9, xm3, xm1         ; l7..l0
    movu        m10, [r1-2]           ; lt t0..t14
    movu        m11, [r1]             ; t0..t15
    movu         m0, [r1+2]
    pblendw      m1, m0, m11, 0x80
    vpblendd     m0, m0, m1, 0x80     ; t1..t15 t15
    ; edge E[i] = F2(U[i-1], U[i], U[i+1]), U = l7 l7 l6..l0 lt t0..t15 t15
    paddw        m0, m10
    psrlw        m0, 1
    pavgw        m8, m11, m0          ; E16..E31
    palignr     xm1, xm10, xm9, 2     ; l6..l0 lt
    palignr     xm2, xm10, xm9, 4     ; l5..l0 lt t0
    paddw       xm2, xm9
    psrlw       xm2, 1
    pavgw       xm2, xm1              ; E8..E15
    paddw       xm3, xm9, xm1
    psrlw       xm3, 1
    pavgw       xm3, xm9              ; E7 = F2(l7, l7, l6)
    pshuflw     xm3, xm3, q0000
    movd  [lr_edge+12], xm3           ; E6 = E7
    movu  [lr_edge+16], xm2
    movu  [lr_edge+32], m8
    vextracti128 xm4, m8, 1
    vpextrw [lr_edge+64], xm4, 7      ; E32 = E31

    ; v
    vbroadcasti128 m4, [r1]
    psubw        m0, m12, m4
    psubw        m1, m13, m4
    psubw        m2, m14, m4
    psubw        m3, m15, m4
    LOWRES_SATD  m6
    ; h
    vinserti128  m5, m9, xm9, 1
    pshufb       m0, m5, [lowres_h0]
    pshufb       m1, m5, [lowres_h1]
    pshufb       m2, m5, [lowres_h2]
    pshufb       m3, m5, [lowres_h3]
    LOWRES_DIFF10
    LOWRES_SATD  m7
    phaddw       m6, m7
    pmaddwd      m6, [pw_1]
    ; dc
    phaddw      xm4, xm11, xm9
    phaddw      xm4, xm4              ; s0 s1 s3 s2
    pshuflw     xm5, xm4, q1210
    pshuflw     xm4, xm4, q2213
    paddw       xm4, xm5              ; s0+s2 2*s1 2*s3 s1+s3
    paddw       xm4, [pw_4]
    psrlw       xm4, 3
    vpbroadcastq m4, xm4
    pshufb       m4, [intra_8x8c_dc_shuf]
    psubw        m0, m12, m4
    psubw        m1, m13, m4
    psubw        m2, m14, m4
    psubw        m3, m15, m4
    LOWRES_SATD  m7

    ; the x9 tables, once the edge stores have retired
    movu         m0, [lr_edge+12]
    movu         m1, [lr_edge+14]
    movu         m2, [lr_edge+16]
    pavgw        m3, m1, m2           ; G7..G22
    paddw        m0, m2
    psrlw        m0, 1
    pavgw        m0, m1               ; F7..F22
    movu         m4, [lr_edge+30]
    movu         m5, [lr_edge+32]
    movu        m11, [lr_edge+34]
    pavgw        m8, m5, m11          ; G16..G31
    paddw        m4, m11
    psrlw        m4, 1
    pavgw        m4, m5               ; F16..F31
    movu  [lr_f], m0
    movu  [lr_f+18], m4
    movu  [lr_g], m8
    vextracti128 [lr_ce+8], m3, 1
    movu  [lr_co+8], xm4
    movu  [lr_p+32], xm4
    vextracti128 xm5, m0, 1
    palignr     xm8, xm5, xm0, 2      ; F8..F15
    pshufb      xm1, xm8, [x9h_deint]
    movq  [lr_ce], xm1
    movhps [lr_co], xm1
    punpcklwd   xm2, xm3, xm8
    punpckhwd   xm5, xm3, xm8
    movu  [lr_p], xm2
    movu  [lr_p+16], xm5
    pshufb      xm2, xm3, [x9h_rev]
    pshufb      xm5, xm0, [x9h_rev]
    punpcklwd   xm8, xm2, xm5
    punpckhwd   xm2, xm5
    vpbroadcastw xm5, [lr_edge+14]
    movu  [lr_q], xm8
    movu  [lr_q+16], xm2
    movu  [lr_q+32], xm5

    ; p: max(0, (a + 16 + b*(x-3) + c*(y-3)) >> 5), saturating as predict_8x8c_p_core
    vinserti128  m0, m10, xm9, 1      ; lt t0..t6 | l7..l0
    vperm2i128   m1, m10, m10, 0x01   ; t7..t14 | lt t0..t6
    paddw       xm2, xm1, xm9         ; t7 + l7
    pmaddwd      m0, [lowres_p_w1]
    pmaddwd      m1, [lowres_p_w2]
    paddd        m0, m1
    phaddd       m0, m0
    phaddd       m0, m0               ; H | V
    psllw       xm2, 4
    vpbroadcastw m2, xm2
    paddw       m11, m2, [pw_16]      ; a + 16
    vpbroadcastw m3, xm0
    vextracti128 xm0, m0, 1
    vpbroadcastw m4, xm0
    pmulhrsw     m3, [pw_17408]       ; b
    pmulhrsw     m4, [pw_17408]       ; c
    pmullw       m8, m3, [lowres_p_x]
    pmullw       m5, m4, [lowres_p_y] ; c*(y-3), rows 0 | 4
    paddsw       m0, m8, m5
    paddw        m5, m4
    paddsw       m1, m8, m5
    paddw        m5, m4
    paddsw       m2, m8, m5
    paddw        m5, m4
    paddsw       m3, m8, m5
    pxor         m4, m4
    paddsw       m0, m11
    paddsw       m1, m11
    paddsw       m2, m11
    paddsw       m3, m11
    psraw        m0, 5
    psraw        m1, 5
    psraw        m2, 5
    psraw        m3, 5
    pmaxsw       m0, m4
    pmaxsw       m1, m4
    pmaxsw       m2, m4
    pmaxsw       m3, m4
    LOWRES_DIFF10
    LOWRES_SATD  m8
    phaddw       m7, m8
    pmaddwd      m7, [pw_1]
    phaddd       m6, m7               ; v h dc p

    LOWRES_ROWS10 [lr_f+20], [lr_f+22], [lr_f+24], [lr_f+26], [lr_f+28], [lr_f+30], [lr_f+32], [lr_f+34]
    LOWRES_SATD  m7                   ; ddl
    LOWRES_ROWS10 [lr_g+0], [lr_f+20], [lr_g+2], [lr_f+22], [lr_g+4], [lr_f+24], [lr_g+6], [lr_f+26]
    LOWRES_SATD  m8                   ; vl
    phaddw       m7, m8
    pmaddwd      m7, [pw_1]
    LOWRES_ROWS10 [lr_f+16], [lr_f+14], [lr_f+12], [lr_f+10], [lr_f+8], [lr_f+6], [lr_f+4], [lr_f+2]
    LOWRES_SATD  m8                   ; ddr
    LOWRES_ROWS10 [lr_ce+8], [lr_co+6], [lr_ce+6], [lr_co+4], [lr_ce+4], [lr_co+2], [lr_ce+2], [lr_co+0]
    LOWRES_SATD  m9                   ; vr
    phaddw       m8, m9
    pmaddwd      m8, [pw_1]
    phaddd       m7, m8               ; ddl vl ddr vr
    LOWRES_ROWS10 [lr_p+28], [lr_p+24], [lr_p+20], [lr_p+16], [lr_p+12], [lr_p+8], [lr_p+4], [lr_p+0]
    LOWRES_SATD  m8                   ; hd
    LOWRES_ROWS10 [lr_q+4], [lr_q+8], [lr_q+12], [lr_q+16], [lr_q+20], [lr_q+24], [lr_q+28], [lr_q+32]
    LOWRES_SATD  m9                   ; hu
    phaddw       m8, m9
    pmaddwd      m8, [pw_1]
    phaddd       m8, m8               ; hd hu hd hu

    vperm2i128   m0, m6, m7, 0x20
    vperm2i128   m1, m6, m7, 0x31
    paddd        m0, m1
    vextracti128 xm1, m0, 1
    pminud      xm0, xm1
    vextracti128 xm1, m8, 1
    paddd       xm1, xm8
    pminud      xm0, xm1
    pshufd      xm1, xm0, q1032
    pminud      xm0, xm1
    pshufd      xm1, xm0, q2301
    pminud      xm0, xm1
    movd        eax, xm0
    RET

%endif ; HIGH_BIT_DEPTH && ARCH_X86_64

%if HIGH_BIT_DEPTH == 0
%define LOAD_SUMSUB_8x4P LOAD_SUMSUB8_16x4P_AVX2
%define LOAD_DUP_4x8P LOAD_DUP_4x16P_AVX2
%define TRANS TRANS_SSE4
INIT_YMM avx2
HADAMARD_AC_SSE2
%if ARCH_X86_64
SA8D_SATD
%endif

HADAMARD_AC_8x8_AVX2

%if ARCH_X86_64
; 8-bit, ymm: 8 pixel rows as [row row | row+8 row+8], lane 1 at r4 = r0+8*stride
%macro LOAD_DUP_8x2P_VSTACK 2 ; dst, offset
    vpbroadcastq m%1, [r0+%2]
    vpbroadcastq m11, [r4+%2]
    vpblendd     m%1, m%1, m11, 0xf0
%endmacro

%macro LOAD_INC_8x4W_VSTACK 5
    LOAD_DUP_8x2P_VSTACK %1, r2
    LOAD_DUP_8x2P_VSTACK %2, r1
    LOAD_DUP_8x2P_VSTACK %3, r1*2
    LOAD_DUP_8x2P_VSTACK %4, 0
%ifidn %1, 0
    lea       r0, [r0+r1*4]
    lea       r4, [r4+r1*4]
%endif
    HSUMSUB %1, %2, %3, %4, %5
%endmacro

; 8x16: lane 0 is the top 8x8, lane 1 the bottom one, one pass like 16x8
%define LOAD_INC_8x4W LOAD_INC_8x4W_VSTACK
HADAMARD_AC_SSE2 v
%define LOAD_INC_8x4W LOAD_INC_8x4W_SSSE3
cglobal pixel_hadamard_ac_8x16, 2,5,12
    mov   r3, rsp
    and  rsp, ~(mmsize-1)
    sub  rsp, mmsize*3
    lea   r2, [r1*3]
    lea   r4, [r0+r1*8]
    call hadamard_ac_8x8v
    HADAMARD_AC_WXH_SUM_SSE2 8, 16
    movd edx, xm0
    movd eax, xm1
    shr  edx, 2
    shr  eax, 1
    shl  rdx, 32
    add  rax, rdx
    mov  rsp, r3
    RET
%endif

;-----------------------------------------------------------------------------
; int pixel_ssd_8xN( uint8_t *, intptr_t, uint8_t *, intptr_t )
; four 8 pixel rows a ymm, the two sources interleaved for pmaddubsw
;-----------------------------------------------------------------------------
%macro SSD_W8_4ROWS_AVX2 1 ; first
    movq        xm1, [r0]
    movhps      xm1, [r0+r1]
    movq        xm3, [r0+r1*2]
    movhps      xm3, [r0+r4]
    movq        xm2, [r2]
    movhps      xm2, [r2+r3]
    movq        xm4, [r2+r3*2]
    movhps      xm4, [r2+r5]
    vinserti128  m1, m1, xm3, 1
    vinserti128  m2, m2, xm4, 1
    punpckhbw    m3, m1, m2
    punpcklbw    m1, m2
    pmaddubsw    m1, m5
    pmaddubsw    m3, m5
    pmaddwd      m1, m1
    pmaddwd      m3, m3
%if %1
    paddd        m0, m1, m3
%else
    paddd        m1, m3
    paddd        m0, m1
%endif
%endmacro

%macro SSD_W8_AVX2 1 ; height
cglobal pixel_ssd_8x%1, 4,6,6
    lea          r4, [r1*3]
    lea          r5, [r3*3]
    mova         m5, [hsub_mul]
    SSD_W8_4ROWS_AVX2 1
%rep %1/4-1
    lea          r0, [r0+r1*4]
    lea          r2, [r2+r3*4]
    SSD_W8_4ROWS_AVX2 0
%endrep
    vextracti128 xm1, m0, 1
    paddd       xm0, xm1
    pshufd      xm1, xm0, q1032
    paddd       xm0, xm1
    pshufd      xm1, xm0, q2301
    paddd       xm0, xm1
    movd        eax, xm0
    RET
%endmacro

SSD_W8_AVX2  8
SSD_W8_AVX2 16

;-----------------------------------------------------------------------------
; uint64_t pixel_var_8xN( uint8_t *, intptr_t )
; four 8 pixel rows a ymm: psadbw sums, zero extended pmaddwd squares
;-----------------------------------------------------------------------------
%macro VAR_W8_4ROWS_AVX2 1 ; first
    movq        xm0, [r0]
    movhps      xm0, [r0+r1]
    movq        xm1, [r0+r1*2]
    movhps      xm1, [r0+r2]
    vinserti128  m0, m0, xm1, 1
%if %1
    psadbw       m5, m0, m4
%else
    psadbw       m1, m0, m4
%endif
    punpcklbw    m2, m0, m4
    punpckhbw    m0, m4
    pmaddwd      m2, m2
    pmaddwd      m0, m0
%if %1
    paddd        m6, m2, m0
%else
    paddd        m5, m1
    paddd        m2, m0
    paddd        m6, m2
%endif
%endmacro

%macro VAR_W8_AVX2 1 ; height
cglobal pixel_var_8x%1, 2,3,7
    pxor         m4, m4
    lea          r2, [r1*3]
    VAR_W8_4ROWS_AVX2 1
%rep %1/4-1
    lea          r0, [r0+r1*4]
    VAR_W8_4ROWS_AVX2 0
%endrep
    pshufd       m0, m6, q2301
    paddd        m6, m0              ; squares, dword pairs
    vpblendd     m5, m5, m6, 0xaa    ; sum, squares in each qword
    vextracti128 xm0, m5, 1
    paddd       xm5, xm0
    pshufd      xm0, xm5, q1032
    paddd       xm5, xm0
%if ARCH_X86_64
    movq        rax, xm5
%else
    movd        eax, xm5
    pextrd      edx, xm5, 1
%endif
    RET
%endmacro

VAR_W8_AVX2  8
VAR_W8_AVX2 16


; 8 pixel rows %3 and %4 as [%3 %3 | %4 %4]
%macro LOAD_DUP_8x2P_AVX2 4 ; dst, tmp, 2*mem
    vpbroadcastq m%1, %3
    vpbroadcastq m%2, %4
    vpblendd     m%1, m%1, m%2, 0xf0
%endmacro

%macro LOAD_SUMSUB_8x2P_AVX2 7 ; dst, 2*tmp, mul, offset, fenc row +4, ref row +4
    LOAD_DUP_8x2P_AVX2 %1, %2, [r0+%5*r1], [r0+%6]
    LOAD_DUP_8x2P_AVX2 %2, %3, [r2+%5*r3], [r2+%7]
    pmaddubsw m%1, m%4
    pmaddubsw m%2, m%4
    psubw     m%1, m%2
%endmacro

%macro LOAD_SUMSUB_8x8P_AVX2 7 ; 4*dst, 2*tmp, mul]
    LOAD_SUMSUB_8x2P_AVX2 %1, %5, %6, %7, 0, 4*r1, 4*r3
    LOAD_SUMSUB_8x2P_AVX2 %2, %5, %6, %7, 1, r4, r5
    lea      r0, [r0+2*r1]
    lea      r2, [r2+2*r3]
    LOAD_SUMSUB_8x2P_AVX2 %3, %5, %6, %7, 0, 4*r1, 4*r3
    LOAD_SUMSUB_8x2P_AVX2 %4, %5, %6, %7, 1, r4, r5
%endmacro

%macro SATD_START_AVX2 2-3 0
    FIX_STRIDES r1, r3
%if %3
    mova    %2, [hmul_8p]
    lea     r4, [5*r1]
    lea     r5, [5*r3]
%else
    mova    %2, [hmul_16p]
    lea     r4, [3*r1]
    lea     r5, [3*r3]
%endif
    pxor    %1, %1
%endmacro

%define TRANS TRANS_SSE4
INIT_YMM avx2
cglobal pixel_satd_16x8_internal
    LOAD_SUMSUB_16x4P_AVX2 0, 1, 2, 3, 4, 5, 7, r0, r2, 1
    SATD_8x4_SSE 0, 0, 1, 2, 3, 4, 5, 6
    LOAD_SUMSUB_16x4P_AVX2 0, 1, 2, 3, 4, 5, 7, r0, r2, 0
    SATD_8x4_SSE 0, 0, 1, 2, 3, 4, 5, 6
    ret

cglobal pixel_satd_16x16, 4,6,8
    SATD_START_AVX2 m6, m7
    call pixel_satd_16x8_internal
    lea  r0, [r0+4*r1]
    lea  r2, [r2+4*r3]
pixel_satd_16x8_internal:
    call pixel_satd_16x8_internal
    vextracti128 xm0, m6, 1
    paddw        xm0, xm6
    SATD_END_SSE2 xm0
    RET

cglobal pixel_satd_16x8, 4,6,8
    SATD_START_AVX2 m6, m7
    jmp pixel_satd_16x8_internal

cglobal pixel_satd_8x8_internal
    LOAD_SUMSUB_8x8P_AVX2 0, 1, 2, 3, 4, 5, 7
    SATD_8x4_SSE 0, 0, 1, 2, 3, 4, 5, 6
    ret

cglobal pixel_satd_8x16, 4,6,8
    SATD_START_AVX2 m6, m7, 1
    call pixel_satd_8x8_internal
    lea  r0, [r0+2*r1]
    lea  r2, [r2+2*r3]
    lea  r0, [r0+4*r1]
    lea  r2, [r2+4*r3]
    call pixel_satd_8x8_internal
    vextracti128 xm0, m6, 1
    paddw        xm0, xm6
    SATD_END_SSE2 xm0
    RET

cglobal pixel_satd_8x8, 4,6,8
    SATD_START_AVX2 m6, m7, 1
    call pixel_satd_8x8_internal
    vextracti128 xm0, m6, 1
    paddw        xm0, xm6
    SATD_END_SSE2 xm0
    RET

%if ARCH_X86_64
;-----------------------------------------------------------------------------
; int pixel_satd_avg2_WxH( uint8_t *fenc, uint8_t *src1, uint8_t *src2, intptr_t stride )
; satd( fenc, (src1+src2+1)>>1 ) with the layout of the satd functions above:
; only the reference rows change, to pavgb of the two sources.
;-----------------------------------------------------------------------------
; 16 wide: rows %5, %6 (fenc offsets) and %7, %8 (source offsets), each row in both lanes
%macro SATD_AVG2_SUMSUB16x2 8 ; 2*dst, 2*tmp, 2*fenc offset, 2*src offset; m8 = tmp
    vbroadcasti128 m%1, [r0+%5]
    vbroadcasti128 m%2, [r0+%6]
    vbroadcasti128 m%3, [r1+%7]
    vbroadcasti128 m8,  [r2+%7]
    pavgb          m%3, m8
    vbroadcasti128 m%4, [r1+%8]
    vbroadcasti128 m8,  [r2+%8]
    pavgb          m%4, m8
    DIFF_SUMSUB_SSSE3 %1, %3, %2, %4, 7
%endmacro

; four 16 pixel rows, r4 = 3*stride
%macro SATD_AVG2_16x4 0
    SATD_AVG2_SUMSUB16x2 0, 1, 4, 5, 0, FENC_STRIDE, 0, r3
    SATD_AVG2_SUMSUB16x2 2, 3, 4, 5, 2*FENC_STRIDE, 3*FENC_STRIDE, 2*r3, r4
    SATD_8x4_SSE 0, 0, 1, 2, 3, 4, 5, 6
%endmacro

; 8 wide, lanes = rows k, k+4 as in LOAD_SUMSUB_8x8P_AVX2 (r5/r6 = src1/src2
; four rows down)
%macro SATD_AVG2_SUMSUB8 3 ; dst (number), k, source offset
    LOAD_DUP_8x2P_AVX2 %1, 4, [r0+%2*FENC_STRIDE], [r0+(%2+4)*FENC_STRIDE]
    LOAD_DUP_8x2P_AVX2 4, 5, [r1+%3], [r5+%3]
    LOAD_DUP_8x2P_AVX2 8, 5, [r2+%3], [r6+%3]
    pavgb          m4, m8
    pmaddubsw     m%1, m7
    pmaddubsw      m4, m7
    psubw         m%1, m4
%endmacro

%macro SATD_AVG2_8x8 0
    SATD_AVG2_SUMSUB8 0, 0, 0
    SATD_AVG2_SUMSUB8 1, 1, r3
    SATD_AVG2_SUMSUB8 2, 2, 2*r3
    SATD_AVG2_SUMSUB8 3, 3, r4
    SATD_8x4_SSE 0, 0, 1, 2, 3, 4, 5, 6
%endmacro

%macro SATD_AVG2_END 0
    vextracti128 xm0, m6, 1
    paddw        xm0, xm6
    SATD_END_SSE2 xm0
%endmacro

cglobal pixel_satd_avg2_16x16, 4,5,9
    mova     m7, [hmul_16p]
    lea      r4, [3*r3]
    pxor     m6, m6
    SATD_AVG2_16x4
%rep 3
    lea      r1, [r1+4*r3]
    lea      r2, [r2+4*r3]
    add      r0, 4*FENC_STRIDE
    SATD_AVG2_16x4
%endrep
    SATD_AVG2_END

cglobal pixel_satd_avg2_16x8, 4,5,9
    mova     m7, [hmul_16p]
    lea      r4, [3*r3]
    pxor     m6, m6
    SATD_AVG2_16x4
    lea      r1, [r1+4*r3]
    lea      r2, [r2+4*r3]
    add      r0, 4*FENC_STRIDE
    SATD_AVG2_16x4
    SATD_AVG2_END

cglobal pixel_satd_avg2_8x16, 4,7,9
    mova     m7, [hmul_8p]
    lea      r4, [3*r3]
    lea      r5, [r1+4*r3]
    lea      r6, [r2+4*r3]
    pxor     m6, m6
    SATD_AVG2_8x8
    lea      r1, [r1+8*r3]
    lea      r2, [r2+8*r3]
    lea      r5, [r5+8*r3]
    lea      r6, [r6+8*r3]
    add      r0, 8*FENC_STRIDE
    SATD_AVG2_8x8
    SATD_AVG2_END

cglobal pixel_satd_avg2_8x8, 4,7,9
    mova     m7, [hmul_8p]
    lea      r4, [3*r3]
    lea      r5, [r1+4*r3]
    lea      r6, [r2+4*r3]
    pxor     m6, m6
    SATD_AVG2_8x8
    SATD_AVG2_END

;-----------------------------------------------------------------------------
; void pixel_satd_fenc_pre_16x16( int16_t dst[256], uint8_t *fenc )
; void pixel_satd_fenc_pre_8x8( int16_t dst[64], uint8_t *fenc )
; int  pixel_satd_pre_WxH( int16_t *fenc_pre, uint8_t *pix, intptr_t stride )
; int  pixel_satd_avg2_pre_WxH( int16_t *fenc_pre, uint8_t *src1, uint8_t *src2, intptr_t stride )
; fenc_pre holds fenc's first (pmaddubsw) stage in the layout of the satd
; functions above, a 32 byte register a row (16 wide) or a row pair k, k+4
; (8 wide, 4 per 8x8, an 8x16 reading two 8x8 in a row). The stage is linear,
; so the candidate's is computed and fenc_pre subtracted: every value of the
; transform is negated and the satd is unchanged.
;-----------------------------------------------------------------------------
cglobal pixel_satd_fenc_pre_16x16, 2,2,2
    mova     m1, [hmul_16p]
%assign fpre_i 0
%rep 16
    vbroadcasti128 m0, [r1+fpre_i*FENC_STRIDE]
    pmaddubsw      m0, m1
    mova [r0+fpre_i*32], m0
%assign fpre_i fpre_i+1
%endrep
    RET

cglobal pixel_satd_fenc_pre_8x8, 2,2,3
    mova     m2, [hmul_8p]
%assign fpre_i 0
%rep 4
    LOAD_DUP_8x2P_AVX2 0, 1, [r1+fpre_i*FENC_STRIDE], [r1+(fpre_i+4)*FENC_STRIDE]
    pmaddubsw      m0, m2
    mova [r0+fpre_i*32], m0
%assign fpre_i fpre_i+1
%endrep
%undef fpre_i
    RET

; SATD_8x4_SSE 0, 0, 1, 2, 3, 4, 5, 6, %1 (avx512icl: SATD_ICL_8x4, k1 = 0x5555)
%macro SATD_PRE_UNIT 1
%if cpuflag(avx512icl)
    SATD_ICL_8x4 %1
%else
    SATD_8x4_SSE 0, 0, 1, 2, 3, 4, 5, 6, %1
%endif
%endmacro

; [%2 %2 | %3 %3] (avx512icl: k2 = 0xc)
%macro SATD_PRE_DUP8 3 ; dst, 2*mem
%if cpuflag(avx512icl)
    SATD_ICL_DUP8 %1, %2, %3
%else
    LOAD_DUP_8x2P_AVX2 %1, 4, %2, %3
%endif
%endmacro

%macro SATD_PRE_KMASK 1 ; gpr (dword) to clobber
%if cpuflag(avx512icl)
    SATD_ICL_KMASK %1
%endif
%endmacro

; four 16 pixel rows (r3 = 3*stride) less fenc_pre rows %1 to %1+3
%macro SATD_PRE_16x4 2 ; fenc_pre row, swap/add
    vbroadcasti128 m0, [r1]
    vbroadcasti128 m1, [r1+r2]
    vbroadcasti128 m2, [r1+2*r2]
    vbroadcasti128 m3, [r1+r3]
    pmaddubsw      m0, m7
    pmaddubsw      m1, m7
    pmaddubsw      m2, m7
    pmaddubsw      m3, m7
    psubw          m0, [r0+(%1+0)*32]
    psubw          m1, [r0+(%1+1)*32]
    psubw          m2, [r0+(%1+2)*32]
    psubw          m3, [r0+(%1+3)*32]
    SATD_PRE_UNIT %2
%endmacro

; rows k, k+4 (r1, r4 = r1+4*stride, %2 = k*stride) less fenc_pre's
%macro SATD_PRE_SUMSUB8 3 ; dst (number), source offset, fenc_pre offset
    SATD_PRE_DUP8 %1, [r1+%2], [r4+%2]
    pmaddubsw     m%1, m7
    psubw         m%1, [r0+%3]
%endmacro

%macro SATD_PRE_8x8 2 ; fenc_pre offset, swap/add
    SATD_PRE_SUMSUB8 0, 0,    %1
    SATD_PRE_SUMSUB8 1, r2,   %1+32
    SATD_PRE_SUMSUB8 2, 2*r2, %1+64
    SATD_PRE_SUMSUB8 3, r3,   %1+96
    SATD_PRE_UNIT %2
%endmacro

%macro SATD_PRE_FUNCS 0
cglobal pixel_satd_pre_16x16, 3,4,8
    SATD_PRE_KMASK r3d
    mova     m7, [hmul_16p]
    lea      r3, [3*r2]
    SATD_PRE_16x4 0, swap
    lea      r1, [r1+4*r2]
    SATD_PRE_16x4 4, add
    lea      r1, [r1+4*r2]
    SATD_PRE_16x4 8, add
    lea      r1, [r1+4*r2]
    SATD_PRE_16x4 12, add
    SATD_AVG2_END

cglobal pixel_satd_pre_16x8, 3,4,8
    SATD_PRE_KMASK r3d
    mova     m7, [hmul_16p]
    lea      r3, [3*r2]
    SATD_PRE_16x4 0, swap
    lea      r1, [r1+4*r2]
    SATD_PRE_16x4 4, add
    SATD_AVG2_END

cglobal pixel_satd_pre_8x16, 3,5,8
    SATD_PRE_KMASK r3d
    mova     m7, [hmul_8p]
    lea      r3, [3*r2]
    lea      r4, [r1+4*r2]
    SATD_PRE_8x8 0, swap
    lea      r1, [r1+8*r2]
    lea      r4, [r4+8*r2]
    SATD_PRE_8x8 128, add
    SATD_AVG2_END

cglobal pixel_satd_pre_8x8, 3,5,8
    SATD_PRE_KMASK r3d
    mova     m7, [hmul_8p]
    lea      r3, [3*r2]
    lea      r4, [r1+4*r2]
    SATD_PRE_8x8 0, swap
    SATD_AVG2_END
%endmacro

SATD_PRE_FUNCS

; 16 wide: row (%2 = k*stride) of pavgb( src1, src2 ) less fenc_pre's
%macro SATD_AVG2_PRE_ROW16 3 ; dst (number), source offset, fenc_pre offset
    vbroadcasti128 m%1, [r1+%2]
    vbroadcasti128 m4, [r2+%2]
    pavgb          m%1, m4
    pmaddubsw      m%1, m7
    psubw          m%1, [r0+%3]
%endmacro

%macro SATD_AVG2_PRE_16x4 2 ; fenc_pre row, swap/add
    SATD_AVG2_PRE_ROW16 0, 0,    (%1+0)*32
    SATD_AVG2_PRE_ROW16 1, r3,   (%1+1)*32
    SATD_AVG2_PRE_ROW16 2, 2*r3, (%1+2)*32
    SATD_AVG2_PRE_ROW16 3, r4,   (%1+3)*32
    SATD_PRE_UNIT %2
%endmacro

; 8 wide: rows k, k+4 (r5/r6 = src1/src2 four rows down)
%macro SATD_AVG2_PRE_SUMSUB8 3 ; dst (number), source offset, fenc_pre offset
    SATD_PRE_DUP8 %1, [r1+%2], [r5+%2]
    SATD_PRE_DUP8 5, [r2+%2], [r6+%2]
    pavgb         m%1, m5
    pmaddubsw     m%1, m7
    psubw         m%1, [r0+%3]
%endmacro

%macro SATD_AVG2_PRE_8x8 2 ; fenc_pre offset, swap/add
    SATD_AVG2_PRE_SUMSUB8 0, 0,    %1
    SATD_AVG2_PRE_SUMSUB8 1, r3,   %1+32
    SATD_AVG2_PRE_SUMSUB8 2, 2*r3, %1+64
    SATD_AVG2_PRE_SUMSUB8 3, r4,   %1+96
    SATD_PRE_UNIT %2
%endmacro

%macro SATD_AVG2_PRE_FUNCS 0
cglobal pixel_satd_avg2_pre_16x16, 4,5,8
    SATD_PRE_KMASK r4d
    mova     m7, [hmul_16p]
    lea      r4, [3*r3]
    SATD_AVG2_PRE_16x4 0, swap
%assign fpre_i 4
%rep 3
    lea      r1, [r1+4*r3]
    lea      r2, [r2+4*r3]
    SATD_AVG2_PRE_16x4 fpre_i, add
%assign fpre_i fpre_i+4
%endrep
%undef fpre_i
    SATD_AVG2_END

cglobal pixel_satd_avg2_pre_16x8, 4,5,8
    SATD_PRE_KMASK r4d
    mova     m7, [hmul_16p]
    lea      r4, [3*r3]
    SATD_AVG2_PRE_16x4 0, swap
    lea      r1, [r1+4*r3]
    lea      r2, [r2+4*r3]
    SATD_AVG2_PRE_16x4 4, add
    SATD_AVG2_END

cglobal pixel_satd_avg2_pre_8x16, 4,7,8
    SATD_PRE_KMASK r4d
    mova     m7, [hmul_8p]
    lea      r4, [3*r3]
    lea      r5, [r1+4*r3]
    lea      r6, [r2+4*r3]
    SATD_AVG2_PRE_8x8 0, swap
    lea      r1, [r1+8*r3]
    lea      r2, [r2+8*r3]
    lea      r5, [r5+8*r3]
    lea      r6, [r6+8*r3]
    SATD_AVG2_PRE_8x8 128, add
    SATD_AVG2_END

cglobal pixel_satd_avg2_pre_8x8, 4,7,8
    SATD_PRE_KMASK r4d
    mova     m7, [hmul_8p]
    lea      r4, [3*r3]
    lea      r5, [r1+4*r3]
    lea      r6, [r2+4*r3]
    SATD_AVG2_PRE_8x8 0, swap
    SATD_AVG2_END
%endmacro

SATD_AVG2_PRE_FUNCS

;-----------------------------------------------------------------------------
; satd_bi/satd_bi4 (see SATD_BI) against fenc_pre, the rows as satd_pre's. The
; weighted average is BIWEIGHT_SSSE3's: pmaddubsw by (w, 64-w), pmulhrsw by 512.
;-----------------------------------------------------------------------------
; 16 wide: rows %3, %3+1 of list %2 in the lanes of m%1; m4 tmp
%macro BI_PRE_SRC16x2 3
    BI_ROW_OFF %2, %3
    %xdefine bi_o0 bi_o
    BI_ROW_OFF %2, %3+1
    movu          xm%1, [bi_p%2a+bi_o0]
    vinserti128    m%1, m%1, [bi_p%2a+bi_o], 1
%if bi_four
    movu           xm4, [bi_p%2b+bi_o0]
    vinserti128     m4, m4, [bi_p%2b+bi_o], 1
    pavgb          m%1, m4
%endif
%endmacro

; 16 wide, weighted: m%1, m%2 = rows %3, %3+1 less fenc_pre's (pass row bi_fr)
%macro BI_PRE_W16x2 3
    BI_PRE_SRC16x2 %1, 0, %3
    BI_PRE_SRC16x2 %2, 1, %3
    punpckhbw       m4, m%1, m%2
    punpcklbw      m%1, m%2
    pmaddubsw       m4, m8
    pmaddubsw      m%1, m8
    pmulhrsw        m4, m9
    pmulhrsw       m%1, m9
    packuswb       m%1, m4
    vpermq         m%2, m%1, q3232
    vpermq         m%1, m%1, q1010
    pmaddubsw      m%1, m7
    pmaddubsw      m%2, m7
    psubw          m%1, [r0+(bi_fr+%3)*32]
    psubw          m%2, [r0+(bi_fr+%3+1)*32]
%endmacro

; 16 wide, pavgb: m%1 = row %2 less fenc_pre's
%macro BI_PRE_A16 2
    BI_ROW_OFF 0, %2
    vbroadcasti128 m%1, [bi_p0a+bi_o]
%if bi_four
    vbroadcasti128  m4, [bi_p0b+bi_o]
    pavgb          m%1, m4
%endif
    BI_ROW_OFF 1, %2
    vbroadcasti128  m4, [bi_p1a+bi_o]
%if bi_four
    vbroadcasti128  m5, [bi_p1b+bi_o]
    pavgb           m4, m5
%endif
    pavgb          m%1, m4
    pmaddubsw      m%1, m7
    psubw          m%1, [r0+(bi_fr+%2)*32]
%endmacro

; 8 wide: list %2's rows %3, %3+4 as [k k | k+4 k+4] in m%1; m4, m10 tmp
%macro BI_PRE_SRC8 3
    BI_ROW_OFF %2, %3
    SATD_PRE_DUP8 %1, [bi_p%2a+bi_o], [bi_q%2a+bi_o]
%if bi_four
    SATD_PRE_DUP8 10, [bi_p%2b+bi_o], [bi_q%2b+bi_o]
    pavgb          m%1, m10
%endif
%endmacro

; 8 wide: m%1 = rows %2, %2+4 less fenc_pre's (the 8x8's at byte bi_fp)
%macro BI_PRE_8 2
    BI_PRE_SRC8 %1, 0, %2
    BI_PRE_SRC8  5, 1, %2
%if bi_weight
    punpcklbw      m%1, m5
    pmaddubsw      m%1, m8
    pmulhrsw       m%1, m9
    packuswb       m%1, m%1
%else
    pavgb          m%1, m5
%endif
    pmaddubsw      m%1, m7
    psubw          m%1, [r0+bi_fp+%2*32]
%endmacro

%macro SATD_BI_BODY 2 ; height, weighted
%assign bi_weight %2
%if bi_wide
    mova            m7, [hmul_16p]
%else
    mova            m7, [hmul_8p]
%endif
%if bi_weight
    movzx        bi_wd, bi_wb
    imul         bi_wd, bi_wd, -255
    add          bi_wd, 64<<8 ; w | (64-w)<<8 as in BIWEIGHT_START_SSSE3
    movd           xm8, bi_wd
    vpbroadcastw    m8, xm8
    vpbroadcastd    m9, [pw_512]
%endif
%assign bi_pass 0
%if bi_wide
%rep %1/4
%if bi_pass
    BI_NEXT 4
%endif
%assign bi_fr 4*bi_pass
%if bi_weight
    BI_PRE_W16x2 0, 1, 0
    BI_PRE_W16x2 2, 3, 2
%else
    BI_PRE_A16 0, 0
    BI_PRE_A16 1, 1
    BI_PRE_A16 2, 2
    BI_PRE_A16 3, 3
%endif
    BI_SATD_PASS 0
%assign bi_pass bi_pass+1
%endrep
%else
%rep %1/8
%if bi_pass
    BI_NEXT 8
%endif
%assign bi_fp 128*bi_pass
    BI_PRE_8 0, 0
    BI_PRE_8 1, 1
    BI_PRE_8 2, 2
    BI_PRE_8 3, 3
    BI_SATD_PASS 0
%assign bi_pass bi_pass+1
%endrep
%endif
    SATD_AVG2_END
%endmacro

SATD_BI 16, 16, 0
SATD_BI 16,  8, 0
SATD_BI  8, 16, 0
SATD_BI  8,  8, 0
SATD_BI 16, 16, 1
SATD_BI 16,  8, 1
SATD_BI  8, 16, 1
SATD_BI  8,  8, 1

;-----------------------------------------------------------------------------
; void intra_satd_x3_16x16( uint8_t *fenc, uint8_t *fdec, int res[3] ) (V, H, DC)
; With the layout of the satd functions above, the first (pmaddubsw) stage of a
; row is linear, so fenc's is computed once for the three modes, and V's and
; DC's, being the same for every row, once for the block.
;-----------------------------------------------------------------------------
; word accumulator m%1 -> 4 dword sums in xm%1
%macro INTRA_X3_FOLD 1
    vextracti128 xm4, m%1, 1
    paddw        xm%1, xm4
    pmaddwd      xm%1, [pw_1]
%endmacro

%macro INTRA_X3_LEFT4 2 ; dst gpr, first row
    movzx         %1, byte [r1+%2*FDEC_STRIDE-1]
%assign intra_x3_y %2+1
%rep 3
    movzx         r4d, byte [r1+intra_x3_y*FDEC_STRIDE-1]
    add           %1, r4d
%assign intra_x3_y intra_x3_y+1
%endrep
%endmacro

; SATD_8x4_SSE 0, 0, 1, 2, 3, 4, 5, %1 (avx512icl: SATD_ICL_8x4, k1 = 0x5555)
%macro INTRA_X3_SATD 1 ; accumulator
%if cpuflag(avx512icl)
    SATD_ICL_8x4 add, %1
%else
    SATD_8x4_SSE 0, 0, 1, 2, 3, 4, 5, %1
%endif
%endmacro

; avx2, and avx512icl after the SATD_ICL macros
%macro INTRA_SATD_X3_8BIT 0
cglobal intra_satd_x3_16x16, 3,5,16
    ; DC = (sum of top + sum of left + 16) >> 5
    movzx         r3d, byte [r1-1]
%assign intra_x3_y 1
%rep 15
    movzx         r4d, byte [r1+intra_x3_y*FDEC_STRIDE-1]
    add           r3d, r4d
%assign intra_x3_y intra_x3_y+1
%endrep
    pxor          xm0, xm0
    movu          xm1, [r1-FDEC_STRIDE]
    psadbw        xm1, xm0
    movhlps       xm0, xm1
    paddw         xm1, xm0
    movd          r4d, xm1
    lea           r3d, [r3+r4+16]
    shr           r3d, 5
%if cpuflag(avx512icl)
    mov           r4d, 0x5555
    kmovd          k1, r4d
%endif
    mova           m7, [hmul_16p]
    movd         xm13, r3d
    vpbroadcastb  m13, xm13
    pmaddubsw     m13, m7                  ; DC, first stage
    vbroadcasti128 m12, [r1-FDEC_STRIDE]
    pmaddubsw     m12, m7                  ; V, first stage
    pxor          m14, m14
    pxor          m15, m15
    pxor           m6, m6
%assign intra_x3_g 0
%rep 4
%assign intra_x3_k 0
%rep 4
    %assign intra_x3_f 8+intra_x3_k
    vbroadcasti128 m %+ intra_x3_f, [r0+(4*intra_x3_g+intra_x3_k)*FENC_STRIDE]
    pmaddubsw      m %+ intra_x3_f, m7
%assign intra_x3_k intra_x3_k+1
%endrep
    psubw          m0, m8, m12             ; V
    psubw          m1, m9, m12
    psubw          m2, m10, m12
    psubw          m3, m11, m12
    INTRA_X3_SATD 14
%assign intra_x3_k 0
%rep 4                                     ; H: the row's left neighbour
    %assign intra_x3_f 8+intra_x3_k
    vpbroadcastb   m %+ intra_x3_k, [r1+(4*intra_x3_g+intra_x3_k)*FDEC_STRIDE-1]
    pmaddubsw      m %+ intra_x3_k, m7
    psubw          m %+ intra_x3_k, m %+ intra_x3_f, m %+ intra_x3_k
%assign intra_x3_k intra_x3_k+1
%endrep
    INTRA_X3_SATD 15
    psubw          m0, m8, m13             ; DC
    psubw          m1, m9, m13
    psubw          m2, m10, m13
    psubw          m3, m11, m13
    INTRA_X3_SATD 6
%assign intra_x3_g intra_x3_g+1
%endrep
    INTRA_X3_FOLD 14
    INTRA_X3_FOLD 15
    INTRA_X3_FOLD 6
    ; transpose-add the three 4 dword sums into res[0..2]
    punpckldq     xm4, xm14, xm15
    punpckhdq    xm14, xm15
    paddd        xm14, xm4                 ; V0+V2 H0+H2 V1+V3 H1+H3
    punpckhdq     xm5, xm6, xm6
    punpckldq     xm6, xm6
    paddd         xm6, xm5                 ; D0+D2 D0+D2 D1+D3 D1+D3
    punpcklqdq    xm4, xm14, xm6
    punpckhqdq   xm14, xm6
    paddd        xm14, xm4                 ; V H D D
    movq        [r2], xm14
    pextrd    [r2+8], xm14, 2
    RET

;-----------------------------------------------------------------------------
; void intra_satd_x3_8x8c( uint8_t *fenc, uint8_t *fdec, int res[3] ) (DC, H, V)
; 8 wide layout of pixel_satd_8x8: lanes = rows k, k+4, each row twice
;-----------------------------------------------------------------------------
cglobal intra_satd_x3_8x8c, 3,7,16
    movq          xm0, [r1-FDEC_STRIDE]
    pxor          xm1, xm1
    punpcklbw     xm0, xm1
    pmaddwd       xm0, [pw_1]
%if cpuflag(avx512icl)
    pshufd        xm1, xm0, q2301
    paddd         xm0, xm1                 ; s0 s0 s1 s1
    movd          r3d, xm0
    pextrd        r5d, xm0, 2
    mov           r4d, 0x5555000c
    kmovd          k2, r4d
    kshiftrd       k1, k2, 16
    mov           r4d, 0xffff0000
    kmovd          k3, r4d
%else
    phaddd        xm0, xm0                 ; s0 s1 (top 0-3, top 4-7)
    movd          r3d, xm0
    pextrd        r5d, xm0, 1
%endif
    INTRA_X3_LEFT4 r6d, 0                  ; s2
    lea           r3d, [r3+r6+4]
    shr           r3d, 3                   ; dc0 = (s0 + s2 + 4) >> 3
    lea           r6d, [r5+2]
    shr           r6d, 2                   ; dc1 = (s1 + 2) >> 2
    shl           r6d, 8
    or            r3d, r6d
    INTRA_X3_LEFT4 r6d, 4                  ; s3
    lea           r4d, [r6+2]
    shr           r4d, 2                   ; dc2 = (s3 + 2) >> 2
    shl           r4d, 16
    or            r3d, r4d
    lea           r4d, [r5+r6+4]
    shr           r4d, 3                   ; dc3 = (s1 + s3 + 4) >> 3
    shl           r4d, 24
    or            r3d, r4d
    mova           m7, [hmul_8p]
    movd         xm13, r3d
    vpbroadcastd  m13, xm13
    pshufb        m13, [intra_8x8c_dc_shufb]
    pmaddubsw     m13, m7                  ; DC, first stage
    vpbroadcastq  m12, [r1-FDEC_STRIDE]
    pmaddubsw     m12, m7                  ; V, first stage
%assign intra_x3_k 0
%rep 4
    %assign intra_x3_f 8+intra_x3_k
%if cpuflag(avx512icl)
    vpbroadcastq   m %+ intra_x3_f, [r0+intra_x3_k*FENC_STRIDE]
    vpbroadcastq   m %+ intra_x3_f {k2}, [r0+(intra_x3_k+4)*FENC_STRIDE]
%else
    movq          xm %+ intra_x3_f, [r0+intra_x3_k*FENC_STRIDE]
    vinserti128    m %+ intra_x3_f, m %+ intra_x3_f, [r0+(intra_x3_k+4)*FENC_STRIDE], 1
    punpcklqdq     m %+ intra_x3_f, m %+ intra_x3_f
%endif
    pmaddubsw      m %+ intra_x3_f, m7
%assign intra_x3_k intra_x3_k+1
%endrep
    pxor          m14, m14
    pxor          m15, m15
    pxor           m6, m6
    psubw          m0, m8, m13             ; DC
    psubw          m1, m9, m13
    psubw          m2, m10, m13
    psubw          m3, m11, m13
    INTRA_X3_SATD 14
%assign intra_x3_k 0
%rep 4                                     ; H
    %assign intra_x3_f 8+intra_x3_k
%if cpuflag(avx512icl)
    vpbroadcastb   m %+ intra_x3_k, [r1+intra_x3_k*FDEC_STRIDE-1]
    vpbroadcastb   m %+ intra_x3_k {k3}, [r1+(intra_x3_k+4)*FDEC_STRIDE-1]
%else
    vpbroadcastb  xm %+ intra_x3_k, [r1+intra_x3_k*FDEC_STRIDE-1]
    vpbroadcastb  xm4, [r1+(intra_x3_k+4)*FDEC_STRIDE-1]
    vinserti128    m %+ intra_x3_k, m %+ intra_x3_k, xm4, 1
%endif
    pmaddubsw      m %+ intra_x3_k, m7
    psubw          m %+ intra_x3_k, m %+ intra_x3_f, m %+ intra_x3_k
%assign intra_x3_k intra_x3_k+1
%endrep
    INTRA_X3_SATD 15
    psubw          m0, m8, m12             ; V
    psubw          m1, m9, m12
    psubw          m2, m10, m12
    psubw          m3, m11, m12
    INTRA_X3_SATD 6
    INTRA_X3_FOLD 14
    INTRA_X3_FOLD 15
    INTRA_X3_FOLD 6
    punpckldq     xm4, xm14, xm15
    punpckhdq    xm14, xm15
    paddd        xm14, xm4
    punpckhdq     xm5, xm6, xm6
    punpckldq     xm6, xm6
    paddd         xm6, xm5
    punpcklqdq    xm4, xm14, xm6
    punpckhqdq   xm14, xm6
    paddd        xm14, xm4                 ; DC H V V
    movq        [r2], xm14
    pextrd    [r2+8], xm14, 2
    RET
%endmacro

INTRA_SATD_X3_8BIT
INIT_YMM avx2

;-----------------------------------------------------------------------------
; int intra_satd_lowres( int16_t *fenc_pre, uint8_t *src, intptr_t stride )
;-----------------------------------------------------------------------------
; m0-m3 prediction rows (k, k+4), each row twice -> less fenc_pre's first stage
%macro LOWRES_PRE8 0
    pmaddubsw    m0, m15
    pmaddubsw    m1, m15
    pmaddubsw    m2, m15
    pmaddubsw    m3, m15
    psubw        m0, [r0+0*32]
    psubw        m1, [r0+1*32]
    psubw        m2, [r0+2*32]
    psubw        m3, [r0+3*32]
%endmacro

%macro LOWRES_SHUF8 5 ; tables suffix, 4*sources
    pshufb       m0, %2, [lowres_%1 %+ 0]
    pshufb       m1, %3, [lowres_%1 %+ 1]
    pshufb       m2, %4, [lowres_%1 %+ 2]
    pshufb       m3, %5, [lowres_%1 %+ 3]
    LOWRES_PRE8
%endmacro

; avx2, and avx512icl in the ymm0-15 block after the SATD_ICL macros (phaddw,
; pblendw, vpblendd, vperm2i128 and phminposuw have no EVEX form)
%macro LOWRES_8BIT 0
cglobal intra_satd_lowres, 3,5,16
%if cpuflag(avx512icl)
    mov         r3d, 0x5555
    kmovd        k1, r3d
%endif
    sub          r1, r2               ; top row, row k at r1+(k+1)*r2
    lea          r3, [3*r2]
    lea          r4, [r1+4*r2]        ; row 3
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
    pshufb       m9, [lowres_shuf_ul] ; U5..U15: l6 l7 l7 l6..l0 lt
    pslldq       m0, m9, 1
    palignr      m1, m10, m9, 1
    PRED4x4_LOWPASS m14, m0, m1, m9, m2
    pshufb       m0, m10, [lowres_shuf_t2]
    PRED4x4_LOWPASS m13, m11, m0, m10, m1
    mova        m15, [hmul_8p]

    ; v
    vpbroadcastq m4, [r1]
    pmaddubsw    m4, m15
    psubw        m0, m4, [r0+0*32]
    psubw        m1, m4, [r0+1*32]
    psubw        m2, m4, [r0+2*32]
    psubw        m3, m4, [r0+3*32]
    LOWRES_SATD  m6
    ; h
    LOWRES_SHUF8 h, m12, m12, m12, m12
    LOWRES_SATD  m7
    phaddw       m6, m7
    ; dc
    vpblendd    xm4, xm10, xm12, 0x0c ; t0..t7 l7..l0
    pmaddubsw   xm4, [pb_1]
    phaddw      xm4, xm4              ; s0 s1 s3 s2
    pshuflw     xm5, xm4, q1210
    pshuflw     xm4, xm4, q2213
    paddw       xm4, xm5              ; s0+s2 2*s1 2*s3 s1+s3
    paddw       xm4, [pw_4]
    psrlw       xm4, 3
    packuswb    xm4, xm4
    vpbroadcastd m4, xm4
    pshufb       m4, [intra_8x8c_dc_shufb]
    pmaddubsw    m4, m15
    psubw        m0, m4, [r0+0*32]
    psubw        m1, m4, [r0+1*32]
    psubw        m2, m4, [r0+2*32]
    psubw        m3, m4, [r0+3*32]
    LOWRES_SATD  m7
    ; p: clip((a + 16 + b*(x-3) + c*(y-3)) >> 5)
    pmaddubsw   xm0, xm11, [lowres_p_wh]
    pmaddubsw   xm1, xm9, [lowres_p_wv]
    vpblendd    xm2, xm10, xm12, 0x0c
    pmaddubsw   xm2, [lowres_p_wa]
    phaddw      xm0, xm1
    phaddw      xm0, xm2
    phaddw      xm0, xm0              ; H V 16*t7 16*l7
    pmulhrsw    xm1, xm0, [pw_17408]  ; b c
    pmaddwd     xm0, [pw_1]
    pshufd      xm0, xm0, q1111
    vpbroadcastw m0, xm0              ; a
    vpbroadcastw m2, xm1
    psrld       xm1, 16
    vpbroadcastw m4, xm1              ; c
    paddw        m0, [pw_16]
    pmullw       m2, [lowres_p_x]
    paddw        m0, m2
    pmullw       m2, m4, [lowres_p_y]
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
    LOWRES_PRE8
    LOWRES_SATD  m8
    phaddw       m7, m8
    phaddw       m6, m7               ; v h dc p

    ; ddl, vl
    pshufb      m10, m13, [lowres_shuf_t2] ; E17..E32
    pslldq      m11, m13, 1
    pavgb        m9, m13, m10
    PRED4x4_LOWPASS m12, m11, m10, m13, m0
    LOWRES_SHUF8 ddl, m12, m12, m12, m12
    LOWRES_SATD  m7
    LOWRES_SHUF8 vl, m9, m12, m9, m12
    LOWRES_SATD  m8
    phaddw       m7, m8
    ; ddr, vr
    palignr     m10, m13, m14, 8      ; E8..E23
    palignr     m11, m13, m14, 7      ; E7..E22
    palignr     m12, m13, m14, 6      ; E6..E21
    pavgb        m9, m10, m11
    PRED4x4_LOWPASS m11, m12, m10, m11, m0
    LOWRES_SHUF8 ddr, m11, m11, m11, m11
    LOWRES_SATD  m8
    vpblendd    m10, m9, m11, 0x33
    LOWRES_SHUF8 vr, m10, m11, m10, m11
    LOWRES_SATD m12
    phaddw       m8, m12
    phaddw       m7, m8               ; ddl vl ddr vr
    phaddw       m6, m7               ; v h dc p ddl vl ddr vr
    ; hd, hu
    pshufd      m10, m9, q0001
    pblendw     m10, m11, q3330
    punpcklbw   m11, m9
    vpblendd    m10, m10, m11, 0xf0   ; rows 0-3 | rows 4-7
    LOWRES_SHUF8 hd, m10, m10, m10, m10
    LOWRES_SATD  m7
    pshufd      m10, m14, q1000
    pblendw     m11, m11, m10, 0x80   ; E7 in byte 15
    LOWRES_SHUF8 hu, m11, m11, m11, m11
    LOWRES_SATD  m8
    phaddw       m7, m8
    phaddw       m7, m7
    phaddw       m7, m7               ; hd hu hd hu

    vperm2i128   m0, m6, m7, 0x20
    vperm2i128   m1, m6, m7, 0x31
    paddw        m0, m1
    vextracti128 xm1, m0, 1
    pminuw      xm0, xm1
    phminposuw  xm0, xm0
    movd        eax, xm0
    movzx       eax, ax
    RET
%endmacro

LOWRES_8BIT

%endif ; ARCH_X86_64

cglobal pixel_sa8d_8x8_internal
    LOAD_SUMSUB_8x8P_AVX2 0, 1, 2, 3, 4, 5, 7
    HADAMARD4_V 0, 1, 2, 3, 4
    HADAMARD 8, sumsub, 0, 1, 4, 5
    HADAMARD 8, sumsub, 2, 3, 4, 5
    HADAMARD 2, sumsub, 0, 1, 4, 5
    HADAMARD 2, sumsub, 2, 3, 4, 5
    HADAMARD 1, amax, 0, 1, 4, 5
    HADAMARD 1, amax, 2, 3, 4, 5
    paddw  m6, m0
    paddw  m6, m2
    ret

cglobal pixel_sa8d_8x8, 4,6,8
    SATD_START_AVX2 m6, m7, 1
    call pixel_sa8d_8x8_internal
    vextracti128 xm1, m6, 1
    paddw xm6, xm1
    HADDW xm6, xm1
    movd  eax, xm6
    add   eax, 1
    shr   eax, 1
    RET

cglobal intra_sad_x9_8x8, 5,7,8
    %define pred(i,j) [rsp+i*0x40+j*0x20]

    mov         r6, rsp
    and        rsp, ~31
    sub        rsp, 0x240
    movu        m5, [r0+0*FENC_STRIDE]
    movu        m6, [r0+4*FENC_STRIDE]
    punpcklqdq  m5, [r0+2*FENC_STRIDE]
    punpcklqdq  m6, [r0+6*FENC_STRIDE]

    ; save instruction size: avoid 4-byte memory offsets
    lea         r0, [intra8x9_h1+128]
    %define off(m) (r0+m-(intra8x9_h1+128))

    vpbroadcastq m0, [r2+16]
    psadbw      m4, m0, m5
    psadbw      m2, m0, m6
    mova pred(0,0), m0
    mova pred(0,1), m0
    paddw       m4, m2

    vpbroadcastq m1, [r2+7]
    pshufb      m3, m1, [off(intra8x9_h1)]
    pshufb      m2, m1, [off(intra8x9_h3)]
    mova pred(1,0), m3
    mova pred(1,1), m2
    psadbw      m3, m5
    psadbw      m2, m6
    paddw       m3, m2

    lea         r5, [rsp+0x100]
    %define pred(i,j) [r5+i*0x40+j*0x20-0x100]

    ; combine the first two
    pslldq      m3, 2
    por         m4, m3

    pxor        m2, m2
    psadbw      m0, m2
    psadbw      m1, m2
    paddw       m0, m1
    psrlw       m0, 3
    pavgw       m0, m2
    pshufb      m0, m2
    mova pred(2,0), m0
    mova pred(2,1), m0
    psadbw      m3, m0, m5
    psadbw      m2, m0, m6
    paddw       m3, m2

    pslldq      m3, 4
    por         m4, m3

    vbroadcasti128 m0, [r2+16]
    vbroadcasti128 m2, [r2+17]
    pslldq      m1, m0, 1
    pavgb       m3, m0, m2
    PRED4x4_LOWPASS m0, m1, m2, m0, m7
    pshufb      m1, m0, [off(intra8x9_ddl1)]
    pshufb      m2, m0, [off(intra8x9_ddl3)]
    mova pred(3,0), m1
    mova pred(3,1), m2
    psadbw      m1, m5
    psadbw      m2, m6
    paddw       m1, m2

    pslldq      m1, 6
    por         m4, m1
    vextracti128 xm1, m4, 1
    paddw      xm4, xm1
    mova      [r4], xm4

    ; for later
    vinserti128 m7, m3, xm0, 1

    vbroadcasti128 m2, [r2+8]
    vbroadcasti128 m0, [r2+7]
    vbroadcasti128 m1, [r2+6]
    pavgb       m3, m2, m0
    PRED4x4_LOWPASS m0, m1, m2, m0, m4
    pshufb      m1, m0, [off(intra8x9_ddr1)]
    pshufb      m2, m0, [off(intra8x9_ddr3)]
    mova pred(4,0), m1
    mova pred(4,1), m2
    psadbw      m4, m1, m5
    psadbw      m2, m6
    paddw       m4, m2

    add         r0, 256
    add         r5, 0xC0
    %define off(m) (r0+m-(intra8x9_h1+256+128))
    %define pred(i,j) [r5+i*0x40+j*0x20-0x1C0]

    vpblendd    m2, m3, m0, 11110011b
    pshufb      m1, m2, [off(intra8x9_vr1)]
    pshufb      m2, m2, [off(intra8x9_vr3)]
    mova pred(5,0), m1
    mova pred(5,1), m2
    psadbw      m1, m5
    psadbw      m2, m6
    paddw       m1, m2

    pslldq      m1, 2
    por         m4, m1

    psrldq      m2, m3, 4
    pblendw     m2, m0, q3330
    punpcklbw   m0, m3
    pshufb      m1, m2, [off(intra8x9_hd1)]
    pshufb      m2, m0, [off(intra8x9_hd3)]
    mova pred(6,0), m1
    mova pred(6,1), m2
    psadbw      m1, m5
    psadbw      m2, m6
    paddw       m1, m2

    pslldq      m1, 4
    por         m4, m1

    pshufb      m1, m7, [off(intra8x9_vl1)]
    pshufb      m2, m7, [off(intra8x9_vl3)]
    mova pred(7,0), m1
    mova pred(7,1), m2
    psadbw      m1, m5
    psadbw      m2, m6
    paddw       m1, m2

    pslldq      m1, 6
    por         m4, m1
    vextracti128 xm1, m4, 1
    paddw      xm4, xm1
    mova       xm3, [r4]
    SBUTTERFLY qdq, 3, 4, 7
    paddw      xm3, xm4

    pslldq      m1, m0, 1
    vpbroadcastd m0, [r2+7]
    palignr     m0, m1, 1
    pshufb      m1, m0, [off(intra8x9_hu1)]
    pshufb      m2, m0, [off(intra8x9_hu3)]
    mova pred(8,0), m1
    mova pred(8,1), m2
    psadbw      m1, m5
    psadbw      m2, m6
    paddw       m1, m2
    vextracti128 xm2, m1, 1
    paddw      xm1, xm2
    movhlps    xm2, xm1
    paddw      xm1, xm2
    movd       r2d, xm1

    paddw      xm3, [r3]
    mova      [r4], xm3
    add        r2w, word [r3+16]
    mov    [r4+16], r2w

    phminposuw xm3, xm3
    movd       r3d, xm3
    add        r2d, 8<<16
    cmp        r3w, r2w
    cmovg      r3d, r2d

    mov        r2d, r3d
    shr         r3, 16
    shl         r3, 6
    add         r1, 4*FDEC_STRIDE
    mova       xm0, [rsp+r3+0x00]
    mova       xm1, [rsp+r3+0x10]
    mova       xm2, [rsp+r3+0x20]
    mova       xm3, [rsp+r3+0x30]
    movq   [r1+FDEC_STRIDE*-4], xm0
    movhps [r1+FDEC_STRIDE*-2], xm0
    movq   [r1+FDEC_STRIDE*-3], xm1
    movhps [r1+FDEC_STRIDE*-1], xm1
    movq   [r1+FDEC_STRIDE* 0], xm2
    movhps [r1+FDEC_STRIDE* 2], xm2
    movq   [r1+FDEC_STRIDE* 1], xm3
    movhps [r1+FDEC_STRIDE* 3], xm3
    mov        rsp, r6
    mov        eax, r2d
    RET

%if ARCH_X86_64
;-----------------------------------------------------------------------------
; 8-bit intra x9 (avx2): all nine predictions are scored, bitcosts added and
; the best (mode<<16 | cost) returned, its prediction written to fdec.
; Prediction rows are pshufb'd from edge vectors, each row twice per lane,
; so pmaddubsw does the first hadamard stage as in the 8-bit satd/sa8d.
;-----------------------------------------------------------------------------

; 4x4 block in one ymm: rows 0,1 in lane 0, rows 2,3 in lane 1.
; m%1: pred in, |three of the four hadamard stages of pred-fenc| out
; (m8 fenc, m11 hmul_4p, m12 swapw, m13-m14 signs). The cross-lane stage is
; the max in X9B_MERGE.
%macro X9B_SATD 2
    pmaddubsw   m%1, m11
    psubw       m%1, m8
    pshufb      m%2, m%1, m12
    psignw      m%1, m13
    paddw       m%1, m%2
    pshufd      m%2, m%1, q1032
    psignw      m%1, m14
    paddw       m%1, m%2
    pabsw       m%1, m%1
%endmacro

; m%1 = (8 maxes of mode %1 | 8 maxes of mode %2), their sums are the satds
%macro X9B_MERGE 3
    vperm2i128  m%3, m%1, m%2, 0x20
    vperm2i128  m%1, m%1, m%2, 0x31
    pmaxsw      m%1, m%3
%endmacro

;-----------------------------------------------------------------------------
; int intra_satd_x9_4x4( uint8_t *fenc, uint8_t *fdec, uint16_t *bitcosts )
;-----------------------------------------------------------------------------
cglobal intra_satd_x9_4x4, 3,4,16, 9*32
    %define pred_buf rsp
    movu        xm1, [r1-1*FDEC_STRIDE-8]
    pinsrb      xm1, [r1+3*FDEC_STRIDE-1], 0
    pinsrb      xm1, [r1+2*FDEC_STRIDE-1], 1
    pinsrb      xm1, [r1+1*FDEC_STRIDE-1], 2
    pinsrb      xm1, [r1+0*FDEC_STRIDE-1], 3
    pshufb      xm1, [intrax9_edge]   ; l3 l3 l2 l1 l0 lt t0 t1 t2 t3 t4 t5 t6 t7 t7 t7
    pxor        xm4, xm4
    pshufb      xm2, xm1, [intrax9a_dc]
    psadbw      xm2, xm4
    psrlw       xm2, 2
    pavgw       xm2, xm4
    vpbroadcastb m2, xm2              ; dc
    vpermq       m1, m1, q1010
    psrldq       m0, m1, 1
    psrldq       m3, m1, 2
    pavgb        m5, m0, m1
    PRED4x4_LOWPASS m0, m1, m3, m0, m4 ; F: Fl3 Fl2 Fl1 Fl0 Flt Ft0 .. Ft7
    pslldq       m6, m0, 5
    palignr      m7, m5, m6, 5        ; Q: Fl3 .. Ft5 Gl3 Gl2 Gl1 Gl0 Glt
    psrldq       m5, 5
    palignr      m5, m5, m6, 6        ; P: __ Fl1 .. Ft5 Gt0 .. Gt5

    movd        xm8, [r0+0*FENC_STRIDE]
    pinsrd      xm8, [r0+1*FENC_STRIDE], 1
    movd        xm9, [r0+2*FENC_STRIDE]
    pinsrd      xm9, [r0+3*FENC_STRIDE], 1
    vinserti128  m8, m8, xm9, 1
    punpckldq    m8, m8
    vbroadcasti128 m11, [hmul_4p]
    vbroadcasti128 m12, [x9b_swapw]
    vbroadcasti128 m13, [pw_pmpmpmpm]
    vbroadcasti128 m14, [pw_ppppmmmm]
    pmaddubsw    m8, m11

    pshufb       m9, m1, [x9b4_v]
    mova [pred_buf+0*32], m9
    X9B_SATD      9, 10
    vperm2i128  m10, m9, m9, 0x01
    pmaxsw       m9, m10              ; v | v
    pshufb      m10, m1, [x9b4_h]
    mova [pred_buf+1*32], m10
    mova [pred_buf+2*32], m2
    X9B_SATD     10, 3
    X9B_SATD      2, 3
    X9B_MERGE    10, 2, 3             ; h | dc
    pshufb       m1, m0, [x9b4_ddl]
    pshufb       m2, m0, [x9b4_ddr]
    mova [pred_buf+3*32], m1
    mova [pred_buf+4*32], m2
    X9B_SATD      1, 3
    X9B_SATD      2, 3
    X9B_MERGE     1, 2, 3             ; ddl | ddr
    pshufb       m0, m5, [x9b4_vr]
    pshufb       m2, m7, [x9b4_hd]
    mova [pred_buf+5*32], m0
    mova [pred_buf+6*32], m2
    X9B_SATD      0, 3
    X9B_SATD      2, 3
    X9B_MERGE     0, 2, 3             ; vr | hd
    pshufb       m2, m5, [x9b4_vl]
    pshufb       m3, m7, [x9b4_hu]
    mova [pred_buf+7*32], m2
    mova [pred_buf+8*32], m3
    X9B_SATD      2, 4
    X9B_SATD      3, 4
    X9B_MERGE     2, 3, 4             ; vl | hu

    phaddw      m10, m1
    phaddw       m0, m2
    phaddw      m10, m0
    phaddw       m9, m9
    phaddw       m9, m9
    phaddw      m10, m9               ; h ddl vr vl v v v v | dc ddr hd hu v v v v
    vextracti128 xm0, m10, 1
    pextrw      r3d, xm10, 4
    punpcklwd   xm0, xm10, xm0
    paddw       xm0, [r2+2]
    phminposuw  xm0, xm0
    movzx       r0d, word [r2]
    add         r3d, r0d
    movd        eax, xm0
    add         eax, 1<<16
    cmp          ax, r3w
    cmovae      eax, r3d

    mov         r3d, eax
    shr         r3d, 16
    shl         r3d, 5
    mov         r0d, [pred_buf+r3+ 0]
    mov         r2d, [pred_buf+r3+ 8]
    mov [r1+0*FDEC_STRIDE], r0d
    mov [r1+1*FDEC_STRIDE], r2d
    mov         r0d, [pred_buf+r3+16]
    mov         r2d, [pred_buf+r3+24]
    mov [r1+2*FDEC_STRIDE], r0d
    mov [r1+3*FDEC_STRIDE], r2d
    RET

;-----------------------------------------------------------------------------
; int intra_sa8d_x9_8x8( uint8_t *fenc, uint8_t *fdec, uint8_t edge[36], uint16_t *bitcosts, uint16_t *satds )
;-----------------------------------------------------------------------------
; Modes go through .sa8d in pairs, mode 2k in lane 0 and 2k+1 in lane 1.
; FL, GL = F2, F1 of edge[7..22] (centred, rightwards); FT, GT of edge[16..31].
; HADAMARD8_2D_HMUL 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 (avx512icl: the amax stage
; with SATD_ICL_HMAX, k1 = 0x5555)
%macro SA8D_X9_HMUL 0
%if cpuflag(avx512icl)
    HADAMARD4_V 0, 1, 2, 3, 8
    HADAMARD4_V 4, 5, 6, 7, 8
    SUMSUB_BADC w, 0, 4, 1, 5, 8
    HADAMARD 2, sumsub, 0, 4, 8, 9
    HADAMARD 2, sumsub, 1, 5, 8, 9
    SUMSUB_BADC w, 2, 6, 3, 7, 8
    HADAMARD 2, sumsub, 2, 6, 8, 9
    HADAMARD 2, sumsub, 3, 7, 8, 9
    ABSW2 m0, m4, m0, m4, m8, m9
    ABSW2 m1, m5, m1, m5, m8, m9
    ABSW2 m2, m6, m2, m6, m8, m9
    ABSW2 m3, m7, m3, m7, m8, m9
    SATD_ICL_HMAX 0, 4, 8
    SATD_ICL_HMAX 1, 5, 8
    SATD_ICL_HMAX 2, 6, 8
    SATD_ICL_HMAX 3, 7, 8
%else
    HADAMARD8_2D_HMUL 0, 1, 2, 3, 4, 5, 6, 7, 8, 9
%endif
%endmacro

; avx2, and avx512icl in the ymm0-15 block after the SATD_ICL macros (phaddw,
; vpblendd, vperm2i128 and phminposuw have no EVEX form)
%macro SA8D_X9_8BIT 0
cglobal intra_sa8d_x9_8x8, 5,7,16, 0x600
%if cpuflag(avx512icl)
    mov         r5d, 0x5555
    kmovd        k1, r5d
%endif
    %define fenc_buf rsp
    %define pred_buf rsp+0x100
    mova        m15, [hmul_8p]
%assign x9i 0
%rep 8
    vpbroadcastq m %+ x9i, [r0+x9i*FENC_STRIDE]
    pmaddubsw    m %+ x9i, m15
    mova [fenc_buf+x9i*32], m %+ x9i
%assign x9i x9i+1
%endrep

    movu        xm0, [r2+6]
    vinserti128  m0, m0, [r2+15], 1
    movu        xm1, [r2+7]
    vinserti128  m1, m1, [r2+16], 1
    movu        xm2, [r2+8]
    vinserti128  m2, m2, [r2+17], 1
    pavgb        m8, m1, m2           ; GL | GT
    PRED4x4_LOWPASS m9, m0, m2, m1, m5 ; FL | FT
    pxor        xm0, xm0
    psadbw       m5, m1, m0
    vextracti128 xm2, m5, 1
    paddw       xm5, xm2
    psrlw       xm5, 3
    pavgw       xm5, xm0
    vpbroadcastb m5, xm5              ; dc
    vpermq      m12, m1, q1032        ; v | h
    vpblendd    m13, m9, m5, 0x0f     ; dc | ddl
    vpermq      m10, m9, q1010        ; ddr | vr odd rows
    vpblendd     m2, m9, m8, 0xcc
    vperm2i128  m11, m9, m2, 0x20     ; ddr | vr even rows
    punpcklbw   m14, m8, m9
    vpbroadcastb m0, [r2+7]
    vpblendw    m14, m14, m0, 0x80    ; hu
    psrldq       m0, m9, 1
    punpcklbw    m0, m8, m0           ; HDT[0..15]: GL[0] FL[1] .. GL[7] FL[8]
    psrldq       m1, m9, 9
    palignr      m1, m1, m0, 6        ; HDT[6..21]
    vpblendd     m4, m1, m8, 0xf0
    vpblendd     m3, m1, m9, 0xf0
    vpblendd     m6, m0, m8, 0xf0
    vpblendd     m7, m0, m9, 0xf0

    ; hd | vl
    pshufb       m0, m4, [x9b8_hdvl+0*32]
    pshufb       m1, m3, [x9b8_hdvl+1*32]
    pshufb       m2, m4, [x9b8_hdvl+2*32]
    pshufb       m3, m3, [x9b8_hdvl+3*32]
    pshufb       m4, m4, [x9b8_hdvl+4*32]
    pshufb       m5, m7, [x9b8_hdvl+5*32]
    pshufb       m6, m6, [x9b8_hdvl+6*32]
    pshufb       m7, m7, [x9b8_hdvl+7*32]
    lea          r5, [pred_buf+3*0x100]
    lea          r6, [fenc_buf]
    call .sa8d
    mova         m8, m0
    ; ddr | vr
%assign x9i 0
%rep 8
%if x9i & 1
    pshufb       m %+ x9i, m10, [x9b8_ddrvr+x9i*32]
%else
    pshufb       m %+ x9i, m11, [x9b8_ddrvr+x9i*32]
%endif
%assign x9i x9i+1
%endrep
    mova        m10, m8
    sub          r5, 0x100
    call .sa8d
    phaddw      m11, m0, m10          ; ddr hd | vr vl
    ; v | h
%assign x9i 0
%rep 8
    pshufb       m %+ x9i, m12, [x9b8_vh+x9i*32]
%assign x9i x9i+1
%endrep
    sub          r5, 0x200
    call .sa8d
    mova        m12, m0
    ; dc | ddl
%assign x9i 0
%rep 8
    pshufb       m %+ x9i, m13, [x9b8_dcddl+x9i*32]
%assign x9i x9i+1
%endrep
    add          r5, 0x100
    call .sa8d
    phaddw      m12, m0               ; v dc | h ddl
    phaddw      m12, m11              ; v dc ddr hd | h ddl vr vl
    ; hu
%assign x9i 0
%rep 8
    pshufb       m %+ x9i, m14, [x9b8_hu+x9i*32]
%assign x9i x9i+1
%endrep
    add          r5, 0x300
    call .sa8d

    phaddw       m0, m0
    phaddw       m0, m0
    phaddw      m12, m0               ; v dc ddr hd hu hu hu hu | h ddl vr vl x x x x
    pxor        xm1, xm1
    pavgw       m12, m1
    vextracti128 xm1, m12, 1
    punpcklwd   xm2, xm12, xm1        ; v h dc ddl ddr vr hd vl
    pextrw      r5d, xm12, 4
    paddw       xm2, [r3]
    movu       [r4], xm2
    movzx       r2d, word [r3+16]
    add         r2d, r5d
    mov     [r4+16], r2w
    phminposuw  xm0, xm2
    movd        eax, xm0
    add         r2d, 8<<16
    cmp          ax, r2w
    cmova       eax, r2d

    mov         r2d, eax
    shr         r2d, 16
    mov         r3d, r2d
    and         r3d, 1
    and         r2d, ~1
    shl         r2d, 7
    shl         r3d, 4
    add         r2d, r3d
%assign x9i 0
%rep 8
    movq        xm0, [pred_buf+r2+32*x9i]
    movq [r1+x9i*FDEC_STRIDE], xm0
%assign x9i x9i+1
%endrep
    RET

RESET_MM_PERMUTATION
ALIGN 16
.sa8d: ; m0-m7 pred rows (stored to r5), r6 fenc rows -> m0 = 8 word sums of the maxes per lane
    %xdefine mret m0
%assign x9i 0
%rep 8
    mova [r5+x9i*32], m %+ x9i
    pmaddubsw    m %+ x9i, m15
    psubw        m %+ x9i, [r6+x9i*32]
%assign x9i x9i+1
%endrep
    SA8D_X9_HMUL
    paddw        m0, m1
    paddw        m2, m3
    paddw      mret, m0, m2
    ret
%endmacro

SA8D_X9_8BIT

;-----------------------------------------------------------------------------
; avx512icl 8-bit satd family, the avx2 layouts with:
; - HADAMARD 1, max in 3 uops: vpblendmw (k1 = 0x5555) and vpshldd give the
;   pairs of TRANS d unord with the two words of each dword swapped, so the
;   sum is unchanged;
; - 8 wide row pairs [k k | k+4 k+4] from a broadcast and a merge-masked
;   broadcast (k2 = 0xc) instead of two broadcasts and vpblendd.
; The whole block is ICL_LOW (m0-m15 on ymm0-15).
;-----------------------------------------------------------------------------
ICL_LOW_BEGIN
%macro SATD_ICL_KMASK 1 ; gpr (dword) to clobber
    mov       %1, 0x5555000c
    kmovd     k2, %1
    kshiftrd  k1, k2, 16
%endmacro

%macro SATD_ICL_HMAX 3 ; a, b, tmp
    vpblendmw m%3 {k1}, m%1, m%2
    vpshldd   m%2, m%1, m%2, 16
    pmaxsw    m%1, m%3, m%2
%endmacro

; SATD_8x4_SSE 0, 0, 1, 2, 3, 4, 5, %2, %1
%macro SATD_ICL_8x4 1-2 6 ; swap/add, accumulator
    HADAMARD4_V 0, 1, 2, 3, 4
    pabsw     m0, m0
    pabsw     m2, m2
    pabsw     m1, m1
    pabsw     m3, m3
    SATD_ICL_HMAX 0, 2, 4
    SATD_ICL_HMAX 1, 3, 5
%ifidn %1, swap
    paddw    m%2, m0, m1
%else
    paddw     m0, m1
    paddw    m%2, m0
%endif
%endmacro

%macro SATD_ICL_DUP8 3 ; dst, 2*mem: [%2 %2 | %3 %3]
    vpbroadcastq m%1, %2
    vpbroadcastq m%1 {k2}, %3
%endmacro

; rows k, k+4 (r0/r2 and r6/r7 = four rows down), %3/%4 = k*stride1/k*stride2
%macro SATD_ICL_SUMSUB8 4 ; dst, tmp, 2*offset
    SATD_ICL_DUP8 %1, [r0+%3], [r6+%3]
    SATD_ICL_DUP8 %2, [r2+%4], [r7+%4]
    pmaddubsw m%1, m7
    pmaddubsw m%2, m7
    psubw     m%1, m%2
%endmacro

%macro SATD_ICL_8x8 1 ; swap/add
    SATD_ICL_SUMSUB8 0, 4, 0, 0
    SATD_ICL_SUMSUB8 1, 5, r1, r3
    SATD_ICL_SUMSUB8 2, 4, 2*r1, 2*r3
    SATD_ICL_SUMSUB8 3, 5, r4, r5
    SATD_ICL_8x4 %1
%endmacro

%macro SATD_ICL_START8 0
    SATD_ICL_KMASK r4d
    mova      m7, [hmul_8p]
    lea       r4, [3*r1]
    lea       r5, [3*r3]
    lea       r6, [r0+4*r1]
    lea       r7, [r2+4*r3]
%endmacro

%macro SATD_ICL_END 0
    vextracti128 xm0, m6, 1
    paddw        xm0, xm6
    SATD_END_SSE2 xm0
%endmacro

cglobal pixel_satd_8x8, 4,8,8
    SATD_ICL_START8
    SATD_ICL_8x8 swap
    SATD_ICL_END

cglobal pixel_satd_8x16, 4,8,8
    SATD_ICL_START8
    SATD_ICL_8x8 swap
    lea       r0, [r0+8*r1]
    lea       r2, [r2+8*r3]
    lea       r6, [r6+8*r1]
    lea       r7, [r7+8*r3]
    SATD_ICL_8x8 add
    SATD_ICL_END

; m6 += the satd of 16x8 at r0/r2, which move down 8 rows
cglobal pixel_satd_16x8_internal
%rep 2
    LOAD_SUMSUB_16x4P_AVX2 0, 1, 2, 3, 4, 5, 7, r0, r2, 1
    SATD_ICL_8x4 add
%endrep
    ret

%macro SATD_ICL_START16 0
    mov      r4d, 0x5555
    kmovd     k1, r4d
    mova      m7, [hmul_16p]
    lea       r4, [3*r1]
    lea       r5, [3*r3]
    pxor      m6, m6
%endmacro

cglobal pixel_satd_16x16, 4,6,8
    SATD_ICL_START16
    call pixel_satd_16x8_internal
    call pixel_satd_16x8_internal
    SATD_ICL_END

cglobal pixel_satd_16x8, 4,6,8
    SATD_ICL_START16
    call pixel_satd_16x8_internal
    SATD_ICL_END

; satd_avg2: as the avx2 SATD_AVG2_16x4 / SATD_AVG2_8x8
%macro SATD_AVG2_ICL_16x4 0
    SATD_AVG2_SUMSUB16x2 0, 1, 4, 5, 0, FENC_STRIDE, 0, r3
    SATD_AVG2_SUMSUB16x2 2, 3, 4, 5, 2*FENC_STRIDE, 3*FENC_STRIDE, 2*r3, r4
    SATD_ICL_8x4 add
%endmacro

%macro SATD_AVG2_ICL_SUMSUB8 3 ; dst (number), k, source offset
    SATD_ICL_DUP8 %1, [r0+%2*FENC_STRIDE], [r0+(%2+4)*FENC_STRIDE]
    SATD_ICL_DUP8 4, [r1+%3], [r5+%3]
    SATD_ICL_DUP8 8, [r2+%3], [r6+%3]
    pavgb          m4, m8
    pmaddubsw     m%1, m7
    pmaddubsw      m4, m7
    psubw         m%1, m4
%endmacro

%macro SATD_AVG2_ICL_8x8 1 ; swap/add
    SATD_AVG2_ICL_SUMSUB8 0, 0, 0
    SATD_AVG2_ICL_SUMSUB8 1, 1, r3
    SATD_AVG2_ICL_SUMSUB8 2, 2, 2*r3
    SATD_AVG2_ICL_SUMSUB8 3, 3, r4
    SATD_ICL_8x4 %1
%endmacro

cglobal pixel_satd_avg2_16x16, 4,5,9
    mov      r4d, 0x5555
    kmovd     k1, r4d
    mova      m7, [hmul_16p]
    lea       r4, [3*r3]
    pxor      m6, m6
    SATD_AVG2_ICL_16x4
%rep 3
    lea       r1, [r1+4*r3]
    lea       r2, [r2+4*r3]
    add       r0, 4*FENC_STRIDE
    SATD_AVG2_ICL_16x4
%endrep
    SATD_ICL_END

cglobal pixel_satd_avg2_16x8, 4,5,9
    mov      r4d, 0x5555
    kmovd     k1, r4d
    mova      m7, [hmul_16p]
    lea       r4, [3*r3]
    pxor      m6, m6
    SATD_AVG2_ICL_16x4
    lea       r1, [r1+4*r3]
    lea       r2, [r2+4*r3]
    add       r0, 4*FENC_STRIDE
    SATD_AVG2_ICL_16x4
    SATD_ICL_END

%macro SATD_AVG2_ICL_START8 0
    SATD_ICL_KMASK r4d
    mova      m7, [hmul_8p]
    lea       r4, [3*r3]
    lea       r5, [r1+4*r3]
    lea       r6, [r2+4*r3]
%endmacro

cglobal pixel_satd_avg2_8x16, 4,7,9
    SATD_AVG2_ICL_START8
    SATD_AVG2_ICL_8x8 swap
    lea       r1, [r1+8*r3]
    lea       r2, [r2+8*r3]
    lea       r5, [r5+8*r3]
    lea       r6, [r6+8*r3]
    add       r0, 8*FENC_STRIDE
    SATD_AVG2_ICL_8x8 add
    SATD_ICL_END

cglobal pixel_satd_avg2_8x8, 4,7,9
    SATD_AVG2_ICL_START8
    SATD_AVG2_ICL_8x8 swap
    SATD_ICL_END

; HADAMARD 8, sumsub (vperm2i128 has no EVEX form)
%macro SA8D_ICL_H8 3 ; a, b, tmp
    vshufi32x4  m%3, m%1, m%2, 3
    vinserti128 m%1, m%1, xm%2, 1
    SWAP         %2, %3
    SUMSUB_BA    w, %1, %2, %3
%endmacro

; as pixel_sa8d_8x8_avx2
cglobal pixel_sa8d_8x8, 4,8,8
    SATD_ICL_START8
    SATD_ICL_SUMSUB8 0, 4, 0, 0
    SATD_ICL_SUMSUB8 1, 5, r1, r3
    SATD_ICL_SUMSUB8 2, 4, 2*r1, 2*r3
    SATD_ICL_SUMSUB8 3, 5, r4, r5
    HADAMARD4_V 0, 1, 2, 3, 4
    SA8D_ICL_H8 0, 1, 4
    SA8D_ICL_H8 2, 3, 4
    HADAMARD 2, sumsub, 0, 1, 4, 5
    HADAMARD 2, sumsub, 2, 3, 4, 5
    pabsw     m0, m0
    pabsw     m1, m1
    pabsw     m2, m2
    pabsw     m3, m3
    SATD_ICL_HMAX 0, 1, 4
    SATD_ICL_HMAX 2, 3, 5
    paddw     m6, m0, m2
    vextracti128 xm1, m6, 1
    paddw    xm6, xm1
    HADDW    xm6, xm1
    movd     eax, xm6
    add      eax, 1
    shr      eax, 1
    RET

INTRA_SATD_X3_8BIT
SA8D_SATD
SATD_PRE_FUNCS
SATD_AVG2_PRE_FUNCS
LOWRES_8BIT
SA8D_X9_8BIT
SATD_BI 16, 16, 0
SATD_BI 16,  8, 0
SATD_BI  8, 16, 0
SATD_BI  8,  8, 0
SATD_BI 16, 16, 1
SATD_BI 16,  8, 1
SATD_BI  8, 16, 1
SATD_BI  8,  8, 1
ICL_LOW_END
%endif ; ARCH_X86_64

%macro SATD_AVX512_LOAD4 2 ; size, opmask
    vpbroadcast%1 m0, [r0]
    vpbroadcast%1 m0 {%2}, [r0+2*r1]
    vpbroadcast%1 m2, [r2]
    vpbroadcast%1 m2 {%2}, [r2+2*r3]
    add           r0, r1
    add           r2, r3
    vpbroadcast%1 m1, [r0]
    vpbroadcast%1 m1 {%2}, [r0+2*r1]
    vpbroadcast%1 m3, [r2]
    vpbroadcast%1 m3 {%2}, [r2+2*r3]
%endmacro

%macro SATD_AVX512_LOAD8 5 ; size, halfreg, opmask1, opmask2, opmask3
    vpbroadcast%1 %{2}0, [r0]
    vpbroadcast%1 %{2}0 {%3}, [r0+2*r1]
    vpbroadcast%1 %{2}2, [r2]
    vpbroadcast%1 %{2}2 {%3}, [r2+2*r3]
    vpbroadcast%1    m0 {%4}, [r0+4*r1]
    vpbroadcast%1    m2 {%4}, [r2+4*r3]
    vpbroadcast%1    m0 {%5}, [r0+2*r4]
    vpbroadcast%1    m2 {%5}, [r2+2*r5]
    vpbroadcast%1 %{2}1, [r0+r1]
    vpbroadcast%1 %{2}1 {%3}, [r0+r4]
    vpbroadcast%1 %{2}3, [r2+r3]
    vpbroadcast%1 %{2}3 {%3}, [r2+r5]
    lea              r0, [r0+4*r1]
    lea              r2, [r2+4*r3]
    vpbroadcast%1    m1 {%4}, [r0+r1]
    vpbroadcast%1    m3 {%4}, [r2+r3]
    vpbroadcast%1    m1 {%5}, [r0+r4]
    vpbroadcast%1    m3 {%5}, [r2+r5]
%endmacro

%macro SATD_AVX512_PACKED 0
    DIFF_SUMSUB_SSSE3 0, 2, 1, 3, 4
    SUMSUB_BA      w, 0, 1, 2
    SBUTTERFLY   qdq, 0, 1, 2
    SUMSUB_BA      w, 0, 1, 2
    HMAXABSW2         0, 1, 2, 3
%endmacro

%macro SATD_AVX512_END 0-1 0 ; sa8d
    vpaddw         m0 {k1}{z}, m1 ; zero-extend to dwords
%if ARCH_X86_64
%if mmsize == 64
    vextracti32x8 ym1, m0, 1
    paddd         ym0, ym1
%endif
%if mmsize >= 32
    vextracti128  xm1, ym0, 1
    paddd        xmm0, xm0, xm1
%endif
    punpckhqdq   xmm1, xmm0, xmm0
    paddd        xmm0, xmm1
    movq          rax, xmm0
    rorx          rdx, rax, 32
%if %1
    lea           eax, [rax+rdx+1]
    shr           eax, 1
%else
    add           eax, edx
%endif
%else
    HADDD          m0, m1
    movd          eax, xm0
%if %1
    inc           eax
    shr           eax, 1
%endif
%endif
    RET
%endmacro

%macro HMAXABSW2 4 ; a, b, tmp1, tmp2
    pabsw     m%1, m%1
    pabsw     m%2, m%2
    psrldq    m%3, m%1, 2
    psrld     m%4, m%2, 16
    pmaxsw    m%1, m%3
    pmaxsw    m%2, m%4
%endmacro

INIT_ZMM avx512
cglobal pixel_satd_16x8_internal
    vbroadcasti64x4 m6, [hmul_16p]
    kxnorb           k2, k2, k2
    mov             r4d, 0x55555555
    knotw            k2, k2
    kmovd            k1, r4d
    lea              r4, [3*r1]
    lea              r5, [3*r3]
satd_16x8_avx512:
    vbroadcasti128  ym0,      [r0]
    vbroadcasti32x4  m0 {k2}, [r0+4*r1] ; 0 0 4 4
    vbroadcasti128  ym4,      [r2]
    vbroadcasti32x4  m4 {k2}, [r2+4*r3]
    vbroadcasti128  ym2,      [r0+2*r1]
    vbroadcasti32x4  m2 {k2}, [r0+2*r4] ; 2 2 6 6
    vbroadcasti128  ym5,      [r2+2*r3]
    vbroadcasti32x4  m5 {k2}, [r2+2*r5]
    DIFF_SUMSUB_SSSE3 0, 4, 2, 5, 6
    vbroadcasti128  ym1,      [r0+r1]
    vbroadcasti128  ym4,      [r2+r3]
    vbroadcasti128  ym3,      [r0+r4]
    vbroadcasti128  ym5,      [r2+r5]
    lea              r0, [r0+4*r1]
    lea              r2, [r2+4*r3]
    vbroadcasti32x4  m1 {k2}, [r0+r1] ; 1 1 5 5
    vbroadcasti32x4  m4 {k2}, [r2+r3]
    vbroadcasti32x4  m3 {k2}, [r0+r4] ; 3 3 7 7
    vbroadcasti32x4  m5 {k2}, [r2+r5]
    DIFF_SUMSUB_SSSE3 1, 4, 3, 5, 6
    HADAMARD4_V       0, 1, 2, 3, 4
    HMAXABSW2         0, 2, 4, 5
    HMAXABSW2         1, 3, 4, 5
    paddw            m4, m0, m2 ; m1
    paddw            m2, m1, m3 ; m0
    ret

cglobal pixel_satd_8x8_internal
    vbroadcasti64x4 m4, [hmul_16p]
    mov     r4d, 0x55555555
    kmovd    k1, r4d   ; 01010101
    kshiftlb k2, k1, 5 ; 10100000
    kshiftlb k3, k1, 4 ; 01010000
    lea      r4, [3*r1]
    lea      r5, [3*r3]
satd_8x8_avx512:
    SATD_AVX512_LOAD8 q, ym, k1, k2, k3 ; 2 0 2 0 6 4 6 4
    SATD_AVX512_PACKED                  ; 3 1 3 1 7 5 7 5
    ret

cglobal pixel_satd_16x8, 4,6
    call pixel_satd_16x8_internal_avx512
    jmp satd_zmm_avx512_end

cglobal pixel_satd_16x16, 4,6
    call pixel_satd_16x8_internal_avx512
    lea      r0, [r0+4*r1]
    lea      r2, [r2+4*r3]
    paddw    m7, m0, m1
    call satd_16x8_avx512
    paddw    m1, m7
    jmp satd_zmm_avx512_end

cglobal pixel_satd_8x8, 4,6
    call pixel_satd_8x8_internal_avx512
satd_zmm_avx512_end:
    SATD_AVX512_END

cglobal pixel_satd_8x16, 4,6
    call pixel_satd_8x8_internal_avx512
    lea      r0, [r0+4*r1]
    lea      r2, [r2+4*r3]
    paddw    m5, m0, m1
    call satd_8x8_avx512
    paddw    m1, m5
    jmp satd_zmm_avx512_end

INIT_YMM avx512
cglobal pixel_satd_4x8_internal
    vbroadcasti128 m4, [hmul_4p]
    mov     r4d, 0x55550c
    kmovd    k2, r4d   ; 00001100
    kshiftlb k3, k2, 2 ; 00110000
    kshiftlb k4, k2, 4 ; 11000000
    kshiftrd k1, k2, 8 ; 01010101
    lea      r4, [3*r1]
    lea      r5, [3*r3]
satd_4x8_avx512:
    SATD_AVX512_LOAD8 d, xm, k2, k3, k4 ; 0 0 2 2 4 4 6 6
satd_ymm_avx512:                        ; 1 1 3 3 5 5 7 7
    SATD_AVX512_PACKED
    ret

cglobal pixel_satd_8x4, 4,5
    mova     m4, [hmul_16p]
    mov     r4d, 0x5555
    kmovw    k1, r4d
    SATD_AVX512_LOAD4 q, k1 ; 2 0 2 0
    call satd_ymm_avx512    ; 3 1 3 1
    jmp satd_ymm_avx512_end2

cglobal pixel_satd_4x8, 4,6
    call pixel_satd_4x8_internal_avx512
satd_ymm_avx512_end:
%if ARCH_X86_64 == 0
    pop     r5d
    %assign regs_used 5
%endif
satd_ymm_avx512_end2:
    SATD_AVX512_END

cglobal pixel_satd_4x16, 4,6
    call pixel_satd_4x8_internal_avx512
    lea      r0, [r0+4*r1]
    lea      r2, [r2+4*r3]
    paddw    m5, m0, m1
    call satd_4x8_avx512
    paddw    m1, m5
    jmp satd_ymm_avx512_end

INIT_XMM avx512
cglobal pixel_satd_4x4, 4,5
    mova     m4, [hmul_4p]
    mov     r4d, 0x550c
    kmovw    k2, r4d
    kshiftrw k1, k2, 8
    SATD_AVX512_LOAD4 d, k2 ; 0 0 2 2
    SATD_AVX512_PACKED      ; 1 1 3 3
    SWAP      0, 1
    SATD_AVX512_END

INIT_ZMM avx512
cglobal pixel_sa8d_8x8, 4,6
    vbroadcasti64x4 m4, [hmul_16p]
    mov     r4d, 0x55555555
    kmovd    k1, r4d   ; 01010101
    kshiftlb k2, k1, 5 ; 10100000
    kshiftlb k3, k1, 4 ; 01010000
    lea      r4, [3*r1]
    lea      r5, [3*r3]
    SATD_AVX512_LOAD8 q, ym, k1, k2, k3 ; 2 0 2 0 6 4 6 4
    DIFF_SUMSUB_SSSE3 0, 2, 1, 3, 4     ; 3 1 3 1 7 5 7 5
    SUMSUB_BA      w, 0, 1, 2
    SBUTTERFLY   qdq, 0, 1, 2
    SUMSUB_BA      w, 0, 1, 2
    shufps        m2, m0, m1, q2020
    shufps        m1, m0, m1, q3131
    SUMSUB_BA      w, 2, 1, 0
    vshufi32x4    m0, m2, m1, q1010
    vshufi32x4    m1, m2, m1, q3232
    SUMSUB_BA      w, 0, 1, 2
    HMAXABSW2      0, 1, 2, 3
    SATD_AVX512_END 1

%if ARCH_X86_64
;-----------------------------------------------------------------------------
; avx512icl 8-bit satd 4x4, 4x8, 4x16, 8x4: the avx512 packed layout and
; transform, the last stage (max of absolute word pairs) as SATD_ICL_HMAX
; into one register, so every word counts and pmaddwd sums them.
; Words <= 8*255.
;-----------------------------------------------------------------------------
%macro SATD_ICL_PACKED 0
    DIFF_SUMSUB_SSSE3 0, 2, 1, 3, 4
    SUMSUB_BA      w, 0, 1, 2
    SBUTTERFLY   qdq, 0, 1, 2
    SUMSUB_BA      w, 0, 1, 2
    pabsw         m0, m0
    pabsw         m1, m1
    SATD_ICL_HMAX  0, 1, 2
%endmacro

%macro SATD_ICL_PACKED_END 0
    pmaddwd       m0, [pw_1]
    HADDD         m0, m1
    movd         eax, xm0
    RET
%endmacro

INIT_XMM avx512icl
cglobal pixel_satd_4x4, 4,5,5
    mova          m4, [hmul_4p]
    mov          r4d, 0x550c
    kmovw         k2, r4d
    kshiftrw      k1, k2, 8
    SATD_AVX512_LOAD4 d, k2 ; 0 0 2 2
    SATD_ICL_PACKED         ; 1 1 3 3
    SATD_ICL_PACKED_END

ICL_LOW_BEGIN
%macro SATD_ICL_4x8_START 0
    vbroadcasti128 m4, [hmul_4p]
    mov          r4d, 0x55550c
    kmovd         k2, r4d   ; 00001100
    kshiftlb      k3, k2, 2 ; 00110000
    kshiftlb      k4, k2, 4 ; 11000000
    kshiftrd      k1, k2, 8 ; 01010101
    lea           r4, [3*r1]
    lea           r5, [3*r3]
%endmacro

cglobal pixel_satd_4x8, 4,6,5
    SATD_ICL_4x8_START
    SATD_AVX512_LOAD8 d, xm, k2, k3, k4 ; 0 0 2 2 4 4 6 6
    SATD_ICL_PACKED                     ; 1 1 3 3 5 5 7 7
    SATD_ICL_PACKED_END

cglobal pixel_satd_4x16, 4,6,6
    SATD_ICL_4x8_START
    SATD_AVX512_LOAD8 d, xm, k2, k3, k4
    SATD_ICL_PACKED
    SWAP           0, 5
    lea           r0, [r0+4*r1]
    lea           r2, [r2+4*r3]
    SATD_AVX512_LOAD8 d, xm, k2, k3, k4
    SATD_ICL_PACKED
    paddw         m0, m5
    SATD_ICL_PACKED_END

cglobal pixel_satd_8x4, 4,5,5
    mova          m4, [hmul_16p]
    mov          r4d, 0x5555
    kmovw         k1, r4d
    SATD_AVX512_LOAD4 q, k1 ; 2 0 2 0
    SATD_ICL_PACKED         ; 3 1 3 1
    SATD_ICL_PACKED_END
ICL_LOW_END
%endif ; ARCH_X86_64

%endif ; HIGH_BIT_DEPTH

;=============================================================================
; SSIM
;=============================================================================

;-----------------------------------------------------------------------------
; void pixel_ssim_4x4x2_core( const uint8_t *pix1, intptr_t stride1,
;                             const uint8_t *pix2, intptr_t stride2, int sums[2][4] )
;-----------------------------------------------------------------------------
%macro SSIM_ITER 1
%if HIGH_BIT_DEPTH
    movdqu    m5, [r0+(%1&1)*r1]
    movdqu    m6, [r2+(%1&1)*r3]
%else
    movq      m5, [r0+(%1&1)*r1]
    movq      m6, [r2+(%1&1)*r3]
    punpcklbw m5, m0
    punpcklbw m6, m0
%endif
%if %1==1
    lea       r0, [r0+r1*2]
    lea       r2, [r2+r3*2]
%endif
%if %1==0
    movdqa    m1, m5
    movdqa    m2, m6
%else
    paddw     m1, m5
    paddw     m2, m6
%endif
    pmaddwd   m7, m5, m6
    pmaddwd   m5, m5
    pmaddwd   m6, m6
    ACCUM  paddd, 3, 5, %1
    ACCUM  paddd, 4, 7, %1
    paddd     m3, m6
%endmacro

%macro SSIM 0
cglobal pixel_ssim_4x4x2_core, 4,4,8
    FIX_STRIDES r1, r3
    pxor      m0, m0
    SSIM_ITER 0
    SSIM_ITER 1
    SSIM_ITER 2
    SSIM_ITER 3
    ; PHADDW m1, m2
    ; PHADDD m3, m4
    movdqa    m7, [pw_1]
    pshufd    m5, m3, q2301
    pmaddwd   m1, m7
    pmaddwd   m2, m7
    pshufd    m6, m4, q2301
    packssdw  m1, m2
    paddd     m3, m5
    pshufd    m1, m1, q3120
    paddd     m4, m6
    pmaddwd   m1, m7
    punpckhdq m5, m3, m4
    punpckldq m3, m4

%if UNIX64
    %define t0 r4
%else
    %define t0 rax
    mov t0, r4mp
%endif

    movq      [t0+ 0], m1
    movq      [t0+ 8], m3
    movhps    [t0+16], m1
    movq      [t0+24], m5
    RET

;-----------------------------------------------------------------------------
; float pixel_ssim_end( int sum0[5][4], int sum1[5][4], int width )
;-----------------------------------------------------------------------------
cglobal pixel_ssim_end4, 3,3,7
    movdqa    m0, [r0+ 0]
    movdqa    m1, [r0+16]
    movdqa    m2, [r0+32]
    movdqa    m3, [r0+48]
    movdqa    m4, [r0+64]
    paddd     m0, [r1+ 0]
    paddd     m1, [r1+16]
    paddd     m2, [r1+32]
    paddd     m3, [r1+48]
    paddd     m4, [r1+64]
    paddd     m0, m1
    paddd     m1, m2
    paddd     m2, m3
    paddd     m3, m4
    movdqa    m5, [ssim_c1]
    movdqa    m6, [ssim_c2]
    TRANSPOSE4x4D  0, 1, 2, 3, 4

;   s1=m0, s2=m1, ss=m2, s12=m3
%if BIT_DEPTH == 10
    cvtdq2ps  m0, m0
    cvtdq2ps  m1, m1
    cvtdq2ps  m2, m2
    cvtdq2ps  m3, m3
    mulps     m2, [pf_64] ; ss*64
    mulps     m3, [pf_128] ; s12*128
    movdqa    m4, m1
    mulps     m4, m0      ; s1*s2
    mulps     m1, m1      ; s2*s2
    mulps     m0, m0      ; s1*s1
    addps     m4, m4      ; s1*s2*2
    addps     m0, m1      ; s1*s1 + s2*s2
    subps     m2, m0      ; vars
    subps     m3, m4      ; covar*2
    addps     m4, m5      ; s1*s2*2 + ssim_c1
    addps     m0, m5      ; s1*s1 + s2*s2 + ssim_c1
    addps     m2, m6      ; vars + ssim_c2
    addps     m3, m6      ; covar*2 + ssim_c2
%else
    pmaddwd   m4, m1, m0  ; s1*s2
    pslld     m1, 16
    por       m0, m1
    pmaddwd   m0, m0  ; s1*s1 + s2*s2
    pslld     m4, 1
    pslld     m3, 7
    pslld     m2, 6
    psubd     m3, m4  ; covar*2
    psubd     m2, m0  ; vars
    paddd     m0, m5
    paddd     m4, m5
    paddd     m3, m6
    paddd     m2, m6
    cvtdq2ps  m0, m0  ; (float)(s1*s1 + s2*s2 + ssim_c1)
    cvtdq2ps  m4, m4  ; (float)(s1*s2*2 + ssim_c1)
    cvtdq2ps  m3, m3  ; (float)(covar*2 + ssim_c2)
    cvtdq2ps  m2, m2  ; (float)(vars + ssim_c2)
%endif
    mulps     m4, m3
    mulps     m0, m2
    divps     m4, m0  ; ssim

    cmp       r2d, 4
    je .skip ; faster only if this is the common case; remove branch if we use ssim on a macroblock level
    neg       r2
%ifdef PIC
    lea       r3, [mask_ff + 16]
    movdqu    m1, [r3 + r2*4]
%else
    movdqu    m1, [mask_ff + r2*4 + 16]
%endif
    pand      m4, m1
.skip:
    movhlps   m0, m4
    addps     m0, m4
    pshuflw   m4, m0, q0032
    addss     m0, m4
%if ARCH_X86_64 == 0
    movd     r0m, m0
    fld     dword r0m
%endif
    RET
%endmacro ; SSIM

INIT_XMM sse2
SSIM
INIT_XMM avx
SSIM

;-----------------------------------------------------------------------------
; avx512icl ssim_4x4x2_core: VNNI. A dword is 4 pixels of a row of one block (8-bit) or
; 2 (high bit depth); sums s1 m2, s2 m3, ss m4, s12 m5.
; 8-bit: four rows a ymm; x*1, x*(x ^ 0x80) = x*x - 128*x, a*(b ^ 0x80) = a*b - 128*a.
;-----------------------------------------------------------------------------
%if ARCH_X86_64
INIT_YMM avx512icl
cglobal pixel_ssim_4x4x2_core, 5,8,10
    FIX_STRIDES r1, r3
    lea         r5, [r1*3]
    lea         r6, [r3*3]
    pxor        m2, m2
    pxor        m3, m3
    pxor        m4, m4
    pxor        m5, m5
%if HIGH_BIT_DEPTH
    vpbroadcastd m6, [pw_1]
    movu       xm0, [r0]
    vinserti128 m0, m0, [r0+r1], 1
    movu       xm1, [r2]
    vinserti128 m1, m1, [r2+r3], 1
    movu       xm7, [r0+r1*2]
    vinserti128 m7, m7, [r0+r5], 1
    movu       xm8, [r2+r3*2]
    vinserti128 m8, m8, [r2+r6], 1
    vpdpwssd    m2, m0, m6
    vpdpwssd    m3, m1, m6
    vpdpwssd    m4, m0, m0
    vpdpwssd    m5, m0, m1
    vpdpwssd    m2, m7, m6
    vpdpwssd    m3, m8, m6
    vpdpwssd    m4, m7, m7
    vpdpwssd    m5, m7, m8
    vpdpwssd    m4, m1, m1
    vpdpwssd    m4, m8, m8
    ; dwords per row: L L R R
    punpckldq   m8, m2, m3
    punpckhdq   m2, m3
    punpckldq   m9, m4, m5
    punpckhdq   m4, m5
    punpcklqdq  m3, m8, m9
    punpckhqdq  m8, m9
    paddd       m3, m8            ; s1 s2 ss s12 of L
    punpcklqdq  m8, m2, m4
    punpckhqdq  m2, m4
    paddd       m2, m8            ; of R
%else
    vpbroadcastd m6, [pb_1]
    mov        r7d, 0x80808080
    vpbroadcastd m7, r7d
    movq       xm0, [r0]
    movhps     xm0, [r0+r1]
    movq       xm8, [r0+r1*2]
    movhps     xm8, [r0+r5]
    vinserti128 m0, m0, xm8, 1
    movq       xm1, [r2]
    movhps     xm1, [r2+r3]
    movq       xm8, [r2+r3*2]
    movhps     xm8, [r2+r6]
    vinserti128 m1, m1, xm8, 1
    pxor        m8, m0, m7
    pxor        m9, m1, m7
    vpdpbusd    m2, m0, m6
    vpdpbusd    m3, m1, m6
    vpdpbusd    m4, m0, m8
    vpdpbusd    m5, m0, m9
    vpdpbusd    m4, m1, m9
    paddd       m8, m2, m3
    pslld       m8, 7
    pslld       m9, m2, 7
    paddd       m4, m8
    paddd       m5, m9
    ; dwords per row: L R
    punpckldq   m8, m2, m3
    punpckhdq   m2, m3
    paddd       m2, m8            ; s1 s2 of L, R
    punpckldq   m8, m4, m5
    punpckhdq   m4, m5
    paddd       m4, m8            ; ss s12 of L, R
    punpcklqdq  m3, m2, m4
    punpckhqdq  m2, m4
%endif
    vextracti128 xm8, m3, 1
    paddd      xm3, xm8
    vextracti128 xm8, m2, 1
    paddd      xm2, xm8
    movu   [r4+ 0], xm3
    movu   [r4+16], xm2
    RET
%endif

;-----------------------------------------------------------------------------
; int pixel_asd8( pixel *pix1, intptr_t stride1, pixel *pix2, intptr_t stride2, int height );
;-----------------------------------------------------------------------------
%macro ASD8 0
cglobal pixel_asd8, 5,5
    pxor     m0, m0
    pxor     m1, m1
.loop:
%if HIGH_BIT_DEPTH
    paddw    m0, [r0]
    paddw    m1, [r2]
    paddw    m0, [r0+2*r1]
    paddw    m1, [r2+2*r3]
    lea      r0, [r0+4*r1]
    paddw    m0, [r0]
    paddw    m1, [r2+4*r3]
    lea      r2, [r2+4*r3]
    paddw    m0, [r0+2*r1]
    paddw    m1, [r2+2*r3]
    lea      r0, [r0+4*r1]
    lea      r2, [r2+4*r3]
%else
    movq     m2, [r0]
    movq     m3, [r2]
    movhps   m2, [r0+r1]
    movhps   m3, [r2+r3]
    lea      r0, [r0+2*r1]
    psadbw   m2, m1
    psadbw   m3, m1
    movq     m4, [r0]
    movq     m5, [r2+2*r3]
    lea      r2, [r2+2*r3]
    movhps   m4, [r0+r1]
    movhps   m5, [r2+r3]
    lea      r0, [r0+2*r1]
    paddw    m0, m2
    psubw    m0, m3
    psadbw   m4, m1
    psadbw   m5, m1
    lea      r2, [r2+2*r3]
    paddw    m0, m4
    psubw    m0, m5
%endif
    sub     r4d, 4
    jg .loop
%if HIGH_BIT_DEPTH
    psubw    m0, m1
    HADDW    m0, m1
    ABSD     m1, m0
%else
    movhlps  m1, m0
    paddw    m0, m1
    ABSW     m1, m0
%endif
    movd    eax, m1
    RET
%endmacro

INIT_XMM sse2
ASD8
INIT_XMM ssse3
ASD8
%if HIGH_BIT_DEPTH
INIT_XMM xop
ASD8
%endif

;=============================================================================
; Successive Elimination ADS
;=============================================================================

%macro ADS_START 0
%if UNIX64
    movsxd  r5, r5d
%else
    mov    r5d, r5m
%endif
    mov    r0d, r5d
    lea     r6, [r4+r5+(mmsize-1)]
    and     r6, ~(mmsize-1)
    shl     r2d,  1
%endmacro

%macro ADS_END 1-2 .loop ; unroll_size, loop_label
    add     r1, 2*%1
    add     r3, 2*%1
    add     r6, %1
    sub    r0d, %1
    jg %2
    WIN64_RESTORE_XMM_INTERNAL
%if mmsize==32
    vzeroupper
%endif
    lea     r6, [r4+r5+(mmsize-1)]
    and     r6, ~(mmsize-1)
%if cpuflag(ssse3)
    jmp ads_mvs_ssse3
%else
    jmp ads_mvs_mmx
%endif
%endmacro

;-----------------------------------------------------------------------------
; int pixel_ads4( int enc_dc[4], uint16_t *sums, int delta,
;                 uint16_t *cost_mvx, int16_t *mvs, int width, int thresh )
;-----------------------------------------------------------------------------
%if HIGH_BIT_DEPTH

%macro ADS_XMM 0
%if ARCH_X86_64
cglobal pixel_ads4, 5,7,9
%else
cglobal pixel_ads4, 5,7,8
%endif
%if mmsize >= 32
    vpbroadcastd m7, [r0+ 0]
    vpbroadcastd m6, [r0+ 4]
    vpbroadcastd m5, [r0+ 8]
    vpbroadcastd m4, [r0+12]
%else
    mova      m4, [r0]
    pshufd    m7, m4, 0
    pshufd    m6, m4, q1111
    pshufd    m5, m4, q2222
    pshufd    m4, m4, q3333
%endif
%if ARCH_X86_64
    SPLATD    m8, r6m
%endif
    ADS_START
.loop:
%if cpuflag(avx)
    pmovzxwd  m0, [r1]
    pmovzxwd  m1, [r1+16]
%else
    movh      m0, [r1]
    movh      m1, [r1+16]
    pxor      m3, m3
    punpcklwd m0, m3
    punpcklwd m1, m3
%endif
    psubd     m0, m7
    psubd     m1, m6
    ABSD      m0, m0, m2
    ABSD      m1, m1, m3
%if cpuflag(avx)
    pmovzxwd  m2, [r1+r2]
    pmovzxwd  m3, [r1+r2+16]
    paddd     m0, m1
%else
    movh      m2, [r1+r2]
    movh      m3, [r1+r2+16]
    paddd     m0, m1
    pxor      m1, m1
    punpcklwd m2, m1
    punpcklwd m3, m1
%endif
    psubd     m2, m5
    psubd     m3, m4
    ABSD      m2, m2, m1
    ABSD      m3, m3, m1
    paddd     m0, m2
    paddd     m0, m3
%if cpuflag(avx)
    pmovzxwd  m1, [r3]
%else
    movh      m1, [r3]
    pxor      m3, m3
    punpcklwd m1, m3
%endif
    paddd     m0, m1
%if ARCH_X86_64
    psubd     m1, m8, m0
%else
    SPLATD    m1, r6m
    psubd     m1, m0
%endif
    packssdw  m1, m1
%if mmsize == 32
    vpermq    m1, m1, q3120
    packuswb  m1, m1
    movq    [r6], xm1
%else
    packuswb  m1, m1
    movd    [r6], m1
%endif
    ADS_END mmsize/4

cglobal pixel_ads2, 5,7,8
%if mmsize >= 32
    vpbroadcastd m7, [r0+0]
    vpbroadcastd m6, [r0+4]
    vpbroadcastd m5, r6m
%else
    movq      m6, [r0]
    movd      m5, r6m
    pshufd    m7, m6, 0
    pshufd    m6, m6, q1111
    pshufd    m5, m5, 0
%endif
    pxor      m4, m4
    ADS_START
.loop:
%if cpuflag(avx)
    pmovzxwd  m0, [r1]
    pmovzxwd  m1, [r1+r2]
    pmovzxwd  m2, [r3]
%else
    movh      m0, [r1]
    movh      m1, [r1+r2]
    movh      m2, [r3]
    punpcklwd m0, m4
    punpcklwd m1, m4
    punpcklwd m2, m4
%endif
    psubd     m0, m7
    psubd     m1, m6
    ABSD      m0, m0, m3
    ABSD      m1, m1, m3
    paddd     m0, m1
    paddd     m0, m2
    psubd     m1, m5, m0
    packssdw  m1, m1
%if mmsize == 32
    vpermq    m1, m1, q3120
    packuswb  m1, m1
    movq    [r6], xm1
%else
    packuswb  m1, m1
    movd    [r6], m1
%endif
    ADS_END mmsize/4

cglobal pixel_ads1, 5,7,8
%if mmsize >= 32
    vpbroadcastd m7, [r0]
    vpbroadcastd m6, r6m
%else
    movd      m7, [r0]
    movd      m6, r6m
    pshufd    m7, m7, 0
    pshufd    m6, m6, 0
%endif
    pxor      m5, m5
    ADS_START
.loop:
    movu      m1, [r1]
    movu      m3, [r3]
    punpcklwd m0, m1, m5
    punpckhwd m1, m5
    punpcklwd m2, m3, m5
    punpckhwd m3, m5
    psubd     m0, m7
    psubd     m1, m7
    ABSD      m0, m0, m4
    ABSD      m1, m1, m4
    paddd     m0, m2
    paddd     m1, m3
    psubd     m2, m6, m0
    psubd     m3, m6, m1
    packssdw  m2, m3
    packuswb  m2, m2
%if mmsize == 32
    vpermq    m2, m2, q3120
    mova    [r6], xm2
%else
    movq    [r6], m2
%endif
    ADS_END mmsize/2
%endmacro

INIT_XMM sse2
ADS_XMM
INIT_XMM ssse3
ADS_XMM
INIT_XMM avx
ADS_XMM
INIT_YMM avx2
ADS_XMM

%else ; !HIGH_BIT_DEPTH

%macro ADS_XMM 0
%if ARCH_X86_64 && mmsize == 16
cglobal pixel_ads4, 5,7,12
%elif ARCH_X86_64 && mmsize != 8
cglobal pixel_ads4, 5,7,9
%else
cglobal pixel_ads4, 5,7,8
%endif
    test dword r6m, 0xffff0000
%if mmsize >= 32
    vpbroadcastw m7, [r0+ 0]
    vpbroadcastw m6, [r0+ 4]
    vpbroadcastw m5, [r0+ 8]
    vpbroadcastw m4, [r0+12]
%elif mmsize == 16
    mova       m4, [r0]
    pshuflw    m7, m4, 0
    pshuflw    m6, m4, q2222
    pshufhw    m5, m4, 0
    pshufhw    m4, m4, q2222
    punpcklqdq m7, m7
    punpcklqdq m6, m6
    punpckhqdq m5, m5
    punpckhqdq m4, m4
%else
    mova      m6, [r0]
    mova      m4, [r0+8]
    pshufw    m7, m6, 0
    pshufw    m6, m6, q2222
    pshufw    m5, m4, 0
    pshufw    m4, m4, q2222
%endif
    jnz .nz
    ADS_START
%if ARCH_X86_64 && mmsize == 16
    movu     m10, [r1]
    movu     m11, [r1+r2]
    SPLATW    m8, r6m
.loop:
    psubw     m0, m10, m7
    movu     m10, [r1+16]
    psubw     m1, m10, m6
    ABSW      m0, m0, m2
    ABSW      m1, m1, m3
    psubw     m2, m11, m5
    movu     m11, [r1+r2+16]
    paddw     m0, m1
    psubw     m3, m11, m4
    movu      m9, [r3]
    ABSW      m2, m2, m1
    ABSW      m3, m3, m1
    paddw     m0, m2
    paddw     m0, m3
    paddusw   m0, m9
    psubusw   m1, m8, m0
%else
%if ARCH_X86_64 && mmsize != 8
    SPLATW    m8, r6m
%endif
.loop:
    movu      m0, [r1]
    movu      m1, [r1+16]
    psubw     m0, m7
    psubw     m1, m6
    ABSW      m0, m0, m2
    ABSW      m1, m1, m3
    movu      m2, [r1+r2]
    movu      m3, [r1+r2+16]
    psubw     m2, m5
    psubw     m3, m4
    paddw     m0, m1
    ABSW      m2, m2, m1
    ABSW      m3, m3, m1
    paddw     m0, m2
    paddw     m0, m3
    movu      m2, [r3]
%if ARCH_X86_64 && mmsize != 8
    mova      m1, m8
%else
    SPLATW    m1, r6m
%endif
    paddusw   m0, m2
    psubusw   m1, m0
%endif ; ARCH
    packsswb  m1, m1
%if mmsize == 32
    vpermq    m1, m1, q3120
    mova    [r6], xm1
%else
    movh    [r6], m1
%endif
    ADS_END mmsize/2
.nz:
    ADS_START
%if ARCH_X86_64 && mmsize == 16
    movu     m10, [r1]
    movu     m11, [r1+r2]
    SPLATD    m8, r6m
.loop_nz:
    psubw     m0, m10, m7
    movu     m10, [r1+16]
    psubw     m1, m10, m6
    ABSW      m0, m0, m2
    ABSW      m1, m1, m3
    psubw     m2, m11, m5
    movu     m11, [r1+r2+16]
    paddw     m0, m1
    psubw     m3, m11, m4
    movu      m9, [r3]
    ABSW      m2, m2, m1
    ABSW      m3, m3, m1
    paddw     m0, m2
    paddw     m0, m3
    pxor      m3, m3
    mova      m2, m0
    mova      m1, m9
    punpcklwd m0, m3
    punpcklwd m9, m3
    punpckhwd m2, m3
    punpckhwd m1, m3
    paddd     m0, m9
    paddd     m2, m1
    psubd     m1, m8, m0
    psubd     m3, m8, m2
    packssdw  m1, m3
    packuswb  m1, m1
%else
%if ARCH_X86_64 && mmsize != 8
    SPLATD    m8, r6m
%endif
.loop_nz:
    movu      m0, [r1]
    movu      m1, [r1+16]
    psubw     m0, m7
    psubw     m1, m6
    ABSW      m0, m0, m2
    ABSW      m1, m1, m3
    movu      m2, [r1+r2]
    movu      m3, [r1+r2+16]
    psubw     m2, m5
    psubw     m3, m4
    paddw     m0, m1
    ABSW      m2, m2, m1
    ABSW      m3, m3, m1
    paddw     m0, m2
    paddw     m0, m3
%if mmsize == 32
    movu      m1, [r3]
%else
    movh      m1, [r3]
%endif
    pxor      m3, m3
    mova      m2, m0
    punpcklwd m0, m3
    punpcklwd m1, m3
    punpckhwd m2, m3
    paddd     m0, m1
%if mmsize == 32
    movu      m1, [r3]
    punpckhwd m1, m3
%else
    movh      m1, [r3+mmsize/2]
    punpcklwd m1, m3
%endif
    paddd     m2, m1
%if ARCH_X86_64 && mmsize != 8
    mova      m1, m8
%else
    SPLATD    m1, r6m
%endif
    mova      m3, m1
    psubd     m1, m0
    psubd     m3, m2
    packssdw  m1, m3
    packuswb  m1, m1
%endif ; ARCH
%if mmsize == 32
    vpermq    m1, m1, q3120
    mova    [r6], xm1
%else
    movh    [r6], m1
%endif
    ADS_END mmsize/2, .loop_nz

cglobal pixel_ads2, 5,7,8
    test dword r6m, 0xffff0000
%if mmsize >= 32
    vpbroadcastw m7, [r0+0]
    vpbroadcastw m6, [r0+4]
%elif mmsize == 16
    movq       m6, [r0]
    pshuflw    m7, m6, 0
    pshuflw    m6, m6, q2222
    punpcklqdq m7, m7
    punpcklqdq m6, m6
%else
    mova      m6, [r0]
    pshufw    m7, m6, 0
    pshufw    m6, m6, q2222
%endif
    jnz .nz
    ADS_START
    SPLATW    m5, r6m
.loop:
    movu      m0, [r1]
    movu      m1, [r1+r2]
    movu      m2, [r3]
    psubw     m0, m7
    psubw     m1, m6
    ABSW      m0, m0, m3
    ABSW      m1, m1, m4
    paddw     m0, m1
    paddusw   m0, m2
    psubusw   m1, m5, m0
    packsswb  m1, m1
%if mmsize == 32
    vpermq    m1, m1, q3120
    mova    [r6], xm1
%else
    movh    [r6], m1
%endif
    ADS_END mmsize/2
.nz:
    ADS_START
    SPLATD    m5, r6m
    pxor      m4, m4
.loop_nz:
    movu      m0, [r1]
    movu      m1, [r1+r2]
    movu      m2, [r3]
    psubw     m0, m7
    psubw     m1, m6
    ABSW      m0, m0, m3
    ABSW      m1, m1, m3
    paddw     m0, m1
    punpckhwd m3, m2, m4
    punpckhwd m1, m0, m4
    punpcklwd m2, m4
    punpcklwd m0, m4
    paddd     m1, m3
    paddd     m0, m2
    psubd     m3, m5, m1
    psubd     m2, m5, m0
    packssdw  m2, m3
    packuswb  m2, m2
%if mmsize == 32
    vpermq    m2, m2, q3120
    mova    [r6], xm2
%else
    movh    [r6], m2
%endif
    ADS_END mmsize/2, .loop_nz

cglobal pixel_ads1, 5,7,8
    test dword r6m, 0xffff0000
    SPLATW    m7, [r0]
    jnz .nz
    ADS_START
    SPLATW    m6, r6m
.loop:
    movu      m0, [r1]
    movu      m1, [r1+mmsize]
    movu      m2, [r3]
    movu      m3, [r3+mmsize]
    psubw     m0, m7
    psubw     m1, m7
    ABSW      m0, m0, m4
    ABSW      m1, m1, m5
    paddusw   m0, m2
    paddusw   m1, m3
    psubusw   m4, m6, m0
    psubusw   m5, m6, m1
    packsswb  m4, m5
%if mmsize == 32
    vpermq    m4, m4, q3120
%endif
    mova    [r6], m4
    ADS_END mmsize
.nz:
    ADS_START
    SPLATD    m6, r6m
    pxor      m5, m5
.loop_nz:
    movu      m0, [r1]
    movu      m1, [r1+mmsize]
    movu      m2, [r3]
    psubw     m0, m7
    psubw     m1, m7
    ABSW      m0, m0, m3
    ABSW      m1, m1, m4
    punpckhwd m3, m2, m5
    punpckhwd m4, m0, m5
    punpcklwd m2, m5
    punpcklwd m0, m5
    paddd     m4, m3
    paddd     m0, m2
    psubd     m3, m6, m4
    movu      m4, [r3+mmsize]
    psubd     m2, m6, m0
    packssdw  m2, m3
    punpckhwd m0, m1, m5
    punpckhwd m3, m4, m5
    punpcklwd m1, m5
    punpcklwd m4, m5
    paddd     m0, m3
    paddd     m1, m4
    psubd     m3, m6, m0
    psubd     m4, m6, m1
    packssdw  m4, m3
    packuswb  m2, m4
%if mmsize == 32
    vpermq    m2, m2, q3120
%endif
    mova    [r6], m2
    ADS_END mmsize, .loop_nz
%endmacro

INIT_MMX mmx2
ADS_XMM
INIT_XMM sse2
ADS_XMM
INIT_XMM ssse3
ADS_XMM
INIT_XMM avx
ADS_XMM
INIT_YMM avx2
ADS_XMM

%endif ; HIGH_BIT_DEPTH

; int pixel_ads_mvs( int16_t *mvs, uint8_t *masks, int width )
; {
;     int nmv=0, i, j;
;     *(uint32_t*)(masks+width) = 0;
;     for( i=0; i<width; i+=8 )
;     {
;         uint64_t mask = *(uint64_t*)(masks+i);
;         if( !mask ) continue;
;         for( j=0; j<8; j++ )
;             if( mask & (255<<j*8) )
;                 mvs[nmv++] = i+j;
;     }
;     return nmv;
; }

%macro TEST 1
    mov     [r4+r0*2], r1w
    test    r2d, 0xff<<(%1*8)
    setne   r3b
    add     r0d, r3d
    inc     r1d
%endmacro

INIT_MMX mmx
cglobal pixel_ads_mvs, 0,7,0
ads_mvs_mmx:
    ; mvs = r4
    ; masks = r6
    ; width = r5
    ; clear last block in case width isn't divisible by 8. (assume divisible by 4, so clearing 4 bytes is enough.)
    xor     r0d, r0d
    xor     r1d, r1d
    mov     [r6+r5], r0d
    jmp .loopi
ALIGN 16
.loopi0:
    add     r1d, 8
    cmp     r1d, r5d
    jge .end
.loopi:
    mov     r2,  [r6+r1]
%if ARCH_X86_64
    test    r2,  r2
%else
    mov     r3,  r2
    or     r3d, [r6+r1+4]
%endif
    jz .loopi0
    xor     r3d, r3d
    TEST 0
    TEST 1
    TEST 2
    TEST 3
%if ARCH_X86_64
    shr     r2,  32
%else
    mov     r2d, [r6+r1]
%endif
    TEST 0
    TEST 1
    TEST 2
    TEST 3
    cmp     r1d, r5d
    jl .loopi
.end:
    movifnidn eax, r0d
    RET

INIT_XMM ssse3
cglobal pixel_ads_mvs, 0,7,0
ads_mvs_ssse3:
    mova      m3, [pw_8]
    mova      m4, [pw_76543210]
    pxor      m5, m5
    add       r5, r6
    xor      r0d, r0d ; nmv
    mov     [r5], r0d
%ifdef PIC
    lea       r1, [$$]
    %define GLOBAL +r1-$$
%else
    %define GLOBAL
%endif
.loop:
    movh      m0, [r6]
    pcmpeqb   m0, m5
    pmovmskb r2d, m0
    xor      r2d, 0xffff                         ; skipping if r2d is zero is slower (branch mispredictions)
    movzx    r3d, byte [r2+popcnt_table GLOBAL]  ; popcnt
    add      r2d, r2d
    ; shuffle counters based on mv mask
    pshufb    m2, m4, [r2*8+ads_mvs_shuffle GLOBAL]
    movu [r4+r0*2], m2
    add      r0d, r3d
    paddw     m4, m3                             ; {i*8+0, i*8+1, i*8+2, i*8+3, i*8+4, i*8+5, i*8+6, i*8+7}
    add       r6, 8
    cmp       r6, r5
    jl .loop
    movifnidn eax, r0d
    RET

%if ARCH_X86_64
;-----------------------------------------------------------------------------
; avx512icl ads: no mask buffer. The compare is a k mask, vpcompressw packs the
; indices of the candidates and a masked store writes exactly that many at mvs+nmv.
; ADS_N candidates a chunk: words (8-bit), dwords (high bit depth).
; m4 = indices, m5 = thresh, m6 = ADS_N; r6 = nmv, r9d = -1
;-----------------------------------------------------------------------------
%if HIGH_BIT_DEPTH
    %define ADS_N (mmsize/4)
%else
    %define ADS_N (mmsize/2)
%endif

%macro ADS_ICL_STORE 0 ; k1 = candidates of this chunk
    cmp        r5d, ADS_N
    jge %%full
    kmovd      r7d, k1
    bzhi       r7d, r7d, r5d
    kmovd       k1, r7d
%%full:
    kmovd      r7d, k1
    popcnt     r7d, r7d
    bzhi       r8d, r9d, r7d
    kmovd       k2, r8d
%if HIGH_BIT_DEPTH && mmsize == 64
    vpcompressw ym0 {k1}{z}, ym4
    vmovdqu16  [r4+r6*2] {k2}, ym0
%elif HIGH_BIT_DEPTH
    vpcompressw xm0 {k1}{z}, xm4
    vmovdqu16  [r4+r6*2] {k2}, xm0
%else
    vpcompressw m0 {k1}{z}, m4
    vmovdqu16  [r4+r6*2] {k2}, m0
%endif
    add        r6d, r7d
    paddw       m4, m6
%endmacro

; m0 = sum of |dc - sums| of ADS_N candidates (8-bit: words, < 65536)
%macro ADS_ICL_COST 1 ; size
%if HIGH_BIT_DEPTH
    pmovzxwd    m0, [r1]
    psubd       m0, m7
    pabsd       m0, m0
%if %1 == 4
    pmovzxwd    m1, [r1+16]
    pmovzxwd    m2, [r1+r2]
    pmovzxwd    m3, [r1+r2+16]
    psubd       m1, m8
    psubd       m2, m9
    psubd       m3, m10
    pabsd       m1, m1
    pabsd       m2, m2
    pabsd       m3, m3
    paddd       m0, m1
    paddd       m2, m3
    paddd       m0, m2
%elif %1 == 2
    pmovzxwd    m1, [r1+r2]
    psubd       m1, m8
    pabsd       m1, m1
    paddd       m0, m1
%endif
%else
    psubw       m0, m7, [r1]
    pabsw       m0, m0
%if %1 == 4
    psubw       m1, m8, [r1+16]
    psubw       m2, m9, [r1+r2]
    psubw       m3, m10, [r1+r2+16]
    pabsw       m1, m1
    pabsw       m2, m2
    pabsw       m3, m3
    paddw       m0, m1
    paddw       m2, m3
    paddw       m0, m2
%elif %1 == 2
    psubw       m1, m8, [r1+r2]
    pabsw       m1, m1
    paddw       m0, m1
%endif
%endif
%endmacro

%macro ADS_ICL_NEXT 1 ; loop label
    add         r1, ADS_N*2
    add         r3, ADS_N*2
    sub        r5d, ADS_N
    jg %1
    RET
%endmacro

%macro ADS_ICL 1-2 ; size, name suffix
cglobal pixel_ads%1%2, 7,10,11
    test       r6d, r6d
    jle .zero
    movsxd      r2, r2d
    add         r2, r2
    movu        m4, [ads_idx_w]
    mov        r7d, ADS_N
    vpbroadcastw m6, r7d
    mov        r9d, -1
%if HIGH_BIT_DEPTH
    vpbroadcastd m7, [r0]
%if %1 >= 2
    vpbroadcastd m8, [r0+4]
%endif
%if %1 == 4
    vpbroadcastd m9, [r0+8]
    vpbroadcastd m10, [r0+12]
%endif
    vpbroadcastd m5, r6d
    xor        r6d, r6d
.loop:
    ADS_ICL_COST %1
    pmovzxwd    m1, [r3]
    paddd       m0, m1
    vpcmpd      k1, m0, m5, 1
    ADS_ICL_STORE
    ADS_ICL_NEXT .loop
%else
    vpbroadcastw m7, [r0]
%if %1 >= 2
    vpbroadcastw m8, [r0+4]
%endif
%if %1 == 4
    vpbroadcastw m9, [r0+8]
    vpbroadcastw m10, [r0+12]
%endif
    cmp        r6d, 0xffff
    ja .hi
    vpbroadcastw m5, r6d
    xor        r6d, r6d
.loop:
    ADS_ICL_COST %1
    paddusw     m0, [r3]
    vpcmpuw     k1, m0, m5, 1
    ADS_ICL_STORE
    ADS_ICL_NEXT .loop
.hi: ; thresh > 0xffff: cost < thresh unless the 17-bit cost carries and its low word >= thresh - 0x10000
    sub        r6d, 0x10000
    mov        r7d, 0xffff
    cmp        r6d, r7d
    cmova      r6d, r7d
    vpbroadcastw m5, r6d
    xor        r6d, r6d
.loop_hi:
    ADS_ICL_COST %1
    movu        m1, [r3]
    paddw       m0, m1
    vpcmpuw     k1, m0, m5, 1
    vpcmpuw     k2, m0, m1, 5
    kord        k1, k1, k2
    ADS_ICL_STORE
    ADS_ICL_NEXT .loop_hi
%endif
.zero:
    xor        eax, eax
    RET
%endmacro

INIT_YMM avx512icl
ADS_ICL 4
ADS_ICL 2
ADS_ICL 1
INIT_ZMM avx512icl
ADS_ICL 4, _zmm
ADS_ICL 2, _zmm
ADS_ICL 1, _zmm
%endif ; ARCH_X86_64

%if ARCH_X86_64
;-----------------------------------------------------------------------------
; void pixel_satd_mcc( fenc, int res[2], pixel *src, intptr_t stride,
;                      int dx, int dy, int width, int height )
; Chroma ME: satd of the u and v mc_chroma predictions against fenc's u
; (res[0]) and v (res[1]) without storing them. High bit depth: fenc is the
; interleaved uv fenc plane, with the stride of src. 8-bit: fenc is int16_t
; 64*fenc - 32 from pixel_satd_mcc_fenc_pre, 32 bytes per row (width 8),
; per rows k | k+4 (width 4) or per rows 0 | 2 and 1 | 3 (4x4). The filter is
; mc_chroma's in two exact passes, on words (8-bit pixels zero extended), as
; the 10-bit AVX2 mc_chroma; 8-bit 4x4 in one, pmaddubsw as the 8-bit one.
; Rows stay interleaved: u in even words, v in odd words, so the 4x4 Hadamard
; columns are dwords and u and v never mix. Width 8: one row per ymm; width 4:
; rows k and k+4 per ymm; 4x4: rows 0 | 2 and 1 | 3. Width 8: height 4, 8 or
; 16; width 4: height 4, 8 or 16.
;-----------------------------------------------------------------------------
; H of the interleaved row at %2 (and at %3 into lane 1) -> m%1; clobbers m15
%macro MCC_SATD_H 2-3
%if HIGH_BIT_DEPTH && %0 == 3
    movu         xm%1, [%2]
    vinserti128   m%1, m%1, [%3], 1
    movu         xm15, [%2+4]
    vinserti128   m15, m15, [%3+4], 1
%elif HIGH_BIT_DEPTH
    movu          m%1, [%2]
    movu          m15, [%2+4]
%elif %0 == 3
    movq         xm%1, [%2]
    movhps       xm%1, [%3]
    vpmovzxbw     m%1, xm%1
    movq         xm15, [%2+2]
    movhps       xm15, [%3+2]
    vpmovzxbw     m15, xm15
%else
    vpmovzxbw     m%1, [%2]
    vpmovzxbw     m15, [%2+2]
%endif
    pmullw        m%1, m8
    pmullw        m15, m9
    paddw         m%1, m15
%endmacro

; prediction from H m%2 (row above) and m%3 -> m%1, interleaved uv; clobbers m15.
; With %4 = 64*fenc - 32: minus fenc, (V+32-64*fenc)>>6 = ((V+32)>>6) - fenc
%macro MCC_SATD_V 3-4
    pmullw        m15, m%2, m10
    pmullw        m%1, m%3, m11
    paddw         m%1, m15
%if %0 == 4
    psubw         m%1, %4
    psraw         m%1, 6
%else
    paddw         m%1, m12
    psrlw         m%1, 6
%endif
%endmacro

; satd of the interleaved uv differences in m0-m3 -> m6 (u even, v odd words);
; clobbers m4, m5. Same coefficients and pairings as HADAMARD4_2D_SSE amax:
; vertical, then columns c0/c2, c1/c3 as dwords, then the amax stage.
%macro MCC_SATD_4x4 0
    SUMSUB_BADC    w, 0, 1, 2, 3, 4
    SUMSUB_BADC    w, 0, 2, 1, 3, 4
    SBUTTERFLY    dq, 0, 1, 4
    SBUTTERFLY    dq, 2, 3, 4
    SUMSUB_BADC    w, 0, 1, 2, 3, 4
    SBUTTERFLY   qdq, 0, 1, 4
    SBUTTERFLY   qdq, 2, 3, 4
    HADAMARD   0, amax, 0, 1, 4, 5
    HADAMARD   0, amax, 2, 3, 4, 5
    paddw          m6, m0
    paddw          m6, m2
%endmacro

; MCC_SATD_4x4 of the differences of rows 0 | 2 in m0 and 1 | 3 in m1 -> m6;
; clobbers m2. The second vertical stage pairs the lanes.
%macro MCC_SATD_4x4_LANES 0
    SUMSUB_BA      w, 0, 1, 2          ; 0+1 | 2+3, 1-0 | 3-2
    SBUTTERFLY  dqqq, 0, 1, 2          ; 0+1 | 1-0, 2+3 | 3-2
    SUMSUB_BA      w, 0, 1, 2
    SBUTTERFLY    dq, 0, 1, 2
    SUMSUB_BA      w, 0, 1, 2
    SBUTTERFLY   qdq, 0, 1, 2
    pabsw          m0, m0
    pabsw          m1, m1
    pmaxsw         m6, m0, m1
%endmacro

; res[0] = sum of the even words of m6, res[1] of the odd; clobbers m7
%macro MCC_SATD_END 0
    ; at most 4 passes, two words each: unsigned words
    psrld          m7, m6, 16         ; v
    pslld          m6, 16
    psrld          m6, 16             ; u
    phaddd         m6, m7
    vextracti128  xm7, m6, 1
    paddd         xm6, xm7
    phaddd        xm6, xm6
    movq        [r1], xm6
    RET
%endmacro

; row %2 (0-4) from base %1 -> mcc_row, r4 = 3*stride
%macro MCC_ROW 2
%assign mcc_i %2
%if mcc_i == 0
    %define mcc_row %1
%elif mcc_i == 1
    %define mcc_row %1+r3
%elif mcc_i == 2
    %define mcc_row %1+r3*2
%elif mcc_i == 3
    %define mcc_row %1+r4
%else
    %define mcc_row %1+r3*4
%endif
%endmacro

; H registers of rows k (mcc_h0) and k+1 (mcc_h1): m7 and m13 alternately
%macro MCC_HREGS 0
%assign mcc_h0 7+6*(mcc_k&1)
%assign mcc_h1 20-mcc_h0
%endmacro

INIT_YMM avx2
cglobal pixel_satd_mcc, 4,8,16
    FIX_STRIDES   r3
    movifnidn    r4d, r4m
    movifnidn    r5d, r5m
    mov          r6d, r5d
    sar          r6d, 3
    movsxd        r6, r6d
    imul          r6, r3
    add           r2, r6
    mov          r6d, r4d
    sar          r6d, 3
    movsxd        r6, r6d
    lea           r2, [r2+r6*2*SIZEOF_PIXEL] ; src += (dx>>3)*2 + (dy>>3)*stride pixels
    and          r4d, 7
    and          r5d, 7
%if HIGH_BIT_DEPTH == 0
    mov          r6d, r6m
    add          r6d, r7m
    cmp          r6d, 8               ; width + height 8: 4x4
    je .w4h4
%endif
    mov          r6d, 8
    sub          r6d, r4d
    movd         xm8, r6d
    vpbroadcastw  m8, xm8              ; 8-dx
    movd         xm9, r4d
    vpbroadcastw  m9, xm9              ; dx
    mov          r6d, 8
    sub          r6d, r5d
    movd        xm10, r6d
    vpbroadcastw m10, xm10             ; 8-dy
    movd        xm11, r5d
    vpbroadcastw m11, xm11             ; dy
%if HIGH_BIT_DEPTH
    vpbroadcastw m12, [pw_32]
%endif
    lea           r4, [r3*3]
    mov          r7d, r7m
    pxor          m6, m6
    cmp dword    r6m, 4
    je .w4

    MCC_SATD_H     7, r2
.loop8:
%assign mcc_k 0
%rep 4
    MCC_HREGS
    MCC_ROW        r2, mcc_k+1
    MCC_SATD_H     mcc_h1, mcc_row
%if HIGH_BIT_DEPTH
    MCC_SATD_V     mcc_k, mcc_h0, mcc_h1
    MCC_ROW        r0, mcc_k
    psubw         m %+ mcc_k, [mcc_row]
%else
    MCC_SATD_V     mcc_k, mcc_h0, mcc_h1, [r0+32*mcc_k]
%endif
%assign mcc_k mcc_k+1
%endrep
    MCC_SATD_4x4
%if HIGH_BIT_DEPTH
    lea           r0, [r0+r3*4]
%else
    sub           r0, -128
%endif
    lea           r2, [r2+r3*4]
    sub          r7d, 4
    jg .loop8
    jmp .end

.w4:
%if HIGH_BIT_DEPTH
    cmp          r7d, 4
    je .w4h4
%endif
.w4loop:
    lea           r6, [r2+r3*4]
%if HIGH_BIT_DEPTH
    lea           r5, [r0+r3*4]
%endif
    MCC_SATD_H     7, r2, r6          ; rows 0 | 4
%assign mcc_k 0
%rep 4
    MCC_HREGS
    MCC_ROW        r6, mcc_k+1
    %xdefine mcc_row4 mcc_row
    MCC_ROW        r2, mcc_k+1
    MCC_SATD_H     mcc_h1, mcc_row, mcc_row4 ; rows k+1 | k+5
%if HIGH_BIT_DEPTH
    MCC_SATD_V     mcc_k, mcc_h0, mcc_h1     ; rows k | k+4
    MCC_ROW        r0, mcc_k
    movu         xm15, [mcc_row]
    MCC_ROW        r5, mcc_k
    vinserti128   m15, m15, [mcc_row], 1
    psubw         m %+ mcc_k, m15
%else
    MCC_SATD_V     mcc_k, mcc_h0, mcc_h1, [r0+32*mcc_k]
%endif
%assign mcc_k mcc_k+1
%endrep
    MCC_SATD_4x4
%if HIGH_BIT_DEPTH
    lea           r0, [r0+r3*8]
%else
    sub           r0, -128
%endif
    lea           r2, [r2+r3*8]
    sub          r7d, 8
    jg .w4loop

.end:
    MCC_SATD_END

.w4h4:
%if HIGH_BIT_DEPTH
    lea           r6, [r2+r3*2]
    MCC_SATD_H     2, r2, r6          ; H rows 0 | 2
    MCC_SATD_H     3, r2+r3, r2+r4    ; H rows 1 | 3
    MCC_SATD_H     4, r6, r6+r3*2     ; H rows 2 | 4
    MCC_SATD_V     0, 2, 3
    MCC_SATD_V     1, 3, 4
    movu         xm2, [r0]
    vinserti128   m2, m2, [r0+r3*2], 1
    movu         xm3, [r0+r3]
    vinserti128   m3, m3, [r0+r4], 1
    psubw         m0, m2
    psubw         m1, m3
%else
    ; pmaddubsw on byte pairs (i, i+2) of rows k and k+1 with mc_chroma's
    ; A | B<<8 = (8-dx | dx<<8)*(8-dy) and C | D<<8 = (8-dx | dx<<8)*dy: each
    ; at most 255*64, minus 64*fenc - 32, >> 6 = ((V+32)>>6) - fenc
    imul         r6d, r4d, 255
    add          r6d, 8               ; 8-dx | dx<<8
    mov          r4d, 8
    sub          r4d, r5d
    imul         r4d, r6d
    imul         r5d, r6d
    movd         xm8, r4d
    vpbroadcastw  m8, xm8              ; A | B<<8
    movd         xm9, r5d
    vpbroadcastw  m9, xm9              ; C | D<<8
    vbroadcasti128 m7, [mcc_ch_shuf]
    lea           r4, [r3*3]
    movu         xm0, [r2]
    vinserti128   m0, m0, [r2+r3*2], 1 ; rows 0 | 2
    movu         xm1, [r2+r3]
    vinserti128   m1, m1, [r2+r4], 1   ; rows 1 | 3
    movu         xm2, [r2+r3*2]
    vinserti128   m2, m2, [r2+r3*4], 1 ; rows 2 | 4
    pshufb        m0, m7
    pshufb        m1, m7
    pshufb        m2, m7
    pmaddubsw     m0, m8
    pmaddubsw     m3, m1, m9
    pmaddubsw     m1, m8
    pmaddubsw     m2, m9
    paddw         m0, m3
    paddw         m1, m2
    psubw         m0, [r0]
    psubw         m1, [r0+32]
    psraw         m0, 6
    psraw         m1, 6
%endif
    MCC_SATD_4x4_LANES
    MCC_SATD_END

%if HIGH_BIT_DEPTH == 0
;-----------------------------------------------------------------------------
; void pixel_satd_mcc_fenc_pre( int16_t pre[512], uint8_t *fenc, int height )
; satd_mcc's fenc: 64*fenc - 32 of the chroma fenc (u then v per row,
; FENC_STRIDE, height 8 or 16), uv interleaved. Width 8: row y at 16*y.
; Width 4: columns 4c to 4c+3 of rows 8g+k | 8g+k+4 at 256+128*c+64*g+16*k.
; 4x4, height 8 only (in place of width 8 rows 8-15): columns 4c to 4c+3 of
; rows 4g+k at 128+32*c+64*g+8*(k>>1)+16*(k&1), so rows 0 | 2 and 1 | 3.
;-----------------------------------------------------------------------------
; rows 8*%1 to 8*%1+7; %2: also the 4x4 blocks
%macro MCC_FENC_PRE 2
%assign mcc_j 0
%rep 4
    movu          xm0, [r1+128*%1+16*mcc_j]
    vinserti128    m0, m0, [r1+128*%1+16*mcc_j+64], 1 ; rows k | k+4
    punpckhbw      m1, m0, m4         ; v
    punpcklbw      m0, m4             ; u
    psllw          m0, 6
    psllw          m1, 6
    psubw          m0, m5
    psubw          m1, m5
    punpckhwd      m2, m0, m1         ; columns 4-7
    punpcklwd      m0, m1             ; columns 0-3
    mova [r0+512+128*%1+32*mcc_j], m0
    mova [r0+768+128*%1+32*mcc_j], m2
%if %2
    %assign mcc_o 256+16*(mcc_j>>1)+32*(mcc_j&1)
    mova     [r0+mcc_o], xm0
    vextracti128 [r0+mcc_o+128], m0, 1
    mova  [r0+mcc_o+64], xm2
    vextracti128 [r0+mcc_o+192], m2, 1
%endif
    vperm2i128     m1, m0, m2, 0x20   ; row k
    vperm2i128     m0, m0, m2, 0x31   ; row k+4
    mova [r0+256*%1+32*mcc_j], m1
    mova [r0+256*%1+32*mcc_j+128], m0
%assign mcc_j mcc_j+1
%endrep
%endmacro

cglobal pixel_satd_mcc_fenc_pre, 3,3,6
    pxor           m4, m4
    vpbroadcastw   m5, [pw_32]
    cmp           r2d, 8
    jg .h16
    MCC_FENC_PRE    0, 1
    RET
.h16:
    MCC_FENC_PRE    0, 0
    MCC_FENC_PRE    1, 0
    RET
%endif ; !HIGH_BIT_DEPTH
%endif ; ARCH_X86_64

;=============================================================================
; x264_weights_analyse luma
;=============================================================================
;-----------------------------------------------------------------------------
; void weightp_dc8x8( int32_t dc[4], pixel *pix1, intptr_t i_pix1, pixel *pix2, intptr_t i_pix2 )
;-----------------------------------------------------------------------------
; The sums of pix1 - pix2 of the 4x4 blocks, in raster order: word column sums of rows
; 0-3 and 4-7 (within +-4 * pixel_max), pmaddwd into pairs, then pairs of pairs.
%macro WEIGHTP_DC_ROW 1 ; acc
%if HIGH_BIT_DEPTH
    movu       m2, [r1]
    movu       m3, [r3]
%else
    movh       m2, [r1]
    movh       m3, [r3]
    punpcklbw  m2, m4
    punpcklbw  m3, m4
%endif
    psubw      m2, m3
    paddw      %1, m2
    add        r1, r2
    add        r3, r4
%endmacro

INIT_XMM sse2
cglobal weightp_dc8x8, 5,5,6
    FIX_STRIDES r2, r4
    pxor       m0, m0
    pxor       m1, m1
%if HIGH_BIT_DEPTH == 0
    pxor       m4, m4
%endif
%rep 4
    WEIGHTP_DC_ROW m0
%endrep
%rep 4
    WEIGHTP_DC_ROW m1
%endrep
    mova       m5, [pw_1]
    pmaddwd    m0, m5
    pmaddwd    m1, m5
    mova       m2, m0
    shufps     m0, m1, q2020
    shufps     m2, m1, q3131
    paddd      m0, m2
    movu     [r0], m0
    RET

%if ARCH_X86_64
; avx512icl: rows 0-3 into m0, 4-7 into m1. 8-bit: vpdpbusd of pix1 by 1 and pix2 by -1,
; four rows of 8 a ymm, dwords r0L r0R r1L r1R | r2L r2R r3L r3R. High bit depth: vpdpwssd
; of pix1 - pix2 by 1, two rows a ymm, dwords pairs of r0 | r1.
%macro WEIGHTP_DC_ICL_LOAD 4 ; dst, src, stride, 3*stride
    movq      xm%1, [%2]
    movhps    xm%1, [%2+%3]
    movq       xm5, [%2+%3*2]
    movhps     xm5, [%2+%4]
    vinserti128 m%1, m%1, xm5, 1
%endmacro

%macro WEIGHTP_DC_ICL_HBD 1 ; acc: four rows
%rep 2
    movu      xm2, [r1]
    vinserti128 m2, m2, [r1+r2], 1
    movu      xm3, [r3]
    vinserti128 m3, m3, [r3+r4], 1
    psubw      m2, m3
    vpdpwssd  m%1, m2, m6
    lea        r1, [r1+r2*2]
    lea        r3, [r3+r4*2]
%endrep
%endmacro

INIT_YMM avx512icl
cglobal weightp_dc8x8, 5,7,8
    FIX_STRIDES r2, r4
    lea        r5, [r2*3]
    lea        r6, [r4*3]
    pxor       m0, m0
    pxor       m1, m1
%if HIGH_BIT_DEPTH
    vpbroadcastd m6, [pw_1]
    WEIGHTP_DC_ICL_HBD 0
    WEIGHTP_DC_ICL_HBD 1
%else
    vpbroadcastd m6, [pb_1]
    vpternlogd m7, m7, m7, 0xff
    WEIGHTP_DC_ICL_LOAD 2, r1, r2, r5
    WEIGHTP_DC_ICL_LOAD 3, r3, r4, r6
    lea        r1, [r1+r2*4]
    lea        r3, [r3+r4*4]
    vpdpbusd   m0, m2, m6
    vpdpbusd   m0, m3, m7
    WEIGHTP_DC_ICL_LOAD 2, r1, r2, r5
    WEIGHTP_DC_ICL_LOAD 3, r3, r4, r6
    vpdpbusd   m1, m2, m6
    vpdpbusd   m1, m3, m7
%endif
    vextracti128 xm2, m0, 1
    paddd     xm0, xm2
    vextracti128 xm2, m1, 1
    paddd     xm1, xm2
%if HIGH_BIT_DEPTH
    shufps    xm2, xm0, xm1, q2020
    shufps    xm0, xm1, q3131
%else
    punpcklqdq xm2, xm0, xm1
    punpckhqdq xm0, xm1
%endif
    paddd     xm0, xm2
    movu     [r0], xm0
    RET
%endif

;=============================================================================
; x264_weights_analyse chroma block statistics
;=============================================================================
%if ARCH_X86_64
%macro LOAD_PIXW 2 ; dst, src: mmsize/2 pixels as words
%if HIGH_BIT_DEPTH
    movu       %1, %2
%else
    pmovzxbw   %1, %2
%endif
%endmacro

; vpermd order of the HADD4D lanes: blocks { 0 2 4 6 | 1 3 5 7 } (ymm), { 0 4 8 12 | 1 5 9 13 | ... } (zmm)
%macro WEIGHTP_PERM 1
%if mmsize == 64
    pmovzxbd   %1, [weightp_perm16]
%else
    pmovzxbd   %1, [weightp_perm8]
%endif
%endmacro

%macro ALL_ONES 1
%if mmsize == 64
    vpternlogd %1, %1, %1, 0xff
%else
    pcmpeqw    %1, %1
%endif
%endmacro

; %1 = per lane { sum of %1, of %2, of %3, of %4 }, from 4 dwords a lane each; clobbers %3
%macro HADD4D 6 ; a, b, c, d, tmp, tmp
    punpckldq  %5, %1, %2
    punpckhdq  %1, %2
    paddd      %1, %5
    punpckldq  %6, %3, %4
    punpckhdq  %3, %4
    paddd      %3, %6
    punpcklqdq %5, %1, %3
    punpckhqdq %1, %3
    paddd      %1, %5
%endmacro

;-----------------------------------------------------------------------------
; void weightp_sum8( int32_t *sum, pixel *src, intptr_t i_src, int n, int height, int scale, int denom )
; void weightp_sum8_clip( int32_t *sum, pixel *src, intptr_t i_src, int n, int height, int scale, int denom,
;                         int offset )
;-----------------------------------------------------------------------------
; Per 8 x height block, the sum of ( x * scale + ((1 << denom) >> 1) ) >> denom: pmaddwd
; of { x, 1 } by { scale, round }. One block a lane, 4 registers a pass, n rounded up to
; mmsize/4. m5 = pw_1, xm6 = denom, m7 = { scale, round }, m10 = block order.
; _clip: each + offset, clipped to [0,pixel_max] as by mc weight. m9 = offset,
; m11 = pixel_max, m12 = 0.
%macro WEIGHTP_SUM8_ROW 3 ; acc, offset, clip
    LOAD_PIXW  m4, [r7+%2]
    punpckhwd  m8, m4, m5
    punpcklwd  m4, m5
    pmaddwd    m4, m7
    pmaddwd    m8, m7
    psrad      m4, xm6
    psrad      m8, xm6
%if %3
    paddd      m4, m9
    paddd      m8, m9
    pmaxsd     m4, m12
    pmaxsd     m8, m12
    pminsd     m4, m11
    pminsd     m8, m11
%endif
    paddd      %1, m4
    paddd      %1, m8
%endmacro

%macro WEIGHTP_SUM8 1 ; clip
%if %1
cglobal weightp_sum8_clip, 8,9,13
    movd      xm9, r7d
    vpbroadcastd m9, xm9
    pcmpeqd   m11, m11
    psrld     m11, 32-BIT_DEPTH
    pxor      m12, m12
%else
cglobal weightp_sum8, 7,9,11
%endif
    FIX_STRIDES r2
    xor       r7d, r7d
    bts       r7d, r6d
    shr       r7d, 1
    shl       r7d, 16
    or        r7d, r5d
    movd      xm7, r7d
    vpbroadcastd m7, xm7
    movd      xm6, r6d
    vpbroadcastd m5, [pw_1]
    WEIGHTP_PERM m10
.loopx:
    pxor       m0, m0
    pxor       m1, m1
    pxor       m2, m2
    pxor       m3, m3
    mov        r7, r1
    mov       r8d, r4d
.loopy:
    WEIGHTP_SUM8_ROW m0, 0, %1
    WEIGHTP_SUM8_ROW m1, mmsize/2*SIZEOF_PIXEL, %1
    WEIGHTP_SUM8_ROW m2, mmsize*SIZEOF_PIXEL, %1
    WEIGHTP_SUM8_ROW m3, mmsize*3/2*SIZEOF_PIXEL, %1
    add        r7, r2
    dec       r8d
    jg .loopy
    HADD4D     m0, m1, m2, m3, m4, m8
    vpermd     m0, m10, m0
    movu     [r0], m0
    add        r0, mmsize
    add        r1, 2*mmsize*SIZEOF_PIXEL
    sub       r3d, mmsize/4
    jg .loopx
    RET
%endmacro

;-----------------------------------------------------------------------------
; void weightp_stats8( int32_t *sum, uint32_t *minmax, pixel *src, intptr_t i_src, int n, int height )
;-----------------------------------------------------------------------------
; Per 8 x height block, height <= 16 (word sums): the sum, min | max << 16. As weightp_sum8.
; m13 = pw_1, m14 = block order.
%macro WEIGHTP_STATS8_ROW 4 ; sum, min, max, offset
    LOAD_PIXW  m12, [r6+%4]
    paddw      %1, m12
    pminuw     %2, m12
    pmaxuw     %3, m12
%endmacro

; min | max << 16 in dword 0 of each lane, from 8 words a lane
%macro WEIGHTP_MINMAX 3 ; min, max, tmp
    pshufd     %3, %1, q1032
    pminuw     %1, %3
    pshufd     %3, %1, q2301
    pminuw     %1, %3
    psrld      %3, %1, 16
    pminuw     %1, %3
    pshufd     %3, %2, q1032
    pmaxuw     %2, %3
    pshufd     %3, %2, q2301
    pmaxuw     %2, %3
    psrld      %3, %2, 16
    pmaxuw     %2, %3
    pslld      %1, 16
    psrld      %1, 16
    pslld      %2, 16
    por        %1, %2
%endmacro

%macro WEIGHTP_STATS8 0
cglobal weightp_stats8, 6,8,15
    FIX_STRIDES r3
    vpbroadcastd m13, [pw_1]
    WEIGHTP_PERM m14
.loopx:
    pxor       m0, m0
    pxor       m1, m1
    pxor       m2, m2
    pxor       m3, m3
    ALL_ONES   m4
    ALL_ONES   m5
    ALL_ONES   m6
    ALL_ONES   m7
    pxor       m8, m8
    pxor       m9, m9
    pxor      m10, m10
    pxor      m11, m11
    mov        r6, r2
    mov       r7d, r5d
.loopy:
    WEIGHTP_STATS8_ROW m0, m4, m8,  0
    WEIGHTP_STATS8_ROW m1, m5, m9,  mmsize/2*SIZEOF_PIXEL
    WEIGHTP_STATS8_ROW m2, m6, m10, mmsize*SIZEOF_PIXEL
    WEIGHTP_STATS8_ROW m3, m7, m11, mmsize*3/2*SIZEOF_PIXEL
    add        r6, r3
    dec       r7d
    jg .loopy
    WEIGHTP_MINMAX m4, m8,  m12
    WEIGHTP_MINMAX m5, m9,  m12
    WEIGHTP_MINMAX m6, m10, m12
    WEIGHTP_MINMAX m7, m11, m12
    punpckldq  m4, m5
    punpckldq  m6, m7
    punpcklqdq m4, m6
    vpermd     m4, m14, m4
    movu     [r1], m4
    pmaddwd    m0, m13
    pmaddwd    m1, m13
    pmaddwd    m2, m13
    pmaddwd    m3, m13
    HADD4D     m0, m1, m2, m3, m8, m9
    vpermd     m0, m14, m0
    movu     [r0], m0
    add        r0, mmsize
    add        r1, mmsize
    add        r2, 2*mmsize*SIZEOF_PIXEL
    sub       r4d, mmsize/4
    jg .loopx
    RET
%endmacro

;-----------------------------------------------------------------------------
; void weightp_sum8_nv( int32_t *sumu, int32_t *sumv, pixel *src, intptr_t i_src, int n, int height )
;-----------------------------------------------------------------------------
; Per block of 8 interleaved u v pairs x height, height <= 16 (word sums): the u and v
; sums. A block is 16 words, 8 registers a pass, n rounded up to mmsize/4. m15 = pd_ffff.
%macro WEIGHTP_SUM8_NV_ROW 2 ; acc, offset
    LOAD_PIXW  m8, [r6+%2]
    paddw      %1, m8
%endmacro

; u (low words) and v (high words) of 4 accumulators, %1-%4 = u, %5-%8 = v, per lane sums in %1, %5
%macro WEIGHTP_NV_SPLIT 10 ; u0-3, v0-3, tmp, tmp
    psrld      %5, %1, 16
    psrld      %6, %2, 16
    psrld      %7, %3, 16
    psrld      %8, %4, 16
    pand       %1, m15
    pand       %2, m15
    pand       %3, m15
    pand       %4, m15
    HADD4D     %1, %2, %3, %4, %9, %10
    HADD4D     %5, %6, %7, %8, %9, %10
%endmacro

; zmm: two blocks a register, in lanes 0 1 and 2 3. %1 %2: HADD4D of registers 0-3 and
; 4-7 (blocks 0-7, 8-15); %1 = blocks 0 2 4 6 | 1 3 5 7 | 8 10 12 14 | 9 11 13 15
%macro WEIGHTP_NV_LANES 3 ; lo, hi, tmp
    vshufi32x4 %3, %1, %1, q2301
    paddd      %1, %3
    vshufi32x4 %3, %2, %2, q2301
    paddd      %2, %3
    vshufi32x4 %1, %1, %2, q2020
%endmacro

%macro WEIGHTP_SUM8_NV 0
%if mmsize == 64
cglobal weightp_sum8_nv, 6,8,20
    pmovzxbd  m14, [weightp_perm_nv16]
%else
cglobal weightp_sum8_nv, 6,8,16
%endif
    FIX_STRIDES r3
    vpbroadcastd m15, [pd_ffff]
.loopx:
    pxor       m0, m0
    pxor       m1, m1
    pxor       m2, m2
    pxor       m3, m3
    pxor       m4, m4
    pxor       m5, m5
    pxor       m6, m6
    pxor       m7, m7
    mov        r6, r2
    mov       r7d, r5d
.loopy:
    WEIGHTP_SUM8_NV_ROW m0, 0*mmsize/2*SIZEOF_PIXEL
    WEIGHTP_SUM8_NV_ROW m1, 1*mmsize/2*SIZEOF_PIXEL
    WEIGHTP_SUM8_NV_ROW m2, 2*mmsize/2*SIZEOF_PIXEL
    WEIGHTP_SUM8_NV_ROW m3, 3*mmsize/2*SIZEOF_PIXEL
    WEIGHTP_SUM8_NV_ROW m4, 4*mmsize/2*SIZEOF_PIXEL
    WEIGHTP_SUM8_NV_ROW m5, 5*mmsize/2*SIZEOF_PIXEL
    WEIGHTP_SUM8_NV_ROW m6, 6*mmsize/2*SIZEOF_PIXEL
    WEIGHTP_SUM8_NV_ROW m7, 7*mmsize/2*SIZEOF_PIXEL
    add        r6, r3
    dec       r7d
    jg .loopy
%if mmsize == 64
    WEIGHTP_NV_SPLIT m0, m1, m2, m3, m8,  m9,  m10, m11, m12, m13
    WEIGHTP_NV_SPLIT m4, m5, m6, m7, m16, m17, m18, m19, m12, m13
    WEIGHTP_NV_LANES m0, m4,  m12
    WEIGHTP_NV_LANES m8, m16, m12
    vpermd     m0, m14, m0
    vpermd     m8, m14, m8
    movu     [r0], m0
    movu     [r1], m8
%else
    ; one block a register: blocks 0-3, then 4-7, each the sum of its two lanes
    WEIGHTP_NV_SPLIT m0, m1, m2, m3, m8, m9, m10, m11, m12, m13
    vextracti128 xm12, m0, 1
    paddd      xm0, xm12
    vextracti128 xm12, m8, 1
    paddd      xm8, xm12
    movu     [r0], xm0
    movu     [r1], xm8
    WEIGHTP_NV_SPLIT m4, m5, m6, m7, m8, m9, m10, m11, m12, m13
    vextracti128 xm12, m4, 1
    paddd      xm4, xm12
    vextracti128 xm12, m8, 1
    paddd      xm8, xm12
    movu  [r0+16], xm4
    movu  [r1+16], xm8
%endif
    add        r0, mmsize
    add        r1, mmsize
    add        r2, 4*mmsize*SIZEOF_PIXEL
    sub       r4d, mmsize/4
    jg .loopx
    RET
%endmacro

%if HIGH_BIT_DEPTH == 0
;-----------------------------------------------------------------------------
; 8-bit weightp_stats8 on bytes: a ymm row is 4 blocks; psadbw block sums, pminub, pmaxub.
; 8 blocks a pass. Then per block: the qword halves of two registers by shufps (lane 0
; blocks 0 1 4 5, lane 1 blocks 2 3 6 7) and the dword's bytes by shifts.
;-----------------------------------------------------------------------------
%macro WEIGHTP_STATS8_B 0
cglobal weightp_stats8, 6,8,13
    pxor       m8, m8
%if cpuflag(avx512icl)
    movu       m9, [weightp_mm_perm]
    movu      m10, [weightp_sum_perm]
    mov       r6d, 0x55555555
    kmovd      k1, r6d
    vpternlogd m12, m12, m12, 0xff ; once: vpternlogd isn't dependency breaking
%else
    pcmpeqb    m9, m9
    psrld      m9, 24
    pslld     m10, m9, 16
%endif
.loopx:
    pxor       m0, m0
    pxor       m1, m1
%if cpuflag(avx512)
    mova       m2, m12
    mova       m3, m12
%else
    pcmpeqb    m2, m2
    pcmpeqb    m3, m3
%endif
    pxor       m4, m4
    pxor       m5, m5
    mov        r6, r2
    mov       r7d, r5d
.loopy:
    movu       m6, [r6]
    movu       m7, [r6+32]
    psadbw    m11, m6, m8
    paddd      m0, m11
    pminub     m2, m6
    pmaxub     m4, m6
    psadbw    m11, m7, m8
    paddd      m1, m11
    pminub     m3, m7
    pmaxub     m5, m7
    add        r6, r3
    dec       r7d
    jg .loopy
    shufps     m6, m2, m3, q2020
    shufps     m2, m3, q3131
    pminub     m2, m6
    shufps     m6, m4, m5, q2020
    shufps     m4, m5, q3131
    pmaxub     m4, m6
    psrld      m6, m2, 16
    pminub     m2, m6
    psrlw      m6, m2, 8
    pminub     m2, m6
    psrld      m6, m4, 16
    pmaxub     m4, m6
    psrlw      m6, m4, 8
    pmaxub     m4, m6
%if cpuflag(avx512icl)
    vpermt2b   m2 {k1}{z}, m9, m4  ; min | max << 16, blocks in order
    vpermt2d   m0, m10, m1
%else
    pand       m2, m9
    pslld      m4, 16
    pand       m4, m10
    por        m2, m4
    vpermq     m2, m2, q3120
    shufps     m0, m1, q2020
    vpermq     m0, m0, q3120
%endif
    movu     [r1], m2
    movu     [r0], m0
    add        r0, 32
    add        r1, 32
    add        r2, 64
    sub       r4d, 8
    jg .loopx
    RET
%endmacro
%endif

INIT_YMM avx2
WEIGHTP_SUM8 0
WEIGHTP_SUM8 1
%if HIGH_BIT_DEPTH
WEIGHTP_STATS8
%else
WEIGHTP_STATS8_B
%endif
WEIGHTP_SUM8_NV

%if HIGH_BIT_DEPTH == 0
INIT_YMM avx512icl
WEIGHTP_STATS8_B

; avx512icl 8-bit weightp_sum8(_clip): on words, x * scale + round fits (scale 0-127):
; pmullw, paddw, psraw [, + offset, clip], then vpdpwssd by 1 into the block's dword pairs.
; As the AVX2 version otherwise: one block a lane, 4 registers a pass.
; m5 = pw_1, m6 = scale, m7 = round, xm8 = denom, m10 = block order;
; _clip: m9 = offset, m11 = 255, m12 = 0.
%macro WEIGHTP_SUM8_ICL_ROW 3 ; acc, offset, clip
    pmovzxbw   m4, [r7+%2]
    pmullw     m4, m6
    paddw      m4, m7
    psraw      m4, xm8
%if %3
    paddw      m4, m9
    pmaxsw     m4, m12
    pminsw     m4, m11
%endif
    vpdpwssd   %1, m4, m5
%endmacro

%macro WEIGHTP_SUM8_ICL 1 ; clip
%if %1
cglobal weightp_sum8_clip, 8,9,14
    vpbroadcastw m9, r7d
    mov       r7d, 255
    vpbroadcastw m11, r7d
    pxor      m12, m12
%else
cglobal weightp_sum8, 7,9,14
%endif
    vpbroadcastw m6, r5d
    xor       r7d, r7d
    bts       r7d, r6d
    shr       r7d, 1
    vpbroadcastw m7, r7d
    movd      xm8, r6d
    vpbroadcastd m5, [pw_1]
    WEIGHTP_PERM m10
.loopx:
    pxor       m0, m0
    pxor       m1, m1
    pxor       m2, m2
    pxor       m3, m3
    mov        r7, r1
    mov       r8d, r4d
.loopy:
    WEIGHTP_SUM8_ICL_ROW m0,  0, %1
    WEIGHTP_SUM8_ICL_ROW m1, 16, %1
    WEIGHTP_SUM8_ICL_ROW m2, 32, %1
    WEIGHTP_SUM8_ICL_ROW m3, 48, %1
    add        r7, r2
    dec       r8d
    jg .loopy
    HADD4D     m0, m1, m2, m3, m4, m13
    vpermd     m0, m10, m0
    movu     [r0], m0
    add        r0, 32
    add        r1, 64
    sub       r3d, 8
    jg .loopx
    RET
%endmacro

WEIGHTP_SUM8_ICL 0
WEIGHTP_SUM8_ICL 1

; avx512icl 8-bit: vpdpbusd of each row by 1,0,1,0 (u) and 0,1,0,1 (v) bytes, no unpacking.
; A ymm is two blocks, 8 a pass; u in m0-m3, v in m4-m7, then as weightp_sum8.
%macro WEIGHTP_NV_ICL_ROW 3 ; u acc, v acc, offset
    movu       m8, [r6+%3]
    vpdpbusd  m%1, m8, m10
    vpdpbusd  m%2, m8, m11
%endmacro

INIT_YMM avx512icl
cglobal weightp_sum8_nv, 6,8,13
    mov       r6d, 0x00010001
    vpbroadcastd m10, r6d
    pslld     m11, m10, 8
    WEIGHTP_PERM m9
.loopx:
    pxor       m0, m0
    pxor       m1, m1
    pxor       m2, m2
    pxor       m3, m3
    pxor       m4, m4
    pxor       m5, m5
    pxor       m6, m6
    pxor       m7, m7
    mov        r6, r2
    mov       r7d, r5d
.loopy:
    WEIGHTP_NV_ICL_ROW 0, 4, 0
    WEIGHTP_NV_ICL_ROW 1, 5, 32
    WEIGHTP_NV_ICL_ROW 2, 6, 64
    WEIGHTP_NV_ICL_ROW 3, 7, 96
    add        r6, r3
    dec       r7d
    jg .loopy
    HADD4D     m0, m1, m2, m3, m8, m12
    HADD4D     m4, m5, m6, m7, m8, m12
    vpermd     m0, m9, m0
    vpermd     m4, m9, m4
    movu     [r0], m0
    movu     [r1], m4
    add        r0, 32
    add        r1, 32
    add        r2, 128
    sub       r4d, 8
    jg .loopx
    RET
%endif
%endif ; ARCH_X86_64
