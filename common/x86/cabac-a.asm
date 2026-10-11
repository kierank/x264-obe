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

SECTION_RODATA

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

; CABAC_RESIDUAL reuses the r7 = $$ PIC base set by cabac_encode_decision_asm:
; with --enable-func-sections they must share its section
%xdefine function_section mangle(private_prefix %+ _cabac_encode_decision_asm)
CABAC asm
%undef function_section
CABAC bmi2

; %1 = label name
; %2 = node_ctx init?
%macro COEFF_ABS_LEVEL_GT1 2
%if %2
    %define ctx 1
%else
    movzx  r11d, byte [coeff_abs_level1_ctx+r2 GLOBAL]
    %define ctx r11
%endif
    movzx   r9d, byte [r8+ctx]
; if( coeff_abs > 1 )
    cmp     r1d, 1
    jg .%1_gt1
; x264_cabac_encode_decision( cb, ctx_level+ctx, 0 )
    movzx  r10d, byte [cabac_transition+r9*2 GLOBAL]
    movzx   r9d, word [cabac_entropy+r9*2 GLOBAL]
    lea     r0d, [r0+r9+256]
    mov [r8+ctx], r10b
%if %2
    mov     r2d, 1
%else
    movzx   r2d, byte [coeff_abs_level_transition+r2 GLOBAL]
%endif
    jmp .%1_end

.%1_gt1:
; x264_cabac_encode_decision( cb, ctx_level+ctx, 1 )
    movzx  r10d, byte [cabac_transition+r9*2+1 GLOBAL]
    xor     r9d, 1
    movzx   r9d, word [cabac_entropy+r9*2 GLOBAL]
    mov [r8+ctx], r10b
    add     r0d, r9d
%if %2
    %define ctx 5
%else
    movzx  r11d, byte [coeff_abs_levelgt1_ctx+r2 GLOBAL]
    %define ctx r11
%endif
; if( coeff_abs < 15 )
    cmp     r1d, 15
    jge .%1_escape
    shl     r1d, 7
; x264_cabac_transition_unary[coeff_abs-1][cb->state[ctx_level+ctx]]
    movzx   r9d, byte [r8+ctx]
    add     r9d, r1d
    movzx  r10d, byte [cabac_transition_unary-128+r9 GLOBAL]
; x264_cabac_size_unary[coeff_abs-1][cb->state[ctx_level+ctx]]
    movzx   r9d, word [cabac_size_unary-256+r9*2 GLOBAL]
    mov [r8+ctx], r10b
    add     r0d, r9d
    jmp .%1_gt1_end

.%1_escape:
; x264_cabac_transition_unary[14][cb->state[ctx_level+ctx]]
    movzx   r9d, byte [r8+ctx]
    movzx  r10d, byte [cabac_transition_unary+128*14+r9 GLOBAL]
; x264_cabac_size_unary[14][cb->state[ctx_level+ctx]]
    movzx   r9d, word [cabac_size_unary+256*14+r9*2 GLOBAL]
    add     r0d, r9d
    mov [r8+ctx], r10b
    sub     r1d, 14
%if cpuflag(lzcnt)
    lzcnt   r9d, r1d
    xor     r9d, 0x1f
%else
    bsr     r9d, r1d
%endif
; bs_size_ue_big(coeff_abs-15)<<8
    shl     r9d, 9
; (ilog2(coeff_abs-14)+1) << 8
    lea     r0d, [r0+r9+256]
.%1_gt1_end:
%if %2
    mov     r2d, 4
%else
    movzx   r2d, byte [coeff_abs_level_transition+8+r2 GLOBAL]
%endif
.%1_end:
%endmacro

%macro LOAD_DCTCOEF 1
%if HIGH_BIT_DEPTH
    mov     %1, [dct+r6*4]
%else
    movzx   %1, word [dct+r6*2]
%endif
%endmacro

%macro ABS_DCTCOEFS 2
%if HIGH_BIT_DEPTH
    %define %%abs ABSD
%else
    %define %%abs ABSW
%endif
%if mmsize == %2*SIZEOF_DCTCOEF
    %%abs   m0, [%1], m1
    mova [rsp], m0
%elif mmsize == %2*SIZEOF_DCTCOEF/2
    %%abs   m0, [%1+0*mmsize], m2
    %%abs   m1, [%1+1*mmsize], m3
    mova [rsp+0*mmsize], m0
    mova [rsp+1*mmsize], m1
