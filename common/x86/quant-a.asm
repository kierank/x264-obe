;*****************************************************************************
;* quant-a.asm: x86 quantization and level-run
;*****************************************************************************
;* Copyright (C) 2005-2014 x264 project
;*
;* Authors: Loren Merritt <lorenm@u.washington.edu>
;*          Jason Garrett-Glaser <darkshikari@gmail.com>
;*          Christian Heine <sennindemokrit@gmx.net>
;*          Oskar Arvidsson <oskar@irock.se>
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

SECTION_RODATA 64

%if HIGH_BIT_DEPTH
decimate_shuf_avx512: dd 0, 4, 8,12, 1, 5, 9,13, 2, 6,10,14, 3, 7,11,15
qscan4_frame_avx512:  dd 0, 4, 1, 2, 5, 8,12, 9, 6, 3, 7,10,13,14,11,15
qscan4_field_avx512:  dd 0, 1, 4, 2, 3, 5, 6, 7, 8, 9,10,11,12,13,14,15
levelrun_rev_avx512:  dd 15,14,13,12,11,10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0
%else
dequant_shuf_avx512: dw  0, 2, 4, 6, 8,10,12,14,16,18,20,22,24,26,28,30
                     dw 32,34,36,38,40,42,44,46,48,50,52,54,56,58,60,62
qscan4_frame_avx512: dw  0, 4, 1, 2, 5, 8,12, 9, 6, 3, 7,10,13,14,11,15
                     dw 16,20,17,18,21,24,28,25,22,19,23,26,29,30,27,31
qscan4_field_avx512: dw  0, 1, 4, 2, 3, 5, 6, 7, 8, 9,10,11,12,13,14,15
                     dw 16,17,20,18,19,21,22,23,24,25,26,27,28,29,30,31
levelrun_rev_avx512: dw 15,14,13,12,11,10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0, 4, 5, 6, 7
%endif
ALIGN 64, db 0

%macro DQM4 3
    dw %1, %2, %1, %2, %2, %3, %2, %3
%endmacro
%macro DQM8 6
    dw %1, %4, %5, %4, %1, %4, %5, %4
    dw %4, %2, %6, %2, %4, %2, %6, %2
    dw %5, %6, %3, %6, %5, %6, %3, %6
    dw %4, %2, %6, %2, %4, %2, %6, %2
%endmacro

dequant8_scale:
    DQM8 20, 18, 32, 19, 25, 24
    DQM8 22, 19, 35, 21, 28, 26
    DQM8 26, 23, 42, 24, 33, 31
    DQM8 28, 25, 45, 26, 35, 33
    DQM8 32, 28, 51, 30, 40, 38
    DQM8 36, 32, 58, 34, 46, 43

dequant4_scale:
    DQM4 10, 13, 16
    DQM4 11, 14, 18
    DQM4 13, 16, 20
    DQM4 14, 18, 23
    DQM4 16, 20, 25
    DQM4 18, 23, 29

decimate_mask_table4:
    db  0,3,2,6,2,5,5,9,1,5,4,8,5,8,8,12,1,4,4,8,4,7,7,11,4,8,7,11,8,11,11,15,1,4
    db  3,7,4,7,7,11,3,7,6,10,7,10,10,14,4,7,7,11,7,10,10,14,7,11,10,14,11,14,14
    db 18,0,4,3,7,3,6,6,10,3,7,6,10,7,10,10,14,3,6,6,10,6,9,9,13,6,10,9,13,10,13
    db 13,17,4,7,6,10,7,10,10,14,6,10,9,13,10,13,13,17,7,10,10,14,10,13,13,17,10
    db 14,13,17,14,17,17,21,0,3,3,7,3,6,6,10,2,6,5,9,6,9,9,13,3,6,6,10,6,9,9,13
    db  6,10,9,13,10,13,13,17,3,6,5,9,6,9,9,13,5,9,8,12,9,12,12,16,6,9,9,13,9,12
    db 12,16,9,13,12,16,13,16,16,20,3,7,6,10,6,9,9,13,6,10,9,13,10,13,13,17,6,9
    db  9,13,9,12,12,16,9,13,12,16,13,16,16,20,7,10,9,13,10,13,13,17,9,13,12,16
    db 13,16,16,20,10,13,13,17,13,16,16,20,13,17,16,20,17,20,20,24

chroma_dc_dct_mask_mmx: dw 0, 0,-1,-1, 0, 0,-1,-1
chroma_dc_dmf_mask_mmx: dw 0, 0,-1,-1, 0,-1,-1, 0
chroma_dc_dct_mask:     dw 1, 1,-1,-1, 1, 1,-1,-1
chroma_dc_dmf_mask:     dw 1, 1,-1,-1, 1,-1,-1, 1

ALIGN 32
%if HIGH_BIT_DEPTH
qscan4_frame_i: dd 0, 4, 1, 2, 5, 6, 3, 7
qscan4_frame_j: dd 6, 3, 7, 0, 0, 0, 4, 1
qscan4_field:   dd 0, 1, 4, 2, 3, 5, 6, 7
qscan4_bytes:   dd 0, 4, 1, 5, 2, 6, 3, 7
%else
qscan4_frame_a: SHUFFLE_MASK_W 0, 4, 1, 2, 5, 0x80, 0x80, 0x80
                SHUFFLE_MASK_W 0x80, 0x80, 0x80, 2, 5, 6, 3, 7
qscan4_frame_b: SHUFFLE_MASK_W 0x80, 0x80, 0x80, 0x80, 0x80, 0, 4, 1
                SHUFFLE_MASK_W 6, 3, 7, 0x80, 0x80, 0x80, 0x80, 0x80
qscan4_field:   SHUFFLE_MASK_W 0, 1, 4, 2, 3, 5, 6, 7
                SHUFFLE_MASK_W 0, 1, 2, 3, 4, 5, 6, 7
%endif
qscan4_acmask:  db 0, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1
                db 0, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1

%if HIGH_BIT_DEPTH==0
dct_coef_shuffle:
%macro DCT_COEF_SHUFFLE 8
    %assign y x
    %rep 8
        %rep 7
            %rotate (~(y>>7))&1
            %assign y y<<((~(y>>7))&1)
        %endrep
        db %1*2
        %rotate 1
        %assign y y<<1
    %endrep
%endmacro
%assign x 0
%rep 256
    DCT_COEF_SHUFFLE 7, 6, 5, 4, 3, 2, 1, 0
%assign x x+1
%endrep
%endif
; optimize_chroma_2x4_dc avx512icl: columns of the dc transform, rounding constants
optchroma_col2x4: dd 1, 1, 1, 1, 1, 1, 1, 1
                  dd 1,-1, 1,-1, 1,-1, 1,-1
                  dd 1, 1, 1, 1,-1,-1,-1,-1
                  dd 1,-1, 1,-1,-1, 1,-1, 1
                  dd 1, 1,-1,-1,-1,-1, 1, 1
                  dd 1,-1,-1, 1,-1, 1, 1,-1
                  dd 1, 1,-1,-1, 1, 1,-1,-1
                  dd 1,-1,-1, 1, 1,-1,-1, 1
optchroma_2080:   dd 2080
optchroma_m64:    dd -64
%if HIGH_BIT_DEPTH
; optimize_chroma_2x2_dc avx512icl
optchroma_col2x2: dd 1, 1, 1, 1,  1, 1,-1,-1,  1,-1, 1,-1,  1,-1,-1, 1
optchroma_32:     dd 32
%endif

SECTION .text

cextern pb_1
cextern pw_1
cextern pw_2
cextern pw_256
cextern pw_m2
cextern pd_1
cextern pb_01
cextern pd_1024
cextern deinterleave_shufd
cextern popcnt_table

%macro QUANT_DC_START 2
    movd      xm%1, r1m     ; mf
    movd      xm%2, r2m     ; bias
%if cpuflag(avx2)
    vpbroadcastdct m%1, xm%1
    vpbroadcastdct m%2, xm%2
%elif HIGH_BIT_DEPTH
    SPLATD     m%1, m%1
    SPLATD     m%2, m%2
%elif cpuflag(sse4) ; ssse3, but not faster on conroe
    mova       m5, [pb_01]
    pshufb     m%1, m5
    pshufb     m%2, m5
%else
    SPLATW     m%1, m%1
    SPLATW     m%2, m%2
%endif
%endmacro

%macro QUANT_END 0
    xor      eax, eax
%if cpuflag(sse4)
    ptest     m5, m5
%else ; !sse4
%if ARCH_X86_64
%if mmsize == 16
    packsswb  m5, m5
%endif
    movq     rcx, m5
    test     rcx, rcx
%else
%if mmsize == 16
    pxor      m4, m4
    pcmpeqb   m5, m4
    pmovmskb ecx, m5
    cmp      ecx, (1<<mmsize)-1
%else
    packsswb  m5, m5
    movd     ecx, m5
    test     ecx, ecx
%endif
%endif
%endif ; cpuflag
    setne     al
%endmacro

%if HIGH_BIT_DEPTH
%macro QUANT_ONE_DC 4
%if cpuflag(sse4)
    mova        m0, [%1]
    ABSD        m1, m0
    paddd       m1, %3
    pmulld      m1, %2
    psrld       m1, 16
%else ; !sse4
    mova        m0, [%1]
    ABSD        m1, m0
    paddd       m1, %3
    mova        m2, m1
    psrlq       m2, 32
    pmuludq     m1, %2
    pmuludq     m2, %2
    psllq       m2, 32
    paddd       m1, m2
    psrld       m1, 16
%endif ; cpuflag
    PSIGND      m1, m0
    mova      [%1], m1
    ACCUM     por, 5, 1, %4
%endmacro

%macro QUANT_TWO_DC 4
%if cpuflag(sse4)
    mova        m0, [%1       ]
    mova        m1, [%1+mmsize]
    ABSD        m2, m0
    ABSD        m3, m1
    paddd       m2, %3
    paddd       m3, %3
    pmulld      m2, %2
    pmulld      m3, %2
    psrld       m2, 16
    psrld       m3, 16
    PSIGND      m2, m0
    PSIGND      m3, m1
    mova [%1       ], m2
    mova [%1+mmsize], m3
    ACCUM      por, 5, 2, %4
    por         m5, m3
%else ; !sse4
    QUANT_ONE_DC %1, %2, %3, %4
    QUANT_ONE_DC %1+mmsize, %2, %3, %4+mmsize
%endif ; cpuflag
%endmacro

%macro QUANT_ONE_AC_MMX 5
    mova        m0, [%1]
    mova        m2, [%2]
    ABSD        m1, m0
    mova        m4, m2
    paddd       m1, [%3]
    mova        m3, m1
    psrlq       m4, 32
    psrlq       m3, 32
    pmuludq     m1, m2
    pmuludq     m3, m4
    psllq       m3, 32
    paddd       m1, m3
    psrld       m1, 16
    PSIGND      m1, m0
    mova      [%1], m1
    ACCUM      por, %5, 1, %4
%endmacro

%macro QUANT_TWO_AC 5
%if cpuflag(sse4)
    mova        m0, [%1       ]
    mova        m1, [%1+mmsize]
    ABSD        m2, m0
    ABSD        m3, m1
    paddd       m2, [%3       ]
    paddd       m3, [%3+mmsize]
    pmulld      m2, [%2       ]
    pmulld      m3, [%2+mmsize]
    psrld       m2, 16
    psrld       m3, 16
    PSIGND      m2, m0
    PSIGND      m3, m1
    mova [%1       ], m2
    mova [%1+mmsize], m3
    ACCUM      por, %5, 2, %4
    por        m%5, m3
%else ; !sse4
    QUANT_ONE_AC_MMX %1, %2, %3, %4, %5
    QUANT_ONE_AC_MMX %1+mmsize, %2+mmsize, %3+mmsize, 1, %5
%endif ; cpuflag
%endmacro

;-----------------------------------------------------------------------------
; int quant_2x2( int32_t dct[M*N], int mf, int bias )
;-----------------------------------------------------------------------------
%macro QUANT_DC 2
cglobal quant_%1x%2_dc, 3,3,8
    QUANT_DC_START 6,7
%if %1*%2 <= mmsize/4
    QUANT_ONE_DC r0, m6, m7, 0
%else
%assign x 0
%rep %1*%2/(mmsize/2)
    QUANT_TWO_DC r0+x, m6, m7, x
%assign x x+mmsize*2
%endrep
%endif
    QUANT_END
    RET
%endmacro

;-----------------------------------------------------------------------------
; int quant_MxN( int32_t dct[M*N], uint32_t mf[M*N], uint32_t bias[M*N] )
;-----------------------------------------------------------------------------
%macro QUANT_AC 2
cglobal quant_%1x%2, 3,3,8
%assign x 0
%rep %1*%2/(mmsize/2)
    QUANT_TWO_AC r0+x, r1+x, r2+x, x, 5
%assign x x+mmsize*2
%endrep
    QUANT_END
    RET
%endmacro

%macro QUANT_4x4 2
    QUANT_TWO_AC r0+%1+mmsize*0, r1+mmsize*0, r2+mmsize*0, 0, %2
    QUANT_TWO_AC r0+%1+mmsize*2, r1+mmsize*2, r2+mmsize*2, 1, %2
%endmacro

%macro QUANT_4x4x4 0
cglobal quant_4x4x4, 3,3,8
    QUANT_4x4  0, 5
    QUANT_4x4 64, 6
    add       r0, 128
    packssdw  m5, m6
    QUANT_4x4  0, 6
    QUANT_4x4 64, 7
    packssdw  m6, m7
    packssdw  m5, m6
    packssdw  m5, m5  ; AA BB CC DD
    packsswb  m5, m5  ; A B C D
    pxor      m4, m4
    pcmpeqb   m5, m4
    pmovmskb eax, m5
    not      eax
    and      eax, 0xf
    RET
%endmacro

INIT_XMM sse2
QUANT_DC 2, 2
QUANT_DC 4, 4
QUANT_AC 4, 4
QUANT_AC 8, 8
QUANT_4x4x4

INIT_XMM ssse3
QUANT_DC 2, 2
QUANT_DC 4, 4
QUANT_AC 4, 4
QUANT_AC 8, 8
QUANT_4x4x4

INIT_XMM sse4
QUANT_DC 2, 2
QUANT_DC 4, 4
QUANT_AC 4, 4
QUANT_AC 8, 8
QUANT_4x4x4

INIT_YMM avx2
QUANT_DC 4, 4
QUANT_AC 4, 4
QUANT_AC 8, 8

; dct, mf (2x), bias (2x), accumulator
%macro QUANT_TWO_AC_AVX2 6
    mova        m0, [%1   ]
    mova        m1, [%1+32]
    ABSD        m2, m0
    ABSD        m3, m1
    paddd       m2, %4
    paddd       m3, %5
    pmulld      m2, %2
    pmulld      m3, %3
    psrad       m2, 16
    psrad       m3, 16
    PSIGND      m2, m0
    PSIGND      m3, m1
    mova [%1   ], m2
    mova [%1+32], m3
    ACCUM      por, %6, 2, 0
    por        m%6, m3
%endmacro

INIT_YMM avx2
%if ARCH_X86_64
cglobal quant_4x4x4, 3,3,10
    mova      m6, [r1]
    mova      m7, [r1+32]
    mova      m8, [r2]
    mova      m9, [r2+32]
    %define quant444_mf0   m6
    %define quant444_mf1   m7
    %define quant444_bias0 m8
    %define quant444_bias1 m9
%else
cglobal quant_4x4x4, 3,3,6
    %define quant444_mf0   [r1]
    %define quant444_mf1   [r1+32]
    %define quant444_bias0 [r2]
    %define quant444_bias1 [r2+32]
