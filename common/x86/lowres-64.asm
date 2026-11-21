;*****************************************************************************
;* lowres-64.asm: x86_64 lowres analysis
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

SECTION_RODATA

; x264_hpel_ref0, x264_hpel_ref1
lp_hpel_ref: db 0,1,1,1,0,1,1,1,2,3,3,3,0,1,1,1
             db 0,0,1,0,2,2,3,2,2,2,3,2,2,2,3,2
; the qpel diamond, dx dy of dir+1
lp_qpel_dir: db 0,0, 0,-1, 0,1, -1,0, 1,0
; pixel-a.asm's hmul_8p, a lane
lp_hmul_8p:  times 8 db 1
             times 4 db 1, -1

SECTION .text

cextern pw_1
cextern pixel_sad_hex_search_8x8_avx2
cextern pixel_sad_hex_search_reg_8x8_avx2

%define TRANS TRANS_SSE4

; x264_lowres_p_t (encoder/me.h); the layout is checked in encoder/me.c
struc lowres_p
    .fenc_pre:     resq 1
    .satd:         resq 1
    .satd_avg2:    resq 1
    .sad:          resq 1
    .sad_avg2:     resq 1
    .hex_search:   resq 1
    .hpel_min:     resq 1
    .intra:        resq 1
    .get_ref:      resq 1
    .fenc:         resq 1
    .ref:          resq 4
    .ref_w:        resq 1
    .weight:       resq 1
    .cost_mv:      resq 1
    .mvs:          resq 1
    .mv_costs:     resq 1
    .costs:        resq 1
    .intra_cost:   resq 1
    .inv_qscale:   resq 1
    .output_inter: resq 1
    .output_intra: resq 1
    .stride:       resq 1
    .lambda:       resd 1
    .skip_thresh:  resd 1
    .mv_range:     resd 1
    .me_range:     resd 1
    .mb_width:     resd 1
    .mb_height:    resd 1
    .slice_start:  resd 1
    .slice_end:    resd 1
    .start_x:      resd 1
    .end_x:        resd 1
    .start_y:      resd 1
    .end_y:        resd 1
    .do_search:    resd 1
    .weighted:     resd 1
    .corr_intra:   resq 1
    .corr_inter:   resq 1
    .corr_intra_max: resd 1
    .corr_inter_max: resd 1
endstruc

; stack: outgoing arguments at 0, then 64-aligned buffers and the locals.
; Offsets are preprocessor numbers: cglobal's stack size has to be one.
%assign lp_stack_pos 0
%macro LP_STACK_FIELD 2 ; name, bytes
    %xdefine S_%1 lp_stack_pos
    %assign lp_stack_pos lp_stack_pos+%2
%endmacro
LP_STACK_FIELD ARGS,    64  ; outgoing arguments
LP_STACK_FIELD FENC,   128  ; 8x8 at FENC_STRIDE
LP_STACK_FIELD PRE,    128  ; fenc_pre
LP_STACK_FIELD PIX,    640  ; get_ref's dst, 64*10
LP_STACK_FIELD FREF,    32  ; the 4 planes at the mb
LP_STACK_FIELD REFW,     8
LP_STACK_FIELD CMX,      8
LP_STACK_FIELD CMY,      8
LP_STACK_FIELD RANGE,    8
LP_STACK_FIELD HSTR,     8  ; get_ref's stride
LP_STACK_FIELD SRC0,     8
LP_STACK_FIELD KEY,      8
LP_STACK_FIELD ROW,      8
LP_STACK_FIELD MVC,     16  ; 4 mvs
LP_STACK_FIELD MVCT,    16  ; 4 clipped mvs
LP_STACK_FIELD XMIN,     4  ; spel limits
LP_STACK_FIELD XMAX,     4
LP_STACK_FIELD YMIN,     4
LP_STACK_FIELD YMAX,     4
LP_STACK_FIELD XMINF,    4  ; fpel limits
LP_STACK_FIELD XMAXF,    4
LP_STACK_FIELD YMINF,    4
LP_STACK_FIELD YMAXF,    4
LP_STACK_FIELD MVP,      4
LP_STACK_FIELD NMVC,     4
LP_STACK_FIELD PMV,      4
LP_STACK_FIELD PMVC,     4
LP_STACK_FIELD BPC,      4
LP_STACK_FIELD BPX,      4
LP_STACK_FIELD BPY,      4
LP_STACK_FIELD BC,       4
LP_STACK_FIELD BMX,      4
LP_STACK_FIELD BMY,      4
LP_STACK_FIELD TMX,      4
LP_STACK_FIELD TMY,      4
LP_STACK_FIELD I,        4
LP_STACK_FIELD N,        4
LP_STACK_FIELD MV,       4
LP_STACK_FIELD MCOST,    4
LP_STACK_FIELD SCORE,    4
%assign LP_STACK (lp_stack_pos+63) & ~63

; x264_clip3( %1, %2, %3 ) into %1; %4 temp
%macro CLIP3 4
    mov    %4, %1
    cmp    %1, %3
    cmovg  %4, %3
    cmp    %1, %2
    cmovl  %4, %2
    mov    %1, %4
%endmacro

; eax += cost_mvx[tmx] + cost_mvy[tmy]
%macro MVCOST 0
    movsxd rcx, dword [rsp+S_TMX]
    mov    rdx, [rsp+S_CMX]
    movzx  ecx, word [rdx+rcx*2]
    add    eax, ecx
    movsxd rcx, dword [rsp+S_TMY]
    mov    rdx, [rsp+S_CMY]
    movzx  ecx, word [rdx+rcx*2]
    add    eax, ecx
%endmacro

; eax = cmp of the qpel mv (tmx, tmy): %1 0 sad, as subpel_cmp; 1 satd on fenc_pre,
; as subpel_luma_cost
%macro SUBPEL_COST 1
    cmp    dword [rbx+lowres_p.weighted], 0
    jne %%weighted
    movsxd rdi, dword [rsp+S_TMY]
    movsxd rsi, dword [rsp+S_TMX]
    mov    eax, edi
    and    eax, 3
    mov    R11d, esi
    and    R11d, 3
    lea    R8d, [R11+rax*4]         ; qpel_idx
    sar    rdi, 2
    imul   rdi, rbp
    sar    rsi, 2
    add    rdi, rsi                 ; offset
    lea    R10, [lp_hpel_ref]
    movzx  R9d, byte [R10+R8]
    mov    rsi, [rsp+S_FREF+R9*8]
    add    rsi, rdi
    xor    R9d, R9d
    cmp    eax, 3
    cmove  R9, rbp
    add    rsi, R9                  ; src1
    mov    rcx, rbp
    test   R8d, 5
    jz %%one
    movzx  R9d, byte [R10+R8+16]
    mov    rdx, [rsp+S_FREF+R9*8]
    add    rdx, rdi
    xor    R9d, R9d
    cmp    R11d, 3
    sete   R9b
    add    rdx, R9                  ; src2
%if %1
    lea    rdi, [rsp+S_PRE]
    call   [rbx+lowres_p.satd_avg2]
%else
    lea    rdi, [rsp+S_FENC]
    call   [rbx+lowres_p.sad_avg2]
%endif
    jmp %%done
%%weighted:
    mov    qword [rsp+S_HSTR], 16
    lea    rdi, [rsp+S_PIX]
    lea    rsi, [rsp+S_HSTR]
    lea    rdx, [rsp+S_FREF]
    mov    rcx, rbp
    mov    R8d, [rsp+S_TMX]
    mov    R9d, [rsp+S_TMY]
    mov    qword [rsp], 8
    mov    qword [rsp+8], 8
    mov    rax, [rbx+lowres_p.weight]
    mov    [rsp+16], rax
    call   [rbx+lowres_p.get_ref]
    mov    rsi, rax
    mov    rcx, [rsp+S_HSTR]
%%one:
%if %1
    mov    rdx, rcx
    lea    rdi, [rsp+S_PRE]
    call   [rbx+lowres_p.satd]
%else
    mov    rdx, rsi
    mov    esi, 16
    lea    rdi, [rsp+S_FENC]
    call   [rbx+lowres_p.sad]
%endif
%%done:
%endmacro

INIT_XMM avx2
;-----------------------------------------------------------------------------
; void lowres_p_mbs( x264_lowres_p_t *c )
;-----------------------------------------------------------------------------
; rbx: c, rbp: stride, R12: mb_x, R13: mb_y, R14: pel offset, R15: mb_xy
cglobal lowres_p_mbs, 1,15,0, LP_STACK
    mov    rbx, rdi
    mov    rbp, [rbx+lowres_p.stride]
    mov    R13d, [rbx+lowres_p.start_y]
    cmp    R13d, [rbx+lowres_p.end_y]
    jl .end
