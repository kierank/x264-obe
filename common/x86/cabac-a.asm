;*****************************************************************************
;* cabac-a.asm: x86 cabac
;*****************************************************************************
;* Copyright (C) 2008-2014 x264 project
;*
;* Authors: Loren Merritt <lorenm@u.washington.edu>
;*          Jason Garrett-Glaser <darkshikari@gmail.com>
;*          Holger Lubitz <holger@lubitz.org>
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

; rd 4x4 sig/last map (avx512icl): entropy[state^bin] split in bytes, and
; transition[state][bin] == rd_transition_xor[state^bin] ^ (state&1)
rd_entropy_lo:      db 7, 189, 7, 169, 8, 150, 8, 131, 9, 112, 9, 92, 10, 73, 10, 54
                    db 11, 35, 11, 15, 12, 252, 12, 233, 13, 214, 14, 194, 15, 175, 15, 156
                    db 16, 137, 17, 117, 18, 98, 19, 79, 20, 60, 21, 40, 22, 21, 24, 2
                    db 25, 239, 26, 219, 28, 200, 29, 181, 31, 162, 33, 142, 35, 123, 37, 104
                    db 39, 85, 41, 65, 43, 46, 46, 27, 48, 8, 51, 244, 54, 225, 57, 206
                    db 60, 187, 64, 167, 68, 148, 72, 129, 76, 110, 80, 90, 85, 71, 90, 52
                    db 96, 33, 102, 13, 108, 250, 115, 231, 122, 212, 130, 192, 139, 173, 148, 154
                    db 157, 135, 168, 115, 180, 96, 192, 77, 206, 58, 221, 39, 238, 19, 0, 0
rd_entropy_hi:      db 0, 5, 0, 5, 0, 5, 0, 5, 0, 5, 0, 5, 0, 5, 0, 5
                    db 0, 5, 0, 5, 0, 4, 0, 4, 0, 4, 0, 4, 0, 4, 0, 4
                    db 0, 4, 0, 4, 0, 4, 0, 4, 0, 4, 0, 4, 0, 4, 0, 4
                    db 0, 3, 0, 3, 0, 3, 0, 3, 0, 3, 0, 3, 0, 3, 0, 3
                    db 0, 3, 0, 3, 0, 3, 0, 3, 0, 3, 0, 2, 0, 2, 0, 2
                    db 0, 2, 0, 2, 0, 2, 0, 2, 0, 2, 0, 2, 0, 2, 0, 2
                    db 0, 2, 0, 2, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1
                    db 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 1, 1
rd_transition_xor:  db 0, 0, 2, 50, 2, 50, 4, 52, 6, 52, 8, 52, 10, 54, 12, 54
                    db 14, 54, 16, 56, 18, 56, 20, 56, 22, 58, 24, 58, 26, 60, 28, 60
                    db 30, 60, 32, 62, 34, 62, 36, 64, 38, 66, 40, 66, 42, 66, 44, 68
                    db 46, 68, 48, 70, 50, 72, 52, 72, 54, 74, 56, 74, 58, 76, 60, 78
                    db 62, 78, 64, 80, 66, 82, 68, 82, 70, 84, 72, 84, 74, 88, 76, 88
                    db 78, 90, 80, 90, 82, 94, 84, 94, 86, 96, 88, 96, 90, 100, 92, 100
                    db 94, 102, 96, 104, 98, 104, 100, 108, 102, 108, 104, 110, 106, 112, 108, 114
                    db 110, 116, 112, 118, 114, 118, 116, 122, 118, 122, 120, 124, 122, 126, 124, 127
; entropy[(i>>1)^(i&1)]: index 2*state+bin
rd_entropy_sb:      dw 7, 1469, 1469, 7, 7, 1449, 1449, 7, 8, 1430, 1430, 8, 8, 1411, 1411, 8
                    dw 9, 1392, 1392, 9, 9, 1372, 1372, 9, 10, 1353, 1353, 10, 10, 1334, 1334, 10
                    dw 11, 1315, 1315, 11, 11, 1295, 1295, 11, 12, 1276, 1276, 12, 12, 1257, 1257, 12
                    dw 13, 1238, 1238, 13, 14, 1218, 1218, 14, 15, 1199, 1199, 15, 15, 1180, 1180, 15
                    dw 16, 1161, 1161, 16, 17, 1141, 1141, 17, 18, 1122, 1122, 18, 19, 1103, 1103, 19
                    dw 20, 1084, 1084, 20, 21, 1064, 1064, 21, 22, 1045, 1045, 22, 24, 1026, 1026, 24
                    dw 25, 1007, 1007, 25, 26, 987, 987, 26, 28, 968, 968, 28, 29, 949, 949, 29
                    dw 31, 930, 930, 31, 33, 910, 910, 33, 35, 891, 891, 35, 37, 872, 872, 37
                    dw 39, 853, 853, 39, 41, 833, 833, 41, 43, 814, 814, 43, 46, 795, 795, 46
                    dw 48, 776, 776, 48, 51, 756, 756, 51, 54, 737, 737, 54, 57, 718, 718, 57
                    dw 60, 699, 699, 60, 64, 679, 679, 64, 68, 660, 660, 68, 72, 641, 641, 72
                    dw 76, 622, 622, 76, 80, 602, 602, 80, 85, 583, 583, 85, 90, 564, 564, 90
                    dw 96, 545, 545, 96, 102, 525, 525, 102, 108, 506, 506, 108, 115, 487, 487, 115
                    dw 122, 468, 468, 122, 130, 448, 448, 130, 139, 429, 429, 139, 148, 410, 410, 148
                    dw 157, 391, 391, 157, 168, 371, 371, 168, 180, 352, 352, 180, 192, 333, 333, 192
                    dw 206, 314, 314, 206, 221, 295, 295, 221, 238, 275, 275, 238, 256, 256, 256, 256
rd_level_transition: db 1, 4, 2, 4, 3, 4, 3, 4, 4, 5, 5, 6, 6, 7, 7, 7 ; [2*node_ctx+b]
rd_lanes_4x4:       dw 0xffff, 0x7fff, 0xffff, 0x000f, 0x7fff, 0xffff, 0xffff
                    dw 0x7fff, 0xffff, 0xffff, 0xffff, 0x7fff, 0xffff, 0xffff
rd_nzmask_4x4:  dd 0xffff, 0, 0xffff, 1, 0xffff, 0, 0x000f, 0, 0xffff, 1, 0xffff, 0, 0xffff, 0
                dd 0xffff, 1, 0xffff, 0, 0xffff, 0, 0xffff, 0, 0xffff, 1, 0xffff, 0, 0xffff, 0

coeff_abs_level1_ctx:       db 1, 2, 3, 4, 0, 0, 0, 0
coeff_abs_levelgt1_ctx:     db 5, 5, 5, 5, 6, 7, 8, 9
coeff_abs_level_transition: db 1, 2, 3, 3, 4, 5, 6, 7
                            db 4, 4, 4, 4, 5, 6, 7, 7

%if ARCH_X86_64
%macro COEFF_LAST_TABLE 17
    %define funccpu1 %1
    %define funccpu2 %2
    %define funccpu3 %3
    %rep 14
        %ifidn %4, 4
            dq mangle(private_prefix %+ _coeff_last%4_ %+ funccpu1)
        %elifidn %4, 64
            dq mangle(private_prefix %+ _coeff_last%4_ %+ funccpu2)
        %else
            dq mangle(private_prefix %+ _coeff_last%4_ %+ funccpu3)
        %endif
        %rotate 1
    %endrep
%endmacro