%endif
    QUANT_TWO_AC_AVX2 r0,    quant444_mf0, quant444_mf1, quant444_bias0, quant444_bias1, 4
    QUANT_TWO_AC_AVX2 r0+64, quant444_mf0, quant444_mf1, quant444_bias0, quant444_bias1, 5
    add       r0, 128
    packssdw  m4, m5
    QUANT_TWO_AC_AVX2 r0,    quant444_mf0, quant444_mf1, quant444_bias0, quant444_bias1, 5
    QUANT_TWO_AC_AVX2 r0+64, quant444_mf0, quant444_mf1, quant444_bias0, quant444_bias1, 1
    %undef quant444_mf0
    %undef quant444_mf1
    %undef quant444_bias0
    %undef quant444_bias1
    packssdw  m5, m1
    packssdw  m4, m5
    pxor      m3, m3
    pcmpeqd   m4, m3
    movmskps eax, m4
    mov      edx, eax
    shr      eax, 4
    and      eax, edx
    xor      eax, 0xf
    RET

%endif ; HIGH_BIT_DEPTH

%if HIGH_BIT_DEPTH == 0
%macro QUANT_ONE 5
;;; %1      (m64)       dct[y][x]
;;; %2      (m64/mmx)   mf[y][x] or mf[0][0] (as uint16_t)
;;; %3      (m64/mmx)   bias[y][x] or bias[0][0] (as uint16_t)
    mova       m1, %1   ; load dct coeffs
    ABSW       m0, m1, sign
    paddusw    m0, %3   ; round
    pmulhuw    m0, %2   ; divide
    PSIGNW     m0, m1   ; restore sign
    mova       %1, m0   ; store
    ACCUM     por, %5, 0, %4
%endmacro

%macro QUANT_TWO 8
    mova       m1, %1
    mova       m3, %2
    ABSW       m0, m1, sign
    ABSW       m2, m3, sign
    paddusw    m0, %5
    paddusw    m2, %6
    pmulhuw    m0, %3
    pmulhuw    m2, %4
    PSIGNW     m0, m1
    PSIGNW     m2, m3
    mova       %1, m0
    mova       %2, m2
    ACCUM     por, %8, 0, %7
    ACCUM     por, %8, 2, %7+mmsize
%endmacro

;-----------------------------------------------------------------------------
; void quant_4x4_dc( int16_t dct[16], int mf, int bias )
;-----------------------------------------------------------------------------
%macro QUANT_DC 2-3 0
cglobal %1, 1,1,%3
%if %2==1
    QUANT_DC_START 2,3
    QUANT_ONE [r0], m2, m3, 0, 5
%else
    QUANT_DC_START 4,6
%assign x 0
%rep %2/2
    QUANT_TWO [r0+x], [r0+x+mmsize], m4, m4, m6, m6, x, 5
%assign x x+mmsize*2
%endrep
%endif
    QUANT_END
    RET
%endmacro

;-----------------------------------------------------------------------------
; int quant_4x4( int16_t dct[16], uint16_t mf[16], uint16_t bias[16] )
;-----------------------------------------------------------------------------
%macro QUANT_AC 2
cglobal %1, 3,3
%if %2==1
    QUANT_ONE [r0], [r1], [r2], 0, 5
%else
%assign x 0
%rep %2/2
    QUANT_TWO [r0+x], [r0+x+mmsize], [r1+x], [r1+x+mmsize], [r2+x], [r2+x+mmsize], x, 5
%assign x x+mmsize*2
%endrep
%endif
    QUANT_END
    RET
%endmacro

%macro QUANT_4x4 2
%if UNIX64
    QUANT_TWO [r0+%1+mmsize*0], [r0+%1+mmsize*1], m8, m9, m10, m11, mmsize*0, %2
%else
    QUANT_TWO [r0+%1+mmsize*0], [r0+%1+mmsize*1], [r1+mmsize*0], [r1+mmsize*1], [r2+mmsize*0], [r2+mmsize*1], mmsize*0, %2
%if mmsize==8
    QUANT_TWO [r0+%1+mmsize*2], [r0+%1+mmsize*3], [r1+mmsize*2], [r1+mmsize*3], [r2+mmsize*2], [r2+mmsize*3], mmsize*2, %2
%endif
%endif
%endmacro

%macro QUANT_4x4x4 0
cglobal quant_4x4x4, 3,3,7
%if UNIX64
    mova      m8, [r1+mmsize*0]
    mova      m9, [r1+mmsize*1]
    mova     m10, [r2+mmsize*0]
    mova     m11, [r2+mmsize*1]
%endif
    QUANT_4x4  0, 4
    QUANT_4x4 32, 5
    packssdw  m4, m5
    QUANT_4x4 64, 5
    QUANT_4x4 96, 6
    packssdw  m5, m6
    packssdw  m4, m5
%if mmsize == 16
    packssdw  m4, m4  ; AA BB CC DD
%endif
    packsswb  m4, m4  ; A B C D
    pxor      m3, m3
    pcmpeqb   m4, m3
    pmovmskb eax, m4
    not      eax
    and      eax, 0xf
    RET
%endmacro

INIT_MMX mmx2
QUANT_DC quant_2x2_dc, 1
%if ARCH_X86_64 == 0 ; not needed because sse2 is faster
QUANT_DC quant_4x4_dc, 4
INIT_MMX mmx
QUANT_AC quant_4x4, 4
QUANT_AC quant_8x8, 16
QUANT_4x4x4
%endif

INIT_XMM sse2
QUANT_DC quant_4x4_dc, 2, 7
QUANT_AC quant_4x4, 2
QUANT_AC quant_8x8, 8
QUANT_4x4x4

INIT_XMM ssse3
QUANT_DC quant_4x4_dc, 2, 7
QUANT_AC quant_4x4, 2
QUANT_AC quant_8x8, 8
QUANT_4x4x4

INIT_MMX ssse3
QUANT_DC quant_2x2_dc, 1

INIT_XMM sse4
;Not faster on Conroe, so only used in SSE4 versions
QUANT_DC quant_4x4_dc, 2, 7
QUANT_AC quant_4x4, 2
QUANT_AC quant_8x8, 8

INIT_YMM avx2
QUANT_AC quant_4x4, 1
QUANT_AC quant_8x8, 4
QUANT_DC quant_4x4_dc, 1, 6

INIT_YMM avx2
cglobal quant_4x4x4, 3,3,6
    mova      m2, [r1]
    mova      m3, [r2]
    QUANT_ONE [r0+ 0], m2, m3, 0, 4
    QUANT_ONE [r0+32], m2, m3, 0, 5
    packssdw  m4, m5
    QUANT_ONE [r0+64], m2, m3, 0, 5
    QUANT_ONE [r0+96], m2, m3, 0, 1
    packssdw  m5, m1
    packssdw  m4, m5
    pxor      m3, m3
    pcmpeqd   m4, m3
    movmskps eax, m4
    mov      edx, eax
    shr      eax, 4
    and      eax, edx
    xor      eax, 0xf
    RET
%endif ; !HIGH_BIT_DEPTH

%if ARCH_X86_64
; k1: nonzero coefs, 16 bits per block -> r6 (eax): nonzero blocks, k2: store mask of the nonzero blocks
%macro QUANT_SCAN_NZ_AVX512 0
    kmovq     r6, k1
    mov       r7, 0x7fff7fff7fff7fff
    mov       r8, r6
    and       r8, r7
    add       r8, r7
    or        r8, r6
    not       r7
    and       r8, r7          ; bit 15 of each block: block is nonzero
    pext      r6, r8, r7
    shr       r8, 15
    imul      r8, r8, 0xffff
    kmovq     k2, r8
%endmacro

; dst, src, mf, bias; m7: 0
%macro QUANT_ONE_AVX512 4
%if HIGH_BIT_DEPTH
    pabsd     %1, %2
    paddd     %1, %4
    pmulld    %1, %3
    psrld     %1, 16
    vpmovd2m  k1, %2
    vpsubd    %1{k1}, m7, %1
%else
    pabsw     %1, %2
    paddusw   %1, %4
    pmulhuw   %1, %3
    vpmovw2m  k1, %2
    vpsubw    %1{k1}, m7, %1
%endif
%endmacro

INIT_ZMM avx512icl
cglobal quant_8x8, 3,3,8
    pxor     xm7, xm7
%assign qi 0
%rep SIZEOF_DCTCOEF
    movu      m0, [r0+qi]
    QUANT_ONE_AVX512 m1, m0, [r1+qi], [r2+qi]
    movu [r0+qi], m1
%if qi
    por       m6, m1
%else
    mova      m6, m1
%endif
%assign qi qi+64
%endrep
%undef qi
    vptestmd  k1, m6, m6
    xor      eax, eax
    kortestw  k1, k1
    setnz     al
    RET

cglobal quant_4x4x4, 3,9,8
    pxor     xm7, xm7
%if HIGH_BIT_DEPTH
    movu      m2, [r1]
    movu      m3, [r2]
    movu      m0, [r0+  0]
    QUANT_ONE_AVX512 m4, m0, m2, m3
    movu      m0, [r0+ 64]
    QUANT_ONE_AVX512 m5, m0, m2, m3
    movu [r0+  0], m4
    movu [r0+ 64], m5
    vptestmd  k3, m4, m4
    vptestmd  k4, m5, m5
    movu      m0, [r0+128]
    QUANT_ONE_AVX512 m4, m0, m2, m3
    movu      m0, [r0+192]
    QUANT_ONE_AVX512 m5, m0, m2, m3
    movu [r0+128], m4
    movu [r0+192], m5
    vptestmd  k5, m4, m4
    vptestmd  k6, m5, m5
    kunpckwd  k3, k4, k3
    kunpckwd  k5, k6, k5
    kunpckdq  k1, k5, k3
%else
    vbroadcasti32x8 m2, [r1]
    vbroadcasti32x8 m3, [r2]
    movu      m0, [r0+ 0]
    QUANT_ONE_AVX512 m4, m0, m2, m3
    movu      m0, [r0+64]
    QUANT_ONE_AVX512 m5, m0, m2, m3
    movu [r0+ 0], m4
    movu [r0+64], m5
    vptestmw  k3, m4, m4
    vptestmw  k4, m5, m5
    kunpckdq  k1, k4, k3
%endif
    QUANT_SCAN_NZ_AVX512
    RET

%if HIGH_BIT_DEPTH
cglobal quant_4x4, 3,3,8
    pxor     xm7, xm7
    movu      m0, [r0]
    QUANT_ONE_AVX512 m1, m0, [r1], [r2]
    movu    [r0], m1
    vptestmd  k1, m1, m1
    xor      eax, eax
    kortestw  k1, k1
    setnz     al
    RET

cglobal quant_4x4_dc, 3,3,8
    pxor     xm7, xm7
    vpbroadcastd m2, r1d
    vpbroadcastd m3, r2d
    movu      m0, [r0]
    QUANT_ONE_AVX512 m1, m0, m2, m3
    movu    [r0], m1
    vptestmd  k1, m1, m1
    xor      eax, eax
    kortestw  k1, k1
    setnz     al
    RET
%endif
%endif ; ARCH_X86_64

;-----------------------------------------------------------------------------
; int quant_2x2_dc( dctcoef dct[4], int mf, int bias )
;-----------------------------------------------------------------------------
INIT_XMM avx512icl
cglobal quant_2x2_dc, 3,3
%if HIGH_BIT_DEPTH
    movu          m0, [r0]
    vpbroadcastd  m2, r1d
    vpbroadcastd  m3, r2d
    pabsd         m1, m0
    paddd         m1, m3
    pmulld        m1, m2
    psrld         m1, 16
    vpmovd2m      k1, m0
    pxor          m2, m2
    vpsubd        m1 {k1}, m2, m1
    movu        [r0], m1
    vptestmd      k1, m1, m1
%else
    movq          m0, [r0]
    vpbroadcastw  m2, r1d
    vpbroadcastw  m3, r2d
    pabsw         m1, m0
    paddusw       m1, m3
    pmulhuw       m1, m2
    vpmovw2m      k1, m0
    pxor          m2, m2
    vpsubw        m1 {k1}, m2, m1
    movq        [r0], m1
    vptestmw      k1, m1, m1
%endif
    xor          eax, eax
    ktestb        k1, k1
    setnz         al
    RET

;=============================================================================
; dequant
;=============================================================================

%macro DEQUANT16_L 4
;;; %1      dct[y][x]
;;; %2,%3   dequant_mf[i_mf][y][x]
;;; m2      i_qbits
%if HIGH_BIT_DEPTH
    mova     m0, %1
    mova     m1, %4
    pmaddwd  m0, %2
    pmaddwd  m1, %3
    pslld    m0, xm2
    pslld    m1, xm2
    mova     %1, m0
    mova     %4, m1
%else
    mova     m0, %2
    packssdw m0, %3
%if mmsize==32
    vpermq   m0, m0, q3120
%endif
    pmullw   m0, %1
    psllw    m0, xm2
    mova     %1, m0
%endif
%endmacro

%macro DEQUANT32_R 4
;;; %1      dct[y][x]
;;; %2,%3   dequant_mf[i_mf][y][x]
;;; m2      -i_qbits
;;; m3      f
;;; m4      0
%if HIGH_BIT_DEPTH
    mova      m0, %1
    mova      m1, %4
    pmadcswd  m0, m0, %2, m3
    pmadcswd  m1, m1, %3, m3
    psrad     m0, xm2
    psrad     m1, xm2
    mova      %1, m0
    mova      %4, m1
%else
%if mmsize == 32
    pmovzxwd  m0, %1
    pmovzxwd  m1, %4
%else
    mova      m0, %1
    punpckhwd m1, m0, m4
    punpcklwd m0, m4
%endif
    pmadcswd  m0, m0, %2, m3
    pmadcswd  m1, m1, %3, m3
    psrad     m0, xm2
    psrad     m1, xm2
    packssdw  m0, m1
%if mmsize == 32
    vpermq    m0, m0, q3120
%endif
    mova      %1, m0
%endif
%endmacro

%macro DEQUANT_LOOP 3
%if 8*(%2-2*%3) > 0
    mov t0d, 8*(%2-2*%3)
%%loop:
    %1 [r0+(t0     )*SIZEOF_PIXEL], [r1+t0*2      ], [r1+t0*2+ 8*%3], [r0+(t0+ 4*%3)*SIZEOF_PIXEL]
    %1 [r0+(t0+8*%3)*SIZEOF_PIXEL], [r1+t0*2+16*%3], [r1+t0*2+24*%3], [r0+(t0+12*%3)*SIZEOF_PIXEL]
    sub t0d, 16*%3
    jge %%loop
    RET
%else
%if mmsize < 32
    %1 [r0+(8*%3)*SIZEOF_PIXEL], [r1+16*%3], [r1+24*%3], [r0+(12*%3)*SIZEOF_PIXEL]
%endif
    %1 [r0+(0   )*SIZEOF_PIXEL], [r1+0    ], [r1+ 8*%3], [r0+( 4*%3)*SIZEOF_PIXEL]
    RET
%endif
%endmacro

%macro DEQUANT16_FLAT 2-5
    mova   m0, %1
    psllw  m0, m4
%assign i %0-2
%rep %0-1
%if i
    mova   m %+ i, [r0+%2]
    pmullw m %+ i, m0
%else
    pmullw m0, [r0+%2]
%endif
    mova   [r0+%2], m %+ i
    %assign i i-1
    %rotate 1
%endrep
%endmacro

%if ARCH_X86_64
    DECLARE_REG_TMP 6,3,2
%else
    DECLARE_REG_TMP 2,0,1
%endif

%macro DEQUANT_START 2
    movifnidn t2d, r2m
    imul t0d, t2d, 0x2b
    shr  t0d, 8     ; i_qbits = i_qp / 6
    lea  t1d, [t0*5]
    sub  t2d, t0d
    sub  t2d, t1d   ; i_mf = i_qp % 6
    shl  t2d, %1
%if ARCH_X86_64
    add  r1, t2     ; dequant_mf[i_mf]