.row:
    ; y spel limits of slicetype_mb_cost
    mov    eax, R13d
    shl    eax, 5
    neg    eax
    sub    eax, 48
    mov    ecx, [rbx+lowres_p.mv_range]
    neg    ecx
    cmp    eax, ecx
    cmovl  eax, ecx
    mov    [rsp+S_YMIN], eax
    sar    eax, 2
    mov    [rsp+S_YMINF], eax
    mov    eax, [rbx+lowres_p.mb_height]
    sub    eax, R13d
    dec    eax
    shl    eax, 5
    add    eax, 48
    mov    ecx, [rbx+lowres_p.mv_range]
    dec    ecx
    cmp    eax, ecx
    cmovg  eax, ecx
    mov    [rsp+S_YMAX], eax
    sar    eax, 2
    mov    [rsp+S_YMAXF], eax
    mov    eax, R13d
    sub    eax, [rbx+lowres_p.slice_start]
    add    eax, 4
    mov    [rsp+S_ROW], rax
    mov    R12d, [rbx+lowres_p.start_x]
    cmp    R12d, [rbx+lowres_p.end_x]
    jl .rownext

.col:
    mov    eax, R13d
    imul   eax, [rbx+lowres_p.mb_width]
    add    eax, R12d
    mov    R15d, eax
    mov    eax, R13d
    imul   rax, rbp
    add    rax, R12
    lea    R14, [rax*8]
    ; b_frame_score_mb
    xor    eax, eax
    mov    ecx, [rbx+lowres_p.mb_width]
    mov    edx, [rbx+lowres_p.mb_height]
    cmp    ecx, 2
    jle .score1
    cmp    edx, 2
    jle .score1
    test   R12d, R12d
    jle .score0
    dec    ecx
    cmp    R12d, ecx
    jge .score0
    test   R13d, R13d
    jle .score0
    dec    edx
    cmp    R13d, edx
    jge .score0
.score1:
    mov    eax, 1
.score0:
    mov    [rsp+S_SCORE], eax

    ; fenc to FENC_STRIDE, fenc_pre
    mov    rsi, [rbx+lowres_p.fenc]
    add    rsi, R14
    lea    rdx, [rbp*3]
    mov    rax, [rsi]
    mov    rcx, [rsi+rbp]
    mov    R8,  [rsi+rbp*2]
    mov    R9,  [rsi+rdx]
    mov    [rsp+S_FENC+ 0], rax
    mov    [rsp+S_FENC+16], rcx
    mov    [rsp+S_FENC+32], R8
    mov    [rsp+S_FENC+48], R9
    lea    rsi, [rsi+rbp*4]
    mov    rax, [rsi]
    mov    rcx, [rsi+rbp]
    mov    R8,  [rsi+rbp*2]
    mov    R9,  [rsi+rdx]
    mov    [rsp+S_FENC+ 64], rax
    mov    [rsp+S_FENC+ 80], rcx
    mov    [rsp+S_FENC+ 96], R8
    mov    [rsp+S_FENC+112], R9
    lea    rdi, [rsp+S_PRE]
    lea    rsi, [rsp+S_FENC]
    call   [rbx+lowres_p.fenc_pre]

    cmp    dword [rbx+lowres_p.do_search], 0
    je .nosearch

    ; reverse-order mv prediction
    mov    rsi, [rbx+lowres_p.mvs]
    lea    rsi, [rsi+R15*4]
    xor    ecx, ecx
    mov    qword [rsp+S_MVC], 0
    mov    qword [rsp+S_MVC+8], 0
    mov    R8d, [rbx+lowres_p.mb_width]
    dec    R8d
    cmp    R12d, R8d
    jge .noright
    mov    eax, [rsi+4]
    mov    [rsp+S_MVC+rcx*4], eax
    inc    ecx
.noright:
    mov    eax, [rbx+lowres_p.slice_end]
    dec    eax
    cmp    R13d, eax
    jge .nobelow
    mov    eax, [rbx+lowres_p.mb_width]
    lea    rdx, [rsi+rax*4]
    mov    eax, [rdx]
    mov    [rsp+S_MVC+rcx*4], eax
    inc    ecx
    test   R12d, R12d
    jle .nobelowleft
    mov    eax, [rdx-4]
    mov    [rsp+S_MVC+rcx*4], eax
    inc    ecx
.nobelowleft:
    cmp    R12d, R8d
    jge .nobelow
    mov    eax, [rdx+4]
    mov    [rsp+S_MVC+rcx*4], eax
    inc    ecx
.nobelow:
    mov    [rsp+S_NMVC], ecx
    mov    eax, [rsp+S_MVC]
    cmp    ecx, 1
    jle .mvp
    vmovd  xmm0, [rsp+S_MVC]
    vmovd  xmm1, [rsp+S_MVC+4]
    vmovd  xmm2, [rsp+S_MVC+8]
    vpmaxsw xmm3, xmm0, xmm1
    vpminsw xmm0, xmm0, xmm1
    vpminsw xmm3, xmm3, xmm2
    vpmaxsw xmm0, xmm0, xmm3
    vmovd  eax, xmm0
.mvp:
    mov    [rsp+S_MVP], eax
    test   eax, eax
    jnz .search
    ; fast skip of near-zero residual at mv 0
    lea    rdi, [rsp+S_PRE]
    mov    rsi, [rbx+lowres_p.ref]
    add    rsi, R14
    mov    rdx, rbp
    call   [rbx+lowres_p.satd]
    cmp    eax, [rbx+lowres_p.skip_thresh]
    jge .search
    mov    [rsp+S_MCOST], eax
    mov    dword [rsp+S_MV], 0
    jmp .store

.search:
    ; x spel limits; fpel limits and me.c's packed range
    mov    eax, R12d
    shl    eax, 5
    neg    eax
    sub    eax, 48
    mov    ecx, [rbx+lowres_p.mv_range]
    neg    ecx
    cmp    eax, ecx
    cmovl  eax, ecx
    mov    [rsp+S_XMIN], eax
    sar    eax, 2
    mov    [rsp+S_XMINF], eax
    mov    eax, [rbx+lowres_p.mb_width]
    sub    eax, R12d
    dec    eax
    shl    eax, 5
    add    eax, 48
    mov    ecx, [rbx+lowres_p.mv_range]
    dec    ecx
    cmp    eax, ecx
    cmovg  eax, ecx
    mov    [rsp+S_XMAX], eax
    sar    eax, 2
    mov    [rsp+S_XMAXF], eax
    shl    eax, 16
    mov    ecx, [rsp+S_YMAXF]
    and    ecx, 0x7fff
    or     eax, ecx
    or     eax, 0x8000
    shl    rax, 32
    mov    ecx, [rsp+S_XMINF]
    neg    ecx
    shl    ecx, 16
    mov    edx, [rsp+S_YMINF]
    neg    edx
    and    edx, 0x7fff
    or     ecx, edx
    or     rax, rcx
    mov    [rsp+S_RANGE], rax
    ; mv costs about the mvp
    mov    rax, [rbx+lowres_p.cost_mv]
    movsx  rcx, word [rsp+S_MVP]
    movsx  rdx, word [rsp+S_MVP+2]
    add    rcx, rcx
    add    rdx, rdx
    mov    rsi, rax
    sub    rsi, rcx
    mov    [rsp+S_CMX], rsi
    sub    rax, rdx
    mov    [rsp+S_CMY], rax
    ; the planes at the mb
    mov    rax, [rbx+lowres_p.ref]
    mov    rcx, [rbx+lowres_p.ref+8]
    mov    rdx, [rbx+lowres_p.ref+16]
    mov    rsi, [rbx+lowres_p.ref+24]
    mov    rdi, [rbx+lowres_p.ref_w]
    add    rax, R14
    add    rcx, R14
    add    rdx, R14
    add    rsi, R14
    add    rdi, R14
    mov    [rsp+S_FREF], rax
    mov    [rsp+S_FREF+8], rcx
    mov    [rsp+S_FREF+16], rdx
    mov    [rsp+S_FREF+24], rsi
    mov    [rsp+S_REFW], rdi

    ; x264_me_search_ref: the clipped mvp
    mov    R10d, [rsp+S_XMINF]
    mov    R11d, [rsp+S_XMAXF]
    shl    R10d, 2
    shl    R11d, 2
    movsx  eax, word [rsp+S_MVP]
    CLIP3  eax, R10d, R11d, ecx
    mov    [rsp+S_BPX], eax
    mov    [rsp+S_TMX], eax
    mov    R10d, [rsp+S_YMINF]
    mov    R11d, [rsp+S_YMAXF]
    shl    R10d, 2
    shl    R11d, 2
    movsx  edx, word [rsp+S_MVP+2]
    CLIP3  edx, R10d, R11d, ecx
    mov    [rsp+S_BPY], edx
    mov    [rsp+S_TMY], edx
    shl    edx, 16
    movzx  eax, ax
    or     eax, edx
    mov    [rsp+S_PMV], eax
    SUBPEL_COST 0
    MVCOST
    mov    [rsp+S_BPC], eax
    mov    [rsp+S_PMVC], eax
    mov    rcx, [rbx+lowres_p.cost_mv]
    movzx  ecx, word [rcx]
    add    ecx, ecx
    cmp    eax, ecx
    jne .preds
    ; pred == fenc at the mvp: the search and refine_subpel stay
    mov    ecx, [rsp+S_PMV]
    mov    [rsp+S_MV], ecx
    mov    [rsp+S_MCOST], eax
    jmp .searched

