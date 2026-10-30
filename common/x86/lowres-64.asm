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

; x264_lowres_p_t (encoder/me.h)
%define C_FENCPRE    0
%define C_SATD       8
%define C_SATD2     16
%define C_SAD       24
%define C_SAD2      32
%define C_HEX       40
%define C_HPEL      48
%define C_INTRA     56
%define C_GETREF    64
%define C_FENC      72
%define C_REF       80
%define C_REFW     112
%define C_WEIGHT   120
%define C_COSTMV   128
%define C_MVS      136
%define C_MVCOSTS  144
%define C_COSTS    152
%define C_ICOST    160
%define C_INVQ     168
%define C_OUTI     176
%define C_OUTA     184
%define C_STRIDE   192
%define C_LAMBDA   200
%define C_SKIP     204
%define C_MVRANGE  208
%define C_MERANGE  212
%define C_W        216
%define C_H        220
%define C_SSTART   224
%define C_SEND     228
%define C_SX       232
%define C_EX       236
%define C_SY       240
%define C_EY       244
%define C_DOSEARCH 248
%define C_WEIGHTED 252

; stack: outgoing arguments at 0, then 64-aligned buffers and the locals
%define S_FENC     64  ; 8x8 at FENC_STRIDE
%define S_PRE     192  ; fenc_pre
%define S_PIX     320  ; get_ref's dst, 64*10
%define S_FREF    960  ; the 4 planes at the mb
%define S_REFW    992
%define S_CMX    1000
%define S_CMY    1008
%define S_RANGE  1016
%define S_HSTR   1024  ; get_ref's stride
%define S_SRC0   1032
%define S_KEY    1040
%define S_ROW    1048
%define S_MVC    1056  ; 4 mvs
%define S_MVCT   1072  ; 4 clipped mvs
%define S_XMIN   1088  ; spel limits
%define S_XMAX   1092
%define S_YMIN   1096
%define S_YMAX   1100
%define S_XMINF  1104  ; fpel limits
%define S_XMAXF  1108
%define S_YMINF  1112
%define S_YMAXF  1116
%define S_MVP    1120
%define S_NMVC   1124
%define S_PMV    1128
%define S_PMVC   1132
%define S_BPC    1136
%define S_BPX    1140
%define S_BPY    1144
%define S_BC     1148
%define S_BMX    1152
%define S_BMY    1156
%define S_TMX    1160
%define S_TMY    1164
%define S_I      1168
%define S_N      1172
%define S_MV     1176
%define S_MCOST  1180
%define S_SCORE  1184
%define LP_STACK 1216

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
    cmp    dword [rbx+C_WEIGHTED], 0
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
    call   [rbx+C_SATD2]
%else
    lea    rdi, [rsp+S_FENC]
    call   [rbx+C_SAD2]
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
    mov    rax, [rbx+C_WEIGHT]
    mov    [rsp+16], rax
    call   [rbx+C_GETREF]
    mov    rsi, rax
    mov    rcx, [rsp+S_HSTR]
%%one:
%if %1
    mov    rdx, rcx
    lea    rdi, [rsp+S_PRE]
    call   [rbx+C_SATD]
%else
    mov    rdx, rsi
    mov    esi, 16
    lea    rdi, [rsp+S_FENC]
    call   [rbx+C_SAD]
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
    mov    rbp, [rbx+C_STRIDE]
    mov    R13d, [rbx+C_SY]
    cmp    R13d, [rbx+C_EY]
    jl .end
.row:
    ; y spel limits of slicetype_mb_cost
    mov    eax, R13d
    shl    eax, 5
    neg    eax
    sub    eax, 48
    mov    ecx, [rbx+C_MVRANGE]
    neg    ecx
    cmp    eax, ecx
    cmovl  eax, ecx
    mov    [rsp+S_YMIN], eax
    sar    eax, 2
    mov    [rsp+S_YMINF], eax
    mov    eax, [rbx+C_H]
    sub    eax, R13d
    dec    eax
    shl    eax, 5
    add    eax, 48
    mov    ecx, [rbx+C_MVRANGE]
    dec    ecx
    cmp    eax, ecx
    cmovg  eax, ecx
    mov    [rsp+S_YMAX], eax
    sar    eax, 2
    mov    [rsp+S_YMAXF], eax
    mov    eax, R13d
    sub    eax, [rbx+C_SSTART]
    add    eax, 4
    mov    [rsp+S_ROW], rax
    mov    R12d, [rbx+C_SX]
    cmp    R12d, [rbx+C_EX]
    jl .rownext