%else
    add  r1, r1mp   ; dequant_mf[i_mf]
    mov  r0, r0mp   ; dct
%endif
    sub  t0d, %2
    jl   .rshift32  ; negative qbits => rightshift
%endmacro

;-----------------------------------------------------------------------------
; void dequant_4x4( dctcoef dct[4][4], int dequant_mf[6][4][4], int i_qp )
;-----------------------------------------------------------------------------
%macro DEQUANT 3
cglobal dequant_%1x%1, 0,3,6
.skip_prologue:
    DEQUANT_START %2+2, %2

.lshift:
    movd xm2, t0d
    DEQUANT_LOOP DEQUANT16_L, %1*%1/4, %3

.rshift32:
    neg   t0d
    mova  m3, [pd_1]
    movd xm2, t0d
    pslld m3, xm2
    pxor  m4, m4
    psrld m3, 1
    DEQUANT_LOOP DEQUANT32_R, %1*%1/4, %3

%if HIGH_BIT_DEPTH == 0 && (notcpuflag(avx) || mmsize == 32)
cglobal dequant_%1x%1_flat16, 0,3
    movifnidn t2d, r2m
%if %1 == 8
    cmp  t2d, 12
    jl dequant_%1x%1 %+ SUFFIX %+ .skip_prologue
    sub  t2d, 12
%endif
    imul t0d, t2d, 0x2b
    shr  t0d, 8     ; i_qbits = i_qp / 6
    lea  t1d, [t0*5]
    sub  t2d, t0d
    sub  t2d, t1d   ; i_mf = i_qp % 6
    shl  t2d, %2
%ifdef PIC
    lea  r1, [dequant%1_scale]
    add  r1, t2
%else
    lea  r1, [dequant%1_scale + t2]
%endif
    movifnidn r0, r0mp
    movd xm4, t0d
%if %1 == 4
%if mmsize == 8
    DEQUANT16_FLAT [r1], 0, 16
    DEQUANT16_FLAT [r1+8], 8, 24
%elif mmsize == 16
    DEQUANT16_FLAT [r1], 0, 16
%else
    vbroadcasti128 m0, [r1]
    psllw  m0, xm4
    pmullw m0, [r0]
    mova [r0], m0
%endif
%elif mmsize == 8
    DEQUANT16_FLAT [r1], 0, 8, 64, 72
    DEQUANT16_FLAT [r1+16], 16, 24, 48, 56
    DEQUANT16_FLAT [r1+16], 80, 88, 112, 120
    DEQUANT16_FLAT [r1+32], 32, 40, 96, 104
%elif mmsize == 16
    DEQUANT16_FLAT [r1], 0, 64
    DEQUANT16_FLAT [r1+16], 16, 48, 80, 112
    DEQUANT16_FLAT [r1+32], 32, 96
%else
    mova   m1, [r1+ 0]
    mova   m2, [r1+32]
    psllw  m1, xm4
    psllw  m2, xm4
    pmullw m0, m1, [r0+ 0]
    pmullw m3, m2, [r0+32]
    pmullw m4, m1, [r0+64]
    pmullw m5, m2, [r0+96]
    mova [r0+ 0], m0
    mova [r0+32], m3
    mova [r0+64], m4
    mova [r0+96], m5
%endif
    RET
%endif ; !HIGH_BIT_DEPTH && !AVX
%endmacro ; DEQUANT

%if HIGH_BIT_DEPTH
INIT_XMM sse2
DEQUANT 4, 4, 2
DEQUANT 8, 6, 2
INIT_XMM xop
DEQUANT 4, 4, 2
DEQUANT 8, 6, 2
INIT_YMM avx2
DEQUANT 4, 4, 4
DEQUANT 8, 6, 4
%else
%if ARCH_X86_64 == 0
INIT_MMX mmx
DEQUANT 4, 4, 1
DEQUANT 8, 6, 1
%endif
INIT_XMM sse2
DEQUANT 4, 4, 2
DEQUANT 8, 6, 2
INIT_XMM avx
DEQUANT 4, 4, 2
DEQUANT 8, 6, 2
INIT_XMM xop
DEQUANT 4, 4, 2
DEQUANT 8, 6, 2
INIT_YMM avx2
DEQUANT 4, 4, 4
DEQUANT 8, 6, 4
%endif

%macro DEQUANT_START_AVX512 1-2 0 ; shift, flat
%if %2 == 0
    movifnidn t2d, r2m
%endif
    imul t0d, t2d, 0x2b
    shr  t0d, 8     ; i_qbits = i_qp / 6
    lea  t1d, [t0*5]
    sub  t2d, t0d
    sub  t2d, t1d   ; i_mf = i_qp % 6
    shl  t2d, %1
%if %2
%ifdef PIC
%define dmf r1+t2
    lea   r1, [dequant8_scale]
%else
%define dmf t2+dequant8_scale
%endif
%elif ARCH_X86_64
%define dmf r1+t2
%else
%define dmf r1
    add  r1, r1mp   ; dequant_mf[i_mf]
%endif
    movifnidn r0, r0mp
%endmacro

INIT_ZMM avx512
cglobal dequant_4x4, 0,3
    DEQUANT_START_AVX512 6
    mova          m0, [dmf]
%if HIGH_BIT_DEPTH
    pmaddwd       m0, [r0]
%endif
    sub          t0d, 4
    jl .rshift
%if HIGH_BIT_DEPTH
    vpbroadcastd  m1, t0d
    vpsllvd       m0, m1
    mova        [r0], m0
%else
    vpbroadcastw ym1, t0d
    vpmovsdw     ym0, m0
    pmullw       ym0, [r0]
    vpsllvw      ym0, ym1
    mova        [r0], ym0
%endif
    RET
.rshift:
%if HIGH_BIT_DEPTH == 0
    pmovzxwd      m1, [r0]
    pmaddwd       m0, m1
%endif
    mov          r1d, 1<<31
    shrx         r1d, r1d, t0d ; 1 << (-i_qbits-1)
    neg          t0d
    vpbroadcastd  m1, r1d
    vpbroadcastd  m2, t0d
    paddd         m0, m1
    vpsravd       m0, m2
%if HIGH_BIT_DEPTH
    mova        [r0], m0
%else
    vpmovsdw    [r0], m0
%endif
    RET

cglobal dequant_8x8, 0,3
    DEQUANT_START_AVX512 8
    mova          m0, [dmf+0*64]
    mova          m1, [dmf+1*64]
    mova          m2, [dmf+2*64]
    mova          m3, [dmf+3*64]
%if HIGH_BIT_DEPTH
    pmaddwd       m0, [r0+0*64]
    pmaddwd       m1, [r0+1*64]
    pmaddwd       m2, [r0+2*64]
    pmaddwd       m3, [r0+3*64]
%else
    mova          m6, [dequant_shuf_avx512]
%endif
    sub          t0d, 6
    jl .rshift
%if HIGH_BIT_DEPTH
    vpbroadcastd  m4, t0d
    vpsllvd       m0, m4
    vpsllvd       m1, m4
    vpsllvd       m2, m4
    vpsllvd       m3, m4
    jmp .end
.rshift:
%else
    vpbroadcastw  m4, t0d
    vpermt2w      m0, m6, m1
    vpermt2w      m2, m6, m3
    pmullw        m0, [r0]
    pmullw        m2, [r0+64]
    vpsllvw       m0, m4
    vpsllvw       m2, m4
    mova        [r0], m0
    mova     [r0+64], m2
    RET
.rshift:
    pmovzxwd      m4, [r0+0*32]
    pmovzxwd      m5, [r0+1*32]
    pmaddwd       m0, m4
    pmaddwd       m1, m5
    pmovzxwd      m4, [r0+2*32]
    pmovzxwd      m5, [r0+3*32]
    pmaddwd       m2, m4
    pmaddwd       m3, m5
%endif
    mov          r1d, 1<<31
    shrx         r1d, r1d, t0d ; 1 << (-i_qbits-1)
    neg          t0d
    vpbroadcastd  m4, r1d
    vpbroadcastd  m5, t0d
    paddd         m0, m4
    paddd         m1, m4
    vpsravd       m0, m5
    vpsravd       m1, m5
    paddd         m2, m4
    paddd         m3, m4
    vpsravd       m2, m5
    vpsravd       m3, m5
%if HIGH_BIT_DEPTH
.end:
    mova   [r0+0*64], m0
    mova   [r0+1*64], m1
    mova   [r0+2*64], m2
    mova   [r0+3*64], m3
%else
    vpermt2w      m0, m6, m1
    vpermt2w      m2, m6, m3
    mova        [r0], m0
    mova     [r0+64], m2
%endif
    RET

%if HIGH_BIT_DEPTH == 0
cglobal dequant_8x8_flat16, 0,3
    movifnidn    t2d, r2m
    cmp          t2d, 12
    jl dequant_8x8_avx512
    sub          t2d, 12
    DEQUANT_START_AVX512 6, 1
    vpbroadcastw  m0, t0d
    mova          m1, [dmf]
    vpsllvw       m1, m0
    pmullw        m0, m1, [r0]
    pmullw        m1, [r0+64]
    mova        [r0], m0
    mova     [r0+64], m1
    RET
%endif

%if HIGH_BIT_DEPTH
; avx512icl: the right shift path adds the rounding inside VNNI vpdpwssd
; (the accumulator starts at f)
INIT_ZMM avx512icl
cglobal dequant_4x4, 0,3
    DEQUANT_START_AVX512 6
    mova          m0, [dmf]
    sub          t0d, 4
    jl .rshift
    pmaddwd       m0, [r0]
    vpbroadcastd  m1, t0d
    vpsllvd       m0, m1
    mova        [r0], m0
    RET
.rshift:
    mov          r1d, 1<<31
    shrx         r1d, r1d, t0d ; 1 << (-i_qbits-1)
    neg          t0d
    vpbroadcastd  m1, r1d
    vpbroadcastd  m2, t0d
    vpdpwssd      m1, m0, [r0]
    vpsravd       m1, m2
    mova        [r0], m1
    RET
%endif ; HIGH_BIT_DEPTH

%if HIGH_BIT_DEPTH == 0 && ARCH_X86_64
; avx512icl: the right shift path adds the rounding inside VNNI vpdpwssd,
; one accumulator per vector
INIT_ZMM avx512icl
cglobal dequant_8x8, 0,3,12
    DEQUANT_START_AVX512 8
    mova          m0, [dmf+0*64]
    mova          m1, [dmf+1*64]
    mova          m2, [dmf+2*64]
    mova          m3, [dmf+3*64]
    mova          m6, [dequant_shuf_avx512]
    sub          t0d, 6
    jl .rshift
    vpbroadcastw  m4, t0d
    vpermt2w      m0, m6, m1
    vpermt2w      m2, m6, m3
    pmullw        m0, [r0]
    pmullw        m2, [r0+64]
    vpsllvw       m0, m4
    vpsllvw       m2, m4
    mova        [r0], m0
    mova     [r0+64], m2
    RET
.rshift:
    mov          r1d, 1<<31
    shrx         r1d, r1d, t0d ; 1 << (-i_qbits-1)
    neg          t0d
    vpbroadcastd  m4, r1d
    vpbroadcastd  m5, t0d
    mova          m7, m4
    mova          m8, m4
    mova          m9, m4
    pmovzxwd     m10, [r0+0*32]
    pmovzxwd     m11, [r0+1*32]
    vpdpwssd      m4, m0, m10
    vpdpwssd      m7, m1, m11
    pmovzxwd     m10, [r0+2*32]
    pmovzxwd     m11, [r0+3*32]
    vpdpwssd      m8, m2, m10
    vpdpwssd      m9, m3, m11
    vpsravd       m4, m5
    vpsravd       m7, m5
    vpsravd       m8, m5
    vpsravd       m9, m5
    vpermt2w      m4, m6, m7
    vpermt2w      m8, m6, m9
    mova        [r0], m4
    mova     [r0+64], m8
    RET
%endif ; !HIGH_BIT_DEPTH && ARCH_X86_64

%undef dmf

%macro DEQUANT_DC 2
cglobal dequant_4x4dc, 0,3,6
    DEQUANT_START 6, 6

.lshift:
%if cpuflag(avx2)
    vpbroadcastdct m3, [r1]
%else
    movd    xm3, [r1]
    SPLAT%1  m3, xm3
%endif
    movd    xm2, t0d
%if HIGH_BIT_DEPTH
%assign %%x 0
%rep SIZEOF_PIXEL*32/mmsize
    %2       m0, m3, [r0+%%x]   ; dmf < 2^15 before the shift, not after
    pslld    m0, xm2
    mova     [r0+%%x], m0
%assign %%x %%x+mmsize
%endrep
%else
    pslld    m3, xm2
%assign %%x 0
%rep SIZEOF_PIXEL*32/mmsize
    %2       m0, m3, [r0+%%x]
    mova     [r0+%%x], m0
%assign %%x %%x+mmsize
%endrep
%endif
    RET

.rshift32:
    neg      t0d
%if cpuflag(avx2)
    vpbroadcastdct m2, [r1]
%else
    movd     xm2, [r1]
%endif
    mova      m5, [p%1_1]
    movd     xm3, t0d
    pslld     m4, m5, xm3
    psrld     m4, 1
%if HIGH_BIT_DEPTH
%if notcpuflag(avx2)
    pshufd    m2, m2, 0
%endif
%assign %%x 0
%rep SIZEOF_PIXEL*32/mmsize
    pmadcswd  m0, m2, [r0+%%x], m4
    psrad     m0, xm3
    mova      [r0+%%x], m0
%assign %%x %%x+mmsize
%endrep

%else ; !HIGH_BIT_DEPTH
%if notcpuflag(avx2)
    PSHUFLW   m2, m2, 0
%endif
    punpcklwd m2, m4
%assign %%x 0
%rep SIZEOF_PIXEL*32/mmsize
    mova      m0, [r0+%%x]
    punpckhwd m1, m0, m5
    punpcklwd m0, m5
    pmaddwd   m0, m2
    pmaddwd   m1, m2
    psrad     m0, xm3
    psrad     m1, xm3
    packssdw  m0, m1
    mova      [r0+%%x], m0
%assign %%x %%x+mmsize
%endrep
%endif ; !HIGH_BIT_DEPTH
    RET
%endmacro

%if HIGH_BIT_DEPTH
INIT_XMM sse2
DEQUANT_DC d, pmaddwd
INIT_XMM xop
DEQUANT_DC d, pmaddwd
INIT_YMM avx2
DEQUANT_DC d, pmaddwd

; avx512icl: the 16 coefficients in one zmm; the right shift adds the
; rounding inside vpdpwssd
INIT_ZMM avx512icl
cglobal dequant_4x4dc, 0,3
    DEQUANT_START 6, 6
.lshift:
    vpbroadcastd m3, [r1]
    pmaddwd      m0, m3, [r0]
    movd        xm2, t0d
    pslld        m0, xm2
    mova       [r0], m0
    RET
.rshift32:
    neg         t0d
    mov         t1d, 1
    shlx        t1d, t1d, t0d
    shr         t1d, 1
    vpbroadcastd m0, t1d
    vpbroadcastd m2, [r1]
    vpdpwssd     m0, m2, [r0]
    movd        xm3, t0d
    psrad        m0, xm3
    mova       [r0], m0
    RET
%else
%if ARCH_X86_64 == 0
INIT_MMX mmx2
DEQUANT_DC w, pmullw
%endif
INIT_XMM sse2
DEQUANT_DC w, pmullw
INIT_XMM avx
DEQUANT_DC w, pmullw
INIT_YMM avx2
DEQUANT_DC w, pmullw
%endif

%macro PEXTRW 4
    %if cpuflag(sse4)
        pextrw %1, %2, %3
    %else
        ; pextrw with a memory destination requires SSE4.1, go through a GPR as a fallback
        %if %3
            pextrw %4d, %2, %3
        %else
            movd %4d, %2
        %endif
        mov %1, %4w
    %endif