.preds:
    ; x264_predictor_clip
    mov    ecx, [rsp+S_NMVC]
    test   ecx, ecx
    jz .fpel
    mov    R10d, [rsp+S_XMINF]
    mov    R11d, [rsp+S_XMAXF]
    mov    edi, [rsp+S_YMINF]
    mov    esi, [rsp+S_YMAXF]
    shl    R10d, 2
    shl    R11d, 2
    shl    edi, 2
    shl    esi, 2
    xor    R8d, R8d
    xor    R9d, R9d
.clip:
    mov    eax, [rsp+S_MVC+R9*4]
    test   eax, eax
    jz .clipnext
    cmp    eax, [rsp+S_PMV]
    je .clipnext
    movsx  eax, word [rsp+S_MVC+R9*4]
    CLIP3  eax, R10d, R11d, edx
    mov    [rsp+S_MVCT+R8*4], ax
    movsx  eax, word [rsp+S_MVC+R9*4+2]
    CLIP3  eax, edi, esi, edx
    mov    [rsp+S_MVCT+R8*4+2], ax
    inc    R8d
.clipnext:
    inc    R9d
    cmp    R9d, ecx
    jl .clip
    test   R8d, R8d
    jz .fpel
    mov    [rsp+S_N], R8d
    mov    eax, [rsp+S_BPC]
    shl    eax, 4
    mov    [rsp+S_KEY], eax
    mov    dword [rsp+S_I], 1
.pred:
    mov    ecx, [rsp+S_I]
    movsx  eax, word [rsp+S_MVCT+rcx*4-4]
    movsx  edx, word [rsp+S_MVCT+rcx*4-2]
    mov    [rsp+S_TMX], eax
    mov    [rsp+S_TMY], edx
    SUBPEL_COST 0
    MVCOST
    shl    eax, 4
    add    eax, [rsp+S_I]
    cmp    eax, [rsp+S_KEY]
    jge .prednext
    mov    [rsp+S_KEY], eax
.prednext:
    mov    ecx, [rsp+S_I]
    inc    ecx
    mov    [rsp+S_I], ecx
    cmp    ecx, [rsp+S_N]
    jle .pred
    mov    eax, [rsp+S_KEY]
    mov    ecx, eax
    and    ecx, 15
    jz .predkeep
    movsx  edx, word [rsp+S_MVCT+rcx*4-4]
    movsx  esi, word [rsp+S_MVCT+rcx*4-2]
    mov    [rsp+S_BPX], edx
    mov    [rsp+S_BPY], esi
.predkeep:
    sar    eax, 4
    mov    [rsp+S_BPC], eax

.fpel:
    ; the best predictor at fullpel
    mov    eax, [rsp+S_BPX]
    mov    ecx, [rsp+S_BPY]
    mov    edx, eax
    or     edx, ecx
    add    eax, 2
    add    ecx, 2
    sar    eax, 2
    sar    ecx, 2
    mov    [rsp+S_BMX], eax
    mov    [rsp+S_BMY], ecx
    test   edx, 3
    jz .fpelpred
    movsxd rdx, dword [rsp+S_BMY]
    imul   rdx, rbp
    movsxd rax, dword [rsp+S_BMX]
    add    rdx, rax
    add    rdx, [rsp+S_REFW]
    lea    rdi, [rsp+S_FENC]
    mov    esi, 16
    mov    rcx, rbp
    call   [rbx+lowres_p.sad]
    mov    ecx, [rsp+S_BMX]
    mov    edx, [rsp+S_BMY]
    shl    ecx, 2
    shl    edx, 2
    mov    [rsp+S_TMX], ecx
    mov    [rsp+S_TMY], edx
    MVCOST
    mov    [rsp+S_BC], eax
    jmp .zero
.fpelpred:
    mov    eax, [rsp+S_BPC]
    mov    [rsp+S_BC], eax
.zero:
    ; the zero vector
    cmp    dword [rsp+S_PMV], 0
    je .zeropmv
    mov    eax, [rsp+S_BMX]
    or     eax, [rsp+S_BMY]
    jz .hex
    lea    rdi, [rsp+S_FENC]
    mov    esi, 16
    mov    rdx, [rsp+S_REFW]
    mov    rcx, rbp
    call   [rbx+lowres_p.sad]
    mov    dword [rsp+S_TMX], 0
    mov    dword [rsp+S_TMY], 0
    MVCOST
    jmp .zerocmp
.zeropmv:
    mov    eax, [rsp+S_PMVC]
.zerocmp:
    cmp    eax, [rsp+S_BC]
    jge .hex
    mov    [rsp+S_BC], eax
    mov    dword [rsp+S_BMX], 0
    mov    dword [rsp+S_BMY], 0

.hex:
    lea    rdi, [rsp+S_FENC]
    mov    rsi, [rsp+S_REFW]
    mov    rdx, rbp
    mov    rcx, [rsp+S_CMX]
    mov    R8,  [rsp+S_CMY]
    movzx  R9d, word [rsp+S_BMX]
    mov    eax, [rsp+S_BMY]
    shl    eax, 16
    or     R9d, eax
    mov    eax, [rsp+S_BC]
    mov    [rsp], rax
    mov    eax, [rbx+lowres_p.me_range]
    mov    [rsp+8], rax
    mov    rax, [rsp+S_RANGE]
    mov    [rsp+16], rax
    call   [rbx+lowres_p.hex_search]
    mov    ecx, eax
    mov    rdx, rax
    shr    rdx, 32
    shr    rax, 48
    cmp    [rsp+S_BPC], ecx
    jge .hexbest
    mov    ecx, [rsp+S_BPC]
    mov    edx, [rsp+S_BPX]
    mov    eax, [rsp+S_BPY]
    jmp .hpel
.hexbest:
    shl    edx, 2
    shl    eax, 2
    movsx  edx, dx
    cwde

.hpel:
    ; refine_subpel: the halfpel diamond
    mov    [rsp+S_BC], ecx
    mov    [rsp+S_BMX], edx
    mov    [rsp+S_BMY], eax
    or     edx, eax
    test   edx, 1
    jnz .hpelref
    cmp    dword [rbx+lowres_p.weighted], 0
    jne .hpelref
    lea    R10, [lp_hpel_ref]
    mov    eax, [rsp+S_BMY]
    mov    edx, [rsp+S_BMX]
    lea    ecx, [rax-2]
    and    ecx, 3
    mov    R8d, edx
    and    R8d, 3
    lea    ecx, [R8+rcx*4]
    movzx  ecx, byte [R10+rcx]
    mov    rsi, [rsp+S_FREF+rcx*8]
    movsxd rax, dword [rsp+S_BMY]
    sub    rax, 2
    sar    rax, 2
    imul   rax, rbp
    add    rsi, rax
    movsxd rax, dword [rsp+S_BMX]
    sar    rax, 2
    add    rsi, rax                 ; src0
    mov    eax, [rsp+S_BMY]
    and    eax, 3
    lea    ecx, [rdx-2]
    and    ecx, 3
    lea    ecx, [rcx+rax*4]
    movzx  ecx, byte [R10+rcx]
    mov    rdx, [rsp+S_FREF+rcx*8]
    movsxd rax, dword [rsp+S_BMY]
    sar    rax, 2
    imul   rax, rbp
    add    rdx, rax
    movsxd rax, dword [rsp+S_BMX]
    sub    rax, 2
    sar    rax, 2
    add    rdx, rax                 ; src2
    mov    [rsp+S_HSTR], rbp
    jmp .hpelmin
.hpelref:
    mov    qword [rsp+S_HSTR], 64
    lea    rdi, [rsp+S_PIX]
    lea    rsi, [rsp+S_HSTR]
    lea    rdx, [rsp+S_FREF]
    mov    rcx, rbp
    mov    R8d, [rsp+S_BMX]
    mov    R9d, [rsp+S_BMY]
    sub    R9d, 2
    mov    qword [rsp], 8
    mov    qword [rsp+8], 9
    mov    rax, [rbx+lowres_p.weight]
    mov    [rsp+16], rax
    call   [rbx+lowres_p.get_ref]
    mov    [rsp+S_SRC0], rax
    lea    rdi, [rsp+S_PIX+32]
    lea    rsi, [rsp+S_HSTR]
    lea    rdx, [rsp+S_FREF]
    mov    rcx, rbp
    mov    R8d, [rsp+S_BMX]
    sub    R8d, 2
    mov    R9d, [rsp+S_BMY]
    mov    qword [rsp], 12
    mov    qword [rsp+8], 8
    mov    rax, [rbx+lowres_p.weight]
    mov    [rsp+16], rax
    call   [rbx+lowres_p.get_ref]
    mov    rdx, rax
    mov    rsi, [rsp+S_SRC0]