cextern coeff_last4_mmx2
cextern coeff_last4_mmx2_lzcnt
%if HIGH_BIT_DEPTH
cextern coeff_last4_avx512
%endif
cextern coeff_last15_sse2
cextern coeff_last15_sse2_lzcnt
cextern coeff_last15_avx512
cextern coeff_last16_sse2
cextern coeff_last16_sse2_lzcnt
cextern coeff_last16_avx512
cextern coeff_last64_sse2
cextern coeff_last64_sse2_lzcnt
cextern coeff_last64_avx2_lzcnt
cextern coeff_last64_avx512

%ifdef PIC
SECTION .data
%endif
coeff_last_sse2:       COEFF_LAST_TABLE       mmx2,       sse2,       sse2, 16, 15, 16, 4, 15, 64, 16, 15, 16, 64, 16, 15, 16, 64
coeff_last_sse2_lzcnt: COEFF_LAST_TABLE mmx2_lzcnt, sse2_lzcnt, sse2_lzcnt, 16, 15, 16, 4, 15, 64, 16, 15, 16, 64, 16, 15, 16, 64
coeff_last_avx2_lzcnt: COEFF_LAST_TABLE mmx2_lzcnt, avx2_lzcnt, sse2_lzcnt, 16, 15, 16, 4, 15, 64, 16, 15, 16, 64, 16, 15, 16, 64
%if HIGH_BIT_DEPTH
coeff_last_avx512:     COEFF_LAST_TABLE     avx512,     avx512,     avx512, 16, 15, 16, 4, 15, 64, 16, 15, 16, 64, 16, 15, 16, 64
%else
coeff_last_avx512:     COEFF_LAST_TABLE mmx2_lzcnt,     avx512,     avx512, 16, 15, 16, 4, 15, 64, 16, 15, 16, 64, 16, 15, 16, 64
%endif
%endif

SECTION .text

cextern_common cabac_range_lps
cextern_common cabac_transition
cextern_common cabac_renorm_shift
cextern_common cabac_entropy
cextern cabac_size_unary
cextern cabac_transition_unary
cextern_common significant_coeff_flag_offset
cextern_common significant_coeff_flag_offset_8x8
cextern_common last_coeff_flag_offset
cextern_common last_coeff_flag_offset_8x8
cextern_common coeff_abs_level_m1_offset
cextern_common count_cat_m1
cextern cabac_encode_ue_bypass
cextern pb_1

%if ARCH_X86_64
    %define pointer resq
%else
    %define pointer resd
%endif

struc cb
    .low: resd 1
    .range: resd 1
    .queue: resd 1
    .bytes_outstanding: resd 1
    .start: pointer 1
    .p: pointer 1
    .end: pointer 1
    align 64, resb 1
    .bits_encoded: resd 1
    .state: resb 1024
endstruc

%macro LOAD_GLOBAL 3-5 0 ; dst, base, off1, off2, tmp
%ifdef PIC
    %ifidn %4, 0
        movzx %1, byte [%2+%3+r7-$$]
    %else
        lea   %5, [r7+%4]
        movzx %1, byte [%2+%3+%5-$$]
    %endif
%else
    movzx %1, byte [%2+%3+%4]
%endif
%endmacro

%macro CABAC 1
; t3 must be ecx, since it's used for shift.
%if WIN64
    DECLARE_REG_TMP 3,1,2,0,5,6,4,4
%elif ARCH_X86_64
    DECLARE_REG_TMP 0,1,2,3,4,5,6,6
%else
    DECLARE_REG_TMP 0,4,2,1,3,5,6,2
%endif

cglobal cabac_encode_decision_%1, 1,7
    movifnidn t1d, r1m
    mov   t5d, [r0+cb.range]
    movzx t6d, byte [r0+cb.state+t1]
    movifnidn t0,  r0 ; WIN64
    mov   t4d, ~1
    mov   t3d, t5d
    and   t4d, t6d
    shr   t5d, 6
    movifnidn t2d, r2m
%if WIN64
    PUSH r7
%endif
%ifdef PIC
    lea    r7, [$$]
%endif
    LOAD_GLOBAL t5d, cabac_range_lps-4, t5, t4*2, t4
    LOAD_GLOBAL t4d, cabac_transition, t2, t6*2, t4
    and   t6d, 1
    sub   t3d, t5d
    cmp   t6d, t2d
    mov   t6d, [t0+cb.low]
    lea    t2, [t6+t3]
    cmovne t3d, t5d
    cmovne t6d, t2d
    mov   [t0+cb.state+t1], t4b
;cabac_encode_renorm
    mov   t4d, t3d
%ifidn %1, bmi2
    lzcnt t3d, t3d
    sub   t3d, 23
    shlx  t4d, t4d, t3d
    shlx  t6d, t6d, t3d
%else
    shr   t3d, 3
    LOAD_GLOBAL t3d, cabac_renorm_shift, t3
    shl   t4d, t3b
    shl   t6d, t3b
%endif
%if WIN64
    POP r7
%endif
    mov   [t0+cb.range], t4d
    add   t3d, [t0+cb.queue]
    jge cabac_putbyte_%1
.update_queue_low:
    mov   [t0+cb.low], t6d
    mov   [t0+cb.queue], t3d
    RET

cglobal cabac_encode_bypass_%1, 2,3
    mov       t7d, [r0+cb.low]
    and       r1d, [r0+cb.range]
    lea       t7d, [t7*2+r1]
    movifnidn  t0, r0 ; WIN64
    mov       t3d, [r0+cb.queue]
    inc       t3d
%if ARCH_X86_64 ; .putbyte compiles to nothing but a jmp
    jge cabac_putbyte_%1
%else
    jge .putbyte
%endif
    mov   [t0+cb.low], t7d
    mov   [t0+cb.queue], t3d
    RET
%if ARCH_X86_64 == 0
.putbyte:
    PROLOGUE 0,7
    movifnidn t6d, t7d
    jmp cabac_putbyte_%1
%endif

%ifnidn %1,bmi2
cglobal cabac_encode_terminal_%1, 1,3
    sub  dword [r0+cb.range], 2
; shortcut: the renormalization shift in terminal
; can only be 0 or 1 and is zero over 99% of the time.
    test dword [r0+cb.range], 0x100
    je .renorm
    RET
.renorm:
    shl  dword [r0+cb.low], 1
    shl  dword [r0+cb.range], 1
    inc  dword [r0+cb.queue]
    jge .putbyte
    RET
.putbyte:
    PROLOGUE 0,7
    movifnidn t0, r0 ; WIN64
    mov t3d, [r0+cb.queue]
    mov t6d, [t0+cb.low]
%endif

cabac_putbyte_%1:
    ; alive: t0=cb t3=queue t6=low
%if WIN64
    DECLARE_REG_TMP 3,6,1,0,2,5,4
%endif
%ifidn %1, bmi2
    add   t3d, 10
    shrx  t2d, t6d, t3d
    bzhi  t6d, t6d, t3d
    sub   t3d, 18
%else
    mov   t1d, -1
    add   t3d, 10
    mov   t2d, t6d
    shl   t1d, t3b
    shr   t2d, t3b ; out
    not   t1d
    sub   t3d, 18
    and   t6d, t1d
%endif
    mov   t5d, [t0+cb.bytes_outstanding]
    cmp   t2b, 0xff ; FIXME is a 32bit op faster?
    jz    .postpone
    mov    t1, [t0+cb.p]
    add   [t1-1], t2h
    dec   t2h
.loop_outstanding:
    mov   [t1], t2h
    inc   t1
    dec   t5d
    jge .loop_outstanding
    mov   [t1-1], t2b
    mov   [t0+cb.p], t1