%endmacro

;-----------------------------------------------------------------------------
; void idct_dequant_2x4_dc( dctcoef dct[8], dctcoef dct4x4[8][16], int dequant_mf[6][16], int i_qp )
; void idct_dequant_2x4_dconly( dctcoef dct[8], int dequant_mf[6][16], int i_qp )
;-----------------------------------------------------------------------------

%macro DEQUANT_2x4_DC 1
%ifidn %1, dconly
    DECLARE_REG_TMP 6,3,2
    %define %%args dct, dmf, qp
%else
    DECLARE_REG_TMP 6,4,3
    %define %%args dct, dct4x4, dmf, qp
%endif

%if ARCH_X86_64 == 0
    DECLARE_REG_TMP 2,0,1
%endif

cglobal idct_dequant_2x4_%1, 0,3,5, %%args
    movifnidn  t2d, qpm
    imul       t0d, t2d, 0x2b
    shr        t0d, 8         ; qp / 6
    lea        t1d, [t0*5]
    sub        t2d, t0d
    sub        t2d, t1d       ; qp % 6
    shl        t2d, 6         ; 16 * sizeof(int)
%if ARCH_X86_64
    imul       t2d, [dmfq+t2], -0xffff ; (-dmf) << 16 | dmf
%else
    mov       dctq, dctmp
    add         t2, dmfmp
    imul       t2d, [t2], -0xffff
%endif
%if HIGH_BIT_DEPTH
    mova        m0, [dctq]
    mova        m1, [dctq+16]
    SUMSUB_BA    d, 1, 0, 2   ; 16-bit intermediate precision is enough for the first two sumsub steps,
    packssdw    m1, m0        ; and by packing to words we can use pmaddwd instead of pmulld later.
%else
    movq        m0, [dctq]
    movq        m1, [dctq+8]
    SUMSUB_BA    w, 1, 0, 2
    punpcklqdq  m1, m0        ; a0 a1 a2 a3 a4 a5 a6 a7
%endif
    pshufd      m0, m1, q2301 ; a2 a3 a0 a1 a6 a7 a4 a5
    movd        m3, t2d
    pshuflw     m3, m3, q1000 ; +  +  +  -
    SUMSUB_BA    w, 0, 1, 2
    punpcklqdq  m3, m3        ; +  +  +  -  +  +  +  -
    pshufd      m1, m1, q0022
    sub        t0d, 6
    jl .rshift
    movd        m2, t0d
    psllw       m3, m2
    pmaddwd     m0, m3
    pmaddwd     m1, m3
    jmp .end
.rshift:
    neg        t0d
    movd        m2, t0d
    pcmpeqd     m4, m4
    pmaddwd     m0, m3
    pmaddwd     m1, m3
    pslld       m4, m2
    psrad       m4, 1
    psubd       m0, m4 ; + 1 << (qp/6-1)
    psubd       m1, m4
    psrad       m0, m2
    psrad       m1, m2
.end:
%ifidn %1, dconly
%if HIGH_BIT_DEPTH
    mova    [dctq], m0
    mova [dctq+16], m1
%else
    packssdw    m0, m1
    mova    [dctq], m0
%endif
%else
    movifnidn dct4x4q, dct4x4mp
%if HIGH_BIT_DEPTH
    movd   [dct4x4q+0*64], m0
%if cpuflag(sse4)
    pextrd [dct4x4q+1*64], m0, 1
    add    dct4x4q, 4*64
    pextrd [dct4x4q-2*64], m0, 2
    pextrd [dct4x4q-1*64], m0, 3
    movd   [dct4x4q+0*64], m1
    pextrd [dct4x4q+1*64], m1, 1
    pextrd [dct4x4q+2*64], m1, 2
    pextrd [dct4x4q+3*64], m1, 3
%else
    MOVHL       m2, m0
    psrlq       m0, 32
    movd   [dct4x4q+1*64], m0
    add    dct4x4q, 4*64
    movd   [dct4x4q-2*64], m2
    psrlq       m2, 32
    movd   [dct4x4q-1*64], m2
    movd   [dct4x4q+0*64], m1
    MOVHL       m2, m1
    psrlq       m1, 32
    movd   [dct4x4q+1*64], m1
    movd   [dct4x4q+2*64], m2
    psrlq       m2, 32
    movd   [dct4x4q+3*64], m2
%endif
%else
    PEXTRW [dct4x4q+0*32], m0, 0, eax
    PEXTRW [dct4x4q+1*32], m0, 2, eax
    PEXTRW [dct4x4q+2*32], m0, 4, eax
    PEXTRW [dct4x4q+3*32], m0, 6, eax
    add    dct4x4q, 4*32
    PEXTRW [dct4x4q+0*32], m1, 0, eax
    PEXTRW [dct4x4q+1*32], m1, 2, eax
    PEXTRW [dct4x4q+2*32], m1, 4, eax
    PEXTRW [dct4x4q+3*32], m1, 6, eax
%endif
%endif
    RET
%endmacro

; sse4 reduces code size compared to sse2 but isn't any faster, so just go with sse2+avx
INIT_XMM sse2
DEQUANT_2x4_DC dc
DEQUANT_2x4_DC dconly
INIT_XMM avx
DEQUANT_2x4_DC dc
DEQUANT_2x4_DC dconly

; t4 is eax for return value.
%if ARCH_X86_64
    DECLARE_REG_TMP 0,1,2,3,6,4  ; Identical for both Windows and *NIX
%else
    DECLARE_REG_TMP 4,1,2,3,0,5
%endif

;-----------------------------------------------------------------------------
; x264_optimize_chroma_2x2_dc( dctcoef dct[4], int dequant_mf )
;-----------------------------------------------------------------------------

%macro OPTIMIZE_CHROMA_2x2_DC 0
%assign %%regs 5
%if cpuflag(sse4)
    %assign %%regs %%regs-1
%endif
%if ARCH_X86_64 == 0
    %assign %%regs %%regs+1      ; t0-t4 are volatile on x86-64
%endif
cglobal optimize_chroma_2x2_dc, 0,%%regs,7
    movifnidn t0, r0mp
    movd      m2, r1m
    movq      m1, [t0]
%if cpuflag(sse4)
    pcmpeqb   m4, m4
    pslld     m4, 11
%else
    pxor      m4, m4
%endif
%if cpuflag(ssse3)
    mova      m3, [chroma_dc_dct_mask]
    mova      m5, [chroma_dc_dmf_mask]
%else
    mova      m3, [chroma_dc_dct_mask_mmx]
    mova      m5, [chroma_dc_dmf_mask_mmx]
%endif
    pshuflw   m2, m2, 0
    pshufd    m0, m1, q0101      ;  1  0  3  2  1  0  3  2
    punpcklqdq m2, m2
    punpcklqdq m1, m1            ;  3  2  1  0  3  2  1  0
    mova      m6, [pd_1024]      ; 32<<5, elements are shifted 5 bits to the left
    PSIGNW    m0, m3             ; -1 -0  3  2 -1 -0  3  2
    PSIGNW    m2, m5             ;  +  -  -  +  -  -  +  +
    paddw     m0, m1             ; -1+3 -0+2  1+3  0+2 -1+3 -0+2  1+3  0+2
    pmaddwd   m0, m2             ;  0-1-2+3  0-1+2-3  0+1-2-3  0+1+2+3  * dmf
    punpcklwd m1, m1
    psrad     m2, 16             ;  +  -  -  +
    mov      t1d, 3
    paddd     m0, m6
    xor      t4d, t4d
%if notcpuflag(ssse3)
    psrad     m1, 31             ; has to be 0 or -1 in order for PSIGND_MMX to work correctly
%endif
%if cpuflag(sse4)
    ptest     m0, m4
%else
    mova      m6, m0
    SWAP       0, 6
    psrad     m6, 11
    pcmpeqd   m6, m4
    pmovmskb t5d, m6
    cmp      t5d, 0xffff
%endif
    jz .ret                      ; if the DC coefficients already round to zero, terminate early
    mova      m3, m0
.outer_loop:
    movsx    t3d, word [t0+2*t1] ; dct[coeff]
    pshufd    m6, m1, q3333
    pshufd    m1, m1, q2100      ; move the next element to high dword
    PSIGND    m5, m2, m6
    test     t3d, t3d
    jz .loop_end
.outer_loop_0:
    mov      t2d, t3d
    sar      t3d, 31
    or       t3d, 1
.inner_loop:
    psubd     m3, m5             ; coeff -= sign
    pxor      m6, m0, m3
%if cpuflag(sse4)
    ptest     m6, m4
%else
    psrad     m6, 11
    pcmpeqd   m6, m4
    pmovmskb t5d, m6
    cmp      t5d, 0xffff
%endif
    jz .round_coeff
    paddd     m3, m5             ; coeff += sign
    mov      t4d, 1
.loop_end:
    dec      t1d
    jz .last_coeff
    pshufd    m2, m2, q1320      ;  -  +  -  +  /  -  -  +  +
    jg .outer_loop
.ret:
    REP_RET
.round_coeff:
    sub      t2d, t3d
    mov [t0+2*t1], t2w
    jnz .inner_loop
    jmp .loop_end
.last_coeff:
    movsx    t3d, word [t0]
    punpcklqdq m2, m2            ;  +  +  +  +
    PSIGND    m5, m2, m1
    test     t3d, t3d
    jnz .outer_loop_0
    RET
%endmacro

%if HIGH_BIT_DEPTH == 0
INIT_XMM sse2
OPTIMIZE_CHROMA_2x2_DC
INIT_XMM ssse3
OPTIMIZE_CHROMA_2x2_DC
INIT_XMM sse4
OPTIMIZE_CHROMA_2x2_DC
INIT_XMM avx
OPTIMIZE_CHROMA_2x2_DC
%endif ; !HIGH_BIT_DEPTH

;-----------------------------------------------------------------------------
; int optimize_chroma_2x2_dc( dctcoef dct[4], int dequant_mf )
; int optimize_chroma_2x4_dc( dctcoef dct[8], int dequant_mf )
;-----------------------------------------------------------------------------
; avx512icl: the dc transform is linear, so lowering |dct[k]| by one moves the
; pre-rounding values by -sign*dmf*T[:,k]: each trial is one vector subtract,
; shift, xor and vptestmd against the reference, not a whole transform.
; 2x2: out = (T*dct*dmf >> 5) + 32; 2x4: out = (T*dct*dmf + 2080) >> 6
%macro OPT_CHROMA_T 0 ; m0: dwords -> T*m0, k1/k2 set; clobbers m1, m2
%if mmsize == 16
    pshufd        m1, m0, q2301
    paddd         m2, m0, m1
    vpsubd        m2 {k1}, m1, m0
    pshufd        m1, m2, q1032
    paddd         m0, m2, m1
    vpsubd        m0 {k2}, m1, m2
    pshufd        m0, m0, q3120
%else
    pshufd        m1, m0, q2301
    paddd         m2, m0, m1
    vpsubd        m2 {k1}, m1, m0
    pshufd        m1, m2, q1032
    paddd         m0, m2, m1
    vpsubd        m0 {k2}, m1, m2
    vextracti32x4 xm1, m0, 1
    paddd         xm2, xm0, xm1
    psubd         xm0, xm1
    punpcklqdq    xm1, xm2, xm0
    punpckhqdq    xm0, xm2
    vinserti32x4  m0, m1, xm0, 1
%endif
%endmacro

%macro OPT_CHROMA_ROUND 2 ; dst, src
%if mmsize == 16
    psrad         %1, %2, 5
    paddd         %1, m6
%else
    psrad         %1, %2, 6
%endif
%if HIGH_BIT_DEPTH == 0
    pslld         %1, 16                     ; the C keeps the outputs in int16
    psrad         %1, 16
%endif
%endmacro

%macro OPTIMIZE_CHROMA_ICL 2 ; name, coefs
%if %2 == 4
    %define %%bc {1to4}
%else
    %define %%bc {1to8}
%endif
cglobal optimize_chroma_%1_dc, 2,6
%if HIGH_BIT_DEPTH
    movu          m0, [r0]
%else
    vpmovsxwd     m0, [r0]
%endif
%if mmsize == 16
    mov          r2d, 0xa
    kmovb         k1, r2d
    mov          r2d, 0xc
    kmovb         k2, r2d
    vpbroadcastd  m6, [optchroma_32]
%else
    mov          r2d, 0xaa
    kmovb         k1, r2d
    mov          r2d, 0xcc
    kmovb         k2, r2d
%endif
    OPT_CHROMA_T
    vpbroadcastd  m3, r1d
    pmulld        m0, m3
%if mmsize == 32
    vpaddd        m0, [optchroma_2080] {1to8}
%endif
    OPT_CHROMA_ROUND m4, m0                  ; reference output
    xor          eax, eax
    vptestmd      k3, m4, [optchroma_m64] %%bc
    kortestb      k3, k3
    jz .ret                                  ; already rounds to zero
    mov          r2d, %2-1
    lea           r5, [optchroma_col%1+(%2-1)*mmsize]
.coef:
%if HIGH_BIT_DEPTH
    mov          r3d, [r0+r2*4]
%else
    movsx        r3d, word [r0+r2*2]
%endif
    test         r3d, r3d
    jz .next
    mov          r4d, r3d
    sar          r4d, 31
    or           r4d, 1                      ; sign
    vpbroadcastd  m5, r4d
    pmulld        m5, [r5]
    pmulld        m5, m3                     ; sign*dmf*T[:,k]
.try:
    psubd         m1, m0, m5
    OPT_CHROMA_ROUND m2, m1
    pxor          m2, m4
    vptestmd      k3, m2, [optchroma_m64] %%bc
    kortestb      k3, k3
    jz .accept
    mov          eax, 1
    jmp .store
.accept:
    mova          m0, m1
    sub          r3d, r4d
    jnz .try
.store:
%if HIGH_BIT_DEPTH
    mov    [r0+r2*4], r3d
%else
    mov    [r0+r2*2], r3w
%endif
.next:
    sub           r5, mmsize
    dec          r2d
    jge .coef
.ret:
    RET
%endmacro

INIT_YMM avx512icl
OPTIMIZE_CHROMA_ICL 2x4, 8
%if HIGH_BIT_DEPTH
INIT_XMM avx512icl
OPTIMIZE_CHROMA_ICL 2x2, 4
%endif

%if HIGH_BIT_DEPTH
;-----------------------------------------------------------------------------
; void denoise_dct( int32_t *dct, uint32_t *sum, uint32_t *offset, int size )
;-----------------------------------------------------------------------------
%macro DENOISE_DCT 0
cglobal denoise_dct, 4,4,6
    pxor      m5, m5
    movsxdifnidn r3, r3d
.loop:
    mova      m2, [r0+r3*4-2*mmsize]
    mova      m3, [r0+r3*4-1*mmsize]
    ABSD      m0, m2
    ABSD      m1, m3
    paddd     m4, m0, [r1+r3*4-2*mmsize]
    psubd     m0, [r2+r3*4-2*mmsize]
    mova      [r1+r3*4-2*mmsize], m4
    paddd     m4, m1, [r1+r3*4-1*mmsize]
    psubd     m1, [r2+r3*4-1*mmsize]
    mova      [r1+r3*4-1*mmsize], m4
    pcmpgtd   m4, m0, m5
    pand      m0, m4
    pcmpgtd   m4, m1, m5
    pand      m1, m4
    PSIGND    m0, m2
    PSIGND    m1, m3
    mova      [r0+r3*4-2*mmsize], m0
    mova      [r0+r3*4-1*mmsize], m1
    sub      r3d, mmsize/2
    jg .loop
    RET
%endmacro

%if ARCH_X86_64 == 0
INIT_MMX mmx
DENOISE_DCT
%endif
INIT_XMM sse2
DENOISE_DCT
INIT_XMM ssse3
DENOISE_DCT
INIT_XMM avx
DENOISE_DCT
INIT_YMM avx2
DENOISE_DCT