.hpelmin:
    ; b0 b1 | b2 b3 of (omx, omy-2) (omx, omy+2) | (omx-2, omy) (omx+2, omy)
    mov    R10, [rsp+S_CMX]
    mov    R11, [rsp+S_CMY]
    movsxd rax, dword [rsp+S_BMX]
    movsxd rcx, dword [rsp+S_BMY]
    movzx  edi, word [R10+rax*2]
    movzx  R8d, word [R11+rcx*2-4]
    movzx  R9d, word [R11+rcx*2+4]
    add    R8d, edi
    add    R9d, edi
    shl    R8d, 6
    shl    R9d, 6
    add    R8d, 2
    add    R9d, 6
    shl    R9, 32
    or     R8, R9
    movzx  ecx, word [R11+rcx*2]
    movzx  edi, word [R10+rax*2-4]
    movzx  R9d, word [R10+rax*2+4]
    add    edi, ecx
    add    R9d, ecx
    shl    edi, 6
    shl    R9d, 6
    add    edi, 16
    add    R9d, 48
    shl    R9, 32
    or     R9, rdi
    mov    eax, [rsp+S_BC]
    shl    eax, 6
    mov    [rsp], rax
    mov    rcx, [rsp+S_HSTR]
    lea    rdi, [rsp+S_FENC]
    call   [rbx+lowres_p.hpel_min]
    test   eax, 63
    jz .center
    mov    ecx, eax
    shl    eax, 26
    shl    ecx, 29
    sar    eax, 29
    sar    ecx, 29
    sub    [rsp+S_BMX], eax
    sub    [rsp+S_BMY], ecx
.center:
    mov    eax, [rsp+S_BMX]
    mov    ecx, [rsp+S_BMY]
    mov    [rsp+S_TMX], eax
    mov    [rsp+S_TMY], ecx
    SUBPEL_COST 1
    MVCOST
    mov    [rsp+S_BC], eax
    ; the qpel diamond, inside the spel limits
    mov    ecx, [rsp+S_BMY]
    cmp    ecx, [rsp+S_YMIN]
    jle .qpeldone
    cmp    ecx, [rsp+S_YMAX]
    jge .qpeldone
    mov    ecx, [rsp+S_BMX]
    cmp    ecx, [rsp+S_XMIN]
    jle .qpeldone
    cmp    ecx, [rsp+S_XMAX]
    jge .qpeldone
    shl    rax, 4
    mov    [rsp+S_KEY], rax
    mov    dword [rsp+S_I], 1
.qpel:
    mov    ecx, [rsp+S_I]
    lea    R10, [lp_qpel_dir]
    movsx  eax, byte [R10+rcx*2]
    movsx  edx, byte [R10+rcx*2+1]
    add    eax, [rsp+S_BMX]
    add    edx, [rsp+S_BMY]
    mov    [rsp+S_TMX], eax
    mov    [rsp+S_TMY], edx
    SUBPEL_COST 1
    MVCOST
    mov    ecx, [rsp+S_I]
    shl    rax, 4
    add    rax, rcx
    cmp    rax, [rsp+S_KEY]
    jae .qpelnext
    mov    [rsp+S_KEY], rax
.qpelnext:
    inc    ecx
    mov    [rsp+S_I], ecx
    cmp    ecx, 4
    jle .qpel
    mov    rax, [rsp+S_KEY]
    mov    ecx, eax
    and    ecx, 15
    jz .qpeldone
    shr    rax, 4
    mov    [rsp+S_BC], eax
    lea    R10, [lp_qpel_dir]
    movsx  eax, byte [R10+rcx*2]
    movsx  edx, byte [R10+rcx*2+1]
    add    [rsp+S_BMX], eax
    add    [rsp+S_BMY], edx
.qpeldone:
    movzx  eax, word [rsp+S_BMX]
    mov    ecx, [rsp+S_BMY]
    shl    ecx, 16
    or     eax, ecx
    mov    [rsp+S_MV], eax
    mov    eax, [rsp+S_BC]
    mov    [rsp+S_MCOST], eax

.searched:
    mov    rcx, [rbx+lowres_p.cost_mv]
    movzx  ecx, word [rcx]
    sub    [rsp+S_MCOST], ecx
    cmp    dword [rsp+S_MV], 0
    je .store
    mov    eax, [rbx+lowres_p.lambda]
    lea    eax, [rax+rax*4]
    add    [rsp+S_MCOST], eax
.store:
    mov    rcx, [rbx+lowres_p.mvs]
    mov    eax, [rsp+S_MV]
    mov    [rcx+R15*4], eax
    mov    rcx, [rbx+lowres_p.mv_costs]
    mov    eax, [rsp+S_MCOST]
    mov    [rcx+R15*4], eax
    jmp .intra
.nosearch:
    mov    rcx, [rbx+lowres_p.mv_costs]
    mov    eax, [rcx+R15*4]
    mov    [rsp+S_MCOST], eax

.intra:
    cmp    qword [rbx+lowres_p.output_intra], 0
    je .inter
    lea    rdi, [rsp+S_PRE]
    mov    rsi, [rbx+lowres_p.fenc]
    add    rsi, R14
    mov    rdx, rbp
    call   [rbx+lowres_p.intra]
    mov    ecx, [rbx+lowres_p.lambda]
    lea    ecx, [rcx+rcx*4+4]
    add    eax, ecx
    ; the 8-bit lookahead's correction, floor 5*lambda + 4
    mov    rdx, [rbx+lowres_p.corr_intra]
    test   rdx, rdx
    jz .icorr
    mov    esi, [rbx+lowres_p.corr_intra_max]
    cmp    eax, esi
    cmovb  esi, eax
    movzx  esi, byte [rdx+rsi]
    cmp    ecx, eax
    cmovg  ecx, eax
    sub    eax, esi
    cmp    eax, ecx
    cmovl  eax, ecx
.icorr:
    mov    rcx, [rbx+lowres_p.intra_cost]
    mov    [rcx+R15*2], ax
    mov    ecx, eax
    mov    rdx, [rbx+lowres_p.inv_qscale]
    test   rdx, rdx
    jz .intranoaq
    movzx  edx, word [rdx+R15*2]
    imul   ecx, edx
    add    ecx, 128
    sar    ecx, 8
.intranoaq:
    mov    rdx, [rbx+lowres_p.output_intra]
    mov    rsi, [rsp+S_ROW]
    add    [rdx+rsi*4], ecx
    cmp    dword [rsp+S_SCORE], 0
    je .inter
    add    [rdx], eax
    add    [rdx+4], ecx

.inter:
    mov    eax, [rsp+S_MCOST]
    mov    ecx, 1<<28               ; COST_MAX
    xor    R8d, R8d
    cmp    eax, ecx
    jge .notlist
    mov    ecx, eax
    mov    R8d, 1
.notlist:
    add    ecx, 4
    ; the 8-bit lookahead's correction, floor 4
    mov    rdx, [rbx+lowres_p.corr_inter]
    test   rdx, rdx
    jz .bcorr
    mov    eax, [rbx+lowres_p.corr_inter_max]
    cmp    ecx, eax
    cmovb  eax, ecx
    movzx  eax, byte [rdx+rax]
    mov    edx, 4
    cmp    edx, ecx
    cmovg  edx, ecx
    sub    ecx, eax
    cmp    ecx, edx
    cmovl  ecx, edx
.bcorr:
    mov    rdx, [rbx+lowres_p.intra_cost]
    movzx  eax, word [rdx+R15*2]
    xor    R9d, R9d
    cmp    eax, ecx
    jge .notintra
    mov    ecx, eax
    xor    R8d, R8d
    mov    R9d, 1
.notintra:
    mov    rdx, [rbx+lowres_p.output_inter]
    mov    edi, [rsp+S_SCORE]
    test   edi, edi
    jz .noscore
    add    [rdx+8], R9d
.noscore:
    mov    eax, ecx
    mov    rsi, [rbx+lowres_p.inv_qscale]
    test   rsi, rsi
    jz .internoaq
    movzx  esi, word [rsi+R15*2]
    imul   eax, esi
    add    eax, 128
    sar    eax, 8
.internoaq:
    mov    rsi, [rsp+S_ROW]
    add    [rdx+rsi*4], eax
    test   edi, edi
    jz .noscore2
    add    [rdx], ecx
    add    [rdx+4], eax
.noscore2:
    mov    eax, (1<<14)-1           ; LOWRES_COST_MASK
    cmp    ecx, eax
    cmovl  eax, ecx
    shl    R8d, 14
    add    eax, R8d
    mov    rdx, [rbx+lowres_p.costs]
    mov    [rdx+R15*2], ax

    dec    R12d
    cmp    R12d, [rbx+lowres_p.end_x]
    jge .col
.rownext:
    dec    R13d
    cmp    R13d, [rbx+lowres_p.end_y]
    jge .row