.postpone:
    inc   t5d
    mov   [t0+cb.bytes_outstanding], t5d
    jmp mangle(private_prefix %+ _cabac_encode_decision_%1.update_queue_low)
%endmacro

CABAC asm
CABAC bmi2

; temporaries of COEFF_ABS_LEVEL_GT1 and the rd sig/last code
%macro RD_TMP_REGS 3 ; t0, t1, ctx
    %xdefine lt0  r%1
    %xdefine lt0d r%1d
    %xdefine lt1  r%2
    %xdefine lt1d r%2d
    %xdefine lt1b r%2b
    %xdefine lctx  r%3
    %xdefine lctxd r%3d
%endmacro

; %1 = label name
; %2 = node_ctx init?
%macro COEFF_ABS_LEVEL_GT1 2
%if %2
    %define ctx 1
%else
    movzx  lctxd, byte [coeff_abs_level1_ctx+r2 GLOBAL]
    %define ctx lctx
%endif
    movzx   lt0d, byte [r8+ctx]
; if( coeff_abs > 1 )
    cmp     r1d, 1
    jg .%1_gt1
; x264_cabac_encode_decision( cb, ctx_level+ctx, 0 )
    movzx   lt1d, byte [cabac_transition+lt0*2 GLOBAL]
    movzx   lt0d, word [cabac_entropy+lt0*2 GLOBAL]
    lea     r0d, [r0+lt0+256]
    mov [r8+ctx], lt1b
%if %2
    mov     r2d, 1
%else
    movzx   r2d, byte [coeff_abs_level_transition+r2 GLOBAL]
%endif
    jmp .%1_end

.%1_gt1:
; x264_cabac_encode_decision( cb, ctx_level+ctx, 1 )
    movzx   lt1d, byte [cabac_transition+lt0*2+1 GLOBAL]
    xor     lt0d, 1
    movzx   lt0d, word [cabac_entropy+lt0*2 GLOBAL]
    mov [r8+ctx], lt1b
    add     r0d, lt0d
%if %2
    %define ctx 5
%else
    movzx  lctxd, byte [coeff_abs_levelgt1_ctx+r2 GLOBAL]
    %define ctx lctx
%endif
; if( coeff_abs < 15 )
    cmp     r1d, 15
    jge .%1_escape
    shl     r1d, 7
; x264_cabac_transition_unary[coeff_abs-1][cb->state[ctx_level+ctx]]
    movzx   lt0d, byte [r8+ctx]
    add     lt0d, r1d
    movzx   lt1d, byte [cabac_transition_unary-128+lt0 GLOBAL]
; x264_cabac_size_unary[coeff_abs-1][cb->state[ctx_level+ctx]]
    movzx   lt0d, word [cabac_size_unary-256+lt0*2 GLOBAL]
    mov [r8+ctx], lt1b
    add     r0d, lt0d
    jmp .%1_gt1_end

.%1_escape:
; x264_cabac_transition_unary[14][cb->state[ctx_level+ctx]]
    movzx   lt0d, byte [r8+ctx]
    movzx   lt1d, byte [cabac_transition_unary+128*14+lt0 GLOBAL]
; x264_cabac_size_unary[14][cb->state[ctx_level+ctx]]
    movzx   lt0d, word [cabac_size_unary+256*14+lt0*2 GLOBAL]
    add     r0d, lt0d
    mov [r8+ctx], lt1b
    sub     r1d, 14
%if cpuflag(lzcnt)
    lzcnt   lt0d, r1d
    xor     lt0d, 0x1f
%else
    bsr     lt0d, r1d
%endif
; bs_size_ue_big(coeff_abs-15)<<8
    shl     lt0d, 9
; (ilog2(coeff_abs-14)+1) << 8
    lea     r0d, [r0+lt0+256]
.%1_gt1_end:
%if %2
    mov     r2d, 4
%else
    movzx   r2d, byte [coeff_abs_level_transition+8+r2 GLOBAL]
%endif
.%1_end:
%endmacro

; Branchless COEFF_ABS_LEVEL_GT1 for coeff_abs < 15. Row 0 of the unary
; tables is the sign alone with the state unchanged, so coeff_abs == 1 runs
; the same code with row coeff_abs-1 = 0 on the gt1 context:
;   b = coeff_abs > 1
;   f8 += entropy[s1^b], s1 = transition[s1][b]                   (level1 ctx)
;   f8 += size_unary[coeff_abs-1][s2], s2 = transition_unary[..][s2] (gt1 ctx)
;   node_ctx = coeff_abs_level_transition[b][node_ctx]
; The escape (coeff_abs >= 15) stays a branch, to COEFF_ABS_LEVEL_ESCAPE.
; %1 = label name
; %2 = node_ctx init?
%macro COEFF_ABS_LEVEL_BF 2
    cmp     r1d, 15
    jae .%1_escape
    dec     r1d
    shl     r1d, 7                                            ; (coeff_abs-1)*128
    neg     r1d                                               ; CF = b
%if %2
    %define ctx 1
%else
    movzx  lctxd, byte [coeff_abs_level1_ctx+r2 GLOBAL]
    %define ctx lctx
%endif
    movzx   lt0d, byte [r8+ctx]
    adc     lt0d, lt0d                                        ; 2*s1+b
    movzx   lt1d, byte [cabac_transition+lt0 GLOBAL]
    movzx   lt0d, word [rd_entropy_sb+lt0*2 GLOBAL]
    mov [r8+ctx], lt1b
    add     r0d, lt0d
%if %2
    %define ctx 5
%else
    movzx  lctxd, byte [coeff_abs_levelgt1_ctx+r2 GLOBAL]
    %define ctx lctx
%endif
    movzx   lt0d, byte [r8+ctx]
    sub     lt0d, r1d                                         ; (coeff_abs-1)*128+s2
    movzx   lt1d, byte [cabac_transition_unary+lt0 GLOBAL]
    movzx   lt0d, word [cabac_size_unary+lt0*2 GLOBAL]
    mov [r8+ctx], lt1b
    add     r0d, lt0d
    neg     r1d                                               ; CF = b
%if %2
    sbb     r2d, r2d
    and     r2d, 3
    inc     r2d                                               ; b ? 4 : 1
%else
    adc     r2d, r2d
    movzx   r2d, byte [rd_level_transition+r2 GLOBAL]         ; [2*node_ctx+b]
%endif
.%1_end:
%endmacro

; out of line: coeff_abs >= 15
%macro COEFF_ABS_LEVEL_ESCAPE 2
.%1_escape:
%if %2
    %define ctx 1
%else
    movzx  lctxd, byte [coeff_abs_level1_ctx+r2 GLOBAL]
    %define ctx lctx
%endif
    movzx   lt0d, byte [r8+ctx]
    movzx   lt1d, byte [cabac_transition+lt0*2+1 GLOBAL]
    movzx   lt0d, word [rd_entropy_sb+lt0*4+2 GLOBAL]
    mov [r8+ctx], lt1b
    add     r0d, lt0d
%if %2
    %define ctx 5
%else
    movzx  lctxd, byte [coeff_abs_levelgt1_ctx+r2 GLOBAL]
    %define ctx lctx
%endif
    movzx   lt0d, byte [r8+ctx]
    movzx   lt1d, byte [cabac_transition_unary+128*14+lt0 GLOBAL]
    movzx   lt0d, word [cabac_size_unary+256*14+lt0*2 GLOBAL]
    mov [r8+ctx], lt1b
    add     r0d, lt0d
    sub     r1d, 14
%if cpuflag(lzcnt)
    lzcnt   lt0d, r1d
    xor     lt0d, 0x1f
%else
    bsr     lt0d, r1d