INIT_ZMM avx512icl
cglobal denoise_dct, 4,4,4
    pxor     xm3, xm3
    movsxdifnidn r3, r3d
.loop:
    movu      m1, [r0+r3*4-64]
    pabsd     m0, m1
    paddd     m2, m0, [r1+r3*4-64]
    movu [r1+r3*4-64], m2
    psubd     m0, [r2+r3*4-64]
    pmaxsd    m0, m3
    vpmovd2m  k1, m1
    vpsubd    m0{k1}, m3, m0
    movu [r0+r3*4-64], m0
    sub      r3d, 16
    jg .loop
    RET

%else ; !HIGH_BIT_DEPTH

;-----------------------------------------------------------------------------
; void denoise_dct( int16_t *dct, uint32_t *sum, uint16_t *offset, int size )
;-----------------------------------------------------------------------------
%macro DENOISE_DCT 0
cglobal denoise_dct, 4,4,7
    pxor      m6, m6
    movsxdifnidn r3, r3d
.loop:
    mova      m2, [r0+r3*2-2*mmsize]
    mova      m3, [r0+r3*2-1*mmsize]
    ABSW      m0, m2, sign
    ABSW      m1, m3, sign
    psubusw   m4, m0, [r2+r3*2-2*mmsize]
    psubusw   m5, m1, [r2+r3*2-1*mmsize]
    PSIGNW    m4, m2
    PSIGNW    m5, m3
    mova      [r0+r3*2-2*mmsize], m4
    mova      [r0+r3*2-1*mmsize], m5
    punpcklwd m2, m0, m6
    punpcklwd m3, m1, m6
    punpckhwd m0, m6
    punpckhwd m1, m6
    paddd     m2, [r1+r3*4-4*mmsize]
    paddd     m0, [r1+r3*4-3*mmsize]
    paddd     m3, [r1+r3*4-2*mmsize]
    paddd     m1, [r1+r3*4-1*mmsize]
    mova      [r1+r3*4-4*mmsize], m2
    mova      [r1+r3*4-3*mmsize], m0
    mova      [r1+r3*4-2*mmsize], m3
    mova      [r1+r3*4-1*mmsize], m1
    sub       r3, mmsize
    jg .loop
    RET
%endmacro

%if ARCH_X86_64 == 0
INIT_MMX mmx
DENOISE_DCT
%endif
INIT_XMM sse2
DENOISE_DCT
INIT_XMM ssse3
DENOISE_DCT
INIT_XMM avx
DENOISE_DCT

INIT_YMM avx2
cglobal denoise_dct, 4,4,4
    pxor      m3, m3
    movsxdifnidn r3, r3d
.loop:
    mova      m1, [r0+r3*2-mmsize]
    pabsw     m0, m1
    psubusw   m2, m0, [r2+r3*2-mmsize]
    vpermq    m0, m0, q3120
    psignw    m2, m1
    mova [r0+r3*2-mmsize], m2
    punpcklwd m1, m0, m3
    punpckhwd m0, m3
    paddd     m1, [r1+r3*4-2*mmsize]
    paddd     m0, [r1+r3*4-1*mmsize]
    mova      [r1+r3*4-2*mmsize], m1
    mova      [r1+r3*4-1*mmsize], m0
    sub       r3, mmsize/2
    jg .loop
    RET

INIT_ZMM avx512icl
cglobal denoise_dct, 4,4,4
    pxor     xm3, xm3
    movsxdifnidn r3, r3d
.loop:
    movu     ym1, [r0+r3*2-32]
    pabsw    ym0, ym1
    psubusw  ym2, ym0, [r2+r3*2-32]
    vpmovw2m  k1, ym1
    vpsubw   ym2{k1}, ym3, ym2
    movu [r0+r3*2-32], ym2
    vpmovzxwd m0, ym0
    paddd     m0, [r1+r3*4-64]
    movu [r1+r3*4-64], m0
    sub       r3, 16
    jg .loop
    RET

%endif ; !HIGH_BIT_DEPTH

;-----------------------------------------------------------------------------
; int decimate_score( dctcoef *dct )
;-----------------------------------------------------------------------------

%macro DECIMATE_MASK 5
%if mmsize==16
%if HIGH_BIT_DEPTH
    movdqa    m0, [%3+ 0]
    movdqa    m1, [%3+32]
    packssdw  m0, [%3+16]
    packssdw  m1, [%3+48]
    ABSW2     m0, m1, m0, m1, m3, m4
%else
    ABSW      m0, [%3+ 0], m3
    ABSW      m1, [%3+16], m4
%endif
    packsswb  m0, m1
    pxor      m2, m2
    pcmpeqb   m2, m0
    pcmpgtb   m0, %4
    pmovmskb  %1, m2
    pmovmskb  %2, m0
%else ; mmsize==8
%if HIGH_BIT_DEPTH
    movq      m0, [%3+ 0]
    movq      m1, [%3+16]
    movq      m2, [%3+32]
    movq      m3, [%3+48]
    packssdw  m0, [%3+ 8]
    packssdw  m1, [%3+24]
    packssdw  m2, [%3+40]
    packssdw  m3, [%3+56]
%else
    movq      m0, [%3+ 0]
    movq      m1, [%3+ 8]
    movq      m2, [%3+16]
    movq      m3, [%3+24]
%endif
    ABSW2     m0, m1, m0, m1, m6, m7
    ABSW2     m2, m3, m2, m3, m6, m7
    packsswb  m0, m1
    packsswb  m2, m3
    pxor      m4, m4
    pxor      m6, m6
    pcmpeqb   m4, m0
    pcmpeqb   m6, m2
    pcmpgtb   m0, %4
    pcmpgtb   m2, %4
    pmovmskb  %5, m4
    pmovmskb  %1, m6
    shl       %1, 8
    or        %1, %5
    pmovmskb  %5, m0
    pmovmskb  %2, m2
    shl       %2, 8
    or        %2, %5
%endif
%endmacro

cextern_common decimate_table4
cextern_common decimate_table8

%macro DECIMATE4x4 1

cglobal decimate_score%1, 1,3
%ifdef PIC
    lea r4, [decimate_table4]
    lea r5, [decimate_mask_table4]
    %define table r4
    %define mask_table r5
%else
    %define table decimate_table4
    %define mask_table decimate_mask_table4
%endif
    DECIMATE_MASK edx, eax, r0, [pb_1], ecx
    xor   edx, 0xffff
    je   .ret
%if %1==15
    and   eax, -2       ; not the DC
%else
    test  eax, eax
%endif
    jne  .ret9
%if %1==15
    shr   edx, 1
%endif
    movzx ecx, dl
    movzx eax, byte [mask_table + rcx]
    cmp   edx, ecx
    je   .ret
    bsr   ecx, ecx
    shr   edx, 1
    shr   edx, cl
    tzcnt ecx, edx
    shr   edx, 1
    shr   edx, cl
    add    al, byte [table + rcx]
    add    al, byte [mask_table + rdx]
.ret:
    REP_RET
.ret9:
    mov   eax, 9
    RET

%endmacro

%if ARCH_X86_64 == 0
INIT_MMX mmx2
DECIMATE4x4 15
DECIMATE4x4 16
%endif
INIT_XMM sse2
DECIMATE4x4 15
DECIMATE4x4 16
INIT_XMM ssse3
DECIMATE4x4 15
DECIMATE4x4 16

; 2x gt1 output, 2x nz output, 1x mask
%macro DECIMATE_MASK64_AVX2 5
    pabsw     m0, [r0+ 0]
    pabsw     m2, [r0+32]
    pabsw     m1, [r0+64]
    pabsw     m3, [r0+96]
    packsswb  m0, m2
    packsswb  m1, m3
    pcmpgtb   m2, m0, %5    ; the > 1 checks don't care about order, so
    pcmpgtb   m3, m1, %5    ; we can save latency by doing them here
    pmovmskb  %1, m2
    pmovmskb  %2, m3
    or        %1, %2
    jne .ret9
    vpermq    m0, m0, q3120
    vpermq    m1, m1, q3120
    pxor      m4, m4
    pcmpeqb   m0, m4
    pcmpeqb   m1, m4
    pmovmskb  %3, m0
    pmovmskb  %4, m1
%endmacro

%macro DECIMATE8x8 0

%if ARCH_X86_64
cglobal decimate_score64, 1,5
%ifdef PIC
    lea r4, [decimate_table8]
    %define table r4
%else
    %define table decimate_table8
%endif
    mova  m5, [pb_1]
%if mmsize==32
    DECIMATE_MASK64_AVX2 eax, r2d, r1d, r3d, m5
    shl   r3, 32
    or    r1, r3
    xor   r1, -1
    je  .ret
%else
    DECIMATE_MASK r1d, eax, r0+SIZEOF_DCTCOEF* 0, m5, null
    test eax, eax
    jne  .ret9
    DECIMATE_MASK r2d, eax, r0+SIZEOF_DCTCOEF*16, m5, null
    shl  r2d, 16
    or   r1d, r2d
    DECIMATE_MASK r2d, r3d, r0+SIZEOF_DCTCOEF*32, m5, null
    shl   r2, 32
    or   eax, r3d
    or    r1, r2
    DECIMATE_MASK r2d, r3d, r0+SIZEOF_DCTCOEF*48, m5, null
    shl   r2, 48
    or    r1, r2
    xor   r1, -1
    je   .ret
    add  eax, r3d
    jne  .ret9
%endif
    mov   al, -6
.loop:
    tzcnt rcx, r1
    shr   r1, cl
    add   al, byte [table + rcx]
    jge  .ret9
    shr   r1, 1
    jne  .loop
    add   al, 6
.ret:
    REP_RET
.ret9:
    mov  eax, 9
    RET

%else ; ARCH
%if mmsize == 8
cglobal decimate_score64, 1,6
%else
cglobal decimate_score64, 1,5
%endif
    mova  m5, [pb_1]
%if mmsize==32
    DECIMATE_MASK64_AVX2 r0, r2, r3, r4, m5
    xor   r3, -1
    je .tryret
    xor   r4, -1
.cont:
%else
    DECIMATE_MASK r3, r2, r0+SIZEOF_DCTCOEF* 0, m5, r5
    test  r2, r2
    jne  .ret9
    DECIMATE_MASK r4, r2, r0+SIZEOF_DCTCOEF*16, m5, r5
    shl   r4, 16
    or    r3, r4
    DECIMATE_MASK r4, r1, r0+SIZEOF_DCTCOEF*32, m5, r5
    or    r2, r1
    DECIMATE_MASK r1, r0, r0+SIZEOF_DCTCOEF*48, m5, r5
    shl   r1, 16
    or    r4, r1
    xor   r3, -1
    je   .tryret
    xor   r4, -1
.cont:
    add   r0, r2
    jne  .ret9
%endif
    mov   al, -6
.loop:
    tzcnt ecx, r3
    test  r3, r3
    je   .largerun
    shrd  r3, r4, cl
    shr   r4, cl
    add   al, byte [decimate_table8 + ecx]
    jge  .ret9
    shrd  r3, r4, 1
    shr   r4, 1
    test  r3, r3
    jne  .loop
    test  r4, r4
    jne  .loop
    add   al, 6
.ret:
    REP_RET
.tryret:
    xor   r4, -1
    jne  .cont
    RET
.ret9:
    mov   eax, 9
    RET
.largerun:
    mov   r3, r4
    xor   r4, r4
    tzcnt ecx, r3
    shr   r3, cl
    shr   r3, 1
    jne  .loop
    add   al, 6
    RET
%endif ; ARCH

%endmacro

%if ARCH_X86_64 == 0
INIT_MMX mmx2
DECIMATE8x8
%endif
INIT_XMM sse2
DECIMATE8x8
INIT_XMM ssse3
DECIMATE8x8
INIT_YMM avx2
DECIMATE8x8

%macro DECIMATE_MASK16_AVX512 0
    mova      m0, [r0]
%if HIGH_BIT_DEPTH
    vptestmd  k0, m0, m0
    pabsd     m0, m0
    vpcmpud   k1, m0, [pd_1] {1to16}, 6
%else
    vptestmw  k0, m0, m0
    pabsw     m0, m0
    vpcmpuw   k1, m0, [pw_1], 6
%endif
%endmacro

%macro SHRX 2
%if cpuflag(bmi2)
    shrx %1, %1, %2
%else
    shr  %1, %2b ; %2 has to be rcx/ecx
%endif
%endmacro

%macro BLSR 2
%if cpuflag(bmi1)
    blsr   %1, %2
%else
    lea    %1, [%2-1]
    and    %1, %2
%endif
%endmacro

%macro DECIMATE4x4_AVX512 1
cglobal decimate_score%1, 1,3
    DECIMATE_MASK16_AVX512
    xor   eax, eax
    kmovw edx, k0
%if %1 == 15
    shr   edx, 1
%else
    test  edx, edx
%endif
    jz .ret
%if %1 == 15
    kshiftrw k1, k1, 1  ; not the DC
%endif
    ktestw k1, k1
    jnz .ret9
%ifdef PIC
    lea    r4, [decimate_mask_table4]
    %define mask_table r4
%else
    %define mask_table decimate_mask_table4
%endif
    movzx ecx, dl
    movzx eax, byte [mask_table + rcx]
%if ARCH_X86_64
    xor   edx, ecx
    jz .ret
%if cpuflag(lzcnt)
    lzcnt ecx, ecx
    lea    r5, [decimate_table4-32]
    add    r5, rcx
%else
    bsr   ecx, ecx
    lea    r5, [decimate_table4-1]
    sub    r5, rcx
%endif
    %define table r5
%else
    cmp   edx, ecx
    jz .ret
    bsr   ecx, ecx
    shr   edx, 1
    SHRX  edx, ecx
    %define table decimate_table4
%endif
    tzcnt ecx, edx
    shr   edx, 1
    SHRX  edx, ecx
    add    al, byte [table + rcx]
    add    al, byte [mask_table + rdx]
.ret:
    REP_RET
.ret9:
    mov   eax, 9
    RET
%endmacro

%macro DECIMATE_MASK64_AVX512 0
    mova            m0, [r0]
%if HIGH_BIT_DEPTH
    packssdw        m0, [r0+1*64]
    mova            m1, [r0+2*64]
    packssdw        m1, [r0+3*64]
    packsswb        m0, m1
    vbroadcasti32x4 m1, [pb_1]
    pabsb           m2, m0
    vpcmpub         k0, m2, m1, 6
    ktestq          k0, k0
    jnz .ret9
    mova            m1, [decimate_shuf_avx512]
    vpermd          m0, m1, m0
    vptestmb        k1, m0, m0
%else
    mova            m1, [r0+64]
    vbroadcasti32x4 m3, [pb_1]
    packsswb        m2, m0, m1
    pabsb           m2, m2
    vpcmpub         k0, m2, m3, 6
    ktestq          k0, k0
    jnz .ret9
    vptestmw        k1, m0, m0
    vptestmw        k2, m1, m1
%endif
%endmacro

%macro DECIMATE8x8_AVX512 0
%if ARCH_X86_64
cglobal decimate_score64, 1,5
    DECIMATE_MASK64_AVX512
    xor     eax, eax
%if HIGH_BIT_DEPTH
    kmovq    r1, k1
    test     r1, r1
    jz .ret
%else
    kortestd k1, k2
    jz .ret
    kunpckdq k1, k2, k1
    kmovq    r1, k1
%endif
%ifdef PIC
    lea r4, [decimate_table8]
    %define table r4
%else
    %define table decimate_table8
%endif
    mov    al, -6
.loop:
    tzcnt rcx, r1
    add    al, byte [table + rcx]
    jge .ret9
    shr    r1, 1
    SHRX   r1, rcx
%if cpuflag(bmi2)
    test   r1, r1
