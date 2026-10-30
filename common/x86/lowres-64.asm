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

SECTION .text

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

%endif ; !HIGH_BIT_DEPTH && UNIX64