%endif
    shl     lt0d, 9
    lea     r0d, [r0+lt0+256]                                 ; (ilog2(coeff_abs-14)+1) << 8
%if %2
    mov     r2d, 4
%else
    movzx   r2d, byte [coeff_abs_level_transition+8+r2 GLOBAL]
%endif
    jmp .%1_end
%endmacro

; EXPERIMENT: rd loop heads at the start of a 64 byte window. The padding is
; jumped over, so every arm runs the same instructions. -DRD_LOOP_SKEW=n
; puts the heads n bytes past the boundary instead (layout twin),
; -DRD_LOOP_ALIGN=0 removes the jump and the padding.
%ifndef RD_LOOP_ALIGN
    %define RD_LOOP_ALIGN 64
%endif
%ifndef RD_LOOP_SKEW
    %define RD_LOOP_SKEW 0
%endif
%macro RD_LOOP_HEAD 1
%if RD_LOOP_ALIGN
    jmp %1
    ALIGN RD_LOOP_ALIGN
    times RD_LOOP_SKEW db 0xcc
%endif
%1:
%endmacro

%macro LOAD_DCTCOEF 1
%if HIGH_BIT_DEPTH
    mov     %1, [dct+r6*4]
%else
    movzx   %1, word [dct+r6*2]
%endif
%endmacro

;-----------------------------------------------------------------------------
; void x264_cabac_block_residual_rd_internal_sse2 ( dctcoef *l, int b_interlaced,
;                                                   int ctx_block_cat, x264_cabac_t *cb );
;-----------------------------------------------------------------------------

; 4x4 blocks: a leaf. last comes from the nonzero mask of the abs() copy.
%macro CABAC_RESIDUAL_RD_4x4 0
    %assign rd4_stack (17*SIZEOF_DCTCOEF+15) & ~15 ; the aligned block, one coefficient further down
%ifdef PIC
    cglobal cabac_block_residual_rd_internal, 4,12,6,-rd4_stack
    lea     r11, [$$]
    %define GLOBAL +r11-$$
%else
    cglobal cabac_block_residual_rd_internal, 4,11,6,-rd4_stack
    %define GLOBAL
%endif
    RD_TMP_REGS 9, 4, 10
    %define dct rsp+SIZEOF_DCTCOEF
; AC blocks start one coefficient into an aligned block of 16. abs() the
; whole aligned block onto the stack so that l[0] lands at dct.
    mov      r4, r0
    and     r4d, SIZEOF_DCTCOEF
    neg      r4
%if HIGH_BIT_DEPTH
    ABSD     m0, [r0+r4+0*mmsize], m4
    ABSD     m1, [r0+r4+1*mmsize], m5
    ABSD     m2, [r0+r4+2*mmsize], m4
    ABSD     m3, [r0+r4+3*mmsize], m5
    movu [rsp+r4+SIZEOF_DCTCOEF+0*mmsize], m0
    movu [rsp+r4+SIZEOF_DCTCOEF+1*mmsize], m1
    movu [rsp+r4+SIZEOF_DCTCOEF+2*mmsize], m2
    movu [rsp+r4+SIZEOF_DCTCOEF+3*mmsize], m3
    packssdw m0, m1
    packssdw m2, m3
    packsswb m0, m2
%else
    ABSW     m0, [r0+r4+0*mmsize], m2
    ABSW     m1, [r0+r4+1*mmsize], m2
    movu [rsp+r4+SIZEOF_DCTCOEF+0*mmsize], m0
    movu [rsp+r4+SIZEOF_DCTCOEF+1*mmsize], m1
    packsswb m0, m1
%endif
    pxor     m1, m1
    pcmpeqb  m0, m1
    pmovmskb r9d, m0
    not      r9d
    and      r9d, [rd_nzmask_4x4+r2*8 GLOBAL]                 ; lanes of the block, bit 0 = aligned block start
%if cpuflag(lzcnt)
    lzcnt    r6d, r9d
    xor      r6d, 31
%else
    bsr      r6d, r9d
%endif
    sub      r6d, [rd_nzmask_4x4+r2*8+4 GLOBAL]               ; r6 = last
    shl      r1d, 4                                           ; MB_INTERLACED*16
    add      r1d, r2d
    movzx    r5d, word [significant_coeff_flag_offset+r1*2 GLOBAL]    ; r5 = ctx_sig
    movzx    r7d, word [last_coeff_flag_offset+r1*2 GLOBAL]           ; r7 = ctx_last
    movzx    r8d, word [coeff_abs_level_m1_offset+r2*2 GLOBAL]        ; r8 = ctx_level
    mov      r0d, [r3+cb.bits_encoded]                        ; r0 = cabac.f8_bits_encoded
    add       r3, cb.state
    add       r5, r3
    add       r7, r3
    add       r8, r3                                          ; precalculate cabac state pointers

; if( last != count_cat_m1[ctx_block_cat] )
    cmp      r6b, [count_cat_m1+r2 GLOBAL]
    je .skip_last_sigmap

; x264_cabac_encode_decision( cb, ctx_sig + last, 1 )
; x264_cabac_encode_decision( cb, ctx_last + last, 1 )
    movzx   r1d, byte [r5+r6]
    movzx   r9d, byte [cabac_transition+1+r1*2 GLOBAL]
    xor     r1d, 1
    movzx   r1d, word [cabac_entropy+r1*2 GLOBAL]
    mov [r5+r6], r9b
    add     r0d, r1d

    movzx   r1d, byte [r7+r6]
    movzx   r9d, byte [cabac_transition+1+r1*2 GLOBAL]
    xor     r1d, 1
    movzx   r1d, word [cabac_entropy+r1*2 GLOBAL]
    mov [r7+r6], r9b
    add     r0d, r1d
.skip_last_sigmap:
    LOAD_DCTCOEF r1d
    COEFF_ABS_LEVEL_GT1 last, 1
; for( int i = last-1 ; i >= 0; i-- )
    dec     r6d
    jl .end
    RD_LOOP_HEAD .coeff_loop
    LOAD_DCTCOEF r1d
; if( l[i] )
    movzx   r9d, byte [r5+r6]
    test    r1d, r1d
    jnz .coeff_nonzero
; x264_cabac_encode_decision( cb, ctx_sig + i, 0 )
    movzx   r4d, byte [cabac_transition+r9*2 GLOBAL]
    movzx   r9d, word [cabac_entropy+r9*2 GLOBAL]
    mov [r5+r6], r4b
    add     r0d, r9d
    dec     r6d
    jge .coeff_loop
    jmp .end
.coeff_nonzero:
; x264_cabac_encode_decision( cb, ctx_sig + i, 1 )
    movzx   r4d, byte [cabac_transition+r9*2+1 GLOBAL]
    xor     r9d, 1
    movzx   r9d, word [cabac_entropy+r9*2 GLOBAL]
    mov [r5+r6], r4b
    add     r0d, r9d
; x264_cabac_encode_decision( cb, ctx_last + i, 0 );
    movzx   r9d, byte [r7+r6]
    movzx   r4d, byte [cabac_transition+r9*2 GLOBAL]
    movzx   r9d, word [cabac_entropy+r9*2 GLOBAL]
    mov [r7+r6], r4b
    add     r0d, r9d
    COEFF_ABS_LEVEL_GT1 coeff, 0
    dec     r6d
    jge .coeff_loop
.end:
    mov [r3+cb.bits_encoded-cb.state], r0d
    RET
%endmacro