%endif
    jnz .loop
    add    al, 6
.ret:
    REP_RET
.ret9:
    mov   eax, 9
    RET

%else ; ARCH
cglobal decimate_score64, 1,4
    DECIMATE_MASK64_AVX512
    xor     eax, eax
%if HIGH_BIT_DEPTH
    kshiftrq k2, k1, 32
%endif
    kmovd    r2, k1
    kmovd    r3, k2
    test     r2, r2
    jz .tryret
    mov    al, -6
.loop:
    tzcnt ecx, r2
    add    al, byte [decimate_table8 + ecx]
    jge .ret9
    sub   ecx, 31 ; increase the shift count by one to shift away the lowest set bit as well
    jz .run31     ; only bits 0-4 are used so we have to explicitly handle the case of 1<<31
    shrd   r2, r3, cl
    SHRX   r3, ecx
%if notcpuflag(bmi2)
    test   r2, r2
%endif
    jnz .loop
    BLSR   r2, r3
    jz .end
.largerun:
    tzcnt ecx, r3
    shr    r3, 1
    SHRX   r3, ecx
.loop2:
    tzcnt ecx, r3
    add    al, byte [decimate_table8 + ecx]
    jge .ret9
    shr    r3, 1
    SHRX   r3, ecx
.run31:
    test   r3, r3
    jnz .loop2
.end:
    add    al, 6
    RET
.tryret:
    BLSR   r2, r3
    jz .ret
    mov    al, -6
    jmp .largerun
.ret9:
    mov   eax, 9
.ret:
    REP_RET
%endif ; ARCH
%endmacro

%if HIGH_BIT_DEPTH
INIT_ZMM avx512
%else
INIT_YMM avx512
%endif
DECIMATE4x4_AVX512 15
DECIMATE4x4_AVX512 16
INIT_ZMM avx512
DECIMATE8x8_AVX512

; branchless: the score is a sum of popcounts of the nonzero mask and its shifts
%macro DECIMATE4x4_AVX512ICL 1
cglobal decimate_score%1, 1,4
    DECIMATE_MASK16_AVX512
    kmovw    r1d, k0
%if %1 == 15
    shr      r1d, 1
%endif
    ; score = sum over nonzero coefs of [run<1] + [run<3] + [run<6], run = zeros below
    lea      r2d, [r1+r1]
    lea      r3d, [r1*4]
    lea      eax, [r1*8]
    or       r3d, r2d
    or       r3d, eax       ; shifts 1-3
    lea      eax, [r3*8]
    or       eax, r3d       ; shifts 1-6
    or       r2d, 1
    or       r3d, 7
    or       eax, 0x3f
    and      r2d, r1d
    and      r3d, r1d
    and      eax, r1d
    popcnt   r2d, r2d
    popcnt   r3d, r3d
    popcnt   eax, eax
    add      eax, r2d
    add      eax, r3d
    mov      r2d, 9
%if %1 == 15
    kshiftrw  k1, k1, 1     ; not the DC
%endif
    kortestw  k1, k1
    cmovnz   eax, r2d
    RET
%endmacro

%macro DECIMATE8x8_AVX512ICL 0
cglobal decimate_score64, 1,5
    DECIMATE_MASK64_AVX512
%if HIGH_BIT_DEPTH == 0
    kunpckdq  k1, k2, k1
%endif
    kmovq     r1, k1
    ; score = sum over nonzero coefs of [run<4] + [run<12] + [run<24]
    lea       r2, [r1+r1]
    lea       r3, [r1*4]
    lea       r4, [r1*8]
    mov       rax, r1
    shl       rax, 4
    or        r2, r3
    or        r4, rax
    or        r2, r4        ; shifts 1-4
    mov       r3, r2
    mov       r4, r2
    shl       r3, 4
    shl       r4, 8
    or        r3, r4
    or        r3, r2        ; shifts 1-12
    mov       r4, r3
    shl       r4, 12
    or        r4, r3        ; shifts 1-24
    or        r2, 0xf
    or        r3, 0xfff
    or        r4, 0xffffff
    and       r2, r1
    and       r3, r1
    and       r4, r1
    popcnt    r2, r2
    popcnt    r3, r3
    popcnt    rax, r4
    add       eax, r2d
    add       eax, r3d
    RET
.ret9:
    mov       eax, 9
    RET
%endmacro

%if ARCH_X86_64
%if HIGH_BIT_DEPTH
INIT_ZMM avx512icl
%else
INIT_YMM avx512icl
%endif
DECIMATE4x4_AVX512ICL 15
DECIMATE4x4_AVX512ICL 16
INIT_ZMM avx512icl
DECIMATE8x8_AVX512ICL
%endif

;-----------------------------------------------------------------------------
; int coeff_last( dctcoef *dct )
;-----------------------------------------------------------------------------

%macro BSR 3
%if cpuflag(lzcnt)
    lzcnt %1, %2
    xor %1, %3
%else
    bsr %1, %2
%endif
%endmacro

%macro LZCOUNT 3
%if cpuflag(lzcnt)
    lzcnt %1, %2
%else
    bsr %1, %2
    xor %1, %3
%endif
%endmacro

%if HIGH_BIT_DEPTH
%macro LAST_MASK 3-4
%if %1 == 4
    movq     mm0, [%3]
    packssdw mm0, [%3+8]
    packsswb mm0, mm0
    pcmpeqb  mm0, mm2
    pmovmskb  %2, mm0
%elif mmsize == 16
    movdqa   xmm0, [%3+ 0]
%if %1 == 8
    packssdw xmm0, [%3+16]
    packsswb xmm0, xmm0
%else
    movdqa   xmm1, [%3+32]
    packssdw xmm0, [%3+16]
    packssdw xmm1, [%3+48]
    packsswb xmm0, xmm1
%endif
    pcmpeqb  xmm0, xmm2
    pmovmskb   %2, xmm0
%elif %1 == 8
    movq     mm0, [%3+ 0]
    movq     mm1, [%3+16]
    packssdw mm0, [%3+ 8]
    packssdw mm1, [%3+24]
    packsswb mm0, mm1
    pcmpeqb  mm0, mm2
    pmovmskb  %2, mm0
%else
    movq     mm0, [%3+ 0]
    movq     mm1, [%3+16]
    packssdw mm0, [%3+ 8]
    packssdw mm1, [%3+24]
    movq     mm3, [%3+32]
    movq     mm4, [%3+48]
    packssdw mm3, [%3+40]
    packssdw mm4, [%3+56]
    packsswb mm0, mm1
    packsswb mm3, mm4
    pcmpeqb  mm0, mm2
    pcmpeqb  mm3, mm2
    pmovmskb  %2, mm0
    pmovmskb  %4, mm3
    shl       %4, 8
    or        %2, %4
%endif
%endmacro

%macro COEFF_LAST4 0
cglobal coeff_last4, 1,3
    pxor mm2, mm2
    LAST_MASK 4, r1d, r0
    xor  r1d, 0xff
    shr  r1d, 4
    BSR  eax, r1d, 0x1f
    RET
%endmacro

INIT_MMX mmx2
COEFF_LAST4
INIT_MMX mmx2, lzcnt
COEFF_LAST4

%macro COEFF_LAST8 0
cglobal coeff_last8, 1,3
    pxor m2, m2
    LAST_MASK 8, r1d, r0
%if mmsize == 16
    xor r1d, 0xffff
    shr r1d, 8
%else
    xor r1d, 0xff
%endif
    BSR eax, r1d, 0x1f
    RET
%endmacro

%if ARCH_X86_64 == 0
INIT_MMX mmx2
COEFF_LAST8
%endif
INIT_XMM sse2
COEFF_LAST8
INIT_XMM sse2, lzcnt
COEFF_LAST8

%else ; !HIGH_BIT_DEPTH
%macro LAST_MASK 3-4
%if %1 <= 8
    movq     mm0, [%3+ 0]
%if %1 == 4
    packsswb mm0, mm0
%else
    packsswb mm0, [%3+ 8]
%endif
    pcmpeqb  mm0, mm2
    pmovmskb  %2, mm0
%elif mmsize == 16
    movdqa   xmm0, [%3+ 0]
    packsswb xmm0, [%3+16]
    pcmpeqb  xmm0, xmm2
    pmovmskb   %2, xmm0
%else
    movq     mm0, [%3+ 0]
    movq     mm1, [%3+16]
    packsswb mm0, [%3+ 8]
    packsswb mm1, [%3+24]
    pcmpeqb  mm0, mm2
    pcmpeqb  mm1, mm2
    pmovmskb  %2, mm0
    pmovmskb  %4, mm1
    shl       %4, 8
    or        %2, %4
%endif
%endmacro

%macro COEFF_LAST48 0
%if ARCH_X86_64
cglobal coeff_last4, 1,1
    BSR  rax, [r0], 0x3f
    shr  eax, 4
    RET
%else
cglobal coeff_last4, 0,3
    mov   edx, r0mp
    mov   eax, [edx+4]
    xor   ecx, ecx
    test  eax, eax
    cmovz eax, [edx]
    setnz cl
    BSR   eax, eax, 0x1f
    shr   eax, 4
    lea   eax, [eax+ecx*2]
    RET
%endif

cglobal coeff_last8, 1,3
    pxor m2, m2
    LAST_MASK 8, r1d, r0, r2d
    xor r1d, 0xff
    BSR eax, r1d, 0x1f
    RET
%endmacro

INIT_MMX mmx2
COEFF_LAST48
INIT_MMX mmx2, lzcnt
COEFF_LAST48
%endif ; HIGH_BIT_DEPTH

%macro COEFF_LAST 0
cglobal coeff_last15, 1,3
    pxor m2, m2
    LAST_MASK 15, r1d, r0-SIZEOF_DCTCOEF, r2d
    xor r1d, 0xffff
    BSR eax, r1d, 0x1f
    dec eax
    RET

cglobal coeff_last16, 1,3
    pxor m2, m2
    LAST_MASK 16, r1d, r0, r2d
    xor r1d, 0xffff
    BSR eax, r1d, 0x1f
    RET

%if ARCH_X86_64 == 0
cglobal coeff_last64, 1, 4-mmsize/16
    pxor m2, m2
    LAST_MASK 16, r1d, r0+SIZEOF_DCTCOEF* 32, r3d
    LAST_MASK 16, r2d, r0+SIZEOF_DCTCOEF* 48, r3d
    shl r2d, 16
    or  r1d, r2d
    xor r1d, -1
    jne .secondhalf
    LAST_MASK 16, r1d, r0+SIZEOF_DCTCOEF* 0, r3d
    LAST_MASK 16, r2d, r0+SIZEOF_DCTCOEF*16, r3d
    shl r2d, 16
    or  r1d, r2d
    not r1d
    BSR eax, r1d, 0x1f
    RET
.secondhalf:
    BSR eax, r1d, 0x1f
    add eax, 32
    RET
%else
cglobal coeff_last64, 1,3
    pxor m2, m2
    LAST_MASK 16, r1d, r0+SIZEOF_DCTCOEF* 0
    LAST_MASK 16, r2d, r0+SIZEOF_DCTCOEF*16
    shl r2d, 16
    or  r1d, r2d
    LAST_MASK 16, r2d, r0+SIZEOF_DCTCOEF*32
    LAST_MASK 16, r0d, r0+SIZEOF_DCTCOEF*48
    shl r0d, 16
    or  r2d, r0d
    shl  r2, 32
    or   r1, r2
    not  r1
    BSR rax, r1, 0x3f
    RET
%endif
%endmacro

%if ARCH_X86_64 == 0
INIT_MMX mmx2
COEFF_LAST
%endif
INIT_XMM sse2
COEFF_LAST
INIT_XMM sse2, lzcnt
COEFF_LAST

%macro LAST_MASK_AVX2 2
%if HIGH_BIT_DEPTH
    mova     m0, [%2+ 0]
    packssdw m0, [%2+32]
    mova     m1, [%2+64]
    packssdw m1, [%2+96]
    packsswb m0, m1
    mova     m1, [deinterleave_shufd]
    vpermd   m0, m1, m0
%else
    mova     m0, [%2+ 0]
    packsswb m0, [%2+32]
    vpermq   m0, m0, q3120
%endif
    pcmpeqb  m0, m2
    pmovmskb %1, m0
%endmacro

%if ARCH_X86_64 == 0
INIT_YMM avx2,lzcnt
cglobal coeff_last64, 1,2
    pxor m2, m2
    LAST_MASK_AVX2 r1d, r0+SIZEOF_DCTCOEF*32
    xor r1d, -1
    jne .secondhalf
    LAST_MASK_AVX2 r1d, r0+SIZEOF_DCTCOEF* 0
    not r1d
    BSR eax, r1d, 0x1f
    RET
.secondhalf:
    BSR eax, r1d, 0x1f
    add eax, 32
    RET
%else
INIT_YMM avx2,lzcnt
cglobal coeff_last64, 1,3
    pxor m2, m2
    LAST_MASK_AVX2 r1d, r0+SIZEOF_DCTCOEF* 0
    LAST_MASK_AVX2 r2d, r0+SIZEOF_DCTCOEF*32
    shl  r2, 32
    or   r1, r2
    not  r1
    BSR rax, r1, 0x3f
    RET
%endif

%macro COEFF_LAST_AVX512 2 ; num, w/d
cglobal coeff_last%1, 1,2
    mova         m0, [r0-(%1&1)*SIZEOF_DCTCOEF]
    vptestm%2    k0, m0, m0
%if %1 == 15
    mov         eax, 30
    kmovw       r1d, k0
    lzcnt       r1d, r1d
    sub         eax, r1d
%else
    kmovw       eax, k0
    lzcnt       eax, eax
    xor         eax, 31
%endif
    RET
%endmacro

%macro COEFF_LAST64_AVX512 1 ; w/d
cglobal coeff_last64, 1,2
    pxor        xm0, xm0
    vpcmp%1      k0, m0, [r0+0*64], 4
    vpcmp%1      k1, m0, [r0+1*64], 4
%if HIGH_BIT_DEPTH
    vpcmp%1      k2, m0, [r0+2*64], 4
    vpcmp%1      k3, m0, [r0+3*64], 4
    kunpckwd     k0, k1, k0
    kunpckwd     k1, k3, k2
%endif
%if ARCH_X86_64
    kunpckdq     k0, k1, k0
    kmovq       rax, k0
    lzcnt       rax, rax
    xor         eax, 63
%else
    kmovd       r1d, k1
    kmovd       eax, k0
    lzcnt       r1d, r1d
    lzcnt       eax, eax
    xor         r1d, 32
    cmovnz      eax, r1d
    xor         eax, 31
%endif
    RET
%endmacro

%if HIGH_BIT_DEPTH
INIT_XMM avx512
COEFF_LAST_AVX512  4, d
INIT_YMM avx512
COEFF_LAST_AVX512  8, d
INIT_ZMM avx512
COEFF_LAST_AVX512 15, d
COEFF_LAST_AVX512 16, d
COEFF_LAST64_AVX512 d
%else ; !HIGH_BIT_DEPTH
INIT_XMM avx512
COEFF_LAST_AVX512  8, w
INIT_YMM avx512
COEFF_LAST_AVX512 15, w
COEFF_LAST_AVX512 16, w
INIT_ZMM avx512
COEFF_LAST64_AVX512 w
%endif ; !HIGH_BIT_DEPTH

;-----------------------------------------------------------------------------
; int coeff_level_run( dctcoef *dct, run_level_t *runlevel )
;-----------------------------------------------------------------------------

struc levelrun
    .last: resd 1
    .mask: resd 1
    align 16, resb 1
    .level: resw 16
endstruc

; t6 = eax for return, t3 = ecx for shift, t[01] = r[01] for x86_64 args
%if WIN64
    DECLARE_REG_TMP 3,1,2,0,4,5,6
%elif ARCH_X86_64
    DECLARE_REG_TMP 0,1,2,3,4,5,6