%else
%assign i 0
%rep %2*SIZEOF_DCTCOEF/(4*mmsize)
    %%abs  m0, [%1+(4*i+0)*mmsize], m4
    %%abs  m1, [%1+(4*i+1)*mmsize], m5
    %%abs  m2, [%1+(4*i+2)*mmsize], m4
    %%abs  m3, [%1+(4*i+3)*mmsize], m5
    mova [rsp+(4*i+0)*mmsize], m0
    mova [rsp+(4*i+1)*mmsize], m1
    mova [rsp+(4*i+2)*mmsize], m2
    mova [rsp+(4*i+3)*mmsize], m3
%assign i i+1
%endrep
%endif
%endmacro

%macro SIG_OFFSET 1
%if %1
    movzx  r11d, byte [r4+r6]
%endif
%endmacro

%macro LAST_OFFSET 1
%if %1
    movzx  r11d, byte [last_coeff_flag_offset_8x8+r6 GLOBAL]
%endif
%endmacro

;-----------------------------------------------------------------------------
; void x264_cabac_block_residual_rd_internal_sse2 ( dctcoef *l, int b_interlaced,
;                                                   int ctx_block_cat, x264_cabac_t *cb );
;-----------------------------------------------------------------------------

;%1 = 8x8 mode
%macro CABAC_RESIDUAL_RD 2
%if %1
    %define func cabac_block_residual_8x8_rd_internal
    %define maxcoeffs 64
    %define dct rsp
%else
    %define func cabac_block_residual_rd_internal
    %define maxcoeffs 16
    %define dct r4
%endif

%ifdef PIC
    cglobal func, 4,13,6,-maxcoeffs*SIZEOF_DCTCOEF
    lea     r12, [$$]
    %define GLOBAL +r12-$$
%else
    cglobal func, 4,12,6,-maxcoeffs*SIZEOF_DCTCOEF
    %define GLOBAL
%endif

    shl     r1d, 4                                            ; MB_INTERLACED*16
%if %1
    lea      r4, [significant_coeff_flag_offset_8x8+r1*4 GLOBAL]     ; r12 = sig offset 8x8
%endif
    add     r1d, r2d
    movzx   r5d, word [significant_coeff_flag_offset+r1*2 GLOBAL]    ; r5 = ctx_sig
    movzx   r7d, word [last_coeff_flag_offset+r1*2 GLOBAL]           ; r7 = ctx_last
    movzx   r8d, word [coeff_abs_level_m1_offset+r2*2 GLOBAL]        ; r8 = ctx_level

; abs() all the coefficients; copy them to the stack to avoid
; changing the originals.
; overreading is okay; it's all valid aligned data anyways.
%if %1
    ABS_DCTCOEFS r0, 64
%else
    mov      r4, r0                                           ; r4 = dct
    and      r4, ~SIZEOF_DCTCOEF                              ; handle AC coefficient case
    ABS_DCTCOEFS r4, 16
    xor      r4, r0                                           ; calculate our new dct pointer
    add      r4, rsp                                          ; restore AC coefficient offset
%endif
; for improved OOE performance, run coeff_last on the original coefficients.
    call [%2+gprsize*r2 GLOBAL]                               ; coeff_last[ctx_block_cat]( dct )
; we know on 64-bit that the SSE2 versions of this function only
; overwrite r0, r1, and rax (r6). last64 overwrites r2 too, but we
; don't need r2 in 8x8 mode.
    mov     r0d, [r3+cb.bits_encoded]                         ; r0 = cabac.f8_bits_encoded
; pre-add some values to simplify addressing
    add      r3, cb.state
    add      r5, r3
    add      r7, r3
    add      r8, r3                                           ; precalculate cabac state pointers

; if( last != count_cat_m1[ctx_block_cat] )
%if %1
    cmp     r6b, 63
%else
    cmp     r6b, [count_cat_m1+r2 GLOBAL]
%endif
    je .skip_last_sigmap

; in 8x8 mode we have to do a bit of extra calculation for ctx_sig/last,
; so we'll use r11 for this.
%if %1
    %define siglast_ctx r11
%else
    %define siglast_ctx r6
%endif