; 4x4 blocks, avx512icl: the whole significance map at once. Each sig and
; last context is used at most once per 4x4 block, and the sig, last and
; level context ranges are disjoint, so the decisions are independent and
; only f8_bits (an integer sum) depends on their order.
%macro CABAC_RESIDUAL_RD_4x4_ICL 0
%ifdef PIC
    cglobal cabac_block_residual_rd_internal, 4,11,7,-16*SIZEOF_DCTCOEF
    lea     r10, [$$]
    %define GLOBAL +r10-$$
%else
    cglobal cabac_block_residual_rd_internal, 4,10,7,-16*SIZEOF_DCTCOEF
    %define GLOBAL
%endif
    RD_TMP_REGS 5, 7, 9                                       ; r5/r7 are free once the map is written
    %define dct rsp
    kmovw    k1, [rd_lanes_4x4+r2*2 GLOBAL]
%if HIGH_BIT_DEPTH
    vmovdqu32 zm0 {k1}{z}, [r0]
    vptestmd  k2, zm0, zm0
    vpabsd    zm0, zm0
    vmovdqu32 [rsp], zm0
%else
    vmovdqu16 ym0 {k1}{z}, [r0]
    vptestmw  k2, ym0, ym0
    vpabsw    ym0, ym0
    vmovdqu16 [rsp], ym0
%endif
    shl      r1d, 4                                           ; MB_INTERLACED*16
    add      r1d, r2d
    movzx    r5d, word [significant_coeff_flag_offset+r1*2 GLOBAL]    ; r5 = ctx_sig
    movzx    r7d, word [last_coeff_flag_offset+r1*2 GLOBAL]           ; r7 = ctx_last
    movzx    r8d, word [coeff_abs_level_m1_offset+r2*2 GLOBAL]        ; r8 = ctx_level
    movzx    r9d, byte [count_cat_m1+r2 GLOBAL]
    mov      r0d, [r3+cb.bits_encoded]                        ; r0 = cabac.f8_bits_encoded
    add       r3, cb.state
    add       r5, r3
    add       r7, r3
    add       r8, r3
    kmovd    r4d, k2                                          ; r4 = nonzero mask
    lzcnt    r6d, r4d
    xor      r6d, 31                                          ; r6 = last
; sig flags for i <= last, except last == count_m1
    cmp      r6d, r9d
    mov      r1d, r6d
    adc      r1d, 0
    mov      r9d, -1
    bzhi     r9d, r9d, r1d
; last flags for the nonzero ones among them
    mov      r1d, r4d
    and      r1d, r9d
    shl      r1d, 16
    or       r1d, r9d
    kmovd    k3, r1d                                          ; coded lanes: sig 0-15, last 16-31
; bins: sig = l[i] != 0, last = i == last
    lea      r1d, [r6+16]
    mov      r9d, r4d
    bts      r9d, r1d
    kmovd    k4, r9d
    vmovdqu8 xm1, [r5]
    vinserti32x4 ym1, ym1, [r7], 1                            ; states
    vpmovm2b ym2, k4
    vpternlogd ym2, ym1, [pb_1], 0x6c                         ; state^bin
    vmovdqu8 zm3, [rd_entropy_lo]
    vpermt2b zm3 {k3}{z}, zm2, [rd_entropy_lo+64]
    vmovdqu8 zm4, [rd_entropy_hi]
    vpermt2b zm4 {k3}{z}, zm2, [rd_entropy_hi+64]
    vmovdqu8 zm5, [rd_transition_xor]
    vpermt2b zm5, zm2, [rd_transition_xor+64]
    vpternlogd ym5, ym1, [pb_1], 0x78                         ; transition[state][bin]
    vmovdqu8 ym1 {k3}, ym5
    vmovdqu8 [r5], xm1
    vextracti32x4 [r7], ym1, 1
    vpxord   xm6, xm6, xm6
    vpsadbw  ym3, ym3, ym6
    vpsadbw  ym4, ym4, ym6
    vpsllq   ym4, ym4, 8
    vpaddq   ym3, ym3, ym4
    vextracti32x4 xm4, ym3, 1
    vpaddq   xm3, xm3, xm4
    vpsrldq  xm4, xm3, 8
    vpaddq   xm3, xm3, xm4
    vmovd    r1d, xm3
    add      r0d, r1d
; levels: last, then the other nonzero coefficients in descending order
    LOAD_DCTCOEF r1d
    COEFF_ABS_LEVEL_BF last, 1
    btr      r4d, r6d
    test     r4d, r4d
    jz .end
    RD_LOOP_HEAD .level_loop
    lzcnt    r6d, r4d
    xor      r6d, 31
    btr      r4d, r6d
    LOAD_DCTCOEF r1d
    COEFF_ABS_LEVEL_BF coeff, 0
    test     r4d, r4d
    jnz .level_loop
.end:
    mov [r3+cb.bits_encoded-cb.state], r0d
    RET
    COEFF_ABS_LEVEL_ESCAPE last, 1
    COEFF_ABS_LEVEL_ESCAPE coeff, 0
%endmacro

; abs() of the 64 coefficients of l (r0) to [rsp], nonzero mask to r9
%macro ABS_NZMASK_8x8 0
%if mmsize == 64
%if HIGH_BIT_DEPTH
    ABSD      m0, [r0+0*64]
    ABSD      m1, [r0+1*64]
    ABSD      m2, [r0+2*64]
    ABSD      m3, [r0+3*64]
    mova [rsp+0*64], m0
    mova [rsp+1*64], m1
    mova [rsp+2*64], m2
    mova [rsp+3*64], m3
    vptestmd  k0, m0, m0
    vptestmd  k1, m1, m1
    vptestmd  k2, m2, m2
    vptestmd  k3, m3, m3
    kunpckwd  k0, k1, k0
    kunpckwd  k1, k3, k2
    kunpckdq  k0, k1, k0
%else
    ABSW      m0, [r0+0*64]
    ABSW      m1, [r0+1*64]
    mova [rsp+0*64], m0
    mova [rsp+1*64], m1
    vptestmw  k0, m0, m0
    vptestmw  k1, m1, m1
    kunpckdq  k0, k1, k0
%endif
    kmovq     r9, k0
%else
%assign %%g 0
%rep 4
%if HIGH_BIT_DEPTH
    ABSD      m0, [r0+(4*%%g+0)*16], m4
    ABSD      m1, [r0+(4*%%g+1)*16], m5
    ABSD      m2, [r0+(4*%%g+2)*16], m4
    ABSD      m3, [r0+(4*%%g+3)*16], m5
    mova [rsp+(4*%%g+0)*16], m0
    mova [rsp+(4*%%g+1)*16], m1
    mova [rsp+(4*%%g+2)*16], m2
    mova [rsp+(4*%%g+3)*16], m3
    packssdw  m0, m1
    packssdw  m2, m3
    packsswb  m0, m2
%else
    ABSW      m0, [r0+(2*%%g+0)*16], m2
    ABSW      m1, [r0+(2*%%g+1)*16], m3
    mova [rsp+(2*%%g+0)*16], m0
    mova [rsp+(2*%%g+1)*16], m1
    packsswb  m0, m1
%endif
    pxor      m1, m1
    pcmpeqb   m0, m1
%if %%g == 0
    pmovmskb r9d, m0
%else
    pmovmskb r10d, m0
    shl      r10, 16*%%g
    or        r9, r10
%endif
%assign %%g %%g+1
%endrep
    not       r9                                              ; bit i = l[i] != 0
%endif
%endmacro

; 8x8 blocks. Sig and last contexts repeat within a block, so each kind of
; decision keeps the descending order of the C code: the sig pass codes
; every i < last downwards without a branch on l[i], then the nonzero ones
; below last are visited downwards for their last flag and level. The sig,
; last and level context ranges are disjoint, so this matches the
; interleaved order, and f8_bits is an integer sum.
%macro CABAC_RESIDUAL_RD_8x8 0
    %define dct rsp
    %assign rd8_stack 64*SIZEOF_DCTCOEF+mmsize ; abs() copy, cb
    %define cbm [rsp+64*SIZEOF_DCTCOEF]