%else
    DECLARE_REG_TMP 6,3,2,1,4,5,0
%endif

%macro COEFF_LEVELRUN 1
cglobal coeff_level_run%1,0,7
    movifnidn t0, r0mp
    movifnidn t1, r1mp
    pxor    m2, m2
    xor    t3d, t3d
    LAST_MASK %1, t5d, t0-(%1&1)*SIZEOF_DCTCOEF, t4d
%if %1==15
    shr    t5d, 1
%elif %1==8
    and    t5d, 0xff
%elif %1==4
    and    t5d, 0xf
%endif
    xor    t5d, (1<<%1)-1
    mov [t1+levelrun.mask], t5d
    shl    t5d, 32-%1
    mov    t4d, %1-1
    LZCOUNT t3d, t5d, 0x1f
    xor    t6d, t6d
    add    t5d, t5d
    sub    t4d, t3d
    shl    t5d, t3b
    mov [t1+levelrun.last], t4d
.loop:
    LZCOUNT t3d, t5d, 0x1f
%if HIGH_BIT_DEPTH
    mov    t2d, [t0+t4*4]
%else
    mov    t2w, [t0+t4*2]
%endif
    inc    t3d
    shl    t5d, t3b
%if HIGH_BIT_DEPTH
    mov   [t1+t6*4+levelrun.level], t2d
%else
    mov   [t1+t6*2+levelrun.level], t2w
%endif
    inc    t6d
    sub    t4d, t3d
    jge .loop
    RET
%endmacro

INIT_MMX mmx2
%if ARCH_X86_64 == 0
COEFF_LEVELRUN 15
COEFF_LEVELRUN 16
%endif
COEFF_LEVELRUN 4
COEFF_LEVELRUN 8
INIT_XMM sse2
%if HIGH_BIT_DEPTH
COEFF_LEVELRUN 8
%endif
COEFF_LEVELRUN 15
COEFF_LEVELRUN 16
INIT_XMM sse2, lzcnt
%if HIGH_BIT_DEPTH
COEFF_LEVELRUN 8
%endif
COEFF_LEVELRUN 15
COEFF_LEVELRUN 16
INIT_MMX mmx2, lzcnt
COEFF_LEVELRUN 4
COEFF_LEVELRUN 8

; Similar to the one above, but saves the DCT
; coefficients in m0/m1 so we don't have to load
; them later.
%macro LAST_MASK_LUT 3
    pxor     xm5, xm5
%if %1 <= 8
    mova      m0, [%3]
    packsswb  m2, m0, m0
%else
    mova     xm0, [%3+ 0]
    mova     xm1, [%3+16]
    packsswb xm2, xm0, xm1
%if mmsize==32
    vinserti128 m0, m0, xm1, 1
%endif
%endif
    pcmpeqb  xm2, xm5
    pmovmskb  %2, xm2
%endmacro

%macro COEFF_LEVELRUN_LUT 1
cglobal coeff_level_run%1,2,4+(%1/9)
%ifdef PIC
    lea       r5, [$$]
    %define GLOBAL +r5-$$
%else
    %define GLOBAL
%endif
    LAST_MASK_LUT %1, eax, r0-(%1&1)*SIZEOF_DCTCOEF
%if %1==15
    shr     eax, 1
%elif %1==8
    and     eax, 0xff
%elif %1==4
    and     eax, 0xf
%endif
    xor     eax, (1<<%1)-1
    mov [r1+levelrun.mask], eax
%if %1==15
    add     eax, eax
%endif
%if %1 > 8
%if ARCH_X86_64
    mov     r4d, eax
    shr     r4d, 8
%else
    movzx   r4d, ah ; first 8 bits
%endif
%endif
    movzx   r2d, al ; second 8 bits
    shl     eax, 32-%1-(%1&1)
    LZCOUNT eax, eax, 0x1f
    mov     r3d, %1-1
    sub     r3d, eax
    mov [r1+levelrun.last], r3d
; Here we abuse pshufb, combined with a lookup table, to do a gather
; operation based on a bitmask. For example:
;
; dct 15-8 (input): 0  0  4  0  0 -2  1  0
; dct  7-0 (input): 0  0 -1  0  0  0  0 15
; bitmask 1:        0  0  1  0  0  1  1  0
; bitmask 2:        0  0  1  0  0  0  0  1
; gather 15-8:      4 -2  1 __ __ __ __ __
; gather  7-0:     -1 15 __ __ __ __ __ __
; levels (output):  4 -2  1 -1 15 __ __ __ __ __ __ __ __ __ __ __
;
; The overlapping, dependent stores almost surely cause a mess of
; forwarding issues, but it's still enormously faster.
%if %1 > 8
    movzx   eax, byte [popcnt_table+r4 GLOBAL]
    movzx   r3d, byte [popcnt_table+r2 GLOBAL]
%if mmsize==16
    movh      m3, [dct_coef_shuffle+r4*8 GLOBAL]
    movh      m2, [dct_coef_shuffle+r2*8 GLOBAL]
    mova      m4, [pw_256]
; Storing 8 bytes of shuffle constant and converting it (unpack + or)
; is neutral to slightly faster in local speed measurements, but it
; cuts the table size in half, which is surely a big cache win.
    punpcklbw m3, m3
    punpcklbw m2, m2
    por       m3, m4
    por       m2, m4
    pshufb    m1, m3
    pshufb    m0, m2
    mova [r1+levelrun.level], m1
; This obnoxious unaligned store messes with store forwarding and
; stalls the CPU to no end, but merging the two registers before
; storing requires a variable 128-bit shift. Emulating this does
; work, but requires a lot of ops and the gain is tiny and
; inconsistent, so we'll err on the side of fewer instructions.
    movu [r1+rax*2+levelrun.level], m0
%else ; mmsize==32
    movq     xm2, [dct_coef_shuffle+r4*8 GLOBAL]
    vinserti128 m2, m2, [dct_coef_shuffle+r2*8 GLOBAL], 1
    punpcklbw m2, m2
    por       m2, [pw_256]
    pshufb    m0, m2
    vextracti128 [r1+levelrun.level], m0, 1
    movu [r1+rax*2+levelrun.level], xm0
%endif
    add     eax, r3d
%else
    movzx   eax, byte [popcnt_table+r2 GLOBAL]
    movh m1, [dct_coef_shuffle+r2*8 GLOBAL]
    punpcklbw m1, m1
    por       m1, [pw_256]
    pshufb    m0, m1
    mova [r1+levelrun.level], m0
%endif
    RET
%endmacro

%if HIGH_BIT_DEPTH==0
INIT_MMX ssse3
COEFF_LEVELRUN_LUT 4
INIT_XMM ssse3
COEFF_LEVELRUN_LUT 8
COEFF_LEVELRUN_LUT 15
COEFF_LEVELRUN_LUT 16
INIT_MMX ssse3, lzcnt
COEFF_LEVELRUN_LUT 4
INIT_XMM ssse3, lzcnt
COEFF_LEVELRUN_LUT 8
COEFF_LEVELRUN_LUT 15
COEFF_LEVELRUN_LUT 16
INIT_XMM avx2, lzcnt
COEFF_LEVELRUN_LUT 15
COEFF_LEVELRUN_LUT 16
%endif

; levels from the last nonzero coef down: reverse the coefs, then compress the nonzero ones
%macro COEFF_LEVELRUN_AVX512 2 ; num, w/d
cglobal coeff_level_run%1, 2,3
%if %1 == 4 && HIGH_BIT_DEPTH == 0
    movq        xm0, [r0]
    movu        xm1, [levelrun_rev_avx512+24]
%elif %1 == 4
    movu        xm0, [r0]
%else
    movu         m0, [r0-(%1&1)*SIZEOF_DCTCOEF]
    movu         m1, [levelrun_rev_avx512+(16-mmsize/SIZEOF_DCTCOEF)*SIZEOF_DCTCOEF]
%endif
    vptestm%2    k1, m0, m0
%if %1 == 4 && HIGH_BIT_DEPTH
    pshufd       m1, m0, q0123
%else
    vperm%2      m1, m1, m0
%endif
    vptestm%2    k2, m1, m1 ; for 15 the coef before the block is last, after the levels
    kmovw       eax, k1
%if %1 == 15
    shr         eax, 1
%endif
    vpcompress%2 m1{k2}{z}, m1
    mov [r1+levelrun.mask], eax
    lzcnt       r2d, eax
    xor         r2d, 31
    mov [r1+levelrun.last], r2d
    popcnt      eax, eax
%if %1 == 4 && HIGH_BIT_DEPTH == 0
    movq [r1+levelrun.level], xm1
%else
    movu [r1+levelrun.level], m1
%endif
    RET
%endmacro

%if ARCH_X86_64
%if HIGH_BIT_DEPTH
INIT_XMM avx512icl
COEFF_LEVELRUN_AVX512  4, d
INIT_YMM avx512icl
COEFF_LEVELRUN_AVX512  8, d
INIT_ZMM avx512icl
COEFF_LEVELRUN_AVX512 15, d
COEFF_LEVELRUN_AVX512 16, d
%else
INIT_XMM avx512icl
COEFF_LEVELRUN_AVX512  4, w
COEFF_LEVELRUN_AVX512  8, w
INIT_YMM avx512icl
COEFF_LEVELRUN_AVX512 15, w
COEFF_LEVELRUN_AVX512 16, w
%endif
%endif

;-----------------------------------------------------------------------------
; int quant_4x4x4_scan( dctcoef dct[4][16], dctcoef level[4][16], udctcoef mf[16], udctcoef bias[16],
;                       int dequant_mf[6][16], int i_qp )
;-----------------------------------------------------------------------------
; quant_4x4x4, zigzag the nonzero blocks into level, dequant dct in place unless dequant_mf is NULL,
; sum decimate_score16 (15 for ac) over the nonzero blocks. Returns nz | min(score,9) << 4.
%if ARCH_X86_64

; block, src[, src2]: store to level if the block is nonzero, else to dct (rewritten later)
%macro QUANT_SCAN_STORE 2-3
    bt        r6d, %1
    sbb       r7, r7
    and       r7, r1
%if %0 == 3
    mova [r0+r7+64*%1   ], %2
    mova [r0+r7+64*%1+32], %3
%else
    mova [r0+r7+32*%1   ], %2
%endif
%endmacro

; levels as bytes in scan order, blocks 0-1, blocks 2-3, zero, ac
%macro QUANT_SCAN_SCORE 4
%if %4
    pand      %1, [qscan4_acmask]
    pand      %2, [qscan4_acmask]
%endif
    pabsb     m10, %1
    pabsb     m11, %2
    por       m10, m11
    psubusb   m10, [pb_1]
    pcmpeqb   %1, %3
    pcmpeqb   %2, %3
    pmovmskb  r7d, %1
    pmovmskb  r8d, %2
    shl       r8, 32
    or        r7, r8
    not       r7
    ; score = sum over nonzero coefs of [run<1] + [run<3] + [run<6], run = zeros below
    lea       r1, [r7+r7]
    lea       r2, [r7*4]
    lea       r3, [r7*8]
    or        r2, r1
    or        r2, r3
    lea       r3, [r2*8]
    or        r3, r2
%if %4
    mov       r4, 0x0003000300030003
    mov       r5, 0x000f000f000f000f
    mov       r8, 0x007f007f007f007f
%else
    mov       r4, 0x0001000100010001
    mov       r5, 0x0007000700070007
    mov       r8, 0x003f003f003f003f
%endif
    or        r1, r4
    or        r2, r5
    or        r3, r8
    and       r1, r7
    and       r2, r7
    and       r3, r7
    popcnt    r1, r1
    popcnt    r2, r2
    popcnt    r3, r3
    add       r1d, r2d
    add       r1d, r3d
    mov       r2d, 9
    cmp       r1d, r2d
    cmova     r1d, r2d
    ptest     m10, m10
    cmovnz    r1d, r2d
    shl       r1d, 4
    or        eax, r1d
    RET
%endmacro

%macro QUANT_SCAN_DEQUANT_START 0
    imul      r7d, r5d, 0x2b
    shr       r7d, 8          ; i_qp / 6
    lea       r8d, [r7*3]
    add       r8d, r8d
    sub       r5d, r8d        ; i_qp % 6
    shl       r5d, 6
    add       r4, r5
%endmacro

; k1: nonzero coefs in scan order, 16 bits per block; k4: a level is > 1; ac
; eax |= min(score,9) << 4
%macro QUANT_SCAN_SCORE_AVX512 1
    kmovq     r7, k1
%if %1
    mov       r1, 0xfffefffefffefffe
    and       r7, r1
    mov       r4, 0x0003000300030003
    mov       r5, 0x000f000f000f000f
    mov       r8, 0x007f007f007f007f
%else
    mov       r4, 0x0001000100010001
    mov       r5, 0x0007000700070007
    mov       r8, 0x003f003f003f003f
%endif
    ; score = sum over nonzero coefs of [run<1] + [run<3] + [run<6], run = zeros below
    lea       r1, [r7+r7]
    lea       r2, [r7*4]
    lea       r3, [r7*8]
    or        r2, r1
    or        r2, r3
    lea       r3, [r2*8]
    or        r3, r2
    or        r1, r4
    or        r2, r5
    or        r3, r8
    and       r1, r7
    and       r2, r7
    and       r3, r7
    popcnt    r1, r1
    popcnt    r2, r2
    popcnt    r3, r3
    add       r1d, r2d
    add       r1d, r3d
    mov       r2d, 9
    cmp       r1d, r2d
    cmova     r1d, r2d
    kortestd  k4, k4
    cmovnz    r1d, r2d
    shl       r1d, 4
    or        r6d, r1d
    RET
%endmacro

%if HIGH_BIT_DEPTH
; dst, offset, mf, bias
%macro QUANT_SCAN_ONE 4
    pabsd     m8, [r0+%2]
    paddd     m8, %4
    pmulld    m8, %3
    psrad     m8, 16
    psignd    %1, m8, [r0+%2]
%endmacro

; field, block, A, B, packed dst
%macro QUANT_SCAN_BLOCK 5
%if %1
    vpermd    m8, m10, %3
    QUANT_SCAN_STORE %2, m8, %4
    packssdw  %5, m8, %4
%else
    vpermd    m8, m10, %3
    vpermd    m9, m11, %4
    vpblendd  m8, m8, m9, 0xe0
    vpermd    m9, m11, %3
    vpermd    m12, m10, %4
    vpblendd  m9, m9, m12, 0xf8
    QUANT_SCAN_STORE %2, m8, m9
    packssdw  %5, m8, m9
%endif
%endmacro

%macro QUANT_4x4x4_SCAN 3 ; name, field, ac
cglobal quant_4x4x4_scan_%1, 6,9,16
    mova      m12, [r2]
    mova      m13, [r2+32]
    mova      m14, [r3]
    mova      m15, [r3+32]
    QUANT_SCAN_ONE m0,   0, m12, m14
    QUANT_SCAN_ONE m1,  32, m13, m15
    QUANT_SCAN_ONE m2,  64, m12, m14
    QUANT_SCAN_ONE m3,  96, m13, m15
    QUANT_SCAN_ONE m4, 128, m12, m14
    QUANT_SCAN_ONE m5, 160, m13, m15
    QUANT_SCAN_ONE m6, 192, m12, m14
    QUANT_SCAN_ONE m7, 224, m13, m15
    por       m8, m0, m1
    por       m9, m2, m3
    packssdw  m8, m9
    por       m9, m4, m5
    por       m10, m6, m7
    packssdw  m9, m10
    packssdw  m8, m9
    pxor      m15, m15
    pcmpeqd   m8, m15
    movmskps  r6d, m8
    mov       r7d, r6d
    shr       r6d, 4
    and       r6d, r7d
    xor       r6d, 0xf
    jz .store_q
    sub       r1, r0
%if %2
    mova      m10, [qscan4_field]