.end:
    RET


;=============================================================================
; lowres_p_mbs_regs: lowres_p_mbs with the search in registers. The candidates' sad and
; satd are inline on fenc (m14, m15) and fenc_pre (m10-m13) held in registers, the mv
; cost tables, the hpel table and the best key in R8-R11, the best mv in R12, R13; the
; hexagon (sad_hex_search_8x8's register entry), hpel_min, get_ref at odd mvs and the
; intra cost stay calls, once per MB. Unweighted only: a weighted ref runs lowres_p_mbs.
;=============================================================================

%assign lq_stack_pos 0
%macro LQ_STACK_FIELD 2 ; name, bytes
    %xdefine Q_%1 lq_stack_pos
    %assign lq_stack_pos lq_stack_pos+%2
%endmacro
LQ_STACK_FIELD ARGS,    32  ; outgoing arguments
LQ_STACK_FIELD FENC,   128  ; 8x8 at FENC_STRIDE, as 4 ymm stores
LQ_STACK_FIELD PRE,    128  ; fenc_pre
LQ_STACK_FIELD PIX,    640  ; get_ref's dst, 64*10
LQ_STACK_FIELD FREF,    32  ; the 4 planes at the mb
LQ_STACK_FIELD REFW,     8
LQ_STACK_FIELD CMX,      8
LQ_STACK_FIELD CMY,      8
LQ_STACK_FIELD RANGE,    8
LQ_STACK_FIELD HSTR,     8
LQ_STACK_FIELD SRC0,     8
LQ_STACK_FIELD ROW,      8
LQ_STACK_FIELD MVC,     16
LQ_STACK_FIELD MVCT,    16
LQ_STACK_FIELD MBX,      4
LQ_STACK_FIELD MBY,      4
LQ_STACK_FIELD XMIN,     4  ; spel limits
LQ_STACK_FIELD XMAX,     4
LQ_STACK_FIELD YMIN,     4
LQ_STACK_FIELD YMAX,     4
LQ_STACK_FIELD NMVC,     4
LQ_STACK_FIELD N,        4
LQ_STACK_FIELD MVP,      4
LQ_STACK_FIELD PMV,      4
LQ_STACK_FIELD PMVC,     4
LQ_STACK_FIELD BPX,      4
LQ_STACK_FIELD BPY,      4
LQ_STACK_FIELD BPC,      4
LQ_STACK_FIELD BC,       4
LQ_STACK_FIELD MV,       4
LQ_STACK_FIELD MCOST,    4
LQ_STACK_FIELD SCORE,    4
%assign LQ_STACK (lq_stack_pos+63) & ~63

; m%1 = rows 0, 2 | 1, 3 at %2 (rcx = 3*stride); xm%3 tmp
%macro LQ_ROWS 3
    movq         xm%1, [%2]
    movhps       xm%1, [%2+rbp*2]
    movq         xm%3, [%2+rbp]
    movhps       xm%3, [%2+rcx]
    vinserti128   m%1, m%1, xm%3, 1
%endmacro

; eax (%2: +=) sad( fenc, %1 ? pavgb( rsi, rdi ) : rsi ) at stride rbp; rcx, rsi, rdi; m0-m3
%macro LQ_SAD 2 ; avg2, add
    lea          rcx, [rbp*3]
    LQ_ROWS        0, rsi, 3
%if %1
    LQ_ROWS        1, rdi, 3
    pavgb         m0, m1
    lea          rdi, [rdi+rbp*4]
%endif
    lea          rsi, [rsi+rbp*4]
    psadbw        m0, m14
    LQ_ROWS        1, rsi, 3
%if %1
    LQ_ROWS        2, rdi, 3
    pavgb         m1, m2
%endif
    psadbw        m1, m15
    paddd         m0, m1
    vextracti128 xm1, m0, 1
    paddd        xm0, xm1
    punpckhqdq   xm1, xm0, xm0
    paddd        xm0, xm1
%if %2
    vmovd        ecx, xm0
    add          eax, ecx
%else
    vmovd        eax, xm0
%endif
%endmacro

; rows k+4 of the satd's row pairs (rsi, rdi four rows down) into the high lane of m%1
%macro LQ_SATD_HI 3 ; dst, offset, avg2
    vpbroadcastq  m4, [rsi+%2]
%if %3
    vpbroadcastq  m5, [rdi+%2]
    pavgb         m4, m5
%endif
    vpblendd     m%1, m%1, m4, 0xf0
%endmacro

; eax (%2: +=) satd_avg2_pre( fenc_pre, rsi, %1 ? rdi : rsi ) at stride rbp, in the
; kernel's arithmetic; rcx, rsi, rdi; m0-m6
%macro LQ_SATD 2 ; avg2, add
    lea          rcx, [rbp*3]
    vpbroadcastq  m0, [rsi]
    vpbroadcastq  m1, [rsi+rbp]
    vpbroadcastq  m2, [rsi+rbp*2]
    vpbroadcastq  m3, [rsi+rcx]
%if %1
    vpbroadcastq  m4, [rdi]
    vpbroadcastq  m5, [rdi+rbp]
    pavgb         m0, m4
    pavgb         m1, m5
    vpbroadcastq  m4, [rdi+rbp*2]
    vpbroadcastq  m5, [rdi+rcx]
    pavgb         m2, m4
    pavgb         m3, m5
    lea          rdi, [rdi+rbp*4]
%endif
    lea          rsi, [rsi+rbp*4]
    LQ_SATD_HI     0, 0, %1
    LQ_SATD_HI     1, rbp, %1
    LQ_SATD_HI     2, rbp*2, %1
    LQ_SATD_HI     3, rcx, %1
    pmaddubsw     m0, m9
    pmaddubsw     m1, m9
    pmaddubsw     m2, m9
    pmaddubsw     m3, m9
    psubw         m0, m10
    psubw         m1, m11
    psubw         m2, m12
    psubw         m3, m13
    HADAMARD4_V    0, 1, 2, 3, 4
    ABSW2         m0, m2, m0, m2, m4, m5
    ABSW2         m1, m3, m1, m3, m4, m5
    HADAMARD       1, max, 0, 2, 4, 5
    HADAMARD       1, max, 1, 3, 4, 5
    paddw         m6, m0, m1
    vextracti128 xm0, m6, 1
    paddw        xm0, xm6
    pmaddwd      xm0, [pw_1]
    punpckhqdq   xm1, xm0, xm0
    paddd        xm0, xm1
    pshuflw      xm1, xm0, q1032
    paddd        xm0, xm1
%if %2
    vmovd        ecx, xm0
    add          eax, ecx
%else
    vmovd        eax, xm0
%endif
%endmacro

; eax = cmp (%1: 0 sad, 1 satd) of the qpel mv (rsi, rdi: 64-bit) + its mv cost, as
; lowres_p_subpel unweighted: the planes by R10 = lp_hpel_ref, always averaged (a plane
; with itself where qpel_idx & 5 is 0); rcx, rdx, rsi, rdi, m0-m6
%macro LQ_SUBPEL 1
    movzx        eax, word [R8+rsi*2]
    movzx        ecx, word [R9+rdi*2]
    add          eax, ecx
    mov          ecx, edi
    and          ecx, 3
    mov          edx, esi
    and          edx, 3
    lea          ecx, [rdx+rcx*4]       ; qpel_idx
    sar          rdi, 2
    imul         rdi, rbp
    sar          rsi, 2
    add          rdi, rsi               ; offset
    movzx        edx, byte [R10+rcx]
    mov          rsi, [rsp+Q_FREF+rdx*8]
    add          rsi, rdi
    lea          rdx, [rsi+rbp]
    cmp          ecx, 12
    cmovae       rsi, rdx               ; src1, a row down at qpel y 3
    movzx        edx, byte [R10+rcx+16]
    add          rdi, [rsp+Q_FREF+rdx*8]
    mov          edx, ecx
    and          edx, 3
    cmp          edx, 3
    sete          dl
    add          rdi, rdx               ; src2, a pixel right at qpel x 3
    test         ecx, 5
    cmovz        rdi, rsi
%if %1
    LQ_SATD        1, 1
%else
    LQ_SAD         1, 1
%endif
%endmacro

; predictor %1 (1-4): R11d = min( R11d, (cost << 4) + %1 )
%macro LQ_PRED 1
    cmp    dword [rsp+Q_N], %1
    jl .predsdone
    movsx  rsi, word [rsp+Q_MVCT+(%1-1)*4]
    movsx  rdi, word [rsp+Q_MVCT+(%1-1)*4+2]
    LQ_SUBPEL 0
    shl    eax, 4
    add    eax, %1
    cmp    eax, R11d
    cmovl  R11d, eax
%endmacro

; mvc %1 (0-3, 0 past i_mvc) clipped into mvct[n]; n (edx) += it is neither 0 nor pmv (esi)
%macro LQ_CLIP 1
    mov    eax, [rsp+Q_MVC+%1*4]
    vmovd  xm0, eax
    pmaxsw xm0, xm7
    pminsw xm0, xm8
    vmovd  [rsp+Q_MVCT+rdx*4], xm0
    mov    ecx, 1
    xor    edi, edi
    test   eax, eax
    cmovz  ecx, edi
    cmp    eax, esi
    cmove  ecx, edi
    add    edx, ecx
%endmacro

; qpel candidate (R12 + %1, R13 + %2), dir %3: R11 = min( R11, (cost << 4) + %3 )
%macro LQ_QPEL 3
    lea    rsi, [R12+%1]
    lea    rdi, [R13+%2]
    LQ_SUBPEL 1
    shl    rax, 4
    add    rax, %3
    cmp    rax, R11
    cmovb  R11, rax
%endmacro

INIT_YMM avx2
;-----------------------------------------------------------------------------
; void lowres_p_mbs_regs( x264_lowres_p_t *c )
;-----------------------------------------------------------------------------
cglobal lowres_p_mbs_regs, 1,1
    cmp    dword [r0+lowres_p.weighted], 0
    jne    mangle(private_prefix %+ _lowres_p_mbs %+ SUFFIX)
    jmp    mangle(private_prefix %+ _lowres_p_mbs_regs_body %+ SUFFIX)

; rbx: c, rbp: stride, R14: pel offset, R15: mb_xy; mb_x, mb_y on the stack; R12, R13:
; the search's mv; R8, R9: p_cost_mvx, p_cost_mvy; R10: lp_hpel_ref; R11: the best cost
; or key; m14, m15: fenc rows (0, 2 | 1, 3), (4, 6 | 5, 7); m10-m13: fenc_pre; m9: hmul;
; xm7, xm8: the predictors' clip limits (x, y words)
cglobal lowres_p_mbs_regs_body, 1,15,16, LQ_STACK
    mov    rbx, r0
    mov    rbp, [rbx+lowres_p.stride]
    mov    eax, [rbx+lowres_p.start_y]
    cmp    eax, [rbx+lowres_p.end_y]
    jl .end
    mov    [rsp+Q_MBY], eax
.row:
    ; y spel limits of slicetype_mb_cost
    mov    ecx, eax
    shl    eax, 5
    neg    eax
    sub    eax, 48
    mov    edx, [rbx+lowres_p.mv_range]
    neg    edx
    cmp    eax, edx
    cmovl  eax, edx
    mov    [rsp+Q_YMIN], eax
    mov    eax, [rbx+lowres_p.mb_height]
    sub    eax, ecx
    dec    eax
    shl    eax, 5
    add    eax, 48
    mov    edx, [rbx+lowres_p.mv_range]
    dec    edx
    cmp    eax, edx
    cmovg  eax, edx
    mov    [rsp+Q_YMAX], eax
    mov    eax, ecx
    sub    eax, [rbx+lowres_p.slice_start]
    add    eax, 4
    mov    [rsp+Q_ROW], rax
    mov    eax, [rbx+lowres_p.start_x]
    cmp    eax, [rbx+lowres_p.end_x]
    jl .rownext
    mov    [rsp+Q_MBX], eax

.col:
    mov    R12d, [rsp+Q_MBX]
    mov    R13d, [rsp+Q_MBY]
    mov    eax, R13d
    imul   eax, [rbx+lowres_p.mb_width]
    add    eax, R12d
    mov    R15d, eax
    mov    rax, R13
    imul   rax, rbp
    add    rax, R12
    lea    R14, [rax*8]
    ; b_frame_score_mb
    xor    eax, eax
    mov    ecx, [rbx+lowres_p.mb_width]
    mov    edx, [rbx+lowres_p.mb_height]
    cmp    ecx, 2
    jle .score1
    cmp    edx, 2
    jle .score1
    test   R12d, R12d
    jle .score0
    dec    ecx
    cmp    R12d, ecx
    jge .score0
    test   R13d, R13d
    jle .score0
    dec    edx
    cmp    R13d, edx
    jge .score0
.score1:
    mov    eax, 1
.score0:
    mov    [rsp+Q_SCORE], eax

    ; fenc: rows (2k, 2k+1) at FENC_STRIDE, the sad layout, fenc_pre of rows (k, k+4)
    mov    rsi, [rbx+lowres_p.fenc]
    add    rsi, R14
    lea    rdx, [rbp*3]
    vpbroadcastq m0, [rsi]
    vpbroadcastq m4, [rsi+rbp]
    vpblendd     m0, m0, m4, 0xf0
    vpbroadcastq m1, [rsi+rbp*2]
    vpbroadcastq m4, [rsi+rdx]
    vpblendd     m1, m1, m4, 0xf0
    lea    rsi, [rsi+rbp*4]
    vpbroadcastq m2, [rsi]
    vpbroadcastq m4, [rsi+rbp]
    vpblendd     m2, m2, m4, 0xf0
    vpbroadcastq m3, [rsi+rbp*2]
    vpbroadcastq m4, [rsi+rdx]
    vpblendd     m3, m3, m4, 0xf0
    mova   [rsp+Q_FENC+ 0], m0
    mova   [rsp+Q_FENC+32], m1
    mova   [rsp+Q_FENC+64], m2
    mova   [rsp+Q_FENC+96], m3
    vpunpcklqdq   m14, m0, m1
    vpunpcklqdq   m15, m2, m3
    vbroadcasti128 m9, [lp_hmul_8p]
    vperm2i128    m10, m0, m2, 0x20
    vperm2i128    m11, m0, m2, 0x31
    vperm2i128    m12, m1, m3, 0x20
    vperm2i128    m13, m1, m3, 0x31
    pmaddubsw     m10, m9
    pmaddubsw     m11, m9
    pmaddubsw     m12, m9
    pmaddubsw     m13, m9
    mova   [rsp+Q_PRE+ 0], m10
    mova   [rsp+Q_PRE+32], m11
    mova   [rsp+Q_PRE+64], m12
    mova   [rsp+Q_PRE+96], m13

    cmp    dword [rbx+lowres_p.do_search], 0
    je .nosearch

    ; reverse-order mv prediction
    mov    rsi, [rbx+lowres_p.mvs]
    lea    rsi, [rsi+R15*4]
    xor    ecx, ecx
    mov    qword [rsp+Q_MVC], 0
    mov    qword [rsp+Q_MVC+8], 0
    mov    R8d, [rbx+lowres_p.mb_width]
    dec    R8d
    cmp    R12d, R8d
    jge .noright
    mov    eax, [rsi+4]
    mov    [rsp+Q_MVC+rcx*4], eax
    inc    ecx
.noright:
    mov    eax, [rbx+lowres_p.slice_end]
    dec    eax
    cmp    R13d, eax
    jge .nobelow
    mov    eax, [rbx+lowres_p.mb_width]
    lea    rdx, [rsi+rax*4]
    mov    eax, [rdx]
    mov    [rsp+Q_MVC+rcx*4], eax
    inc    ecx
    test   R12d, R12d
    jle .nobelowleft
    mov    eax, [rdx-4]
    mov    [rsp+Q_MVC+rcx*4], eax
    inc    ecx
.nobelowleft:
    cmp    R12d, R8d
    jge .nobelow
    mov    eax, [rdx+4]
    mov    [rsp+Q_MVC+rcx*4], eax
    inc    ecx
.nobelow:
    mov    [rsp+Q_NMVC], ecx
    mov    eax, [rsp+Q_MVC]
    cmp    ecx, 1
    jle .mvp
    vmovd  xm0, [rsp+Q_MVC]
    vmovd  xm1, [rsp+Q_MVC+4]
    vmovd  xm2, [rsp+Q_MVC+8]
    pmaxsw xm3, xm0, xm1
    pminsw xm0, xm0, xm1
    pminsw xm3, xm3, xm2
    pmaxsw xm0, xm0, xm3
    vmovd  eax, xm0
.mvp:
    mov    [rsp+Q_MVP], eax
    test   eax, eax
    jnz .search
    ; fast skip of near-zero residual at mv 0
    mov    rsi, [rbx+lowres_p.ref]
    add    rsi, R14
    LQ_SATD 0, 0
    cmp    eax, [rbx+lowres_p.skip_thresh]
    jge .search
    mov    [rsp+Q_MCOST], eax
    mov    dword [rsp+Q_MV], 0
    jmp .store

.search:
    ; x spel limits; the fpel limits as me.c's packed range and the clip limits
    mov    eax, R12d
    shl    eax, 5
    neg    eax
    sub    eax, 48
    mov    ecx, [rbx+lowres_p.mv_range]
    neg    ecx
    cmp    eax, ecx
    cmovl  eax, ecx
    mov    [rsp+Q_XMIN], eax
    mov    edx, [rbx+lowres_p.mb_width]
    sub    edx, R12d
    dec    edx
    shl    edx, 5
    add    edx, 48
    mov    ecx, [rbx+lowres_p.mv_range]
    dec    ecx
    cmp    edx, ecx
    cmovg  edx, ecx
    mov    [rsp+Q_XMAX], edx
    sar    eax, 2                   ; mv_x_min
    sar    edx, 2                   ; mv_x_max
    mov    esi, [rsp+Q_YMIN]
    mov    edi, [rsp+Q_YMAX]
    sar    esi, 2                   ; mv_y_min
    sar    edi, 2                   ; mv_y_max
    mov    ecx, eax
    neg    ecx
    shl    ecx, 16
    mov    R8d, esi
    neg    R8d
    and    R8d, 0x7fff
    or     ecx, R8d                 ; mv_min
    mov    R8d, edx
    shl    R8d, 16
    mov    R9d, edi
    and    R9d, 0x7fff
    or     R8d, R9d
    or     R8d, 0x8000              ; mv_max
    shl    R8, 32
    or     R8, rcx
    mov    [rsp+Q_RANGE], R8
    shl    eax, 2
    shl    edx, 2
    shl    esi, 18
    shl    edi, 18
    movzx  eax, ax
    movzx  edx, dx
    or     eax, esi
    or     edx, edi
    vmovd  xm7, eax                 ; 4*mv_x_min, 4*mv_y_min
    vmovd  xm8, edx                 ; 4*mv_x_max, 4*mv_y_max
    ; mv costs about the mvp
    mov    rax, [rbx+lowres_p.cost_mv]
    movsx  rcx, word [rsp+Q_MVP]
    movsx  rdx, word [rsp+Q_MVP+2]
    neg    rcx
    neg    rdx
    lea    R8, [rax+rcx*2]
    lea    R9, [rax+rdx*2]
    mov    [rsp+Q_CMX], R8
    mov    [rsp+Q_CMY], R9
    ; the planes at the mb
    mov    rax, [rbx+lowres_p.ref]
    mov    rcx, [rbx+lowres_p.ref+8]
    mov    rdx, [rbx+lowres_p.ref+16]
    mov    rsi, [rbx+lowres_p.ref+24]
    mov    rdi, [rbx+lowres_p.ref_w]
    add    rax, R14
    add    rcx, R14
    add    rdx, R14
    add    rsi, R14
    add    rdi, R14
    mov    [rsp+Q_FREF], rax
    mov    [rsp+Q_FREF+8], rcx
    mov    [rsp+Q_FREF+16], rdx
    mov    [rsp+Q_FREF+24], rsi
    mov    [rsp+Q_REFW], rdi
    lea    R10, [lp_hpel_ref]

    ; x264_me_search_ref: the clipped mvp
    vmovd  xm0, [rsp+Q_MVP]
    pmaxsw xm0, xm7
    pminsw xm0, xm8
    vmovd  eax, xm0
    mov    [rsp+Q_PMV], eax
    movsx  R12, ax
    sar    eax, 16
    movsxd R13, eax
    mov    rsi, R12
    mov    rdi, R13
    LQ_SUBPEL 0
    mov    R11d, eax
    mov    [rsp+Q_PMVC], eax
    mov    rcx, [rbx+lowres_p.cost_mv]
    movzx  ecx, word [rcx]
    add    ecx, ecx
    cmp    eax, ecx
    jne .preds
    ; pred == fenc at the mvp: the search and refine_subpel stay
    mov    ecx, [rsp+Q_PMV]
    mov    [rsp+Q_MV], ecx
    mov    [rsp+Q_MCOST], eax
    jmp .searched

.preds:
    ; x264_predictor_clip, then the predictors
    mov    esi, [rsp+Q_PMV]
    xor    edx, edx
    LQ_CLIP 0
    LQ_CLIP 1
    LQ_CLIP 2
    LQ_CLIP 3
    mov    [rsp+Q_N], edx
    shl    R11d, 4
    LQ_PRED 1
    LQ_PRED 2
    LQ_PRED 3
    LQ_PRED 4
.predsdone:
    mov    eax, R11d
    and    eax, 15
    jz .predkeep
    movsx  R12, word [rsp+Q_MVCT+rax*4-4]
    movsx  R13, word [rsp+Q_MVCT+rax*4-2]
.predkeep:
    sar    R11d, 4

    ; the best predictor at fullpel
    mov    [rsp+Q_BPX], R12d
    mov    [rsp+Q_BPY], R13d
    mov    [rsp+Q_BPC], R11d
    mov    ecx, R12d
    or     ecx, R13d
    add    R12d, 2
    add    R13d, 2
    sar    R12d, 2
    sar    R13d, 2
    movsxd R12, R12d
    movsxd R13, R13d
    test   ecx, 3
    jz .zero
    mov    rsi, R13
    imul   rsi, rbp
    add    rsi, R12
    add    rsi, [rsp+Q_REFW]
    LQ_SAD 0, 0
    movzx  ecx, word [R8+R12*8]
    add    eax, ecx
    movzx  ecx, word [R9+R13*8]
    add    eax, ecx
    mov    R11d, eax
.zero:
    ; the zero vector
    cmp    dword [rsp+Q_PMV], 0
    je .zeropmv
    mov    eax, R12d
    or     eax, R13d
    jz .hex
    mov    rsi, [rsp+Q_REFW]
    LQ_SAD 0, 0
    movzx  ecx, word [R8]
    add    eax, ecx
    movzx  ecx, word [R9]
    add    eax, ecx
    jmp .zerocmp
.zeropmv:
    mov    eax, [rsp+Q_PMVC]
.zerocmp:
    cmp    eax, R11d
    jge .hex
    mov    R11d, eax
    xor    R12d, R12d
    xor    R13d, R13d

.hex:
    ; hex_search( fenc, ref_w, stride, cost_mvx, cost_mvy, bmv, bcost, me_range, range )
    lea    rdi, [rsp+Q_FENC]
    mov    rsi, [rsp+Q_REFW]
    mov    rdx, rbp
    mov    rcx, R8
    mov    R8, R9
    movzx  R9d, R12w
    shl    R13d, 16
    or     R9d, R13d
    mov    eax, R11d
    mov    R10d, [rbx+lowres_p.me_range]
    mov    R11, [rsp+Q_RANGE]
    mov    R12, [rbx+lowres_p.hex_search]
    lea    R13, [pixel_sad_hex_search_8x8_avx2]
    cmp    R12, R13
    jne .hexstack
    ; sad_hex_search_8x8's register entry: the last three in r6-r8 (rax, R10, R11)
    call   pixel_sad_hex_search_reg_8x8_avx2
    jmp .hexret
.hexstack:
    mov    [rsp], rax
    mov    [rsp+8], R10
    mov    [rsp+16], R11
    call   R12
.hexret:
    mov    ecx, eax
    mov    rdx, rax
    shr    rdx, 32
    shr    rax, 48
    movsx  R12d, dx
    movsx  R13d, ax
    mov    eax, [rsp+Q_BPC]
    cmp    eax, ecx
    jge .hexbest
    mov    ecx, eax
    mov    R12d, [rsp+Q_BPX]
    mov    R13d, [rsp+Q_BPY]
    jmp .hpel
.hexbest:
    shl    R12d, 2
    shl    R13d, 2

.hpel:
    ; refine_subpel: the halfpel diamond
    mov    [rsp+Q_BC], ecx
    movsxd R12, R12d
    movsxd R13, R13d
    mov    eax, R12d
    or     eax, R13d
    test   eax, 1
    jnz .hpelref
    lea    R10, [lp_hpel_ref]
    lea    ecx, [R13-2]
    and    ecx, 3
    mov    edx, R12d
    and    edx, 3
    lea    ecx, [rdx+rcx*4]
    movzx  ecx, byte [R10+rcx]
    mov    rsi, [rsp+Q_FREF+rcx*8]
    lea    rax, [R13-2]
    sar    rax, 2
    imul   rax, rbp
    add    rsi, rax
    mov    rax, R12
    sar    rax, 2
    add    rsi, rax                 ; src0
    mov    eax, R13d
    and    eax, 3
    lea    ecx, [R12-2]
    and    ecx, 3
    lea    ecx, [rcx+rax*4]
    movzx  ecx, byte [R10+rcx]
    mov    rdx, [rsp+Q_FREF+rcx*8]
    mov    rax, R13
    sar    rax, 2
    imul   rax, rbp
    add    rdx, rax
    lea    rax, [R12-2]
    sar    rax, 2
    add    rdx, rax                 ; src2
    mov    rcx, rbp
    jmp .hpelmin
.hpelref:
    mov    qword [rsp+Q_HSTR], 64
    lea    rdi, [rsp+Q_PIX]
    lea    rsi, [rsp+Q_HSTR]
    lea    rdx, [rsp+Q_FREF]
    mov    rcx, rbp
    mov    R8d, R12d
    lea    R9d, [R13-2]
    mov    qword [rsp], 8
    mov    qword [rsp+8], 9
    mov    rax, [rbx+lowres_p.weight]
    mov    [rsp+16], rax
    call   [rbx+lowres_p.get_ref]
    mov    [rsp+Q_SRC0], rax
    lea    rdi, [rsp+Q_PIX+32]
    lea    rsi, [rsp+Q_HSTR]
    lea    rdx, [rsp+Q_FREF]
    mov    rcx, rbp
    lea    R8d, [R12-2]
    mov    R9d, R13d
    mov    qword [rsp], 12
    mov    qword [rsp+8], 8
    mov    rax, [rbx+lowres_p.weight]
    mov    [rsp+16], rax
    call   [rbx+lowres_p.get_ref]
    mov    rdx, rax
    mov    rsi, [rsp+Q_SRC0]
    mov    rcx, [rsp+Q_HSTR]
.hpelmin:
    ; b0 b1 | b2 b3 of (omx, omy-2) (omx, omy+2) | (omx-2, omy) (omx+2, omy)
    mov    R10, [rsp+Q_CMX]
    mov    R11, [rsp+Q_CMY]
    movzx  edi, word [R10+R12*2]
    movzx  R8d, word [R11+R13*2-4]
    movzx  R9d, word [R11+R13*2+4]
    add    R8d, edi
    add    R9d, edi
    shl    R8d, 6
    shl    R9d, 6
    add    R8d, 2
    add    R9d, 6
    shl    R9, 32
    or     R8, R9
    movzx  eax, word [R11+R13*2]
    movzx  edi, word [R10+R12*2-4]
    movzx  R9d, word [R10+R12*2+4]
    add    edi, eax
    add    R9d, eax
    shl    edi, 6
    shl    R9d, 6
    add    edi, 16
    add    R9d, 48
    shl    R9, 32
    or     R9, rdi
    mov    eax, [rsp+Q_BC]
    shl    eax, 6
    mov    [rsp], rax
    lea    rdi, [rsp+Q_FENC]
    call   [rbx+lowres_p.hpel_min]
    test   eax, 63
    jz .center
    mov    ecx, eax
    shl    eax, 26
    shl    ecx, 29
    sar    eax, 29
    sar    ecx, 29
    sub    R12d, eax
    sub    R13d, ecx
    movsxd R12, R12d
    movsxd R13, R13d
.center:
    mov    R8, [rsp+Q_CMX]
    mov    R9, [rsp+Q_CMY]
    lea    R10, [lp_hpel_ref]
    vbroadcasti128 m9, [lp_hmul_8p]
    mova   m10, [rsp+Q_PRE+ 0]
    mova   m11, [rsp+Q_PRE+32]
    mova   m12, [rsp+Q_PRE+64]
    mova   m13, [rsp+Q_PRE+96]
    mov    rsi, R12
    mov    rdi, R13
    LQ_SUBPEL 1
    mov    R11d, eax
    ; the qpel diamond, inside the spel limits
    cmp    R13d, [rsp+Q_YMIN]
    jle .qpeldone
    cmp    R13d, [rsp+Q_YMAX]
    jge .qpeldone
    cmp    R12d, [rsp+Q_XMIN]
    jle .qpeldone
    cmp    R12d, [rsp+Q_XMAX]
    jge .qpeldone
    shl    R11, 4
    LQ_QPEL  0, -1, 1
    LQ_QPEL  0,  1, 2
    LQ_QPEL -1,  0, 3
    LQ_QPEL  1,  0, 4
    mov    ecx, R11d
    and    ecx, 15
    shr    R11, 4
    test   ecx, ecx
    jz .qpeldone
    lea    rdx, [lp_qpel_dir]
    movsx  eax, byte [rdx+rcx*2]
    movsx  ecx, byte [rdx+rcx*2+1]
    add    R12d, eax
    add    R13d, ecx
.qpeldone:
    movzx  eax, R12w
    mov    ecx, R13d
    shl    ecx, 16
    or     eax, ecx
    mov    [rsp+Q_MV], eax
    mov    [rsp+Q_MCOST], R11d

.searched:
    mov    rcx, [rbx+lowres_p.cost_mv]
    movzx  ecx, word [rcx]
    sub    [rsp+Q_MCOST], ecx
    cmp    dword [rsp+Q_MV], 0
    je .store
    mov    eax, [rbx+lowres_p.lambda]
    lea    eax, [rax+rax*4]
    add    [rsp+Q_MCOST], eax
.store:
    mov    rcx, [rbx+lowres_p.mvs]
    mov    eax, [rsp+Q_MV]
    mov    [rcx+R15*4], eax
    mov    rcx, [rbx+lowres_p.mv_costs]
    mov    eax, [rsp+Q_MCOST]
    mov    [rcx+R15*4], eax
    jmp .intra
.nosearch:
    mov    rcx, [rbx+lowres_p.mv_costs]
    mov    eax, [rcx+R15*4]
    mov    [rsp+Q_MCOST], eax

.intra:
    cmp    qword [rbx+lowres_p.output_intra], 0
    je .inter
    lea    rdi, [rsp+Q_PRE]
    mov    rsi, [rbx+lowres_p.fenc]
    add    rsi, R14
    mov    rdx, rbp
    call   [rbx+lowres_p.intra]
    mov    ecx, [rbx+lowres_p.lambda]
    lea    ecx, [rcx+rcx*4+4]
    add    eax, ecx
    ; the 8-bit lookahead's correction, floor 5*lambda + 4
    mov    rdx, [rbx+lowres_p.corr_intra]
    test   rdx, rdx
    jz .icorr
    mov    esi, [rbx+lowres_p.corr_intra_max]
    cmp    eax, esi
    cmovb  esi, eax
    movzx  esi, byte [rdx+rsi]
    cmp    ecx, eax
    cmovg  ecx, eax
    sub    eax, esi
    cmp    eax, ecx
    cmovl  eax, ecx
.icorr:
    mov    rcx, [rbx+lowres_p.intra_cost]
    mov    [rcx+R15*2], ax
    mov    ecx, eax
    mov    rdx, [rbx+lowres_p.inv_qscale]
    test   rdx, rdx
    jz .intranoaq
    movzx  edx, word [rdx+R15*2]
    imul   ecx, edx
    add    ecx, 128
    sar    ecx, 8
.intranoaq:
    mov    rdx, [rbx+lowres_p.output_intra]
    mov    rsi, [rsp+Q_ROW]
    add    [rdx+rsi*4], ecx
    cmp    dword [rsp+Q_SCORE], 0
    je .inter
    add    [rdx], eax
    add    [rdx+4], ecx

.inter:
    mov    eax, [rsp+Q_MCOST]
    mov    ecx, 1<<28               ; COST_MAX
    xor    R8d, R8d
    cmp    eax, ecx
    jge .notlist
    mov    ecx, eax
    mov    R8d, 1
.notlist:
    add    ecx, 4
    ; the 8-bit lookahead's correction, floor 4
    mov    rdx, [rbx+lowres_p.corr_inter]
    test   rdx, rdx
    jz .bcorr
    mov    eax, [rbx+lowres_p.corr_inter_max]
    cmp    ecx, eax
    cmovb  eax, ecx
    movzx  eax, byte [rdx+rax]
    mov    edx, 4
    cmp    edx, ecx
    cmovg  edx, ecx
    sub    ecx, eax
    cmp    ecx, edx
    cmovl  ecx, edx
.bcorr:
    mov    rdx, [rbx+lowres_p.intra_cost]
    movzx  eax, word [rdx+R15*2]
    xor    R9d, R9d
    cmp    eax, ecx
    jge .notintra
    mov    ecx, eax
    xor    R8d, R8d
    mov    R9d, 1
.notintra:
    mov    rdx, [rbx+lowres_p.output_inter]
    mov    edi, [rsp+Q_SCORE]
    test   edi, edi
    jz .noscore
    add    [rdx+8], R9d
.noscore:
    mov    eax, ecx
    mov    rsi, [rbx+lowres_p.inv_qscale]
    test   rsi, rsi
    jz .internoaq
    movzx  esi, word [rsi+R15*2]
    imul   eax, esi
    add    eax, 128
    sar    eax, 8
.internoaq:
    mov    rsi, [rsp+Q_ROW]
    add    [rdx+rsi*4], eax
    test   edi, edi
    jz .noscore2
    add    [rdx], ecx
    add    [rdx+4], eax
.noscore2:
    mov    eax, (1<<14)-1           ; LOWRES_COST_MASK
    cmp    ecx, eax
    cmovl  eax, ecx
    shl    R8d, 14
    add    eax, R8d
    mov    rdx, [rbx+lowres_p.costs]
    mov    [rdx+R15*2], ax

    mov    eax, [rsp+Q_MBX]
    dec    eax
    mov    [rsp+Q_MBX], eax
    cmp    eax, [rbx+lowres_p.end_x]
    jge .col
.rownext:
    mov    eax, [rsp+Q_MBY]
    dec    eax
    mov    [rsp+Q_MBY], eax
    cmp    eax, [rbx+lowres_p.end_y]
    jge .row
.end:
    RET

%endif ; !HIGH_BIT_DEPTH && UNIX64