%ifdef PIC
    cglobal cabac_block_residual_8x8_rd_internal, 4,12,6,-rd8_stack
    lea     r11, [$$]
    %define GLOBAL +r11-$$
%else
    cglobal cabac_block_residual_8x8_rd_internal, 4,11,6,-rd8_stack
    %define GLOBAL
%endif
    ABS_NZMASK_8x8
%if cpuflag(lzcnt)
    lzcnt     r6, r9
    xor      r6d, 63
%else
    bsr       r6, r9                                          ; r6 = last
%endif
    shl      r1d, 4                                           ; MB_INTERLACED*16
    lea       r4, [significant_coeff_flag_offset_8x8+r1*4 GLOBAL]    ; r4 = sig offset 8x8
    add      r1d, r2d
    movzx    r5d, word [significant_coeff_flag_offset+r1*2 GLOBAL]    ; r5 = ctx_sig
    movzx    r7d, word [last_coeff_flag_offset+r1*2 GLOBAL]           ; r7 = ctx_last
    movzx    r8d, word [coeff_abs_level_m1_offset+r2*2 GLOBAL]        ; r8 = ctx_level
    mov      r0d, [r3+cb.bits_encoded]                        ; r0 = cabac.f8_bits_encoded
    mov      cbm, r3
    add       r3, cb.state
    add       r5, r3
    add       r7, r3
    add       r8, r3                                          ; precalculate cabac state pointers

; if( last != 63 )
    cmp      r6d, 63
    je .skip_last_sigmap
; x264_cabac_encode_decision( cb, ctx_sig + sig_off[last], 1 )
; x264_cabac_encode_decision( cb, ctx_last + last_off[last], 1 )
    movzx    r1d, byte [r4+r6]
    movzx    r2d, byte [r5+r1]
    movzx   r10d, byte [cabac_transition+1+r2*2 GLOBAL]
    xor      r2d, 1
    movzx    r2d, word [cabac_entropy+r2*2 GLOBAL]
    mov [r5+r1], r10b
    add      r0d, r2d
    movzx    r1d, byte [last_coeff_flag_offset_8x8+r6 GLOBAL]
    movzx    r2d, byte [r7+r1]
    movzx   r10d, byte [cabac_transition+1+r2*2 GLOBAL]
    xor      r2d, 1
    movzx    r2d, word [cabac_entropy+r2*2 GLOBAL]
    mov [r7+r1], r10b
    add      r0d, r2d
.skip_last_sigmap:
; for( int i = last-1 ; i >= 0; i-- ) x264_cabac_encode_decision( cb, ctx_sig + sig_off[i], !!l[i] )
    mov      r1d, r6d
    dec      r1d
    jl .sig_end
    RD_LOOP_HEAD .sig_loop
    movzx    r2d, byte [r4+r1]
    movzx    r3d, byte [r5+r2]
    bt        r9, r1
    adc      r3d, r3d                                         ; 2*state+bin
    movzx   r10d, byte [cabac_transition+r3 GLOBAL]
    movzx    r3d, word [rd_entropy_sb+r3*2 GLOBAL]
    mov [r5+r2], r10b
    add      r0d, r3d
    dec      r1d
    jge .sig_loop
.sig_end:
    RD_TMP_REGS 4, 5, 3
    LOAD_DCTCOEF r1d
    COEFF_ABS_LEVEL_BF last, 1
    btr       r9, r6
    test      r9, r9
    jz .end
; the nonzero coefficients below last, descending
    RD_LOOP_HEAD .coeff_loop
%if cpuflag(lzcnt)
    lzcnt     r6, r9
    xor      r6d, 63
%else
    bsr       r6, r9
%endif
    btr       r9, r6
; x264_cabac_encode_decision( cb, ctx_last + last_off[i], 0 )
    movzx    r4d, byte [last_coeff_flag_offset_8x8+r6 GLOBAL]
    movzx    r5d, byte [r7+r4]
    movzx   r10d, byte [cabac_transition+r5*2 GLOBAL]
    movzx    r5d, word [cabac_entropy+r5*2 GLOBAL]
    mov [r7+r4], r10b
    add      r0d, r5d
    LOAD_DCTCOEF r1d
    COEFF_ABS_LEVEL_BF coeff, 0
    test      r9, r9
    jnz .coeff_loop
.end:
    mov       r3, cbm
    mov [r3+cb.bits_encoded], r0d
    RET
    COEFF_ABS_LEVEL_ESCAPE last, 1
    COEFF_ABS_LEVEL_ESCAPE coeff, 0
%endmacro

%if ARCH_X86_64
INIT_XMM sse2
CABAC_RESIDUAL_RD_4x4
CABAC_RESIDUAL_RD_8x8
INIT_XMM sse2,lzcnt
CABAC_RESIDUAL_RD_4x4
CABAC_RESIDUAL_RD_8x8
INIT_XMM ssse3
CABAC_RESIDUAL_RD_4x4
CABAC_RESIDUAL_RD_8x8
INIT_XMM ssse3,lzcnt
CABAC_RESIDUAL_RD_4x4
CABAC_RESIDUAL_RD_8x8
INIT_ZMM avx512
CABAC_RESIDUAL_RD_8x8
INIT_ZMM avx512icl
CABAC_RESIDUAL_RD_4x4_ICL
%endif

;-----------------------------------------------------------------------------
; void x264_cabac_block_residual_internal_sse2 ( dctcoef *l, int b_interlaced,
;                                                int ctx_block_cat, x264_cabac_t *cb );
;-----------------------------------------------------------------------------

%macro CALL_CABAC 0
    call cabac_encode_decision_asm
%if WIN64 ; move cabac back
    mov r0, r3
%endif
%endmacro

; %1 = 8x8 mode
; %2 = dct register
; %3 = countcat
; %4 = name
%macro SIGMAP_LOOP 3-4
.sigmap_%4loop:
%if HIGH_BIT_DEPTH
    mov      %2, [dct+r10*4]
%else
    movsx    %2, word [dct+r10*2]
%endif
%if %1
    movzx   r1d, byte [sigoff_8x8 + r10]
    add     r1d, sigoffd
%else
    lea     r1d, [sigoffd + r10d]
%endif
    test     %2, %2
    jz .sigmap_%4zero               ; if( l[i] )
    inc coeffidxd
    mov [coeffs+coeffidxq*4], %2    ; coeffs[++coeff_idx] = l[i];
    mov     r2d, 1
    CALL_CABAC                      ; x264_cabac_encode_decision( cb, ctx_sig + sig_off, 1 );
%if %1
    movzx   r1d, byte [last_coeff_flag_offset_8x8 + r10 GLOBAL]
    add     r1d, lastoffd
%else
    lea     r1d, [lastoffd + r10d]
%endif
    cmp    r10d, lastm              ; if( i == last )
    je .sigmap_%4last
    xor     r2d, r2d
    CALL_CABAC                      ; x264_cabac_encode_decision( cb, ctx_last + last_off, 0 );
    jmp .sigmap_%4loop_endcheck
.sigmap_%4zero:
    xor     r2d, r2d
    CALL_CABAC                      ; x264_cabac_encode_decision( cb, ctx_sig + sig_off, 0 );
.sigmap_%4loop_endcheck:
    inc    r10d
    cmp    r10d, %3
    jne .sigmap_%4loop              ; if( ++i == count_m1 )
%if HIGH_BIT_DEPTH
    mov      %2, [dct+r10*4]
