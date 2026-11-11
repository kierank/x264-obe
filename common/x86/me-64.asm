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

; avx2 8-bit me_search_fpel: per axis the window V = { c(-2) c(2) c(-1) _ c(0) _ c(1) _ } of the
; mv costs about b (dwords), the vpermd indices of the points' dx, dy and their me.c idx
ALIGN 32
mf_hex_xidx: dd 0,2,6,1, 6,2,6,2     ; hex2[1..6], lanes 6, 7 repeat 4, 5
mf_hex_yidx: dd 4,1,1,4, 0,0,0,0
mf_hex_rank: dd 2,3,4,5, 6,7,6,7
mf_sq_xidx:  dd 4,4,2,6, 2,2,6,6     ; square1[1..4] | square1[5..8]
mf_sq_yidx:  dd 2,6,4,4, 2,6,2,6
mf_sq_rank:  dd 1,2,3,4, 5,6,7,8
; half hexagon of dir 0-5: hex2[dir..dir+2], the last repeated
mf_hh_xidx:  dd 2,0,2,2, 0,2,6,6, 2,6,1,1, 6,1,6,6, 1,6,2,2, 6,2,0,0
mf_hh_yidx:  dd 0,4,1,1, 4,1,1,1, 1,1,4,4, 1,4,0,0, 4,0,0,0, 0,0,4,4
mf_hh_rank:  dd 1,2,3,1<<30
mf_pd_ffff:  times 8 dd 0xffff
; 16 wide square in shared windows (sad_sq_min_16x16's): sums of
; (-1,-1) (0,-1) (-1,1) (-1,0) | (1,-1) (0,1) (1,1) (1,0)
mf_sq16_xidx: dd 2,4,2,2, 6,4,6,6
mf_sq16_yidx: dd 2,2,6,4, 2,6,6,4
mf_sq16_rank: dd 5,1,6,3, 7,2,8,4

SECTION .text

%if HIGH_BIT_DEPTH == 0
cextern pixel_sad_hex_search_8x8_avx512
cextern pixel_sad_hex_search_reg_8x8_avx512
cextern pixel_sad_hex_search_8x8_avx2
cextern pixel_sad_hex_search_reg_8x8_avx2
cextern pixel_sad_hex_search_8x8_avx512icl
cextern pixel_sad_hex_search_reg_8x8_avx512icl
cextern pw_1
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
    shl    edx, 16
    and    edi, 0x7fff
    or     edx, edi
    or     edx, 0x8000
    ; one qword store: .hex reads both as a qword (no store forwarding from two dwords)
    shl    rdx, 32
    or     rdx, rax
    mov    [rbp+S_MVMIN], rdx
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
    jne .hex_avx2
    mov    eax, R14d
    call   pixel_sad_hex_search_reg_8x8_avx512
    jmp .hex_ret
.hex_avx2:
%if notcpuflag(avx512)
    lea    rbx, [pixel_sad_hex_search_8x8_avx2]
    cmp    rax, rbx
    jne .hex_stack
    mov    eax, R14d
    call   pixel_sad_hex_search_reg_8x8_avx2
    jmp .hex_ret
%endif
.hex_stack:
%endif
    mov    [rsp+S_OUT], R14     ; qwords, zero-extended by the dword writes
    mov    [rsp+S_OUT+8], R10
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
    ; the int stack arguments as qwords: x86inc loads them as qwords
    mov    eax, [R15+me_t.cost]
    mov    [rsp+S_OUT], rax
    mov    eax, [rbx+me_fpel.iters]
    mov    [rsp+S_OUT+8], rax
    mov    rax, [rbx+me_fpel.range]
    mov    [rsp+S_OUT+16], rax
    mov    rax, [rbp+S_FN]
    mov    R10, [rax+me_fpel_fn.qpel]
    mov    [rsp+S_OUT+32], R10
    mov    R10, [rbx+me_fpel.halfpel_thresh]
    mov    [rsp+S_OUT+40], R10
    mov    R10d, [R15+me_t.mvp]
    mov    [rsp+S_OUT+48], R10
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

;=============================================================================
; me_search_fpel avx2, 8-bit: the search on its own SAD kernels (internal calls, no
; C ABI) and the mv costs of each point set from two cost windows (no bias tables);
; C ABI calls only for predictor_clip, subpel_search and, at 8x8, sad_hex_search's
; register entry. 16 wide squares in sad_sq_min_16x16's shared windows. Bit-exact with
; x264_me_search_ref: every point set is a min of distinct keys (cost << 6) + idx, so the
; order of the sads does not matter. FENC_RES 1: fenc in ymm registers for the whole
; search; 0: fenc as memory operands (16 wide) or a packed copy on the stack (8 wide).
;=============================================================================
%if HIGH_BIT_DEPTH == 0

%ifndef FENC_RES
%define FENC_RES 1
%endif
%ifndef FENC_RES512
%define FENC_RES512 1
%endif

; the frame below the 6 pushes (rsp 64-aligned)
%define F_OUT   0       ; subpel_search's stack arguments
%define F_CMX   56      ; cost_mvx, cost_mvy
%define F_CMY   64
%define F_MVR   72      ; mv_min | mv_max << 32, CHECK_MVRANGE's
%define F_PMV   80
%define F_BPMV  84
%define F_BPC   88
%define F_PMVC  92
%define F_BPX   96
%define F_BPY   100
%define F_MVCT  104     ; mvc_temp[18][2]
%define F_FENC  192     ; !FENC_RES 8 wide: the packed fenc, 128 bytes
%define F_SIZE  328     ; rsp + 8 is 64-aligned at entry: 6 pushes + F_SIZE keep it so

; m%1 = V of cost_mv %2 about b %3; m%4 temp (avx2); avx512: k7 = 2 (MF_FENC_LOAD)
%macro MF_COSTV 4
%if cpuflag(avx512)
    movu           m%1, [%2+%3*8-16]
    vpbroadcastd   m%1 {k7}, [%2+%3*8+16]
%else
    vpbroadcastw   m%4, [%2+%3*8+16]
    vpblendd       m%1, m%4, [%2+%3*8-16], 0xfd
%endif
    pand           m%1, [mf_pd_ffff]
%endmacro

; m%1 = cost_mvx + cost_mvy of the points by indices at %2, %3 (about R12, R13); clobbers
; m%1-m%1+3, rdi
%macro MF_COSTS 3
    %assign %%a %1+1
    %assign %%b %1+2
    %assign %%c %1+3
    mov            rdi, [rsp+F_CMX]
    MF_COSTV       %%a, rdi, R12, %%b
    mov            rdi, [rsp+F_CMY]
    MF_COSTV       %%b, rdi, R13, %%c
    movu           m%1, %2
    vpermd         m%1, m%1, m %+ %%a
    movu           m %+ %%c, %3
    vpermd         m %+ %%c, m %+ %%c, m %+ %%b
    paddd          m%1, m %+ %%c
%endmacro

; min of the dwords of xm0 -> %1
%macro MF_MIN4 1
    pshufd         xm1, xm0, q1032
    pminsd         xm0, xm1
    pshufd         xm1, xm0, q2301
    pminsd         xm0, xm1
    movd            %1, xm0
%endmacro

; m%1 = phaddd( m%1, m%2 ) of packssdw'd sads (dwords below 1 << 15); avx512: phaddd has
; no EVEX form, a second pack and pmaddwd
%macro MF_HADDD 2
%if cpuflag(avx512)
    packssdw       m%1, m%2
    pmaddwd        m%1, [pw_1]
%else
    phaddd         m%1, m%2
%endif
%endmacro

; %1 = fref_w + %3*stride + %2
%macro MF_PTR 3
    mov             %1, %3
    imul            %1, R11
    add             %1, [R15+me_t.p_fref_w]
    add             %1, %2
%endmacro

; the operand of fenc row pair (16 wide) / packed row quad (8 wide) %1
%macro MF_FENC 1
%if mf_fres
    %assign %%r MF_F0+(%1)
    %xdefine mf_fenc m %+ %%r
%else
    %xdefine mf_fenc [R9+32*(%1)]
%endif
%endmacro

; fenc into m(MF_F0..15), or R9 = it (16 wide) / its packed copy (8 wide); 8 wide packs
; rows 4k, 4k+2 | 4k+1, 4k+3 by qword; avx512: MF_COSTV's k7 (here: after every C call)
%macro MF_FENC_LOAD 2 ; w, h
%if cpuflag(avx512)
    mov            eax, 2
    kmovw           k7, eax
%endif
%if %1 == 16
    mov             R9, [R15+me_t.p_fenc]
  %if mf_fres
    %assign %%k 0
    %rep %2/2
    %assign %%r MF_F0+%%k
    movu   m %+ %%r, [R9+32*%%k]
    %assign %%k %%k+1
    %endrep
  %endif
%else
    mov            rax, [R15+me_t.p_fenc]
    %assign %%k 0
    %rep %2/4
  %if mf_fres
    %assign %%r MF_F0+%%k
    movu          m %+ %%r, [rax+64*%%k]
    vpunpcklqdq   m %+ %%r, m %+ %%r, [rax+64*%%k+32]
  %else
    movu            m0, [rax+64*%%k]
    vpunpcklqdq     m0, m0, [rax+64*%%k+32]
    movu [rsp+F_FENC+32*%%k], m0
  %endif
    %assign %%k %%k+1
    %endrep
  %if mf_fres == 0
    lea             R9, [rsp+F_FENC]
  %endif
%endif
%endmacro

; 16 wide: acc m%1 (+)= sad of rows [%3], [%3+stride] against fenc pair %4; m%2 temp
%macro MF_ROW16 5 ; acc, tmp, ptr, k, first
    movu          xm%2, [%3]
    vinserti128    m%2, m%2, [%3+R11], 1
    MF_FENC %4
%if %5
    psadbw         m%1, m%2, mf_fenc
%else
    psadbw         m%2, m%2, mf_fenc
    paddd          m%1, m%2
%endif
%endmacro

; 8 wide: m%2 = rows [%3] .. [%3+3*stride] packed as fenc's; m%4 temp
%macro MF_QUAD8 4 ; -, dst, ptr, tmp
    movu          xm%2, [%3]
    vinserti128    m%2, m%2, [%3+R11], 1
    movu          xm%4, [%3+R11*2]
    vinserti128    m%4, m%4, [%3+R10], 1
    vpunpcklqdq    m%2, m%2, m%4
%endmacro

%macro MF_ROW8 6 ; acc, tmp, tmp2, ptr, k, first
    MF_QUAD8        0, %2, %4, %3
    MF_FENC %5
%if %6
    psadbw         m%1, m%2, mf_fenc
%else
    psadbw         m%2, m%2, mf_fenc
    paddd          m%1, m%2
%endif
%endmacro

%macro MF_ROW 7 ; w, acc, tmp, tmp2 (8 wide), ptr, k, first
%if %1 == 16
    MF_ROW16        %2, %3, %5, %6, %7
%else
    MF_ROW8         %2, %3, %4, %5, %6, %7
%endif
%endmacro

; the kernels of one size, internal calls with fenc as MF_FENC:
; .s1: eax = sad( rdi ); clobbers rdi, m0, m1, m4, m5
; .a1: eax = sad( avg( rdi, rsi ) ); clobbers rdi, rsi, m0-m2, m4, m5
; .x3 / .x4: xm0 = the sads of rdi, rsi, rdx(, rcx) (.x3: lane 3 = lane 2); clobbers the
;   pointers, m0-m2(, m3), m4, m5
; .cf: eax = cost of the fullpel mv rcx, rdx; clobbers rdi, rsi, as .s1
; .chp: eax = me.c's COST_MV_HPEL cost of the qpel mv ecx, edx; clobbers rcx, rdx, rsi, rdi,
;   R8, as .a1
%macro MF_KERNELS 2 ; w, h
%if %1 == 16
    %assign %%n %2/2
    %assign %%step 2
%else
    %assign %%n %2/4
    %assign %%step 4
%endif
.s1_%1x%2:
%assign %%k 0
%rep %%n
    MF_ROW          %1, 0, 4, 5, rdi, %%k, %%k == 0
  %if %%k < %%n-1
    lea            rdi, [rdi+R11*%%step]
  %endif
  %assign %%k %%k+1
%endrep
    vextracti128   xm1, m0, 1
    paddd          xm0, xm1
    punpckhqdq     xm1, xm0, xm0
    paddd          xm0, xm1
    movd           eax, xm0
    ret

.a1_%1x%2:
%assign %%k 0
%rep %%n
  %if %1 == 16
    movu           xm4, [rdi]
    vinserti128     m4, m4, [rdi+R11], 1
    movu           xm5, [rsi]
    vinserti128     m5, m5, [rsi+R11], 1
    pavgb           m4, m5
  %else
    MF_QUAD8        0, 4, rdi, 5
    MF_QUAD8        0, 1, rsi, 2
    pavgb           m4, m1
  %endif
    MF_FENC %%k
  %if %%k == 0
    psadbw          m0, m4, mf_fenc
  %else
    psadbw          m4, m4, mf_fenc
    paddd           m0, m4
  %endif
  %if %%k < %%n-1
    lea            rdi, [rdi+R11*%%step]
    lea            rsi, [rsi+R11*%%step]
  %endif
  %assign %%k %%k+1
%endrep
    vextracti128   xm1, m0, 1
    paddd          xm0, xm1
    punpckhqdq     xm1, xm0, xm0
    paddd          xm0, xm1
    movd           eax, xm0
    ret

%if %1 != 8 || %2 != 8
%assign %%x 3
%rep 2
.x%[%%x]_%1x%2:
  %assign %%k 0
  %rep %%n
    MF_ROW          %1, 0, 4, 5, rdi, %%k, %%k == 0
    MF_ROW          %1, 1, 4, 5, rsi, %%k, %%k == 0
    MF_ROW          %1, 2, 4, 5, rdx, %%k, %%k == 0
    %if %%x == 4
    MF_ROW          %1, 3, 4, 5, rcx, %%k, %%k == 0
    %endif
    %if %%k < %%n-1
    lea            rdi, [rdi+R11*%%step]
    lea            rsi, [rsi+R11*%%step]
    lea            rdx, [rdx+R11*%%step]
     %if %%x == 4
    lea            rcx, [rcx+R11*%%step]
     %endif
    %endif
    %assign %%k %%k+1
  %endrep
    packssdw        m0, m1              ; per lane { s0 s0' s1 s1' }
  %if %%x == 4
    packssdw        m2, m3
  %else
    packssdw        m2, m2
  %endif
    MF_HADDD         0, 2
    vextracti128   xm1, m0, 1
    paddd          xm0, xm1
    ret
  %assign %%x %%x+1
%endrep

; m0 = { the sads of rdi, rsi, rdx, rcx | rax, rbp, rax, rbp }; clobbers them, m1-m7
.x6_%1x%2:
%assign %%k 0
%rep %%n
    MF_ROW          %1, 0, 6, 7, rdi, %%k, %%k == 0
    MF_ROW          %1, 1, 6, 7, rsi, %%k, %%k == 0
    MF_ROW          %1, 2, 6, 7, rdx, %%k, %%k == 0
    MF_ROW          %1, 3, 6, 7, rcx, %%k, %%k == 0
    MF_ROW          %1, 4, 6, 7, rax, %%k, %%k == 0
    MF_ROW          %1, 5, 6, 7, rbp, %%k, %%k == 0
  %if %%k < %%n-1
    lea            rdi, [rdi+R11*%%step]
    lea            rsi, [rsi+R11*%%step]
    lea            rdx, [rdx+R11*%%step]
    lea            rcx, [rcx+R11*%%step]
    lea            rax, [rax+R11*%%step]
    lea            rbp, [rbp+R11*%%step]
  %endif
  %assign %%k %%k+1
%endrep
    packssdw        m0, m1
    packssdw        m2, m3
    packssdw        m4, m5
    MF_HADDD         0, 2               ; per lane { s0 s1 s2 s3 }
    MF_HADDD         4, 4               ; per lane { s4 s5 s4 s5 }
%if cpuflag(avx512)
    vinserti128     m1, m0, xm4, 1
    vshufi64x2      m0, m0, m4, 3
%else
    vperm2i128      m1, m0, m4, 0x20
    vperm2i128      m0, m0, m4, 0x31
%endif
    paddd           m0, m1
    ret
%endif ; !8x8: sad_hex_search_8x8

.cf_%1x%2:
    mov            rax, [rsp+8+F_CMX]
    movzx          esi, word [rax+rcx*8]
    mov            rax, [rsp+8+F_CMY]
    movzx          eax, word [rax+rdx*8]
    add            esi, eax
    MF_PTR         rdi, rcx, rdx
    call .s1_%1x%2
    add            eax, esi
    ret

.chp_%1x%2:
    movsxd         rcx, ecx
    movsxd         rdx, edx
    mov            rax, [rsp+8+F_CMX]
    movzx          R8d, word [rax+rcx*2]
    mov            rax, [rsp+8+F_CMY]
    movzx          eax, word [rax+rdx*2]
    add            R8d, eax             ; the mv cost
    mov            esi, ecx
    and            esi, 3
    mov            edi, edx
    and            edi, 3
    sar            rcx, 2
    sar            rdx, 2
    imul           rdx, R11
    add            rdx, rcx             ; offset
    lea            ecx, [rsi+rdi*4]     ; qpel_idx
    lea            eax, [rdi+1]
    shr            eax, 2
    neg            rax
    and            rax, R11             ; ((my&3) == 3) * stride
    add            rax, rdx
    inc            esi
    shr            esi, 2               ; (mx&3) == 3
    add            rsi, rdx
    lea            rdx, [me_hpel_ref]
    movzx          edi, byte [rdx+rcx]
    mov            rdi, [R15+me_t.p_fref+rdi*8]
    add            rdi, rax             ; src1
    movzx          eax, byte [rdx+rcx+16]
    add            rsi, [R15+me_t.p_fref+rax*8] ; src2
    test           ecx, 5
    jz .chp1_%1x%2
    call .a1_%1x%2
    add            eax, R8d
    ret
.chp1_%1x%2:
    call .s1_%1x%2
    add            eax, R8d
    ret
%endmacro

; mvc[0..i_mvc) -> mvc_temp[2..], eax = the count, as x264_predictor_clip (%1 = 0) or
; x264_predictor_roundclip (%1 = 1): 16-bit lanes, the unclipped (rounded) mv dropped if
; 0 or pmv, max then min; i_mvc > 0; clobbers rsi, ecx, edx, R8d, xm0-xm3
%macro MF_PRED_CLIP 1
    mov            rsi, [rbx+me_fpel.mv_limit]
    movd           xm1, [rsi]
    movd           xm2, [rsi+4]
%if %1 == 0
    psllw          xm1, 2
    psllw          xm2, 2
%else
    vpbroadcastd   xm3, [me_pw_2]
%endif
    mov            rsi, [rbx+me_fpel.mvc]
    mov            ecx, [rbx+me_fpel.i_mvc]
    xor            eax, eax
%%loop:
    movd           xm0, [rsi]
%if %1
    paddw          xm0, xm3
    psraw          xm0, 2
%endif
    movd           R8d, xm0
    pmaxsw         xm0, xm1
    pminsw         xm0, xm2
    movd [rsp+F_MVCT+8+rax*4], xm0
    xor            edx, edx
    cmp            R8d, [rsp+F_PMV]
    setne           dl
    test           R8d, R8d
    cmovz          edx, R8d
    add            eax, edx
    add            rsi, 4
    dec            ecx
    jnz %%loop
%endmacro

; the search of one size from .s%1x%2: R12, R13 bmx, bmy, R14d bcost; to .fpel_done
%macro MF_BODY 2 ; w, h
%if %1 == 16
    %assign MF_F0 16-%2/2
%else
    %assign MF_F0 16-%2/4
%endif
.s%1x%2:
    MF_FENC_LOAD    %1, %2
    test   byte [rbx+me_fpel.flags], ME_FPEL_SUBME3
    jnz .s%1x%2_sub3

    ; subme < 3: the fullpel mvp, its sad alone
    mov            rsi, [rbx+me_fpel.mv_limit]
    movsx          eax, word [R15+me_t.mvp]
    add            eax, 2
    sar            eax, 2
    movsx          ecx, word [rsi]
    movsx          edx, word [rsi+4]
    CLIP3          eax, ecx, edx, edi
    movsxd         R12, eax
    movsx          eax, word [R15+me_t.mvp+2]
    add            eax, 2
    sar            eax, 2
    movsx          ecx, word [rsi+2]
    movsx          edx, word [rsi+6]
    CLIP3          eax, ecx, edx, edi
    movsxd         R13, eax
    PACKMV         eax, R12d, R13d, ecx
    mov    [rsp+F_PMV], eax
    MF_PTR         rdi, R12, R13
    call .s1_%1x%2
    mov           R14d, eax
    test           eax, eax
    jz .fpel_done
    cmp    dword [rbx+me_fpel.i_mvc], 0
    jle .s%1x%2_zero2
    MF_PRED_CLIP    1
    test           eax, eax
    jle .s%1x%2_zero2
    shl           R14d, 4
    mov            ecx, [rsp+F_PMV]
    mov    [rsp+F_MVCT+4], ecx
    mov            R8d, eax
    mov            ebp, 1
.s%1x%2_pred2:
    movsx          rcx, word [rsp+F_MVCT+4+rbp*4]
    movsx          rdx, word [rsp+F_MVCT+6+rbp*4]
    call .cf_%1x%2
    shl            eax, 4
    add            eax, ebp
    cmp            eax, R14d
    cmovl         R14d, eax
    inc            ebp
    cmp            ebp, R8d
    jle .s%1x%2_pred2
    mov            eax, R14d
    and            eax, 15
    movsx          R12, word [rsp+F_MVCT+4+rax*4]
    movsx          R13, word [rsp+F_MVCT+6+rax*4]
    sar           R14d, 4
.s%1x%2_zero2:
    cmp    dword [rsp+F_PMV], 0
    je .s%1x%2_hex
    xor            ecx, ecx
    xor            edx, edx
    call .cf_%1x%2
    cmp            eax, R14d
    jge .s%1x%2_hex
    mov           R14d, eax
    xor           R12d, R12d
    xor           R13d, R13d
    jmp .s%1x%2_hex

.s%1x%2_sub3:
    ; the mvp clipped to the spel limits, its subpel cost
    mov            rsi, [rbx+me_fpel.mv_limit]
    movsx          eax, word [R15+me_t.mvp]
    movsx          ecx, word [rsi]
    shl            ecx, 2
    movsx          edx, word [rsi+4]
    shl            edx, 2
    CLIP3          eax, ecx, edx, R8d
    mov    [rsp+F_BPX], eax
    movsx          edi, word [R15+me_t.mvp+2]
    movsx          ecx, word [rsi+2]
    shl            ecx, 2
    movsx          edx, word [rsi+6]
    shl            edx, 2
    CLIP3          edi, ecx, edx, R8d
    mov    [rsp+F_BPY], edi
    PACKMV         ecx, eax, edi, edx
    mov    [rsp+F_PMV], ecx
    mov            ecx, eax
    mov            edx, edi
    call .chp_%1x%2
    mov    [rsp+F_BPC], eax
    mov    [rsp+F_PMVC], eax
    ; pred == fenc at the unclipped mvp
    mov            rcx, [R15+me_t.p_cost_mv]
    movzx          ecx, word [rcx]
    add            ecx, ecx
    cmp            eax, ecx
    je .zexit
    mov            ecx, [rbx+me_fpel.i_mvc]
    test           ecx, ecx
    jle .s%1x%2_round3
    cmp            ecx, PREDICTOR_DEDUPE_MIN
    jl .s%1x%2_clip3
    mov            rax, [rbx+me_fpel.fn]
    mov            rax, [rax+me_fpel_fn.predictor_clip]
    test           rax, rax
    jz .s%1x%2_clip3
    ; predictor_clip( mvc_temp+2, mvc, i_mvc, mv_limit_fpel, pmv ), then what it clobbered
    lea            rdi, [rsp+F_MVCT+8]
    mov            rsi, [rbx+me_fpel.mvc]
    mov            edx, ecx
    mov            rcx, [rbx+me_fpel.mv_limit]
    mov            R8d, [rsp+F_PMV]
    call           rax
    movsxd         R11, dword [R15+me_t.i_stride]
    lea            R10, [R11*3]
    mov            R12d, eax
    MF_FENC_LOAD    %1, %2
    mov            eax, R12d
    jmp .s%1x%2_clipped3
.s%1x%2_clip3:
    MF_PRED_CLIP    0
.s%1x%2_clipped3:
    test           eax, eax
    jle .s%1x%2_round3
    mov           R14d, [rsp+F_BPC]
    shl           R14d, 4
    mov           R13d, eax
    mov            eax, [rsp+F_PMV]
    mov    [rsp+F_MVCT+4], eax
    mov           R12d, 1
.s%1x%2_pred3:
    movsx          ecx, word [rsp+F_MVCT+4+R12*4]
    movsx          edx, word [rsp+F_MVCT+6+R12*4]
    call .chp_%1x%2
    shl            eax, 4
    add            eax, R12d
    cmp            eax, R14d
    cmovl         R14d, eax
    inc           R12d
    cmp           R12d, R13d
    jle .s%1x%2_pred3
    mov            eax, R14d
    and            eax, 15
    movsx          ecx, word [rsp+F_MVCT+4+rax*4]
    mov    [rsp+F_BPX], ecx
    movsx          ecx, word [rsp+F_MVCT+6+rax*4]
    mov    [rsp+F_BPY], ecx
    sar           R14d, 4
    mov    [rsp+F_BPC], R14d
.s%1x%2_round3:
    ; the best predictor rounded to fullpel; its sad if it is subpel
    mov            eax, [rsp+F_BPX]
    mov            edx, [rsp+F_BPY]
    PACKMV         ecx, eax, edx, edi
    mov    [rsp+F_BPMV], ecx
    add            eax, 2
    sar            eax, 2
    movsxd         R12, eax
    add            edx, 2
    sar            edx, 2
    movsxd         R13, edx
    mov           R14d, [rsp+F_BPC]
    test           ecx, 0x00030003
    jz .s%1x%2_zero3
    mov           R14d, COST_MAX
    mov            rcx, R12
    mov            rdx, R13
    call .cf_%1x%2
    cmp            eax, R14d
    cmovl         R14d, eax
.s%1x%2_zero3:
    cmp    dword [rsp+F_PMV], 0
    je .s%1x%2_zero3_pmv
    mov            eax, R12d
    or             eax, R13d
    jz .s%1x%2_hex
    xor            ecx, ecx
    xor            edx, edx
    call .cf_%1x%2
    cmp            eax, R14d
    jge .s%1x%2_hex
    mov           R14d, eax
    xor           R12d, R12d
    xor           R13d, R13d
    jmp .s%1x%2_hex
.s%1x%2_zero3_pmv:
    ; a subpel candidate better than the zero vector
    mov            eax, [rsp+F_PMVC]
    cmp            eax, R14d
    jge .s%1x%2_hex
    mov           R14d, eax
    xor           R12d, R12d
    xor           R13d, R13d

.s%1x%2_hex:
%if %1 == 8 && %2 == 8
    ; sad_hex_search_8x8's register entry (bcost, iters, range in rax, R10, R11): the
    ; hexagon, half hexagons and square in shared windows
    MF_MVRANGE_INIT
    mov            rdx, R11
    mov            R11, rax
    mov            rdi, [R15+me_t.p_fenc]
    mov            rsi, [R15+me_t.p_fref_w]
    mov            rcx, [rsp+F_CMX]
    mov             R8, [rsp+F_CMY]
    PACKMV         R9d, R12d, R13d, eax
    mov            eax, R14d
    mov           R10d, [rbx+me_fpel.me_range]
%if cpuflag(avx512)
    ; fn->hex_search's kernel: vdbpsadbw, or the avx2 / avx512icl one where that is dispatched
    mov            R12, [rbx+me_fpel.fn]
    mov            R12, [R12+me_fpel_fn.hex_search]
    lea            R13, [pixel_sad_hex_search_8x8_avx2]
    cmp            R13, R12
    je .s%1x%2_hex_avx2
    lea            R13, [pixel_sad_hex_search_8x8_avx512icl]
    cmp            R13, R12
    je .s%1x%2_hex_icl
    call pixel_sad_hex_search_reg_8x8_avx512
    jmp .s%1x%2_hex_ret
.s%1x%2_hex_icl:
    call pixel_sad_hex_search_reg_8x8_avx512icl
    jmp .s%1x%2_hex_ret
.s%1x%2_hex_avx2:
%endif
    call pixel_sad_hex_search_reg_8x8_avx2
.s%1x%2_hex_ret:
    mov           R14d, eax
    shr            rax, 32
    movsx          R12, ax
    sar            eax, 16
    movsxd         R13, eax
    movsxd         R11, dword [R15+me_t.i_stride]
    jmp .fpel_done
%else
    ; hexagon: hex2[1..6], idx 2-7
    shl           R14d, 6
    MF_PTR          R8, R12, R13
    lea            rdi, [R8-2]
    lea            rsi, [R8+R11*2-1]
    lea            rdx, [R8+R11*2+1]
    lea            rcx, [R8+2]
    mov            rbp, R8
    sub            rbp, R11
    sub            rbp, R11
    lea            rax, [rbp+1]
    dec            rbp
    call .x6_%1x%2
    mova            m6, m0
    MF_COSTS        0, [mf_hex_xidx], [mf_hex_yidx]
    paddd           m0, m6
    pslld           m0, 6
    paddd           m0, [mf_hex_rank]
    vextracti128   xm1, m0, 1
    pminsd         xm0, xm1
    MF_MIN4        eax
    cmp            eax, R14d
    cmovl         R14d, eax
    test          R14d, 63
    jz .s%1x%2_hex_end
    mov            eax, R14d
    and            eax, 63
    sub            eax, 2
    mov            ebp, eax
    HEX_MOVE
    ; half hexagons, not overlapping the previous iteration: ebp = dir | i << 8
    mov            eax, [rbx+me_fpel.me_range]
    sar            eax, 1
    dec            eax
    shl            eax, 8
    or             ebp, eax
    cmp            ebp, 1<<8
    jl .s%1x%2_hex_end
    MF_MVRANGE_INIT
.s%1x%2_walk:
    MF_CHECK_MVRANGE .s%1x%2_hex_end
    and           R14d, ~63
    MF_PTR          R8, R12, R13
    movzx          eax, bpl
    lea            rcx, [me_hex2]
    lea            rcx, [rcx+rax*2]
    MF_HH_PTR      rdi, 0
    MF_HH_PTR      rsi, 1
    MF_HH_PTR      rdx, 2
    call .x3_%1x%2
    movzx          eax, bpl
    shl            eax, 4
    lea            rcx, [mf_hh_xidx]
    MF_COSTS        2, [rcx+rax], [rcx+rax+mf_hh_yidx-mf_hh_xidx]
    paddd          xm0, xm2
    pslld          xm0, 6
    paddd          xm0, [mf_hh_rank]
    MF_MIN4        eax
    cmp            eax, R14d
    cmovl         R14d, eax
    test          R14d, 63
    jz .s%1x%2_hex_end
    mov            eax, R14d
    and            eax, 63
    sub            eax, 2
    movzx          ecx, bpl
    add            eax, ecx
    cdqe                                ; -1 .. 6
    lea            rcx, [me_mod6m1]
    movzx          eax, byte [rcx+rax+1]
    sub            ebp, 1<<8
    and            ebp, ~255
    or             ebp, eax
    HEX_MOVE
    cmp            ebp, 1<<8
    jge .s%1x%2_walk
.s%1x%2_hex_end:
    and           R14d, ~63

%if %1 == 16
    ; square refine in windows: rows r-1, r, r+1 at dx -1 | 1 and dx 0 at rows
    ; r-1 | r+1, against fenc row r in both lanes (memory: m8, m9 are free now)
    MF_PTR         rdi, R12, R13
    sub            rdi, R11
    dec            rdi
    MF_SQ16         %2
    packusdw        m1, m3
    packusdw        m2, m0
    packusdw        m1, m2
    pmaddwd         m6, m1, [pw_1]
    MF_COSTS        0, [mf_sq16_xidx], [mf_sq16_yidx]
    paddd           m0, m6
    pslld           m0, 6
    paddd           m0, [mf_sq16_rank]
%else
    ; square refine: square1[1..4] | square1[5..8]
    MF_PTR          R8, R12, R13
    mov            rdi, R8
    sub            rdi, R11
    lea            rsi, [R8+R11]
    lea            rdx, [R8-1]
    lea            rcx, [R8+1]
    call .x4_%1x%2
    mova           xm7, xm0
    lea            rdi, [R8-1]
    sub            rdi, R11
    lea            rsi, [R8+R11-1]
    lea            rdx, [rdi+2]
    lea            rcx, [R8+R11+1]
    call .x4_%1x%2
    vinserti128     m6, m7, xm0, 1
    MF_COSTS        0, [mf_sq_xidx], [mf_sq_yidx]
    paddd           m0, m6
    pslld           m0, 6
    paddd           m0, [mf_sq_rank]
%endif
    vextracti128   xm1, m0, 1
    pminsd         xm0, xm1
    MF_MIN4        eax
    cmp            eax, R14d
    cmovl         R14d, eax
    mov            eax, R14d
    and            eax, 63
    lea            rcx, [me_square1]
    movsx          rdx, byte [rcx+rax*2]
    add            R12, rdx
    movsx          rdx, byte [rcx+rax*2+1]
    add            R13, rdx
    sar           R14d, 6
    jmp .fpel_done
%endif

    MF_KERNELS      %1, %2
%endmacro

; the square of 16 wide blocks at rdi = pix - 1 - stride (advanced): m0 dy 0 (dx -1 | 1), m1 dy -1,
; m2 dy 1, m3 dx 0 (dy -1 | 1); fenc rows from R9; clobbers m4-m9
%macro MF_WIN 3 ; dst, row a, row b
    movu          xm%1, [%2]
    vinserti128    m%1, m%1, [%3], 1
%endmacro
%macro MF_ACC 5 ; acc, src, fenc, tmp, first
%if %5
    psadbw         m%1, m%2, m%3
%else
    psadbw         m%4, m%2, m%3
    paddd          m%1, m%4
%endif
%endmacro
%macro MF_SQ16 1 ; h
    MF_WIN          4, rdi, rdi+2
    MF_WIN          5, rdi+R11, rdi+R11+2
%assign %%r 0
%rep %1
    %assign %%ro 4+(%%r % 3)
    %assign %%rc 4+((%%r+1) % 3)
    %assign %%rn 4+((%%r+2) % 3)
    vbroadcasti128  m8, [R9+%%r*16]
    MF_WIN   %%rn, rdi+R11*2, rdi+R11*2+2
    MF_WIN          9, rdi+1, rdi+R11*2+1
    MF_ACC          1, %%ro, 8, 7, %%r == 0
    MF_ACC          0, %%rc, 8, 7, %%r == 0
    MF_ACC          2, %%rn, 8, 7, %%r == 0
    MF_ACC          3, 9, 8, 7, %%r == 0
  %if %%r < %1-1
    add            rdi, R11
  %endif
  %assign %%r %%r+1
%endrep
%endmacro

; %1 = R8 + hex2[dir+%2] (rcx = &hex2[dir]) as a pointer offset; clobbers rax
%macro MF_HH_PTR 2
    movsx           %1, byte [rcx+2*%2+1]
    imul            %1, R11
    movsx          rax, byte [rcx+2*%2]
    add             %1, rax
    add             %1, R8
%endmacro

; rax = mv_min | mv_max << 32 to F_MVR: mv_min = pack16to32_mask2( -xmin, -ymin ),
; mv_max = pack16to32_mask2( xmax, ymax ) | 0x8000; clobbers rcx, rdx, rsi
%macro MF_MVRANGE_INIT 0
    mov            rsi, [rbx+me_fpel.mv_limit]
    movsx          eax, word [rsi]
    movsx          ecx, word [rsi+2]
    neg            eax
    shl            eax, 16
    neg            ecx
    and            ecx, 0x7fff
    or             eax, ecx
    movsx          edx, word [rsi+4]
    movsx          ecx, word [rsi+6]
    shl            edx, 16
    and            ecx, 0x7fff
    or             edx, ecx
    or             edx, 0x8000
    shl            rdx, 32
    or             rax, rdx
    mov    [rsp+F_MVR], rax
%endmacro

; CHECK_MVRANGE( R12, R13 ), jumps to %1 if out of range
%macro MF_CHECK_MVRANGE 1
    mov            eax, R12d
    shl            eax, 16
    mov            ecx, R13d
    and            ecx, 0x7fff
    or             eax, ecx
    mov            ecx, [rsp+F_MVR]
    add            ecx, eax
    mov            edx, [rsp+F_MVR+4]
    sub            edx, eax
    or             ecx, edx
    test           ecx, 0x80004000
    jnz %1
%endmacro

;-----------------------------------------------------------------------------
; int me_search_fpel( x264_me_fpel_t *c ), see encoder/me.h
;-----------------------------------------------------------------------------
; rbx c, R15 m, R11 stride, R10 3*stride, R9 fenc (MF_FENC_LOAD), R12/R13 bmx/bmy, R14d bcost
; or its key; rbp and R8 loop state. avx512: the same search on m0-m15 (x86inc's ymm16-31,
; EVEX), 8x8 on fn->hex_search's kernel
%macro MF_SEARCH 0
cglobal me_search_fpel, 1,1
    push           rbx
    push           rbp
    push           R12
    push           R13
    push           R14
    push           R15
    sub            rsp, F_SIZE
    mov            rbx, rdi
    mov            R15, [rdi+me_fpel.m]
    movsxd         R11, dword [R15+me_t.i_stride]
    lea            R10, [R11*3]
    mov            rcx, [R15+me_t.p_cost_mv]
    movsx          rax, word [R15+me_t.mvp]
    add            rax, rax
    mov            rdx, rcx
    sub            rdx, rax
    mov    [rsp+F_CMX], rdx
    movsx          rax, word [R15+me_t.mvp+2]
    add            rax, rax
    sub            rcx, rax
    mov    [rsp+F_CMY], rcx
    mov            eax, [R15+me_t.i_pixel]
    test           eax, eax
    jz .s16x16
    cmp            eax, 3               ; PIXEL_8x8
    je .s8x8
    cmp            eax, 1               ; PIXEL_16x8
    je .s16x8
    jmp .s8x16

.zexit:
    ; eax the pmv cost
    mov            ecx, [rsp+F_PMV]
    test   byte [rbx+me_fpel.flags], ME_FPEL_ZEXIT
    jz .zexit_search
    mov    [R15+me_t.mv], ecx
    mov    [R15+me_t.cost], eax
    mov            rcx, [rbx+me_fpel.halfpel_thresh]
    test           rcx, rcx
    jz .zexit_costmv
    imul           edx, eax, 7
    sar            edx, 3
    cmp            edx, [rcx]
    jg .ret0
    cmp            eax, [rcx]
    jge .zexit_costmv
    mov          [rcx], eax
.zexit_costmv:
    mov    [R15+me_t.cost_mv], eax
    jmp .ret0
.zexit_search:
    ; bpred_mv = pmv, bmv the fullpel pmv, bcost COST_MAX
    mov    [rsp+F_BPMV], ecx
    mov            eax, [rsp+F_BPX]
    add            eax, 2
    sar            eax, 2
    movsxd         R12, eax
    mov            eax, [rsp+F_BPY]
    add            eax, 2
    sar            eax, 2
    movsxd         R13, eax
    mov           R14d, COST_MAX

.fpel_done:
    PACKMV         eax, R12d, R13d, ecx
    mov            edx, eax
    shl            edx, 2
    and            edx, 0xFFFCFFFC
    test   byte [rbx+me_fpel.flags], ME_FPEL_SUBME3
    jnz .done3
    ; cost_mv, the real cost (+ cost_mv at the pmv), mv
    mov            rsi, [rsp+F_CMX]
    movzx          ecx, word [rsi+R12*8]
    mov            rsi, [rsp+F_CMY]
    movzx          esi, word [rsi+R13*8]
    add            ecx, esi
    mov    [R15+me_t.cost_mv], ecx
    xor            esi, esi
    cmp            eax, [rsp+F_PMV]
    cmove          esi, ecx
    add            esi, R14d
    mov    [R15+me_t.cost], esi
    mov    [R15+me_t.mv], edx
    jmp .subpel
.done3:
    mov            ecx, [rsp+F_BPC]
    cmp            ecx, R14d
    cmovl          edx, [rsp+F_BPMV]
    mov    [R15+me_t.mv], edx
    cmp            ecx, R14d
    cmovg          ecx, R14d
    mov    [R15+me_t.cost], ecx
.subpel:
    test   byte [rbx+me_fpel.flags], ME_FPEL_REFINE
    jz .ret0
    mov            rax, [rbx+me_fpel.qfenc]
    test           rax, rax
    jnz .subpel_call
    mov            eax, 1
    jmp .ret
.subpel_call:
    ; subpel( fenc, fref, stride, cost_mvx, cost_mvy, mv, cost, iters, range, qfenc, qpel,
    ; halfpel_thresh, mvp ), the int stack arguments as qwords (x86inc loads qwords)
    mov    [rsp+F_OUT+24], rax
    mov            rdi, [R15+me_t.p_fenc]
    lea            rsi, [R15+me_t.p_fref]
    mov            rdx, R11
    mov            rcx, [rsp+F_CMX]
    mov             R8, [rsp+F_CMY]
    mov            R9d, [R15+me_t.mv]
    mov            eax, [R15+me_t.cost]
    mov    [rsp+F_OUT], rax
    mov            eax, [rbx+me_fpel.iters]
    mov    [rsp+F_OUT+8], rax
    mov            rax, [rbx+me_fpel.range]
    mov    [rsp+F_OUT+16], rax
    mov            rax, [rbx+me_fpel.fn]
    mov            R10, [rax+me_fpel_fn.qpel]
    mov    [rsp+F_OUT+32], R10
    mov            R10, [rbx+me_fpel.halfpel_thresh]
    mov    [rsp+F_OUT+40], R10
    mov           R10d, [R15+me_t.mvp]
    mov    [rsp+F_OUT+48], R10
    call   [rax+me_fpel_fn.subpel]
    mov            ecx, eax
    and            ecx, 0x7fffffff
    mov    [R15+me_t.cost], ecx
    mov            rdx, rax
    shr            rdx, 32
    mov    [R15+me_t.mv], edx
    ; the halfpel threshold stop leaves cost_mv
    test           eax, eax
    js .ret0
    movsx          rcx, dx
    sar            edx, 16
    movsxd         rdx, edx
    mov            rsi, [rsp+F_CMX]
    movzx          ecx, word [rsi+rcx*2]
    mov            rsi, [rsp+F_CMY]
    movzx          edx, word [rsi+rdx*2]
    add            ecx, edx
    mov    [R15+me_t.cost_mv], ecx
.ret0:
    xor            eax, eax
.ret:
    add            rsp, F_SIZE
    pop            R15
    pop            R14
    pop            R13
    pop            R12
    pop            rbp
    pop            rbx
%if notcpuflag(avx512)
    vzeroupper
%endif
    ret

    MF_BODY         16, 16
    MF_BODY          8,  8
    MF_BODY         16,  8
    MF_BODY          8, 16
%endmacro

INIT_YMM avx2
%assign mf_fres FENC_RES
MF_SEARCH
INIT_YMM avx512
%assign mf_fres FENC_RES512
MF_SEARCH
%endif ; HIGH_BIT_DEPTH == 0

%if HIGH_BIT_DEPTH
INIT_XMM avx2
ME_SEARCH_FPEL me_search_fpel
INIT_YMM avx512
ME_SEARCH_FPEL me_search_fpel
%endif
INIT_ZMM avx512
ME_SEARCH_FPEL me_search_fpel_zmm

%endif ; UNIX64