; x264_cabac_encode_decision( cb, ctx_sig + last, 1 )
; x264_cabac_encode_decision( cb, ctx_last + last, 1 )
    SIG_OFFSET %1
    movzx   r1d, byte [r5+siglast_ctx]
    movzx   r9d, byte [cabac_transition+1+r1*2 GLOBAL]
    xor     r1d, 1
    movzx   r1d, word [cabac_entropy+r1*2 GLOBAL]
    mov [r5+siglast_ctx], r9b
    add     r0d, r1d

    LAST_OFFSET %1
    movzx   r1d, byte [r7+siglast_ctx]
    movzx   r9d, byte [cabac_transition+1+r1*2 GLOBAL]
    xor     r1d, 1
    movzx   r1d, word [cabac_entropy+r1*2 GLOBAL]
    mov [r7+siglast_ctx], r9b
    add     r0d, r1d
.skip_last_sigmap:
    LOAD_DCTCOEF r1d
    COEFF_ABS_LEVEL_GT1 last, 1
; for( int i = last-1 ; i >= 0; i-- )
    dec     r6d
    jl .end
.coeff_loop:
    LOAD_DCTCOEF r1d
; if( l[i] )
    SIG_OFFSET %1
    movzx   r9d, byte [r5+siglast_ctx]
    test    r1d, r1d
    jnz .coeff_nonzero
; x264_cabac_encode_decision( cb, ctx_sig + i, 0 )
    movzx  r10d, byte [cabac_transition+r9*2 GLOBAL]
    movzx   r9d, word [cabac_entropy+r9*2 GLOBAL]
    mov [r5+siglast_ctx], r10b
    add     r0d, r9d
    dec     r6d
    jge .coeff_loop
    jmp .end
.coeff_nonzero:
; x264_cabac_encode_decision( cb, ctx_sig + i, 1 )
    movzx  r10d, byte [cabac_transition+r9*2+1 GLOBAL]
    xor     r9d, 1
    movzx   r9d, word [cabac_entropy+r9*2 GLOBAL]
    mov [r5+siglast_ctx], r10b
    add     r0d, r9d
; x264_cabac_encode_decision( cb, ctx_last + i, 0 );
    LAST_OFFSET %1
    movzx   r9d, byte [r7+siglast_ctx]
    movzx  r10d, byte [cabac_transition+r9*2 GLOBAL]
    movzx   r9d, word [cabac_entropy+r9*2 GLOBAL]
    mov [r7+siglast_ctx], r10b
    add     r0d, r9d
    COEFF_ABS_LEVEL_GT1 coeff, 0
    dec     r6d
    jge .coeff_loop
.end:
    mov [r3+cb.bits_encoded-cb.state], r0d
    RET
%endmacro

%if ARCH_X86_64
INIT_XMM sse2
CABAC_RESIDUAL_RD 0, coeff_last_sse2
CABAC_RESIDUAL_RD 1, coeff_last_sse2
INIT_XMM sse2,lzcnt
CABAC_RESIDUAL_RD 0, coeff_last_sse2_lzcnt
CABAC_RESIDUAL_RD 1, coeff_last_sse2_lzcnt
INIT_XMM ssse3
CABAC_RESIDUAL_RD 0, coeff_last_sse2
CABAC_RESIDUAL_RD 1, coeff_last_sse2
INIT_XMM ssse3,lzcnt
CABAC_RESIDUAL_RD 0, coeff_last_sse2_lzcnt
CABAC_RESIDUAL_RD 1, coeff_last_sse2_lzcnt
%if HIGH_BIT_DEPTH
INIT_ZMM avx512
%else
INIT_YMM avx512
%endif
CABAC_RESIDUAL_RD 0, coeff_last_avx512
INIT_ZMM avx512
CABAC_RESIDUAL_RD 1, coeff_last_avx512
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
%xdefine function_section mangle(private_prefix %+ _cabac_encode_decision_asm)
INIT_XMM sse2
CABAC_RESIDUAL coeff_last_sse2
INIT_XMM sse2,lzcnt
CABAC_RESIDUAL coeff_last_sse2_lzcnt
%undef function_section
INIT_XMM avx2,bmi2
CABAC_RESIDUAL_BMI2 coeff_last_avx2_lzcnt
INIT_XMM avx512
CABAC_RESIDUAL_BMI2 coeff_last_avx512
%endif
