;*****************************************************************************
;* me-64.asm: x86_64 motion estimation control
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

%if UNIX64

SECTION_RODATA 64

; me.c's hex2, square1 (dx, dy bytes) and mod6m1
me_hex2:     db -1,-2, -2,0, -1,2, 1,2, 2,0, 1,-2, -1,-2, -2,0
me_square1:  db 0,0, 0,-1, 0,1, -1,0, 1,0, -1,-1, -1,1, 1,-1, 1,1
me_mod6m1:   db 5,0,1,2,3,4,5,0
; x264_hpel_ref0, x264_hpel_ref1
me_hpel_ref: db 0,1,1,1,0,1,1,1,2,3,3,3,0,1,1,1
             db 0,0,1,0,2,2,3,2,2,2,3,2,2,2,3,2

; avx512: the mv costs of candidates by vpermi2w from two windows of cost words,
; cost_mvx[4*(bmx-2)..] and cost_mvy[4*(bmy-2)..]; word (d+2)*4 is offset d, the
; second window's words follow the first's (ymm: 16, zmm: 32); ymm moves d = 2 to word 1
me_pw_2:     times 32 dw 2
me_pd_ffff:  times 16 dd 0xffff
me_pw_8:     times 8 dw 8
me_pw_15:    times 8 dw 15
me_wsel16:   times 4 dw 0,16
me_wsel32:   times 4 dw 0,32
me_pd_0123:  dd 0,1,2,3
me_d30:      dd 1<<30
; the square's sq_bias lanes: (dx+2)*4, (dy+2)*4 + window, and the codes
me_sqidx16:  dw 4,20, 8,20, 12,20, 0,16,  4,28, 8,28, 12,28, 0,16
             dw 4,24, 0,16, 12,24, 0,16,  0,16, 0,16, 0,16, 0,16
me_sqidx32:  dw 4,36, 8,36, 12,36, 0,32,  4,44, 8,44, 12,44, 0,32
             dw 4,40, 0,32, 12,40, 0,32,  0,32, 0,32, 0,32, 0,32
me_sqcode:   dd 5,1,7,0, 6,2,8,0, 3,0,4,0, 0,0,0,0

SECTION .text

%if HIGH_BIT_DEPTH == 0
cextern pixel_sad_hex_search_8x8_avx512
cextern pixel_sad_hex_search_reg_8x8_avx512
%endif

%define pointer resq

; x264_me_t (encoder/me.h)
struc me_t
    .i_pixel:     resd 1
    alignb 8
    .p_cost_mv:   pointer 1
    .i_ref_cost:  resd 1
    .i_ref:       resd 1
    .weight:      pointer 1
    .p_fref:      pointer 12
    .p_fref_w:    pointer 1
    .p_fenc:      pointer 3
    .integral:    pointer 1
    .i_stride:    resd 3
    .i_fld_uv_y:  resd 1
    .mvp:         resw 2
    .cost_mv:     resd 1
    .cost:        resd 1
    .mv:          resw 2
    alignb 64
endstruc

; x264_me_fpel_t (encoder/me.h)
struc me_fpel
    .m:              pointer 1
    .mvc:            pointer 1
    .halfpel_thresh: pointer 1
    .fn:             pointer 1
    .qfenc:          pointer 1
    .mv_limit:       pointer 1
    .range:          resq 1
    .i_mvc:          resd 1
    .me_range:       resd 1
    .iters:          resd 1
    .flags:          resd 1
endstruc

; x264_me_fpel_fn_t (common/pixel.h)
struc me_fpel_fn
    .sad:            pointer 1
    .sad_avg2:       pointer 1
    .x3_min:         pointer 1
    .x4_min:         pointer 1
    .sq_min:         pointer 1
    .hex_min:        pointer 1
    .hex_search:     pointer 1
    .predictor_clip: pointer 1
    .subpel:         pointer 1
    .qpel:           pointer 1
endstruc

%define ME_FPEL_SUBME3 1
%define ME_FPEL_ZEXIT  2
%define ME_FPEL_REFINE 4
%define PREDICTOR_DEDUPE_MIN 5
%define COST_MAX (1<<28)

; stack: the outgoing arguments at rsp (7 at most), then the locals at rbp = rsp +
; S_OUTSZ + 128, [rbp+S_*] at every call depth (a byte displacement but for S_BIAS, S_MVCT).
; Offsets are preprocessor numbers: cglobal's stack size has to be one.
%define S_OUTSZ   64
%define S_OUT     0
%assign me_stack_pos -128
%macro ME_STACK_FIELD 2 ; name, bytes
    %xdefine S_%1 me_stack_pos
    %assign me_stack_pos me_stack_pos+%2
%endmacro
ME_STACK_FIELD FENC,   8
ME_STACK_FIELD REFW,   8    ; fref_w
ME_STACK_FIELD STRIDE, 8    ; pixels
ME_STACK_FIELD STRB,   8    ; bytes
ME_STACK_FIELD CMX,    8    ; p_cost_mv - mvp
ME_STACK_FIELD CMY,    8
ME_STACK_FIELD FN,     8
ME_STACK_FIELD C,      8    ; c, m: rbx and R15 outside the loops
ME_STACK_FIELD M,      8
ME_STACK_FIELD FREF,  32    ; m->p_fref[0..3], subme >= 3
ME_STACK_FIELD MVMIN,  4    ; me.c's mv_min, mv_max
ME_STACK_FIELD MVMAX,  4
ME_STACK_FIELD PMV,    4
ME_STACK_FIELD BPMV,   4    ; bpred_mv
ME_STACK_FIELD BPC,    4    ; bpred_cost
ME_STACK_FIELD PMVC,   4    ; pmv_cost
ME_STACK_FIELD BPX,    4    ; bpred_mx, bpred_my
ME_STACK_FIELD BPY,    4
ME_STACK_FIELD FLAGS,  4    ; c->flags
ME_STACK_FIELD NMVC,   4    ; c->i_mvc
ME_STACK_FIELD XMIN,   4    ; mv_limit_fpel
ME_STACK_FIELD YMIN,   4
ME_STACK_FIELD XMAX,   4
ME_STACK_FIELD YMAX,   4
%assign me_stack_pos (me_stack_pos+15) & ~15
ME_STACK_FIELD BIAS,  48    ; 12 dwords
ME_STACK_FIELD MVCT,  72    ; mvc_temp[18][2]
%assign ME_STACK  S_OUTSZ+128+me_stack_pos