%else
    movsx    %2, word [dct+r10*2]
%endif
    inc coeffidxd
    mov [coeffs+coeffidxq*4], %2    ; coeffs[++coeff_idx] = l[i]
    jmp .sigmap_%4end
.sigmap_%4last:                     ; x264_cabac_encode_decision( cb, ctx_last + last_off, 1 );
    mov     r2d, 1
    CALL_CABAC
.sigmap_%4end:
%if %1==0
    jmp .level_loop_start
%endif
%endmacro

%macro CABAC_RESIDUAL 1
cglobal cabac_block_residual_internal, 4,15,0,-4*64
%ifdef PIC
; if we use the same r7 as in cabac_encode_decision, we can cheat and save a register.
    lea     r7, [$$]
    %define lastm [rsp+4*1]
    %define GLOBAL +r7-$$
%else
    %define lastm r7d
    %define GLOBAL
%endif
    shl     r1d, 4

    %define sigoffq r8
    %define sigoffd r8d
    %define lastoffq r9
    %define lastoffd r9d
    %define leveloffq r10
    %define leveloffd r10d
    %define leveloffm [rsp+4*0]
    %define countcatd r11d
    %define sigoff_8x8 r12
    %define coeffidxq r13
    %define coeffidxd r13d
    %define dct r14
    %define coeffs rsp+4*2

    lea sigoff_8x8, [significant_coeff_flag_offset_8x8+r1*4 GLOBAL]
    add     r1d, r2d
    movzx sigoffd, word [significant_coeff_flag_offset+r1*2 GLOBAL]
    movzx lastoffd, word [last_coeff_flag_offset+r1*2 GLOBAL]
    movzx leveloffd, word [coeff_abs_level_m1_offset+r2*2 GLOBAL]
    movzx countcatd, byte [count_cat_m1+r2 GLOBAL]
    mov coeffidxd, -1
    mov     dct, r0
    mov leveloffm, leveloffd

    call [%1+gprsize*r2 GLOBAL]
    mov   lastm, eax
; put cabac in r0; needed for cabac_encode_decision
    mov      r0, r3

    xor    r10d, r10d
    cmp countcatd, 63
    je .sigmap_8x8
    SIGMAP_LOOP 0, r12d, countcatd,
.sigmap_8x8:
    SIGMAP_LOOP 1, r11d, 63, _8x8
.level_loop_start:
; we now have r8, r9, r11, r12, and r7/r14(dct) free for the main loop.
    %define nodectxq r8
    %define nodectxd r8d
    mov leveloffd, leveloffm
    xor nodectxd, nodectxd
.level_loop:
    mov     r9d, [coeffs+coeffidxq*4]
    mov    r11d, r9d
    sar    r11d, 31
    add     r9d, r11d
    movzx   r1d, byte [coeff_abs_level1_ctx+nodectxq GLOBAL]
    xor     r9d, r11d
    add     r1d, leveloffd
    cmp     r9d, 1
    jg .level_gt1
    xor     r2d, r2d
    CALL_CABAC
    movzx nodectxd, byte [coeff_abs_level_transition+nodectxq GLOBAL]
    jmp .level_sign
.level_gt1:
    mov     r2d, 1
    CALL_CABAC
    movzx  r14d, byte [coeff_abs_levelgt1_ctx+nodectxq GLOBAL]
    add    r14d, leveloffd
    cmp     r9d, 15
    mov    r12d, 15
    cmovl  r12d, r9d
    sub    r12d, 2
    jz .level_eq2
.level_gt1_loop:
    mov     r1d, r14d
    mov     r2d, 1
    CALL_CABAC
    dec    r12d
    jg .level_gt1_loop
    cmp     r9d, 15
    jge .level_bypass
.level_eq2:
    mov     r1d, r14d
    xor     r2d, r2d
    CALL_CABAC
    jmp .level_gt1_end
.level_bypass:
    lea     r2d, [r9d-15]
    xor     r1d, r1d
    push     r0
; we could avoid this if we implemented it in asm, but I don't feel like that
; right now.
%if UNIX64
    push     r7
    push     r8
%else
    sub      rsp, 32 ; shadow space
%endif
    call cabac_encode_ue_bypass
%if UNIX64
    pop      r8
    pop      r7
%else
    add      rsp, 32
%endif
    pop      r0
.level_gt1_end:
    movzx nodectxd, byte [coeff_abs_level_transition+8+nodectxq GLOBAL]
.level_sign:
    mov     r1d, r11d
    call cabac_encode_bypass_asm
%if WIN64
    mov      r0, r3
%endif
    dec coeffidxd
    jge .level_loop
    RET
%endmacro

;-----------------------------------------------------------------------------
; BMI2: low/range/queue stay in r8-r10 for the whole block; decision,
; bypass and putbyte are inlined.
;-----------------------------------------------------------------------------

; in: flags from the queue update; clobbers r1, r4-r6
; the no-flush path falls through, the flush is a per-site stub after RET
%macro PUTBYTE 0
    jge .pb %+ pb_count
.pbr %+ pb_count:
    %assign pb_count pb_count+1
%endmacro

; one stub per site: no 0xff byte and nothing outstanding inline, else .putbyte_slow
%macro PUTBYTE_STUBS 0
%assign pb_i 0
%rep pb_count
.pb %+ pb_i:
    lea     r4d, [queueq+10]
    shrx    r1d, lowd, r4d          ; out
    bzhi   lowd, lowd, r4d
    sub  queued, 8
    mov      r6, cbm
    cmp     r1b, 0xff
    je .pbs %+ pb_i
    cmp dword [r6+cb.bytes_outstanding], 0
    jne .pbs %+ pb_i
    mov      r5, [r6+cb.p]
    rorx    r4d, r1d, 8             ; carry
    add  [r5-1], r4b
    mov    [r5], r1b
    inc      r5
    mov [r6+cb.p], r5
    jmp .pbr %+ pb_i
.pbs %+ pb_i:
    call .putbyte_slow
    jmp .pbr %+ pb_i
%assign pb_i pb_i+1
%endrep
%endmacro

; %1 = bin, %2 = state address (else the state is in r2d)
; in: r2d = state if no %2; out: r2d = next state
; clobbers r1, r4-r6
%macro CABAC_BIN 1-2
%if %0 > 1
    movzx   r2d, byte [%2]
%endif
    mov     r4d, ranged
    mov     r5d, r2d
    shr     r4d, 6
    and     r5d, ~1
%ifdef PIC
    lea      r5, [r7+r5*2]
    movzx   r4d, byte [r5+r4+cabac_range_lps-4-$$]
%else
    movzx   r4d, byte [cabac_range_lps-4+r4+r5*2]
%endif
    sub  ranged, r4d
    lea     r6d, [lowq+rangeq]
    test    r2b, 1
%if %1
    cmovz  ranged, r4d
    cmovz    lowd, r6d
%else
    cmovnz ranged, r4d
    cmovnz   lowd, r6d
%endif
    movzx   r2d, byte [cabac_transition+%1+r2*2 GLOBAL]
%if %0 > 1
    mov    [%2], r2b
%endif
    lzcnt   r5d, ranged
    sub     r5d, 23
    shlx ranged, ranged, r5d
    shlx   lowd, lowd, r5d
    add  queued, r5d
    PUTBYTE
%endmacro

; %1 = 8x8 mode, %2 = count_m1
%macro SIGMAP_BMI2 2
%%loop:
%if HIGH_BIT_DEPTH
    mov     r1d, [r14+r12*4]
%else
    movsx   r1d, word [r14+r12*2]