.col:
    mov    eax, R13d
    imul   eax, [rbx+C_W]
    add    eax, R12d
    mov    R15d, eax
    mov    eax, R13d
    imul   rax, rbp
    add    rax, R12
    lea    R14, [rax*8]
    ; b_frame_score_mb
    xor    eax, eax
    mov    ecx, [rbx+C_W]
    mov    edx, [rbx+C_H]
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
    mov    rsi, [rbx+C_FENC]
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
    call   [rbx+C_FENCPRE]

    cmp    dword [rbx+C_DOSEARCH], 0
    je .nosearch

    ; reverse-order mv prediction
    mov    rsi, [rbx+C_MVS]
    lea    rsi, [rsi+R15*4]
    xor    ecx, ecx
    mov    qword [rsp+S_MVC], 0
    mov    qword [rsp+S_MVC+8], 0
    mov    R8d, [rbx+C_W]
    dec    R8d
    cmp    R12d, R8d
    jge .noright
    mov    eax, [rsi+4]
    mov    [rsp+S_MVC+rcx*4], eax
    inc    ecx
.noright:
    mov    eax, [rbx+C_SEND]
    dec    eax
    cmp    R13d, eax
    jge .nobelow
    mov    eax, [rbx+C_W]
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
    mov    rsi, [rbx+C_REF]
    add    rsi, R14
    mov    rdx, rbp
    call   [rbx+C_SATD]
    cmp    eax, [rbx+C_SKIP]
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
    mov    ecx, [rbx+C_MVRANGE]
    neg    ecx
    cmp    eax, ecx
    cmovl  eax, ecx
    mov    [rsp+S_XMIN], eax
    sar    eax, 2
    mov    [rsp+S_XMINF], eax
    mov    eax, [rbx+C_W]
    sub    eax, R12d
    dec    eax
    shl    eax, 5
    add    eax, 48
    mov    ecx, [rbx+C_MVRANGE]
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
    mov    rax, [rbx+C_COSTMV]
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
    mov    rax, [rbx+C_REF]
    mov    rcx, [rbx+C_REF+8]
    mov    rdx, [rbx+C_REF+16]
    mov    rsi, [rbx+C_REF+24]
    mov    rdi, [rbx+C_REFW]
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
    mov    rcx, [rbx+C_COSTMV]
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
    call   [rbx+C_SAD]
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
    call   [rbx+C_SAD]
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
    mov    eax, [rbx+C_MERANGE]
    mov    [rsp+8], rax
    mov    rax, [rsp+S_RANGE]
    mov    [rsp+16], rax
    call   [rbx+C_HEX]
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
    cmp    dword [rbx+C_WEIGHTED], 0
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
    mov    rax, [rbx+C_WEIGHT]
    mov    [rsp+16], rax
    call   [rbx+C_GETREF]
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
    mov    rax, [rbx+C_WEIGHT]
    mov    [rsp+16], rax
    call   [rbx+C_GETREF]
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
    call   [rbx+C_HPEL]
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
    mov    rcx, [rbx+C_COSTMV]
    movzx  ecx, word [rcx]
    sub    [rsp+S_MCOST], ecx
    cmp    dword [rsp+S_MV], 0
    je .store
    mov    eax, [rbx+C_LAMBDA]
    lea    eax, [rax+rax*4]
    add    [rsp+S_MCOST], eax
.store:
    mov    rcx, [rbx+C_MVS]
    mov    eax, [rsp+S_MV]
    mov    [rcx+R15*4], eax
    mov    rcx, [rbx+C_MVCOSTS]
    mov    eax, [rsp+S_MCOST]
    mov    [rcx+R15*4], eax
    jmp .intra
.nosearch:
    mov    rcx, [rbx+C_MVCOSTS]
    mov    eax, [rcx+R15*4]
    mov    [rsp+S_MCOST], eax

.intra:
    cmp    qword [rbx+C_OUTA], 0
    je .inter
    lea    rdi, [rsp+S_PRE]
    mov    rsi, [rbx+C_FENC]
    add    rsi, R14
    mov    rdx, rbp
    call   [rbx+C_INTRA]
    mov    ecx, [rbx+C_LAMBDA]
    lea    ecx, [rcx+rcx*4+4]
    add    eax, ecx
    mov    rcx, [rbx+C_ICOST]
    mov    [rcx+R15*2], ax
    mov    ecx, eax
    mov    rdx, [rbx+C_INVQ]
    test   rdx, rdx
    jz .intranoaq
    movzx  edx, word [rdx+R15*2]
    imul   ecx, edx
    add    ecx, 128
    sar    ecx, 8
.intranoaq:
    mov    rdx, [rbx+C_OUTA]
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
    mov    rdx, [rbx+C_ICOST]
    movzx  eax, word [rdx+R15*2]
    xor    R9d, R9d
    cmp    eax, ecx
    jge .notintra
    mov    ecx, eax
    xor    R8d, R8d
    mov    R9d, 1
.notintra:
    mov    rdx, [rbx+C_OUTI]
    mov    edi, [rsp+S_SCORE]
    test   edi, edi
    jz .noscore
    add    [rdx+8], R9d
.noscore:
    mov    eax, ecx
    mov    rsi, [rbx+C_INVQ]
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
    mov    rdx, [rbx+C_COSTS]
    mov    [rdx+R15*2], ax

    dec    R12d
    cmp    R12d, [rbx+C_EX]
    jge .col
.rownext:
    dec    R13d
    cmp    R13d, [rbx+C_EY]
    jge .row
.end:
    RET

%endif ; !HIGH_BIT_DEPTH && UNIX64