; an internal call that calls a kernel: its frame below the return address keeps rsp
; aligned; the outgoing arguments at SUB_OUT
%define SUB_OUT    0
%assign SUB_FRAME  24 + ((-(24+8)) & (STACK_ALIGNMENT-1))

; %1 = pack16to32_mask( %2, %3 ); %4 temp
%macro PACKMV 4
    mov    %4, %2
    and    %4, 0xffff
    mov    %1, %3
    shl    %1, 16
    or     %1, %4
%endmacro

; x264_clip3( %1, %2, %3 ) into %1; %4 temp
%macro CLIP3 4
    mov    %4, %1
    cmp    %1, %3
    cmovg  %4, %3
    cmp    %1, %2
    cmovl  %4, %2
    mov    %1, %4
%endmacro

; rdx = fref_w + %2*stride + %1 (pixels, 64-bit)
%macro FPEL_REF 2
%ifnidni %2, rdx
    mov    rdx, %2
%endif
    imul   rdx, [rbp+S_STRB]
    add    rdx, [rbp+S_REFW]
    lea    rdx, [rdx+%1*SIZEOF_PIXEL]
%endmacro

; m1, m2 = the cost windows about (R12, R13) (zmm: k1 = 17 words);
; clobbers rax, rdi, m3
%macro COST_WINDOWS 0
    mov    rax, [rbp+S_CMX]
    lea    rax, [rax+R12*8-16]
    mov    rdi, [rbp+S_CMY]
    lea    rdi, [rdi+R13*8-16]
%if mmsize == 64
    vmovdqu16 m1{k1}{z}, [rax]
    vmovdqu16 m2{k1}{z}, [rdi]
%else
    vmovdqu16 m1, [rax]
    vmovdqu16 m2, [rdi]
    vpinsrw  xm3, xm1, word [rax+32], 1
    vinserti32x4 m1, m1, xm3, 0
    vpinsrw  xm3, xm2, word [rdi+32], 1
    vinserti32x4 m2, m2, xm3, 0
%endif
%endmacro