%else
    mova      m10, [qscan4_frame_i]
    mova      m11, [qscan4_frame_j]
%endif
    QUANT_SCAN_BLOCK %2, 0, m0, m1, m13
    QUANT_SCAN_BLOCK %2, 1, m2, m3, m14
    packsswb  m13, m14
    QUANT_SCAN_BLOCK %2, 2, m4, m5, m14
    QUANT_SCAN_BLOCK %2, 3, m6, m7, m8
    packsswb  m14, m8
    test      r4, r4
    jz .store_q_score
    QUANT_SCAN_DEQUANT_START
    mova      m8, [r4]
    mova      m9, [r4+32]
    sub       r7d, 4
    jl .rshift
    movd     xm10, r7d
    pmaddwd   m0, m8
    pmaddwd   m1, m9
    pmaddwd   m2, m8
    pmaddwd   m3, m9
    pmaddwd   m4, m8
    pmaddwd   m5, m9
    pmaddwd   m6, m8
    pmaddwd   m7, m9
    pslld     m0, xm10
    pslld     m1, xm10
    pslld     m2, xm10
    pslld     m3, xm10
    pslld     m4, xm10
    pslld     m5, xm10
    pslld     m6, xm10
    pslld     m7, xm10
.store_q_score:
    mova [r0+  0], m0
    mova [r0+ 32], m1
    mova [r0+ 64], m2
    mova [r0+ 96], m3
    mova [r0+128], m4
    mova [r0+160], m5
    mova [r0+192], m6
    mova [r0+224], m7
    mova      m8, [qscan4_bytes]
    vpermd    m13, m8, m13
    vpermd    m14, m8, m14
    QUANT_SCAN_SCORE m13, m14, m15, %3
.rshift:
    neg       r7d
    movd     xm10, r7d
    mova      m11, [pd_1]
    pslld     m11, xm10
    psrld     m11, 1
    pmaddwd   m0, m8
    pmaddwd   m1, m9
    pmaddwd   m2, m8
    pmaddwd   m3, m9
    pmaddwd   m4, m8
    pmaddwd   m5, m9
    pmaddwd   m6, m8
    pmaddwd   m7, m9
    paddd     m0, m11
    paddd     m1, m11
    paddd     m2, m11
    paddd     m3, m11
    paddd     m4, m11
    paddd     m5, m11
    paddd     m6, m11
    paddd     m7, m11
    psrad     m0, xm10
    psrad     m1, xm10
    psrad     m2, xm10
    psrad     m3, xm10
    psrad     m4, xm10
    psrad     m5, xm10
    psrad     m6, xm10
    psrad     m7, xm10
    jmp .store_q_score
.store_q:
    mova [r0+  0], m0
    mova [r0+ 32], m1
    mova [r0+ 64], m2
    mova [r0+ 96], m3
    mova [r0+128], m4
    mova [r0+160], m5
    mova [r0+192], m6
    mova [r0+224], m7
    RET
%endmacro

%macro QUANT_4x4x4_SCAN_AVX512 3 ; name, field, ac
cglobal quant_4x4x4_scan_%1, 6,9,12
    movu      m4, [r2]
    movu      m5, [r3]
    movu      m0, [r0+  0]
    movu      m1, [r0+ 64]
    movu      m2, [r0+128]
    movu      m3, [r0+192]
    pabsd     m6, m0
    pabsd     m7, m1
    pabsd     m8, m2
    pabsd     m9, m3
    paddd     m6, m5
    paddd     m7, m5
    paddd     m8, m5
    paddd     m9, m5
    pmulld    m6, m4
    pmulld    m7, m4
    pmulld    m8, m4
    pmulld    m9, m4
    psrad     m6, 16
    psrad     m7, 16
    psrad     m8, 16
    psrad     m9, 16
    vpmovd2m  k1, m0
    vpmovd2m  k2, m1
    vpmovd2m  k3, m2
    vpmovd2m  k5, m3
    pxor     xm11, xm11
    vpsubd    m6{k1}, m11, m6
    vpsubd    m7{k2}, m11, m7
    vpsubd    m8{k3}, m11, m8
    vpsubd    m9{k5}, m11, m9
    pabsd     m0, m6
    pabsd     m1, m7
    pabsd     m2, m8
    pabsd     m3, m9
    por       m10, m0, m1
    vpternlogd m10, m2, m3, 0xfe ; |level| of all blocks
%if %3
    mov       r6d, 0xfffe
    kmovw     k1, r6d
    vpcmpud   k4{k1}, m10, [pd_1] {1to16}, 6
%else
    vpcmpud   k4, m10, [pd_1] {1to16}, 6
%endif
    vptestmd  k1, m10, m10
    kortestw  k1, k1
    jz .store_q
%if %2
    movu      m11, [qscan4_field_avx512]
%else
    movu      m11, [qscan4_frame_avx512]
%endif
    vpermd    m0, m11, m6
    vpermd    m1, m11, m7
    vpermd    m2, m11, m8
    vpermd    m3, m11, m9
    vptestmd  k1, m0, m0
    vptestmd  k2, m1, m1
    vptestmd  k3, m2, m2
    vptestmd  k5, m3, m3
    kunpckwd  k1, k2, k1
    kunpckwd  k3, k5, k3
    kunpckdq  k1, k3, k1
    QUANT_SCAN_NZ_AVX512
    vmovdqu32 [r1+  0]{k2}, m0
    kshiftrq  k2, k2, 16
    vmovdqu32 [r1+ 64]{k2}, m1
    kshiftrq  k2, k2, 16
    vmovdqu32 [r1+128]{k2}, m2
    kshiftrq  k2, k2, 16
    vmovdqu32 [r1+192]{k2}, m3
    test      r4, r4
    jz .store_q_score
    QUANT_SCAN_DEQUANT_START
    movu      m0, [r4]
    sub       r7d, 4
    jl .rshift
    movd     xm1, r7d
    pmaddwd   m6, m0
    pmaddwd   m7, m0
    pmaddwd   m8, m0
    pmaddwd   m9, m0
    pslld     m6, xm1
    pslld     m7, xm1
    pslld     m8, xm1
    pslld     m9, xm1
.store_q_score:
    movu [r0+  0], m6
    movu [r0+ 64], m7
    movu [r0+128], m8
    movu [r0+192], m9
    QUANT_SCAN_SCORE_AVX512 %3
.rshift:
    neg       r7d
    movd     xm1, r7d
    vpbroadcastd m2, [pd_1]
    pslld     m2, xm1
    psrld     m2, 1
    pmaddwd   m6, m0
    pmaddwd   m7, m0
    pmaddwd   m8, m0
    pmaddwd   m9, m0
    paddd     m6, m2
    paddd     m7, m2
    paddd     m8, m2
    paddd     m9, m2
    psrad     m6, xm1
    psrad     m7, xm1
    psrad     m8, xm1
    psrad     m9, xm1
    jmp .store_q_score
.store_q:
    movu [r0+  0], m6
    movu [r0+ 64], m7
    movu [r0+128], m8
    movu [r0+192], m9
    xor      eax, eax
    RET
%endmacro

%else ; !HIGH_BIT_DEPTH
; dst, tmp
%macro QUANT_SCAN_RSHIFT 2
    pmullw    %2, %1, m8
    pmulhw    m12, %1, m8
    punpcklwd %1, %2, m12
    punpckhwd %2, m12
    paddd     %1, m10
    paddd     %2, m10
    psrad     %1, xm9
    psrad     %2, xm9
    packssdw  %1, %2
%endmacro

%macro QUANT_4x4x4_SCAN 3 ; name, field, ac
cglobal quant_4x4x4_scan_%1, 6,9,16
    mova      m14, [r2]
    mova      m15, [r3]
    pabsw     m8,  [r0+ 0]
    pabsw     m9,  [r0+32]
    pabsw     m10, [r0+64]
    pabsw     m11, [r0+96]
    paddusw   m8,  m15
    paddusw   m9,  m15
    paddusw   m10, m15
    paddusw   m11, m15
    pmulhuw   m8,  m14
    pmulhuw   m9,  m14
    pmulhuw   m10, m14
    pmulhuw   m11, m14
    psignw    m0, m8,  [r0+ 0]
    psignw    m1, m9,  [r0+32]
    psignw    m2, m10, [r0+64]
    psignw    m3, m11, [r0+96]
    packssdw  m8, m0, m1
    packssdw  m9, m2, m3
    packssdw  m8, m9
    pxor      m13, m13
    pcmpeqd   m8, m13
    movmskps  r6d, m8
    mov       r7d, r6d
    shr       r6d, 4
    and       r6d, r7d
    xor       r6d, 0xf
    jz .store_q
%if %2
    mova      m8, [qscan4_field]
    pshufb    m4, m0, m8
    pshufb    m5, m1, m8
    pshufb    m6, m2, m8
    pshufb    m7, m3, m8
%else
    mova      m10, [qscan4_frame_a]
    mova      m11, [qscan4_frame_b]
    vperm2i128 m8, m0, m0, 0x01
    vperm2i128 m9, m1, m1, 0x01
    pshufb    m4, m0, m10
    pshufb    m5, m1, m10
    pshufb    m8, m11
    pshufb    m9, m11
    por       m4, m8
    por       m5, m9
    vperm2i128 m8, m2, m2, 0x01
    vperm2i128 m9, m3, m3, 0x01
    pshufb    m6, m2, m10
    pshufb    m7, m3, m10
    pshufb    m8, m11
    pshufb    m9, m11
    por       m6, m8
    por       m7, m9
%endif
    sub       r1, r0
    QUANT_SCAN_STORE 0, m4
    QUANT_SCAN_STORE 1, m5
    QUANT_SCAN_STORE 2, m6
    QUANT_SCAN_STORE 3, m7
    test      r4, r4
    jz .store_q_score
    QUANT_SCAN_DEQUANT_START
    mova      m8, [r4]
    packssdw  m8, [r4+32]
    vpermq    m8, m8, q3120
    sub       r7d, 4
    jl .rshift
    movd     xm9, r7d
    psllw     m8, xm9
    pmullw    m0, m8
    pmullw    m1, m8
    pmullw    m2, m8
    pmullw    m3, m8
.store_q_score:
    mova [r0+ 0], m0
    mova [r0+32], m1
    mova [r0+64], m2
    mova [r0+96], m3
    packsswb  m8, m4, m5
    packsswb  m9, m6, m7
    vpermq    m8, m8, q3120
    vpermq    m9, m9, q3120
    QUANT_SCAN_SCORE m8, m9, m13, %3
.rshift:
    neg       r7d
    movd     xm9, r7d
    ; dmf divisible by 1<<shift (flat): the shift is exact, multiply by dmf>>shift like dequant_4x4_flat16
    pcmpeqw   m10, m10
    mov       r8d, 16
    sub       r8d, r7d
    movd     xm11, r8d
    psrlw     m10, xm11
    ptest     m8, m10
    jnz .rshift_round
    psrlw     m8, xm9
    pmullw    m0, m8
    pmullw    m1, m8
    pmullw    m2, m8
    pmullw    m3, m8
    jmp .store_q_score
.rshift_round:
    mova      m10, [pd_1]
    pslld     m10, xm9
    psrld     m10, 1
    QUANT_SCAN_RSHIFT m0, m11
    QUANT_SCAN_RSHIFT m1, m11
    QUANT_SCAN_RSHIFT m2, m11
    QUANT_SCAN_RSHIFT m3, m11
    jmp .store_q_score
.store_q:
    mova [r0+ 0], m0
    mova [r0+32], m1
    mova [r0+64], m2
    mova [r0+96], m3
    RET
%endmacro
; dst; m2: dmf, m4: rounding, xm3: shift
%macro QUANT_SCAN_RSHIFT_AVX512 1
    pmullw    m5, %1, m2
    pmulhw    m6, %1, m2
    punpcklwd %1, m5, m6
    punpckhwd m5, m6
    paddd     %1, m4
    paddd     m5, m4
    psrad     %1, xm3
    psrad     m5, xm3
    packssdw  %1, m5
%endmacro

%macro QUANT_4x4x4_SCAN_AVX512 3 ; name, field, ac
cglobal quant_4x4x4_scan_%1, 6,9,7
    vbroadcasti32x8 m4, [r2]
    vbroadcasti32x8 m5, [r3]
    movu      m2, [r0+ 0]
    movu      m3, [r0+64]
    pabsw     m0, m2
    pabsw     m1, m3
    paddusw   m0, m5
    paddusw   m1, m5
    pmulhuw   m0, m4
    pmulhuw   m1, m4
    vpmovw2m  k1, m2
    vpmovw2m  k2, m3
    pxor     xm5, xm5
    vpsubw    m0{k1}, m5, m0
    vpsubw    m1{k2}, m5, m1
    pabsw     m4, m0
    pabsw     m5, m1
    por       m4, m5        ; |level| of all blocks, wrapped like the stored levels
    vpbroadcastd m6, [pw_m2]
%if %3
    mov       r6d, 0xfffefffe
    kmovd     k1, r6d
    vptestmw  k4{k1}, m4, m6
%else
    vptestmw  k4, m4, m6
%endif
    vptestmw  k1, m4, m4
    kortestd  k1, k1
    jz .store_q
%if %2
    movu      m6, [qscan4_field_avx512]
%else
    movu      m6, [qscan4_frame_avx512]
%endif
    vpermw    m2, m6, m0
    vpermw    m3, m6, m1
    vptestmw  k1, m2, m2
    vptestmw  k2, m3, m3
    kunpckdq  k1, k2, k1
    QUANT_SCAN_NZ_AVX512
    vmovdqu16 [r1+ 0]{k2}, m2
    kshiftrq  k2, k2, 32
    vmovdqu16 [r1+64]{k2}, m3
    test      r4, r4
    jz .store_q_score
    QUANT_SCAN_DEQUANT_START
    movu      m2, [dequant_shuf_avx512]
    vpermw    m2, m2, [r4]  ; dmf of both blocks as words
    sub       r7d, 4
    jl .rshift
    movd     xm3, r7d
    psllw     m2, xm3
    pmullw    m0, m2
    pmullw    m1, m2
.store_q_score:
    movu [r0+ 0], m0
    movu [r0+64], m1
    QUANT_SCAN_SCORE_AVX512 %3
.rshift:
    neg       r7d
    movd     xm3, r7d
    ; dmf divisible by 1<<shift (flat): the shift is exact, multiply by dmf>>shift like dequant_4x4_flat16
    mov       r8d, 1
    shlx      r8d, r8d, r7d
    dec       r8d
    vpbroadcastw m4, r8d
    vptestmw  k3, m2, m4
    kortestd  k3, k3
    jnz .rshift_round
    psrlw     m2, xm3
    pmullw    m0, m2
    pmullw    m1, m2
    jmp .store_q_score
.rshift_round:
    vpbroadcastd m4, [pd_1]
    pslld     m4, xm3
    psrld     m4, 1
    QUANT_SCAN_RSHIFT_AVX512 m0
    QUANT_SCAN_RSHIFT_AVX512 m1
    jmp .store_q_score
.store_q:
    movu [r0+ 0], m0
    movu [r0+64], m1
    xor      eax, eax
    RET
%endmacro
%endif ; HIGH_BIT_DEPTH

INIT_YMM avx2
QUANT_4x4x4_SCAN frame,    0, 0
QUANT_4x4x4_SCAN field,    1, 0
QUANT_4x4x4_SCAN frame_ac, 0, 1
QUANT_4x4x4_SCAN field_ac, 1, 1

INIT_ZMM avx512icl
QUANT_4x4x4_SCAN_AVX512 frame,    0, 0
QUANT_4x4x4_SCAN_AVX512 field,    1, 0
QUANT_4x4x4_SCAN_AVX512 frame_ac, 0, 1
QUANT_4x4x4_SCAN_AVX512 field_ac, 1, 1
%endif ; ARCH_X86_64