%endif
    test    r1d, r1d
    jz %%zero                       ; if( l[i] )
    inc     r13d
    mov [coeffs+r13*4], r1d         ; coeffs[++coeff_idx] = l[i];
%if %1
    movzx   r1d, byte [r0+r12]
    CABAC_BIN 1, r3+r1              ; ctx_sig + sig_off, 1
    movzx   r1d, byte [last_coeff_flag_offset_8x8+r12 GLOBAL]
    %define sm_last r11+r1
%else
    CABAC_BIN 1, r3+r12
    %define sm_last r11+r12
%endif
    cmp     r12d, lastm             ; if( i == last )
    je %%is_last
    CABAC_BIN 0, sm_last            ; ctx_last + last_off, 0
    jmp %%next
%%zero:
%if %1
    movzx   r1d, byte [r0+r12]
    CABAC_BIN 0, r3+r1              ; ctx_sig + sig_off, 0
%else
    CABAC_BIN 0, r3+r12
%endif
%%next:
    inc     r12d
    cmp     r12d, %2
    jne %%loop                      ; if( ++i == count_m1 )
%if HIGH_BIT_DEPTH
    mov     r1d, [r14+r12*4]
%else
    movsx   r1d, word [r14+r12*2]
%endif
    inc     r13d
    mov [coeffs+r13*4], r1d         ; coeffs[++coeff_idx] = l[i]
    jmp .level_loop_start
%%is_last:
    CABAC_BIN 1, sm_last            ; ctx_last + last_off, 1
%if %1 == 0
    jmp .level_loop_start
%endif
%endmacro

%macro CABAC_RESIDUAL_BMI2 1
cglobal cabac_block_residual_internal, 4,15,0,-4*72
%ifdef PIC
    lea      r7, [$$]
    %define GLOBAL +r7-$$
%else
    %define GLOBAL
%endif
    %define cbm    [rsp+0]
    %define levelm [rsp+8]
    %define lastm  [rsp+16]
    %define coeffs rsp+32
    %define lowd   r8d
    %define lowq   r8
    %define ranged r9d
    %define rangeq r9
    %define queued r10d
    %define queueq r10
    %assign pb_count 0

    shl     r1d, 4
    lea     r12, [significant_coeff_flag_offset_8x8+r1*4 GLOBAL]
    add     r1d, r2d
    movzx   r8d, word [significant_coeff_flag_offset+r1*2 GLOBAL]
    movzx   r9d, word [last_coeff_flag_offset+r1*2 GLOBAL]
    movzx  r10d, word [coeff_abs_level_m1_offset+r2*2 GLOBAL]
    movzx  r13d, byte [count_cat_m1+r2 GLOBAL]
    mov     cbm, r3
    mov     r14, r0                 ; dct
    add      r3, cb.state
    lea     r11, [r3+r9]            ; ctx_last state
    add     r10, r3
    mov  levelm, r10                ; ctx_level state
    add      r3, r8                 ; ctx_sig state
    call [%1+gprsize*r2 GLOBAL]     ; preserves r3, r7-r14
    mov   lastm, eax
    mov      r6, cbm
    mov    lowd, [r6+cb.low]
    mov  ranged, [r6+cb.range]
    mov  queued, [r6+cb.queue]
    cmp    r13d, 63
    je .sigmap_8x8
    mov     r0d, r13d
    mov    r13d, -1                 ; coeff_idx
    xor    r12d, r12d               ; i
    SIGMAP_BMI2 0, r0d
.sigmap_8x8:
    mov      r0, r12
    mov    r13d, -1
    xor    r12d, r12d
    SIGMAP_BMI2 1, 63
.level_loop_start:
    mov      r3, levelm
    xor    r12d, r12d               ; node_ctx
.level_loop:
    mov    r11d, [coeffs+r13*4]
    mov     r1d, r11d
    sar     r1d, 31
    add    r11d, r1d
    xor    r11d, r1d                ; abs_coeff
    movzx   r1d, byte [coeff_abs_level1_ctx+r12 GLOBAL]
    cmp    r11d, 1
    jg .level_gt1
    CABAC_BIN 0, r3+r1
    movzx  r12d, byte [coeff_abs_level_transition+r12 GLOBAL]
    jmp .level_sign
.level_gt1:
    CABAC_BIN 1, r3+r1
    movzx  r14d, byte [coeff_abs_levelgt1_ctx+r12 GLOBAL]
    movzx   r2d, byte [r3+r14]      ; state stays in r2d for the run
    mov     r0d, 15
    cmp    r11d, r0d
    cmovl   r0d, r11d
    sub     r0d, 2
    jz .level_eq2
.level_gt1_loop:
    CABAC_BIN 1
    dec     r0d
    jg .level_gt1_loop
    cmp    r11d, 15
    jge .level_bypass
.level_eq2:
    CABAC_BIN 0
    mov [r3+r14], r2b
    jmp .level_gt1_end
.level_bypass:
    mov [r3+r14], r2b
; x264_cabac_encode_ue_bypass( cb, 0, abs_coeff - 15 )
    lea     r0d, [r11-14]           ; v
    lzcnt  r11d, r0d
    xor    r11d, 31                 ; k
    lea    r14d, [r11*2+1]          ; bits left
    mov     r2d, 3
    shlx    r2d, r2d, r11d
    sub     r0d, r2d
    mov     r2d, 1
    shlx    r2d, r2d, r14d
    add     r2d, r0d                ; x = v + bypass_lut[k]
    lea    r11d, [r14-1]
    and    r11d, 7
    inc    r11d                     ; i
.ue_loop:
    sub    r14d, r11d
    shrx    r1d, r2d, r14d
    movzx   r1d, r1b
    imul    r1d, ranged
    shlx   lowd, lowd, r11d
    add    lowd, r1d
    add  queued, r11d
    PUTBYTE
    mov    r11d, 8
    test   r14d, r14d
    jg .ue_loop
.level_gt1_end:
    movzx  r12d, byte [coeff_abs_level_transition+8+r12 GLOBAL]
.level_sign:
; x264_cabac_encode_bypass( cb, coeff_sign )
    mov     r1d, [coeffs+r13*4]
    sar     r1d, 31
    and     r1d, ranged
    lea    lowd, [lowq*2+r1]
    inc  queued
    PUTBYTE
    dec    r13d
    jge .level_loop
    mov      r6, cbm
    mov [r6+cb.low], lowd
    mov [r6+cb.range], ranged
    mov [r6+cb.queue], queued
    RET

; in: r1d = out, r6 = cb; clobbers r4-r6
.putbyte_slow:
    cmp     r1b, 0xff
    je .postpone
    mov     r4d, [r6+cb.bytes_outstanding]
    mov      r5, [r6+cb.p]
    mov     r6d, r1d
    shr     r6d, 8                  ; carry
    add  [r5-1], r6b
    dec     r6d
.loop_outstanding:
    mov    [r5], r6b
    inc      r5
    dec     r4d
    jge .loop_outstanding
    mov  [r5-1], r1b
    mov      r6, [rsp+gprsize]
    mov [r6+cb.p], r5
    mov dword [r6+cb.bytes_outstanding], 0
    ret
.postpone:
    inc dword [r6+cb.bytes_outstanding]
    ret

    PUTBYTE_STUBS
%endmacro

%if ARCH_X86_64
INIT_XMM sse2
CABAC_RESIDUAL coeff_last_sse2
INIT_XMM sse2,lzcnt
CABAC_RESIDUAL coeff_last_sse2_lzcnt
INIT_XMM avx2,bmi2
CABAC_RESIDUAL_BMI2 coeff_last_avx2_lzcnt
INIT_XMM avx512
CABAC_RESIDUAL_BMI2 coeff_last_avx512
%endif