; xm0 = the 4 biases ((cost_mvx + cost_mvy) << 6) + R11d + k of the (dx, dy) bytes at R10
; (.x3 / .x4's); clobbers rax, rdi, m0-m3
%macro FPEL_BIAS_V 0
    COST_WINDOWS
    vpmovsxbw xm0, [R10]
    vpsllw   xm0, 2
    vpaddw   xm0, [me_pw_8]
%if mmsize == 32
    vpsrlw   xm3, xm0, 4
    vpandd   xm0, xm0, [me_pw_15]
    vpord    xm0, xm0, xm3
    vpaddw   xm0, [me_wsel16]
%else
    vpaddw   xm0, [me_wsel32]
%endif
    vpermi2w m0, m1, m2
    vpsrld   xm3, xm0, 16
    vpandd   xm0, xm0, [me_pd_ffff]
    vpaddd   xm0, xm3
    vpslld   xm0, 6
    vpbroadcastd xm3, R11d
    vpaddd   xm0, xm3
    vpaddd   xm0, [me_pd_0123]
%endmacro

; %1 = sq_bias lanes of the words %1 picked from m1, m2 (codes at %2, dummies k2); clobbers m3
%macro SQ_BIAS_V 2
    vpermi2w %1, m1, m2
    vpsrld   m3, %1, 16
    vpandd   %1, %1, [me_pd_ffff]
    vpaddd   %1, m3
    vpslld   %1, 6
    vpaddd   %1, [%2]
    vpbroadcastd %1{k2}, [me_d30]
%endmacro

; avx512 PRED_CLIP for i_mvc <= mmsize/4: one masked load, the drops into k2, a compress
; and one store (mvc_temp has the room); the limits are PRED_CLIP's
%macro PRED_CLIP_V 1
    mov    eax, [rbp+S_XMIN]
    mov    ecx, [rbp+S_YMIN]
    mov    edx, [rbp+S_XMAX]
    mov    edi, [rbp+S_YMAX]
%if %1 == 0
    shl    eax, 2
    shl    ecx, 2
    shl    edx, 2
    shl    edi, 2
%endif
    and    eax, 0xffff
    shl    ecx, 16
    or     eax, ecx
    and    edx, 0xffff
    shl    edi, 16
    or     edx, edi
    vpbroadcastd m1, eax
    vpbroadcastd m2, edx
    mov    ecx, [rbp+S_NMVC]
    mov    eax, -1
    bzhi   eax, eax, ecx
    kmovw  k1, eax
    mov    rsi, [rbp+S_C]
    mov    rsi, [rsi+me_fpel.mvc]
    vmovdqu32 m0{k1}{z}, [rsi]
%if %1
    vpaddw   m0, m0, [me_pw_2]
    vpsraw   m0, m0, 2
%endif
    vptestmd k2{k1}, m0, m0
    vpbroadcastd m3, [rbp+S_PMV]
    vpcmpd   k2{k2}, m0, m3, 4
    vpmaxsw  m0, m0, m1
    vpminsw  m0, m0, m2
    vpcompressd m0{k2}{z}, m0
    vmovdqu32 [rbp+S_MVCT+8], m0
    kmovw  eax, k2
    popcnt eax, eax
%endmacro

; mvc[0..i_mvc) -> mvc_temp[2..], eax = the count, as x264_predictor_clip (%1 = 0) or
; x264_predictor_roundclip (%1 = 1) of common/x86/util.h: 16-bit lanes (the + 2 and the
; limits << 2 wrap), the unclipped (rounded) mv dropped if 0 or pmv, max then min;
; i_mvc > 0, the limits in R9d-R11d, ebx
%macro PRED_CLIP 1
    mov    R9d, [rbp+S_XMIN]
    mov    R10d, [rbp+S_YMIN]
    mov    R11d, [rbp+S_XMAX]
    mov    ebx, [rbp+S_YMAX]
%if %1 == 0
    shl    R9d, 2
    movsx  R9d, R9w
    shl    R10d, 2
    movsx  R10d, R10w
    shl    R11d, 2
    movsx  R11d, R11w
    shl    ebx, 2
    movsx  ebx, bx
%endif
    mov    rsi, [rbp+S_C]
    mov    rsi, [rsi+me_fpel.mvc]
    mov    ecx, [rbp+S_NMVC]
    xor    eax, eax
%%loop:
%if %1
    movsx  edx, word [rsi]
    add    edx, 2
    movsx  edx, dx
    sar    edx, 2
    movsx  edi, word [rsi+2]
    add    edi, 2
    movsx  edi, di
    sar    edi, 2
    mov    R8d, edi                 ; pack16to32_mask( edx, edi )
    shl    R8d, 16
    mov    R8w, dx
%else
    mov    R8d, [rsi]
    movsx  edx, R8w
    mov    edi, R8d
    sar    edi, 16
%endif
    test   R8d, R8d
    jz %%next
    cmp    R8d, [rbp+S_PMV]
    je %%next
    cmp    edx, R9d
    cmovl  edx, R9d
    cmp    edx, R11d
    cmovg  edx, R11d
    cmp    edi, R10d
    cmovl  edi, R10d
    cmp    edi, ebx
    cmovg  edi, ebx
    mov    [rbp+S_MVCT+8+rax*4], dx
    mov    [rbp+S_MVCT+10+rax*4], di
    inc    eax
%%next:
    add    rsi, 4
    dec    ecx
    jnz %%loop
%endmacro

; PRED_CLIP, or PRED_CLIP_V where the list fits a vector
%macro PRED_CLIP_ANY 1
%if cpuflag(avx512)
    cmp    dword [rbp+S_NMVC], mmsize/4
    jg %%scalar
    PRED_CLIP_V %1
    jmp %%done
%%scalar:
    PRED_CLIP %1
%%done:
%else
    PRED_CLIP %1
%endif
%endmacro

; avx512: the 12 sq_bias at bmv by SQ_BIAS_V
%macro SQ_BIAS_ALL 0
    mov    eax, 0x1ffff
    kmovd  k1, eax
    COST_WINDOWS
%if mmsize == 64
    mov    eax, 0x0a88
    kmovw  k2, eax
    vmovdqu16 m0, [me_sqidx32]
    SQ_BIAS_V m0, me_sqcode
    mov    eax, 0xfff
    kmovw  k3, eax
    vmovdqu32 [rbp+S_BIAS]{k3}, m0
%else
    mov    eax, 0x88
    kmovw  k2, eax
    vmovdqu16 m0, [me_sqidx16]
    SQ_BIAS_V m0, me_sqcode
    vmovdqu32 [rbp+S_BIAS], m0
    mov    eax, 0x0a
    kmovw  k2, eax
    vmovdqu16 m0, [me_sqidx16+32]
    SQ_BIAS_V m0, me_sqcode+32
    vmovdqu32 [rbp+S_BIAS+32], xm0
%endif
%endmacro

; the predictor loop: R14d = min( R14d, (cost( mvc_temp[i+1] ) << 4) + i ) for i = 1..eax;
; R12d i, R13d the count. %1 0: the fullpel cost inline, the sad in R15, the mv cost in rbx
; across the call; 1: .cost_hpel with the kernels at R15
%macro PRED_LOOP 1
    mov    R13d, eax
    mov    eax, [rbp+S_PMV]
    mov    [rbp+S_MVCT+4], eax
    mov    R12d, 1
%if %1
    mov    R15, [rbp+S_FN]
%else
    mov    rax, [rbp+S_FN]
    mov    R15, [rax+me_fpel_fn.sad]
%endif
%%loop:
    movsx  rcx, word [rbp+S_MVCT+4+R12*4]
    movsx  rdx, word [rbp+S_MVCT+6+R12*4]
%if %1
    call   .cost_hpel
%else
    mov    rsi, [rbp+S_CMX]
    movzx  ebx, word [rsi+rcx*8]
    mov    rsi, [rbp+S_CMY]
    movzx  esi, word [rsi+rdx*8]
    add    ebx, esi
    FPEL_REF rcx, rdx
    mov    rdi, [rbp+S_FENC]
    mov    esi, FENC_STRIDE
    mov    rcx, [rbp+S_STRIDE]
    call   R15
    add    eax, ebx
%endif
    shl    eax, 4
    add    eax, R12d
    cmp    eax, R14d
    cmovl  R14d, eax
    inc    R12d
    cmp    R12d, R13d
    jle %%loop
%endmacro

; bias k of the (dx, dy) bytes at R10 around (R12, R13) into %2:
; ((cost_mvx[4*mx] + cost_mvy[4*my]) << 6) + R11d + k; rsi cost_mvx, rdi cost_mvy; clobbers rax, rdx
%macro CAND_BIAS 2 ; k, dst
    movsx  rax, byte [R10+2*%1]
    add    rax, R12
    movzx  %2, word [rsi+rax*8]
    movsx  rdx, byte [R10+2*%1+1]
    add    rdx, R13
    movzx  edx, word [rdi+rdx*8]
    add    %2, edx
    shl    %2, 6
    add    %2, R11d
%if %1
    add    %2, %1
%endif
%endmacro

; the ref pointers of the first %1 (dx, dy) bytes at R10 around (R12, R13) into rsi, rdx,
; rcx(, R8); clobbers rax, rdi, R11
%macro CAND_PTRS 1
    mov    rdi, [rbp+S_STRB]
    mov    rax, R13
    imul   rax, rdi
    add    rax, [rbp+S_REFW]
    lea    rax, [rax+R12*SIZEOF_PIXEL]
    CAND_PTR 0, rsi
    CAND_PTR 1, rdx
    CAND_PTR 2, rcx
%if %1 == 4
    CAND_PTR 3, R8
%endif
%endmacro

%macro CAND_PTR 2 ; k, dst
    movsx  %2, byte [R10+2*%1+1]
    imul   %2, rdi
    add    %2, rax
    movsx  R11, byte [R10+2*%1]
    lea    %2, [%2+R11*SIZEOF_PIXEL]
%endmacro

; CHECK_MVRANGE( R12, R13 ), jumps to %1 if out of range
%macro CHECK_MVRANGE 1
    mov    eax, R12d
    shl    eax, 16
    mov    ecx, R13d
    and    ecx, 0x7fff
    or     eax, ecx
    mov    ecx, [rbp+S_MVMIN]
    add    ecx, eax
    mov    edx, [rbp+S_MVMAX]
    sub    edx, eax
    or     ecx, edx
    test   ecx, 0x80004000
    jnz %1
%endmacro

; R12 += hex2[eax+1] dx, R13 += its dy (eax 0..6); clobbers rcx, rdx
%macro HEX_MOVE 0
    lea    rcx, [me_hex2]
    movsx  rdx, byte [rcx+rax*2+2]
    add    R12, rdx
    movsx  rdx, byte [rcx+rax*2+3]
    add    R13, rdx
%endmacro

; bias k of the square: ((cost_mvx + cost_mvy) << 6) + code
%macro SQ_BIAS 4 ; k, cx, cy, code
    mov    R11d, %2
    add    R11d, %3
    shl    R11d, 6
    add    R11d, %4
    mov    [rbp+S_BIAS+4*%1], R11d
%endmacro

;-----------------------------------------------------------------------------
; int me_search_fpel( x264_me_fpel_t *c ), see encoder/me.h
;-----------------------------------------------------------------------------
; rbp: the locals, R12/R13: bmx/bmy (64-bit), R14d: bcost or its key; rbx: c and R15: m
; but in the predictor loops (R12d i, R13d the count, R15 the sad or the kernels, rbx a
; candidate's mv cost), the hexagon (rbx x3_min, R15d dir | i << 8) and the square (rbx x4_min)
%macro ME_SEARCH_FPEL 1
cglobal %1, 1,15,0, ME_STACK
    lea    rbp, [rsp+S_OUTSZ+128]
    mov    rbx, rdi
    mov    [rbp+S_C], rdi
    mov    R15, [rbx+me_fpel.m]
    mov    [rbp+S_M], R15
    mov    eax, [rbx+me_fpel.flags]
    mov    [rbp+S_FLAGS], eax
    mov    eax, [rbx+me_fpel.i_mvc]
    mov    [rbp+S_NMVC], eax
    mov    rax, [R15+me_t.p_fenc]
    mov    [rbp+S_FENC], rax
    mov    rax, [R15+me_t.p_fref_w]
    mov    [rbp+S_REFW], rax
    movsxd rax, dword [R15+me_t.i_stride]
    mov    [rbp+S_STRIDE], rax
%if HIGH_BIT_DEPTH
    add    rax, rax
%endif
    mov    [rbp+S_STRB], rax
    mov    rax, [rbx+me_fpel.fn]
    mov    [rbp+S_FN], rax
    mov    rcx, [R15+me_t.p_cost_mv]
    movsx  rax, word [R15+me_t.mvp]
    add    rax, rax
    mov    rdx, rcx
    sub    rdx, rax
    mov    [rbp+S_CMX], rdx
    movsx  rax, word [R15+me_t.mvp+2]
    add    rax, rax
    sub    rcx, rax
    mov    [rbp+S_CMY], rcx
    ; mv_limit_fpel; mv_min = pack16to32_mask2( -xmin, -ymin ),
    ; mv_max = pack16to32_mask2( xmax, ymax ) | 0x8000
    mov    rsi, [rbx+me_fpel.mv_limit]
    movsx  eax, word [rsi]
    movsx  ecx, word [rsi+2]
    movsx  edx, word [rsi+4]
    movsx  edi, word [rsi+6]
    mov    [rbp+S_XMIN], eax
    mov    [rbp+S_YMIN], ecx
    mov    [rbp+S_XMAX], edx
    mov    [rbp+S_YMAX], edi
    neg    eax
    shl    eax, 16
    neg    ecx
    and    ecx, 0x7fff
    or     eax, ecx
    mov    [rbp+S_MVMIN], eax
    shl    edx, 16
    and    edi, 0x7fff
    or     edx, edi
    or     edx, 0x8000
    mov    [rbp+S_MVMAX], edx
    test   byte [rbx+me_fpel.flags], ME_FPEL_SUBME3
    jnz .subme3

    ; subme < 3: the fullpel mvp, its sad alone
    movsx  eax, word [R15+me_t.mvp]
    add    eax, 2
    sar    eax, 2
    CLIP3  eax, [rbp+S_XMIN], [rbp+S_XMAX], ecx
    movsx  edx, word [R15+me_t.mvp+2]
    add    edx, 2
    sar    edx, 2
    CLIP3  edx, [rbp+S_YMIN], [rbp+S_YMAX], ecx
    movsxd R12, eax
    movsxd R13, edx
    PACKMV eax, R12d, R13d, ecx
    mov    [rbp+S_PMV], eax
    mov    rdi, [rbp+S_FENC]
    mov    esi, FENC_STRIDE
    FPEL_REF R12, R13
    mov    rcx, [rbp+S_STRIDE]
    mov    rax, [rbp+S_FN]
    call   [rax+me_fpel_fn.sad]
    mov    R14d, eax
    test   eax, eax
    jz .fpel_done
    cmp    dword [rbp+S_NMVC], 0
    jle .zero2
    PRED_CLIP_ANY 1
    test   eax, eax
    jle .zero2
    shl    R14d, 4
    PRED_LOOP 0
    mov    eax, R14d
    and    eax, 15
    movsx  R12, word [rbp+S_MVCT+4+rax*4]
    movsx  R13, word [rbp+S_MVCT+6+rax*4]
    sar    R14d, 4
.zero2:
    cmp    dword [rbp+S_PMV], 0
    je .hex
    xor    ecx, ecx
    xor    edx, edx
    call .cost_fpel
    cmp    eax, R14d
    jge .hex
    mov    R14d, eax
    xor    R12d, R12d
    xor    R13d, R13d
    jmp .hex

.subme3:
    ; the mvp clipped to the spel limits, its subpel cost
    movsx  eax, word [R15+me_t.mvp]
    mov    ecx, [rbp+S_XMIN]
    shl    ecx, 2
    mov    edx, [rbp+S_XMAX]
    shl    edx, 2
    CLIP3  eax, ecx, edx, R8d
    mov    [rbp+S_BPX], eax
    movsx  edi, word [R15+me_t.mvp+2]
    mov    ecx, [rbp+S_YMIN]
    shl    ecx, 2
    mov    edx, [rbp+S_YMAX]
    shl    edx, 2
    CLIP3  edi, ecx, edx, R8d
    mov    [rbp+S_BPY], edi
    PACKMV ecx, eax, edi, edx
    mov    [rbp+S_PMV], ecx
    vmovdqu xm0, [R15+me_t.p_fref]
    vmovdqu xm1, [R15+me_t.p_fref+16]
    vmovdqu [rbp+S_FREF], xm0
    vmovdqu [rbp+S_FREF+16], xm1
    mov    ecx, eax
    mov    edx, edi
    mov    R15, [rbp+S_FN]
    call .cost_hpel
    mov    [rbp+S_BPC], eax
    mov    [rbp+S_PMVC], eax
    ; pred == fenc at the unclipped mvp
    mov    R15, [rbp+S_M]
    mov    rcx, [R15+me_t.p_cost_mv]
    movzx  ecx, word [rcx]
    add    ecx, ecx
    cmp    eax, ecx
    jne .preds3
    mov    rbx, [rbp+S_C]
    mov    ecx, [rbp+S_PMV]
    test   byte [rbx+me_fpel.flags], ME_FPEL_ZEXIT
    jz .zexit_search
    mov    [R15+me_t.mv], ecx
    mov    [R15+me_t.cost], eax
    mov    rcx, [rbx+me_fpel.halfpel_thresh]
    test   rcx, rcx
    jz .zexit_costmv
    imul   edx, eax, 7
    sar    edx, 3
    cmp    edx, [rcx]
    jg .ret0
    cmp    eax, [rcx]
    jge .zexit_costmv
    mov    [rcx], eax
.zexit_costmv:
    mov    [R15+me_t.cost_mv], eax
    jmp .ret0
.zexit_search:
    ; bpred_mv = pmv, bmv the fullpel pmv, bcost COST_MAX
    mov    [rbp+S_BPMV], ecx
    mov    eax, [rbp+S_BPX]
    add    eax, 2
    sar    eax, 2
    movsxd R12, eax
    mov    eax, [rbp+S_BPY]
    add    eax, 2
    sar    eax, 2
    movsxd R13, eax
    mov    R14d, COST_MAX
    jmp .fpel_done

.preds3:
    mov    ecx, [rbp+S_NMVC]
    test   ecx, ecx
    jle .round3
    mov    rax, [rbp+S_FN]
    mov    rax, [rax+me_fpel_fn.predictor_clip]
    test   rax, rax
    jz .clip3
    cmp    ecx, PREDICTOR_DEDUPE_MIN
    jl .clip3
    ; predictor_clip( mvc_temp+2, mvc, i_mvc, mv_limit_fpel, pmv )
    lea    rdi, [rbp+S_MVCT+8]
    mov    rsi, [rbp+S_C]
    mov    rcx, [rsi+me_fpel.mv_limit]
    mov    rsi, [rsi+me_fpel.mvc]
    mov    edx, [rbp+S_NMVC]
    mov    R8d, [rbp+S_PMV]
    call   rax
    jmp .clipped3
.clip3:
    PRED_CLIP_ANY 0
.clipped3:
    test   eax, eax
    jle .round3
    mov    R14d, [rbp+S_BPC]
    shl    R14d, 4
    PRED_LOOP 1
    mov    eax, R14d
    and    eax, 15
    movsx  ecx, word [rbp+S_MVCT+4+rax*4]
    mov    [rbp+S_BPX], ecx
    movsx  ecx, word [rbp+S_MVCT+6+rax*4]
    mov    [rbp+S_BPY], ecx
    sar    R14d, 4
    mov    [rbp+S_BPC], R14d
.round3:
    ; the best predictor rounded to fullpel; its sad if it is subpel
    mov    eax, [rbp+S_BPX]
    mov    edx, [rbp+S_BPY]
    PACKMV ecx, eax, edx, edi
    mov    [rbp+S_BPMV], ecx
    add    eax, 2
    sar    eax, 2
    movsxd R12, eax
    add    edx, 2
    sar    edx, 2
    movsxd R13, edx
    mov    R14d, [rbp+S_BPC]
    test   ecx, 0x00030003
    jz .zero3
    mov    R14d, COST_MAX
    mov    ecx, R12d
    mov    edx, R13d
    call .cost_fpel
    cmp    eax, R14d
    cmovl  R14d, eax
.zero3:
    cmp    dword [rbp+S_PMV], 0
    je .zero3_pmv
    mov    eax, R12d
    or     eax, R13d
    jz .hex
    xor    ecx, ecx
    xor    edx, edx
    call .cost_fpel
    cmp    eax, R14d
    jge .hex
    mov    R14d, eax
    xor    R12d, R12d
    xor    R13d, R13d
    jmp .hex
.zero3_pmv:
    ; a subpel candidate better than the zero vector
    mov    eax, [rbp+S_PMVC]
    cmp    eax, R14d
    jge .hex
    mov    R14d, eax
    xor    R12d, R12d
    xor    R13d, R13d

.hex:
    mov    rax, [rbp+S_FN]
    mov    rax, [rax+me_fpel_fn.hex_search]
    test   rax, rax
    jz .hex_c
    ; hex_search( fenc, ref, stride, cost_mvx, cost_mvy, bmv, bcost, i_me_range, mv_min | mv_max << 32 )
    mov    rdi, [rbp+S_FENC]
    mov    rsi, [rbp+S_REFW]
    mov    rdx, [rbp+S_STRIDE]
    mov    rcx, [rbp+S_CMX]
    mov    R8, [rbp+S_CMY]
    PACKMV R9d, R12d, R13d, R10d
    mov    R10, [rbp+S_C]
    mov    R10d, [R10+me_fpel.me_range]
    mov    R11, [rbp+S_MVMIN]
%if HIGH_BIT_DEPTH == 0
    ; sad_hex_search_8x8's register entry: the last three in r6-r8 (rax, R10, R11)
    lea    rbx, [pixel_sad_hex_search_8x8_avx512]
    cmp    rax, rbx
    jne .hex_stack
    mov    eax, R14d
    call   pixel_sad_hex_search_reg_8x8_avx512
    jmp .hex_ret
.hex_stack:
%endif
    mov    [rsp+S_OUT], R14d
    mov    [rsp+S_OUT+8], R10d
    mov    [rsp+S_OUT+16], R11
    call   rax
.hex_ret:
    mov    R14d, eax
    shr    rax, 32
    movsx  R12, ax
    sar    eax, 16
    movsxd R13, eax
    jmp .fpel_done

.hex_c:
    ; hexagon
    shl    R14d, 6
    mov    rax, [rbp+S_FN]
    mov    rbx, [rax+me_fpel_fn.x3_min]
    cmp    qword [rax+me_fpel_fn.hex_min], 0
    je .hex_x3
    ; pt_bias[j] = (BITS_MVD( bmv + hex2[j+1] ) << 6) + j+2
    lea    R10, [me_hex2+2]
    mov    rsi, [rbp+S_CMX]
    mov    rdi, [rbp+S_CMY]
    xor    ecx, ecx
.hex_bias:
    movsx  rax, byte [R10+rcx*2]
    add    rax, R12
    movzx  edx, word [rsi+rax*8]
    movsx  rax, byte [R10+rcx*2+1]
    add    rax, R13
    movzx  eax, word [rdi+rax*8]
    add    eax, edx
    shl    eax, 6
    lea    eax, [rax+rcx+2]
    mov    [rbp+S_BIAS+rcx*4], eax
    inc    ecx
    cmp    ecx, 6
    jl .hex_bias
    ; hex_min( fenc, ref at bmv, stride, pt_bias, bcost )
    mov    rdi, [rbp+S_FENC]
    FPEL_REF R12, R13
    mov    rsi, rdx
    mov    rdx, [rbp+S_STRIDE]
    lea    rcx, [rbp+S_BIAS]
    mov    R8d, R14d
    mov    rax, [rbp+S_FN]
    call   [rax+me_fpel_fn.hex_min]
    mov    R14d, eax
    jmp .hex_step
.hex_x3:
    lea    R10, [me_hex2+2]
    mov    R11d, 2
    call .x3
    lea    R10, [me_hex2+8]
    mov    R11d, 5
    call .x3
.hex_step:
    test   R14d, 63
    jz .hex_end
    mov    eax, R14d
    and    eax, 63
    sub    eax, 2
    mov    R15d, eax
    HEX_MOVE
    ; half hexagons, not overlapping the previous iteration: R15d = dir | i << 8
    mov    rax, [rbp+S_C]
    mov    eax, [rax+me_fpel.me_range]
    sar    eax, 1
    dec    eax
    shl    eax, 8
    or     R15d, eax
.hex_loop:
    cmp    R15d, 1<<8
    jl .hex_end
    CHECK_MVRANGE .hex_end
    and    R14d, ~63
    movzx  eax, R15b
    lea    R10, [me_hex2]
    lea    R10, [R10+rax*2]
    mov    R11d, 1
    call .x3
    test   R14d, 63
    jz .hex_end
    mov    eax, R14d
    and    eax, 63
    sub    eax, 2
    movzx  ecx, R15b
    add    eax, ecx
    cdqe                        ; movsxd rax, eax
    lea    rcx, [me_mod6m1]
    movzx  eax, byte [rcx+rax+1]
    sub    R15d, 1<<8
    and    R15d, ~255
    or     R15d, eax
    HEX_MOVE
    jmp .hex_loop
.hex_end:
    sar    R14d, 6
    shl    R14d, 6

    ; square refine
    mov    rax, [rbp+S_FN]
    mov    rbx, [rax+me_fpel_fn.x4_min]
    cmp    qword [rax+me_fpel_fn.sq_min], 0
    je .sq_x4
%if cpuflag(avx512)
    SQ_BIAS_ALL
%else
    mov    rsi, [rbp+S_CMX]
    mov    rdi, [rbp+S_CMY]
    movzx  eax, word [rsi+R12*8-8]
    movzx  ecx, word [rsi+R12*8]
    movzx  edx, word [rsi+R12*8+8]
    movzx  R8d, word [rdi+R13*8-8]
    movzx  R9d, word [rdi+R13*8]
    movzx  R10d, word [rdi+R13*8+8]
    SQ_BIAS  0, eax, R8d, 5
    SQ_BIAS  1, ecx, R8d, 1
    SQ_BIAS  2, edx, R8d, 7
    SQ_BIAS  4, eax, R10d, 6
    SQ_BIAS  5, ecx, R10d, 2
    SQ_BIAS  6, edx, R10d, 8
    SQ_BIAS  8, eax, R9d, 3
    SQ_BIAS 10, edx, R9d, 4
    mov    eax, 1<<30
    mov    [rbp+S_BIAS+4*3], eax
    mov    [rbp+S_BIAS+4*7], eax
    mov    [rbp+S_BIAS+4*9], eax
    mov    [rbp+S_BIAS+4*11], eax
%endif
    ; sq_min( fenc, ref at bmv, stride, sq_bias, bcost )
    mov    rdi, [rbp+S_FENC]
    FPEL_REF R12, R13
    mov    rsi, rdx
    mov    rdx, [rbp+S_STRIDE]
    lea    rcx, [rbp+S_BIAS]
    mov    R8d, R14d
    mov    rax, [rbp+S_FN]
    call   [rax+me_fpel_fn.sq_min]
    mov    R14d, eax
    jmp .sq_end
.sq_x4:
    lea    R10, [me_square1+2]
    mov    R11d, 1
    call .x4
    lea    R10, [me_square1+10]
    mov    R11d, 5
    call .x4
.sq_end:
    mov    eax, R14d
    and    eax, 63
    lea    rcx, [me_square1]
    movsx  rdx, byte [rcx+rax*2]
    add    R12, rdx
    movsx  rdx, byte [rcx+rax*2+1]
    add    R13, rdx
    sar    R14d, 6

.fpel_done:
    mov    rbx, [rbp+S_C]
    mov    R15, [rbp+S_M]
    PACKMV eax, R12d, R13d, ecx
    mov    edx, eax
    shl    edx, 2
    and    edx, 0xFFFCFFFC
    test   byte [rbx+me_fpel.flags], ME_FPEL_SUBME3
    jnz .done3
    ; cost_mv, the real cost (+ cost_mv at the pmv), mv
    mov    rsi, [rbp+S_CMX]
    movzx  ecx, word [rsi+R12*8]
    mov    rsi, [rbp+S_CMY]
    movzx  esi, word [rsi+R13*8]
    add    ecx, esi
    mov    [R15+me_t.cost_mv], ecx
    xor    esi, esi
    cmp    eax, [rbp+S_PMV]
    cmove  esi, ecx
    add    esi, R14d
    mov    [R15+me_t.cost], esi
    mov    [R15+me_t.mv], edx
    jmp .subpel
.done3:
    mov    ecx, [rbp+S_BPC]
    cmp    ecx, R14d
    cmovl  edx, [rbp+S_BPMV]
    mov    [R15+me_t.mv], edx
    cmp    ecx, R14d
    cmovg  ecx, R14d
    mov    [R15+me_t.cost], ecx
.subpel:
    test   byte [rbx+me_fpel.flags], ME_FPEL_REFINE
    jz .ret0
    mov    rax, [rbx+me_fpel.qfenc]
    test   rax, rax
    jnz .subpel_call
    mov    eax, 1
    jmp .ret
.subpel_call:
    ; subpel( fenc, fref, stride, cost_mvx, cost_mvy, mv, cost, iters, range, qfenc, qpel, halfpel_thresh, mvp )
    mov    [rsp+S_OUT+24], rax
    mov    rdi, [rbp+S_FENC]
    lea    rsi, [R15+me_t.p_fref]
    mov    rdx, [rbp+S_STRIDE]
    mov    rcx, [rbp+S_CMX]
    mov    R8, [rbp+S_CMY]
    mov    R9d, [R15+me_t.mv]
    mov    eax, [R15+me_t.cost]
    mov    [rsp+S_OUT], eax
    mov    eax, [rbx+me_fpel.iters]
    mov    [rsp+S_OUT+8], eax
    mov    rax, [rbx+me_fpel.range]
    mov    [rsp+S_OUT+16], rax
    mov    rax, [rbp+S_FN]
    mov    R10, [rax+me_fpel_fn.qpel]
    mov    [rsp+S_OUT+32], R10
    mov    R10, [rbx+me_fpel.halfpel_thresh]
    mov    [rsp+S_OUT+40], R10
    mov    R10d, [R15+me_t.mvp]
    mov    [rsp+S_OUT+48], R10d
    call   [rax+me_fpel_fn.subpel]
    mov    ecx, eax
    and    ecx, 0x7fffffff
    mov    [R15+me_t.cost], ecx
    mov    rdx, rax
    shr    rdx, 32
    mov    [R15+me_t.mv], edx
    ; the halfpel threshold stop leaves cost_mv
    test   eax, eax
    js .ret0
    movsx  rcx, dx
    sar    edx, 16
    movsxd rdx, edx
    mov    rsi, [rbp+S_CMX]
    movzx  ecx, word [rsi+rcx*2]
    mov    rsi, [rbp+S_CMY]
    movzx  edx, word [rsi+rdx*2]
    add    ecx, edx
    mov    [R15+me_t.cost_mv], ecx
.ret0:
    xor    eax, eax
.ret:
    RET

; eax = sad( fenc, fref_w + ecx + edx*stride ) + cost_mvx[4*ecx] + cost_mvy[4*edx]; the mv cost
; in rbx across the call
.cost_fpel:
    sub    rsp, SUB_FRAME
    movsxd rcx, ecx
    movsxd rdx, edx
    mov    rsi, [rbp+S_CMX]
    movzx  ebx, word [rsi+rcx*8]
    mov    rsi, [rbp+S_CMY]
    movzx  esi, word [rsi+rdx*8]
    add    ebx, esi
    FPEL_REF rcx, rdx
    mov    rdi, [rbp+S_FENC]
    mov    esi, FENC_STRIDE
    mov    rcx, [rbp+S_STRIDE]
    mov    rax, [rbp+S_FN]
    call   [rax+me_fpel_fn.sad]
    add    eax, ebx
    add    rsp, SUB_FRAME
    ret

; eax = subpel_cmp( qpel mv ecx, edx ) + cost_mvx[ecx] + cost_mvy[edx], unweighted:
; fpelcmp_avg2 of two hpel planes, else fpelcmp of one, as me.c's subpel_cmp; the kernels
; at R15, the planes at S_FREF, the mv cost in rbx across the call
.cost_hpel:
    sub    rsp, SUB_FRAME
    movsxd rcx, ecx
    movsxd rdx, edx
    mov    rsi, [rbp+S_CMX]
    movzx  ebx, word [rsi+rcx*2]
    mov    rsi, [rbp+S_CMY]
    movzx  esi, word [rsi+rdx*2]
    add    ebx, esi
    mov    eax, edx
    and    eax, 3
    mov    R8d, ecx
    and    R8d, 3
    lea    R9d, [R8+rax*4]          ; qpel_idx
    mov    R10, rdx
    sar    R10, 2
    imul   R10, [rbp+S_STRB]
    mov    R11, rcx
    sar    R11, 2
    lea    R10, [R10+R11*SIZEOF_PIXEL] ; offset
    lea    rdi, [me_hpel_ref]
    movzx  esi, byte [rdi+R9]
    mov    rsi, [rbp+S_FREF+rsi*8]
    add    rsi, R10
    xor    R11d, R11d
    cmp    eax, 3
    cmove  R11, [rbp+S_STRB]
    add    rsi, R11                 ; src1
    test   R9d, 5
    jz .cost_hpel_one
    movzx  edx, byte [rdi+R9+16]
    mov    rdx, [rbp+S_FREF+rdx*8]
    add    rdx, R10
    xor    R11d, R11d
    cmp    R8d, 3
    sete   R11b
%if HIGH_BIT_DEPTH
    lea    rdx, [rdx+R11*2]         ; src2
%else
    add    rdx, R11
%endif
    mov    rdi, [rbp+S_FENC]
    mov    rcx, [rbp+S_STRIDE]
    call   [R15+me_fpel_fn.sad_avg2]
    add    eax, ebx
    add    rsp, SUB_FRAME
    ret
.cost_hpel_one:
    mov    rdx, rsi
    mov    rdi, [rbp+S_FENC]
    mov    esi, FENC_STRIDE
    mov    rcx, [rbp+S_STRIDE]
    call   [R15+me_fpel_fn.sad]
    add    eax, ebx
    add    rsp, SUB_FRAME
    ret

; R14d = x3_min( fenc, the 3 candidates of the (dx, dy) bytes at R10 around (R12, R13), their
; biases ((cost_mvx[4*mx] + cost_mvy[4*my]) << 6) + R11d + k (avx512: FPEL_BIAS_V's), R14d ), x3_min
; in rbx
.x3:
    sub    rsp, SUB_FRAME
%if cpuflag(avx512)
%if mmsize == 64
    mov    eax, 0x1ffff
    kmovd  k1, eax
%endif
    FPEL_BIAS_V
    vmovq  R9, xm0
    vpinsrd xm0, xm0, R14d, 3
    vpextrq [rsp+SUB_OUT], xm0, 1
%else
    mov    rsi, [rbp+S_CMX]
    mov    rdi, [rbp+S_CMY]
    CAND_BIAS 0, R9d
    CAND_BIAS 1, ecx
    shl    rcx, 32
    or     R9, rcx
    CAND_BIAS 2, ecx
    mov    eax, R14d
    shl    rax, 32
    or     rcx, rax
    mov    [rsp+SUB_OUT], rcx
%endif
    CAND_PTRS 3
    mov    R8, [rbp+S_STRIDE]
    mov    rdi, [rbp+S_FENC]
    call   rbx
    mov    R14d, eax
    add    rsp, SUB_FRAME
    ret

; R14d = x4_min( fenc, the 4 candidates of the (dx, dy) bytes at R10 around (R12, R13), as .x3 ),
; x4_min in rbx
.x4:
    sub    rsp, SUB_FRAME
%if cpuflag(avx512)
%if mmsize == 64
    mov    eax, 0x1ffff
    kmovd  k1, eax
%endif
    FPEL_BIAS_V
    vmovdqu [rsp+SUB_OUT], xm0
%else
    mov    rsi, [rbp+S_CMX]
    mov    rdi, [rbp+S_CMY]
    CAND_BIAS 0, R8d
    CAND_BIAS 1, ecx
    shl    rcx, 32
    or     R8, rcx
    mov    [rsp+SUB_OUT], R8
    CAND_BIAS 2, R8d
    CAND_BIAS 3, ecx
    shl    rcx, 32
    or     R8, rcx
    mov    [rsp+SUB_OUT+8], R8
%endif
    mov    [rsp+SUB_OUT+16], R14d
    CAND_PTRS 4
    mov    R9, [rbp+S_STRIDE]
    mov    rdi, [rbp+S_FENC]
    call   rbx
    mov    R14d, eax
    add    rsp, SUB_FRAME
    ret
%endmacro

INIT_XMM avx2
ME_SEARCH_FPEL me_search_fpel
INIT_YMM avx512
ME_SEARCH_FPEL me_search_fpel
INIT_ZMM avx512
ME_SEARCH_FPEL me_search_fpel_zmm

%endif ; UNIX64
