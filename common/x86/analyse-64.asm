;*****************************************************************************
;* analyse-64.asm: x86_64 P macroblock partition analysis
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

SECTION .text

; enums of common/pixel.h and common/macroblock.h; checked in encoder/analyse.c
%define PIXEL_16x16 0
%define PIXEL_16x8  1
%define PIXEL_8x16  2
%define PIXEL_8x8   3
%define D_L0_8x8    3
%define D_8x8      13
%define D_16x8     14
%define D_8x16     15
%define D_16x16    16
%define P_L0        4
%define P_8x8       5
%define COST_MAX   (1<<28)
%define INT_MAX    0x7fffffff
%define SCAN8_0    12           ; X264_SCAN8_0

; The layouts below mirror the C structs; encoder/analyse.c checks them.

; x264_weight_t (common/mc.h)
struc wt
    .cachea:      resw 8
    .cacheb:      resw 8
    .i_denom:     resd 1
    .i_scale:     resd 1
    .i_offset:    resd 1
    alignb 8
    .weightfn:    resq 1
    .weightavgfn: resq 1
    alignb 16
endstruc

; x264_me_t (encoder/me.h)
struc me
    .i_pixel:     resd 1
    alignb 8
    .p_cost_mv:   resq 1
    .i_ref_cost:  resd 1
    .i_ref:       resd 1
    .weight:      resq 1
    .p_fref:      resq 12
    .p_fref_w:    resq 1
    .p_fenc:      resq 3
    .integral:    resq 1
    .i_stride:    resd 3
    .i_fld_uv_y:  resd 1
    .mvp:         resw 2
    .cost_mv:     resd 1
    .cost:        resd 1
    .mv:          resw 2
    alignb 64
endstruc

; x264_t.mb.pic (common/common.h)
struc mb_pic
    .fenc_buf:            resb 48*FENC_STRIDE*SIZEOF_PIXEL
    alignb 64
    .fdec_buf:            resb 54*FDEC_STRIDE*SIZEOF_PIXEL
    alignb 32
    .i4x4_fdec_buf:       resb 16*16*SIZEOF_PIXEL
    alignb 32
    .i8x8_fdec_buf:       resb 16*16*SIZEOF_PIXEL
    alignb 64
    .i8x8_dct_buf:        resb 3*64*SIZEOF_DCTCOEF
    alignb 64
    .i4x4_dct_buf:        resb 15*16*SIZEOF_DCTCOEF
    .i4x4_nnz_buf:        resd 4
    .i8x8_nnz_buf:        resd 4
    alignb 64
    .fenc_dct8:           resb 4*64*SIZEOF_DCTCOEF
    alignb 64
    .fenc_dct4:           resb 16*16*SIZEOF_DCTCOEF
    alignb 64
    .fenc_satd_cache:     resd 32
    alignb 16
    .fenc_hadamard_cache: resq 9
    alignb 64
    .fenc_pre:            resw 512
%if HIGH_BIT_DEPTH == 0
    alignb 64
    .mcc_fenc_pre:        resw 512
%endif
    .i_fenc_pre:          resd 1
    .i4x4_cbp:            resd 1
    .i8x8_cbp:            resd 1
    alignb 8
    .p_fenc:              resq 3
    .p_fenc_plane:        resq 3
    .p_fdec:              resq 3
    .i_fref:              resd 2
    alignb 8
    .p_fref:              resq 2*32*12
    .p_fref_w:            resq 32
    .p_integral:          resq 2*16
    .i_fld_uv_y:          resd 1
    .i_fld_uv_lines:      resd 1
    .i_stride:            resd 3
    alignb 64
endstruc

; x264_t.mb.cache (common/common.h)
struc mb_cache
    .intra4x4_pred_mode:         resb 40
    alignb 16
    .non_zero_count:             resb 120
    alignb 4
    .ref:                        resb 2*40
    alignb 16
    .mv:                         resw 2*40*2
    alignb 8
    .mvd:                        resb 2*40*2
    alignb 4
    .skip:                       resb 40
    alignb 4
    .direct_mv:                  resw 2*4*2
    alignb 4
    .direct_ref:                 resb 2*4
    .direct_partition:           resd 1
    alignb 4
    .pskip_mv:                   resw 2
    .i_neighbour_transform_size: resd 1
    .i_neighbour_skip:           resd 1
    .i_cbp_top:                  resd 1
    .i_cbp_left:                 resd 1
    .topright_mv:                resw 2*3*2
    .topright_ref:               resb 2*3
    alignb 8
    .deblock_strength:           resq 1
    alignb 16
endstruc

; x264_t.mb (common/common.h)
struc mb
    .i_mb_width:          resd 1
    .i_mb_height:         resd 1
    .i_mb_count:          resd 1
    .chroma_h_shift:      resd 1
    .chroma_v_shift:      resd 1
    .i_mb_stride:         resd 1
    .i_b8_stride:         resd 1
    .i_b4_stride:         resd 1
    .left_b8:             resd 2
    .left_b4:             resd 2
    .i_mb_x:              resd 1
    .i_mb_y:              resd 1
    .i_mb_xy:             resd 1
    .i_b8_xy:             resd 1
    .i_b4_xy:             resd 1
    .i_me_method:         resd 1
    .i_subpel_refine:     resd 1
    .b_chroma_me:         resd 1
    .b_trellis:           resd 1
    .b_noise_reduction:   resd 1
    .b_dct_decimate:      resd 1
    .i_psy_rd:            resd 1
    .i_psy_trellis:       resd 1
    .b_interlaced:        resd 1
    .b_adaptive_mbaff:    resd 1
    .mv_min:              resd 2
    .mv_max:              resd 2
    .mv_miny_row:         resd 3
    .mv_maxy_row:         resd 3
    .mv_min_spel:         resd 2
    .mv_max_spel:         resd 2
    .mv_miny_spel_row:    resd 3
    .mv_maxy_spel_row:    resd 3
    alignb 8
    .mv_limit_fpel:       resw 4
    .mv_miny_fpel_row:    resd 3
    .mv_maxy_fpel_row:    resd 3
    .i_neighbour:         resd 1
    .i_neighbour8:        resd 4
    .i_neighbour4:        resd 16
    .i_neighbour_intra:   resd 1
    .i_neighbour_frame:   resd 1
    .i_mb_type_top:       resd 1
    .i_mb_type_left:      resd 2
    .i_mb_type_topleft:   resd 1
    .i_mb_type_topright:  resd 1
    .i_mb_prev_xy:        resd 1
    .i_mb_left_xy:        resd 2
    .i_mb_top_xy:         resd 1
    .i_mb_topleft_xy:     resd 1
    .i_mb_topright_xy:    resd 1
    .i_mb_top_y:          resd 1
    .i_mb_topleft_y:      resd 1
    .i_mb_topright_y:     resd 1
    alignb 8
    .left_index_table:    resq 1
    .i_mb_top_mbpair_xy:  resd 1
    .topleft_partition:   resd 1
    .b_allow_skip:        resd 1
    .field_decoding_flag: resd 1
    alignb 8
    .base:                resq 1
    .type:                resq 1
    .partition:           resq 1
    .qp:                  resq 1
    .cbp:                 resq 1
    .intra4x4_pred_mode:  resq 1
    .non_zero_count:      resq 1
    .chroma_pred_mode:    resq 1
    .mv:                  resq 2
    .mvd:                 resq 2
    .ref:                 resq 2
    .mvr:                 resq 2*32
    .skipbp:              resq 1
    .mb_transform_size:   resq 1
    .slice_table:         resq 1
    .field:               resq 1
    .p_weight_buf:        resq 16
    .p_weight_sums:       resq 1
    .fenc_bot:            resq 3
    .b_fenc_bot:          resd 1
    .i_type:              resd 1
    .i_partition:         resd 1
    .i_sub_partition:     resb 4
    .b_transform_8x8:     resd 1
    .i_cbp_luma:          resd 1
    .i_cbp_chroma:        resd 1
    .i_intra16x16_pred_mode: resd 1
    .i_chroma_pred_mode:  resd 1
    .i_skip_intra:        resd 1
    .b_skip_mc:           resd 1
    .b_reencode_mb:       resd 1
    .ip_offset:           resd 1
    .b_deblock_rdo:       resd 1
    .b_overflow:          resd 1
    .i_vbv_emerg:         resd 1
    alignb 64
    .pic:                 resb mb_pic_size
    alignb 16
    .cache:               resb mb_cache_size
    .i_qp:                resd 1
    .i_chroma_qp:         resd 1
    .i_last_qp:           resd 1
    .i_last_dqp:          resd 1
    .b_variable_qp:       resd 1
    .b_lossless:          resd 1
    .b_direct_auto_read:  resd 1
    .b_direct_auto_write: resd 1
    .i_trellis_lambda2:   resd 4
    .i_psy_rd_lambda:     resd 1
    .i_chroma_lambda2_offset: resd 1
    .dist_scale_factor_buf: resw 2*2*32*4
    alignb 8
    .dist_scale_factor:   resq 1
    .bipred_weight_buf:   resb 2*2*32*4
    alignb 8
    .bipred_weight:       resq 1
    .map_col_to_list0:    resb 16+2
    alignb 4
    .ref_blind_dupe:      resd 1
    .deblock_ref_table:   resb 2*(32+2)
    alignb 4
    .mvp16:               resw 2*32*2
    .mvp16_valid:         resd 2
endstruc

; x264_mb_analysis_list_t (encoder/analyse.c)
struc alist
    .me16x16:     resb me_size
    .bi16x16:     resb me_size
    .me8x8:       resb 4*me_size
    .me4x4:       resb 16*me_size
    .me8x4:       resb 8*me_size
    .me4x8:       resb 8*me_size
    .me16x8:      resb 2*me_size
    .me8x16:      resb 2*me_size
    .i_rd16x16:   resd 1
    .i_cost8x8:   resd 1
    .i_cost4x4:   resd 4
    .i_cost8x4:   resd 4
    .i_cost4x8:   resd 4
    .i_cost16x8:  resd 1
    .i_cost8x16:  resd 1
    .mvc:         resw 32*5*2
    alignb 64
endstruc

; x264_mb_analysis_t (encoder/analyse.c)
struc an
    .i_lambda:           resd 1
    .i_lambda2:          resd 1
    .i_qp:               resd 1
    .i_qp_cost:          resd 1
    .p_cost_mv:          resq 1
    .p_cost_ref:         resq 2
    .i_mbrd:             resd 1
    .b_fast_intra:       resd 1
    .b_force_intra:      resd 1
    .b_avoid_topright:   resd 1
    .b_pir_skip_invalid: resd 1
    .b_try_skip:         resd 1
    .i_satd_i16x16:      resd 1
    .i_satd_i16x16_dir:  resd 7
    .i_predict16x16:     resd 1
    .i_satd_i8x8:        resd 1
    .i_cbp_i8x8_luma:    resd 1
    alignb 16
    .i_satd_i8x8_dir:    resw 4*16
    .i_predict8x8:       resd 4
    .i_satd_i4x4:        resd 1
    .i_predict4x4:       resd 16
    .i_satd_pcm:         resd 1
    .i_satd_chroma:      resd 1
    .i_satd_chroma_dir:  resd 7
    .i_predict8x8chroma: resd 1
    alignb 64
    .l0:                 resb alist_size
    .l1:                 resb alist_size
    .i_cost16x16bi:      resd 1
    .i_cost16x16direct:  resd 1
    .i_cost8x8bi:        resd 1
    .i_cost8x8direct:    resd 4
    .i_satd8x8:          resd 3*4
    .i_cost_est16x8:     resd 2
    .i_cost_est8x16:     resd 2
    .i_cost16x8bi:       resd 1
    .i_cost8x16bi:       resd 1
    .i_rd16x16bi:        resd 1
    .i_rd16x16direct:    resd 1
    .i_rd16x8bi:         resd 1
    .i_rd8x16bi:         resd 1
    .i_rd8x8bi:          resd 1
    .i_mb_partition16x8: resd 2
    .i_mb_partition8x16: resd 2
    .i_mb_type16x8:      resd 1
    .i_mb_type8x16:      resd 1
    .b_direct_available: resd 1
    .b_early_terminate:  resd 1
    alignb 64
endstruc

; x264_analyse_p_t (encoder/analyse.c)
struc ap
    .h:           resq 1
    .mb:          resq 1
    .a:           resq 1
    .weight:      resq 1
    .me_search:   resq 1
    .refine_dupe: resq 1
    .predict_ref: resq 1
    .probe_skip:  resq 1
    .cabac:       resd 1
    .v_shift:     resd 1
    .mbaff:       resd 1
    .interlaced:  resd 1
    .gate:        resd 1
    .i_type:      resd 1
    .i_partition: resd 1
    .i_cost:      resd 1
endstruc

%define PIC   (mb.pic)
%define CACHE (mb.cache)
%define CREF  (mb.cache + mb_cache.ref)     ; cache.ref[0]
%define CMV   (mb.cache + mb_cache.mv)      ; cache.mv[0]
%define ME16  (an.l0 + alist.me16x16)
%define ME8   (an.l0 + alist.me8x8)
%define ME168 (an.l0 + alist.me16x8)
%define ME816 (an.l0 + alist.me8x16)
%define L0MVC (an.l0 + alist.mvc)

; stack: a 64-aligned x264_me_t at 0, then the locals. Offsets are preprocessor
; numbers: cglobal's stack size has to be one.
%assign ap_stack_pos 0
%macro AP_STACK_FIELD 2 ; name, bytes
    %xdefine S_%1 ap_stack_pos
    %assign ap_stack_pos ap_stack_pos+%2
%endmacro
AP_STACK_FIELD M,     256  ; x264_me_t
AP_STACK_FIELD MVC,    48  ; mvc[10][2] (16x16), mvc[3][2] (16x8, 8x16)
AP_STACK_FIELD PTHR,    8  ; p_halfpel_thresh
AP_STACK_FIELD THR,     4  ; i_halfpel_thresh
AP_STACK_FIELD NMVC,    4
AP_STACK_FIELD REF,     4
AP_STACK_FIELD REFC,    4  ; the 8x8 ref cost
AP_STACK_FIELD ADDC,    4  ; the 8x8 ref and sub mb type cost
AP_STACK_FIELD COST,    4
AP_STACK_FIELD TYPE,    4
AP_STACK_FIELD PART,    4
%assign AP_STACK (ap_stack_pos+63) & ~63

; eax = x264_mb_blind_dupe_src( h, %1 ), %1 a ref >= 0 not in eax, ecx, edx
%macro BLIND_DUPE_SRC 1
    mov    ecx, [R12+mb.ref_blind_dupe]
    mov    edx, %1
    xor    eax, eax
    cmp    dword [rbx+ap.interlaced], 0
    je %%cmp
    shr    edx, 1
    mov    eax, %1
    and    eax, 1
    test   ecx, ecx
    js %%none
%%cmp:
    cmp    edx, ecx
    je %%done
%%none:
    mov    eax, -1
%%done:
%endmacro

; eax = x264_mb_predict_mv( h, 0, idx, %2, mvp ) for idx&3 < 2 + (%2&1): %1 scan8[idx],
; %2 width, %3 the 16x8 / 8x16 shortcut neighbour (0 none, 1 a, 2 b, 3 c), %4 the
; MBAFF topright entry of idx 2, 8 or 10 (-1 other idx); %5 the ref, else cache.ref[0][%1].
; x264_mb_predict_mv_16x16( h, 0, %5, mvp ) is (12, 4, 0, -1, %5).
; Clobbers rcx, rdx, rsi, rdi, R8-R11, xmm0-3.
%macro PREDMV 4-5
%if %0 == 5
    mov    eax, %5
%else
    movsx  eax, byte [R12+CREF+%1]
%endif
    movsx  ecx, byte [R12+CREF+%1-1]
    movsx  edx, byte [R12+CREF+%1-8]
    movsx  esi, byte [R12+CREF+%1-8+%2]
    mov    R8d, [R12+CMV+(%1-1)*4]
    mov    R9d, [R12+CMV+(%1-8)*4]
    mov    R10d, [R12+CMV+(%1-8+%2)*4]
    cmp    esi, -2
    jne %%cok
    movsx  esi, byte [R12+CREF+%1-9]
    mov    R10d, [R12+CMV+(%1-9)*4]
%if %4 >= 0
    cmp    dword [rbx+ap.mbaff], 0
    je %%cok
    cmp    byte [R12+CREF+SCAN8_0-1], -2
    je %%cok
    movsxd R11, dword [R12+mb.i_mb_left_xy]
    mov    rdi, [R12+mb.field]
    movzx  edi, byte [rdi+R11]
    cmp    edi, [rbx+ap.interlaced]
    je %%cok
    mov    R10d, [R12+CACHE+mb_cache.topright_mv+%4*4]
    movsx  esi, byte [R12+CACHE+mb_cache.topright_ref+%4]
%endif
%%cok:
%if %3
  %if %3 == 1
    cmp    ecx, eax
    mov    edi, R8d
  %elif %3 == 2
    cmp    edx, eax
    mov    edi, R9d
  %else
    cmp    esi, eax
    mov    edi, R10d
  %endif
    jne %%gen
    mov    eax, edi
    jmp %%done
%endif
%%gen:
    ; R11d: a | b << 1 | c << 2, the neighbours of the same ref
    xor    R11d, R11d
    cmp    ecx, eax
    sete   R11b
    xor    edi, edi
    cmp    edx, eax
    sete   dil
    lea    R11d, [R11+rdi*2]
    xor    edi, edi
    cmp    esi, eax
    sete   dil
    lea    R11d, [R11+rdi*4]
    blsr   edi, R11d
    jnz %%median
    test   R11d, R11d
    jz %%none
    mov    eax, R8d
    cmp    R11d, 2
    cmove  eax, R9d
    cmova  eax, R10d
    jmp %%done
%%none:
    cmp    edx, -2
    jne %%median
    cmp    esi, -2
    jne %%median
    cmp    ecx, -2
    je %%median
    mov    eax, R8d
    jmp %%done
%%median:
    vmovd  xmm0, R8d
    vmovd  xmm1, R9d
    vmovd  xmm2, R10d
    vpminsw xmm3, xmm0, xmm1
    vpmaxsw xmm0, xmm0, xmm1
    vpminsw xmm0, xmm0, xmm2
    vpmaxsw xmm0, xmm0, xmm3
    vmovd  eax, xmm0
%%done:
%endmacro

; copy the x264_me_t at %2 to %1
%macro COPY_ME 2
%assign ap_cpo 0
%rep 8 ; sizeof(x264_me_t) / 32, checked in encoder/analyse.c
    vmovdqa xmm0, [%2+ap_cpo]
    vmovdqa xmm1, [%2+ap_cpo+16]
    vmovdqa [%1+ap_cpo], xmm0
    vmovdqa [%1+ap_cpo+16], xmm1
%assign ap_cpo ap_cpo+32
%endrep
%endmacro

; the ME call: %1 mvc, %2 i_mvc, %3 p_fullpel_thresh (0 for NULL), into rbp
%macro ME_SEARCH 3
    mov    rdi, [rbx+ap.h]
    mov    rsi, rbp
    lea    rdx, %1
    mov    ecx, %2
%ifidn %3, 0
    xor    R8d, R8d
%else
    mov    R8, %3
%endif
    call   [rbx+ap.me_search]
%endmacro

INIT_XMM avx2
;-----------------------------------------------------------------------------
; int analyse_p16x16( x264_analyse_p_t *c )
;-----------------------------------------------------------------------------
; x264_mb_analyse_inter_p16x16_search: 1 for the fast skip.
; rbx c, R12 mb, R13 a, rbp m, R14d i_fref[0], R15d i_ref. One ref searches
; into l0.me16x16, more into the stack m.
cglobal analyse_p16x16, 1,15,0, AP_STACK
    mov    rbx, rdi
    mov    R12, [rbx+ap.mb]
    mov    R13, [rbx+ap.a]
    mov    R14d, [R12+PIC+mb_pic.i_fref]
    mov    dword [rsp+S_THR], INT_MAX
    xor    eax, eax
    cmp    R14d, 1
    jle .pthr
    cmp    dword [R13+an.b_early_terminate], 0
    je .pthr
    lea    rax, [rsp+S_THR]
.pthr:
    mov    [rsp+S_PTHR], rax
    mov    dword [R13+ME16+me.cost], INT_MAX
    lea    rbp, [R13+ME16]
    lea    rax, [rsp+S_M]
    cmp    R14d, 1
    cmovg  rbp, rax
    mov    dword [rbp+me.i_pixel], PIXEL_16x16
    xor    R15d, R15d
    test   R14d, R14d
    jle .refs_done
.ref:
    mov    rax, [R13+an.p_cost_ref]
    movzx  eax, word [rax+R15*2]
    mov    [rbp+me.i_ref_cost], eax
    sub    [rsp+S_THR], eax
    mov    rdi, rbp
    mov    esi, R15d
    xor    edx, edx
    xor    ecx, ecx
    call   ap_load
    PREDMV SCAN8_0, 4, 0, -1, R15d
    mov    [rbp+me.mvp], eax
    mov    [R12+mb.mvp16+R15*4], eax
    mov    eax, 1
    shlx   eax, eax, R15d
    or     [R12+mb.mvp16_valid], eax
    BLIND_DUPE_SRC R15d
    test   eax, eax
    js .search
    lea    eax, [rax+rax*4]
    mov    eax, [R13+L0MVC+rax*4]
    mov    [rbp+me.mv], eax
    mov    rdi, [rbx+ap.h]
    mov    rsi, rbp
    mov    rdx, [rsp+S_PTHR]
    call   [rbx+ap.refine_dupe]
    jmp .searched
.search:
    mov    rdi, [rbx+ap.h]
    xor    esi, esi
    mov    edx, R15d
    lea    rcx, [rsp+S_MVC]
    lea    R8, [rsp+S_NMVC]
    call   [rbx+ap.predict_ref]
    ME_SEARCH [rsp+S_MVC], [rsp+S_NMVC], [rsp+S_PTHR]
.searched:
    ; mvr and mvc for the neighbours and the 8x8
    mov    eax, [rbp+me.mv]
    mov    rcx, [R12+mb.mvr+R15*8]
    movsxd rdx, dword [R12+mb.i_mb_xy]
    mov    [rcx+rdx*4], eax
    lea    ecx, [R15+R15*4]
    mov    [R13+L0MVC+rcx*4], eax
    ; fast skip: ref 0, satd < 300 lambda, mv within 1 of the skip mv, probe
    test   R15d, R15d
    jnz .noskip
    cmp    dword [R13+an.b_try_skip], 0
    je .noskip
    mov    ecx, [rbp+me.cost]
    sub    ecx, [rbp+me.cost_mv]
    imul   edx, [R13+an.i_lambda], 300
    cmp    ecx, edx
    jge .noskip
    movsx  ecx, ax
    movsx  edx, word [R12+CACHE+mb_cache.pskip_mv]
    sub    ecx, edx
    mov    edx, ecx
    neg    ecx
    cmovl  ecx, edx
    sar    eax, 16
    movsx  edx, word [R12+CACHE+mb_cache.pskip_mv+2]
    sub    eax, edx
    mov    edx, eax
    neg    eax
    cmovl  eax, edx
    add    eax, ecx
    cmp    eax, 1
    jg .noskip
    mov    rdi, [rbx+ap.h]
    xor    esi, esi
    call   [rbx+ap.probe_skip]
    test   eax, eax
    jz .noskip
    mov    eax, 1
    RET
.noskip:
    mov    eax, [rbp+me.i_ref_cost]
    add    [rbp+me.cost], eax
    add    [rsp+S_THR], eax
    lea    rdi, [R13+ME16]
    cmp    rbp, rdi
    je .next
    mov    eax, [rbp+me.cost]
    cmp    eax, [rdi+me.cost]
    jge .next
    COPY_ME rdi, rbp
.next:
    inc    R15d
    cmp    R15d, R14d
    jl .ref
.refs_done:
    ; x264_macroblock_cache_ref( h, 0, 0, 4, 4, 0, me16x16.i_ref )
    movzx  eax, byte [R13+ME16+me.i_ref]
    imul   eax, eax, 0x01010101
    mov    [R12+CREF+SCAN8_0+0*8], eax
    mov    [R12+CREF+SCAN8_0+1*8], eax
    mov    [R12+CREF+SCAN8_0+2*8], eax
    mov    [R12+CREF+SCAN8_0+3*8], eax
    xor    eax, eax
    RET

; one 8x8 of x264_mb_analyse_inter_p8x8: %1 the block. R14 mvc = l0.mvc[i_ref]
%macro P8x8_BLOCK 1
%assign ap_i8 SCAN8_0 + 2*(%1&1) + 16*(%1>>1)
    lea    rbp, [R13+ME8+%1*me_size]
    mov    dword [rbp+me.i_pixel], PIXEL_8x8
    mov    eax, [rsp+S_REFC]
    mov    [rbp+me.i_ref_cost], eax
    mov    rdi, rbp
    mov    esi, [rsp+S_REF]
    mov    edx, 8*(%1&1)
    mov    ecx, 8*(%1>>1)
    call   ap_load
%if %1 == 2
    PREDMV ap_i8, 2, 0, 1
%else
    PREDMV ap_i8, 2, 0, -1
%endif
    mov    [rbp+me.mvp], eax
    ME_SEARCH [R14], %1+1, 0
    ; x264_macroblock_cache_mv_ptr( h, 2*x8, 2*y8, 2, 2, 0, m->mv )
    mov    eax, [rbp+me.mv]
    mov    ecx, eax
    shl    rcx, 32
    or     rcx, rax
    mov    [R12+CMV+ap_i8*4], rcx
    mov    [R12+CMV+(ap_i8+8)*4], rcx
    mov    [R14+(%1+1)*4], eax
    mov    ecx, [rbp+me.cost]
    sub    ecx, [rbp+me.cost_mv]
    mov    [R13+an.i_satd8x8+%1*4], ecx
    mov    ecx, [rsp+S_ADDC]
    add    [rbp+me.cost], ecx
%endmacro

; partition %2 of x264_mb_analyse_inter_p16x8 (%1 0) or p8x16 (%1 1), up to the
; early termination after partition 0 (to %3). The 8x8s share the ref (no mixed
; refs), so ref8[0] == ref8[1]: one search, into l0m, and no dupe shortcut.
%macro P2_PART 3
%if %1 == 0
  %xdefine ap_l0m  ME168 + %2*me_size
  %assign ap_pix  PIXEL_16x8
  %assign ap_x    0
  %assign ap_y    8*%2
  %assign ap_mva  2*%2+1
  %assign ap_mvb  2*%2+2
  %assign ap_i8   SCAN8_0 + 16*%2
  %assign ap_w    4
  %assign ap_sel  2-%2         ; idx 0: b, idx 8: a
  %assign ap_k    %2*2-1       ; idx 8: topright 1
  %xdefine ap_est  an.i_cost_est16x8+4
  %xdefine ap_cost an.l0+alist.i_cost16x8
%else
  %xdefine ap_l0m  ME816 + %2*me_size
  %assign ap_pix  PIXEL_8x16
  %assign ap_x    8*%2
  %assign ap_y    0
  %assign ap_mva  %2+1
  %assign ap_mvb  %2+3
  %assign ap_i8   SCAN8_0 + 2*%2
  %assign ap_w    2
  %assign ap_sel  1+2*%2       ; idx 0: a, idx 4: c
  %assign ap_k    -1
  %xdefine ap_est  an.i_cost_est8x16+4
  %xdefine ap_cost an.l0+alist.i_cost8x16
%endif
    lea    rbp, [R13+ap_l0m]
    mov    dword [rbp+me.i_pixel], ap_pix
    mov    R14d, [rsp+S_REF]
    mov    rax, [R13+an.p_cost_ref]
    movzx  eax, word [rax+R14*2]
    mov    [rbp+me.i_ref_cost], eax
    lea    eax, [R14+R14*4]
    lea    rax, [R13+L0MVC+rax*4]
    mov    ecx, [rax]
    mov    [rsp+S_MVC], ecx
    mov    ecx, [rax+ap_mva*4]
    mov    [rsp+S_MVC+4], ecx
    mov    ecx, [rax+ap_mvb*4]
    mov    [rsp+S_MVC+8], ecx
    mov    rdi, rbp
    mov    esi, R14d
    mov    edx, ap_x
    mov    ecx, ap_y
    call   ap_load
    ; x264_macroblock_cache_ref of the partition, before its mv prediction
    movzx  eax, R14b
%if %1 == 0
    imul   eax, eax, 0x01010101
    mov    [R12+CREF+ap_i8], eax
    mov    [R12+CREF+ap_i8+8], eax
%else
    imul   eax, eax, 0x0101
    mov    [R12+CREF+ap_i8+0*8], ax
    mov    [R12+CREF+ap_i8+1*8], ax
    mov    [R12+CREF+ap_i8+2*8], ax
    mov    [R12+CREF+ap_i8+3*8], ax
%endif
    PREDMV ap_i8, ap_w, ap_sel, ap_k
    mov    [rbp+me.mvp], eax
    ME_SEARCH [rsp+S_MVC], 3, 0
    mov    eax, [rbp+me.i_ref_cost]
    add    [rbp+me.cost], eax
%if %2 == 0
    ; l0m->cost + est[1] > i_best_satd * (4 + !!i_mbrd) / 4
    cmp    dword [R13+an.b_early_terminate], 0
    je %%cont
    mov    eax, [rbp+me.cost]
    add    eax, [R13+ap_est]
    mov    ecx, [rsp+S_COST]
    cmp    dword [R13+an.i_mbrd], 0
    je %%thr
    lea    ecx, [rcx+rcx*4]
    mov    edx, ecx
    sar    edx, 31
    and    edx, 3
    add    ecx, edx
    sar    ecx, 2
%%thr:
    cmp    eax, ecx
    jle %%cont
    mov    dword [R13+ap_cost], COST_MAX
    jmp %3
%%cont:
%endif
    ; x264_macroblock_cache_mv_ptr of l0m; its cache_ref is the one above
    mov    eax, [rbp+me.mv]
%if %1 == 0
    vmovd  xmm0, eax
    vpbroadcastd xmm0, xmm0
    vmovdqu [R12+CMV+ap_i8*4], xmm0
    vmovdqu [R12+CMV+(ap_i8+8)*4], xmm0
%else
    mov    ecx, eax
    shl    rcx, 32
    or     rcx, rax
    mov    [R12+CMV+(ap_i8+0*8)*4], rcx
    mov    [R12+CMV+(ap_i8+1*8)*4], rcx
    mov    [R12+CMV+(ap_i8+2*8)*4], rcx
    mov    [R12+CMV+(ap_i8+3*8)*4], rcx
%endif
%endmacro

; x264_mb_analyse_inter_p16x8 (%1 0) or p8x16 (%1 1), i_best_satd at [rsp+S_COST]
%macro P2 1
    mov    dword [R12+mb.i_partition], D_16x8+%1
    P2_PART %1, 0, %%end
    P2_PART %1, 1, %%end
%if %1 == 0
    mov    eax, [R13+ME168+me.cost]
    add    eax, [R13+ME168+me_size+me.cost]
    mov    [R13+an.l0+alist.i_cost16x8], eax
%else
    mov    eax, [R13+ME816+me.cost]
    add    eax, [R13+ME816+me_size+me.cost]
    mov    [R13+an.l0+alist.i_cost8x16], eax
%endif
%%end:
%endmacro

;-----------------------------------------------------------------------------
; void analyse_p_sub16x16( x264_analyse_p_t *c )
;-----------------------------------------------------------------------------
; macroblock_analyse's P 8x8 (x264_mb_analyse_inter_p8x8 unless c->gate), the
; 16x16 / 8x8 choice and the 16x8 / 8x16 searches for PSUB16x16 without PSUB8x8
; or mixed refs; out i_type, i_partition and i_cost.
; rbx c, R12 mb, R13 a, rbp m, R14 mvc (8x8) or ref (16x8, 8x16), R15d the 16x16 ref.
cglobal analyse_p_sub16x16, 1,15,0, AP_STACK
    mov    rbx, rdi
    mov    R12, [rbx+ap.mb]
    mov    R13, [rbx+ap.a]
    cmp    dword [rbx+ap.gate], 0
    jne .select
    ; 8x8 at me16x16's ref, the source of a blind dupe
    mov    R15d, [R13+ME16+me.i_ref]
    BLIND_DUPE_SRC R15d
    test   eax, eax
    cmovs  eax, R15d
    mov    [rsp+S_REF], eax
    ; i_ref_cost = PARAM_CABAC || i_ref ? REF_COST( 0, i_ref ) : 0
    mov    rcx, [R13+an.p_cost_ref]
    movzx  ecx, word [rcx+rax*2]
    xor    edx, edx
    mov    esi, eax
    or     esi, [rbx+ap.cabac]
    cmovz  ecx, edx
    mov    [rsp+S_REFC], ecx
    ; !PARAM_CABAC: + lambda * i_sub_mb_p_cost_table[D_L0_8x8] (1)
    cmp    dword [rbx+ap.cabac], 0
    jne .sc
    add    ecx, [R13+an.i_lambda]
.sc:
    mov    [rsp+S_ADDC], ecx
    lea    eax, [rax+rax*4]
    lea    R14, [R13+L0MVC+rax*4]
    mov    dword [R12+mb.i_partition], D_8x8
    mov    eax, [R13+ME16+me.mv]
    mov    [R14], eax
    P8x8_BLOCK 0
    P8x8_BLOCK 1
    P8x8_BLOCK 2
    P8x8_BLOCK 3
    mov    eax, [R13+ME8+0*me_size+me.cost]
    add    eax, [R13+ME8+1*me_size+me.cost]
    add    eax, [R13+ME8+2*me_size+me.cost]
    add    eax, [R13+ME8+3*me_size+me.cost]
    ; 3 ref costs approximate CABAC's 4
    cmp    dword [rbx+ap.cabac], 0
    je .nc
    sub    eax, [rsp+S_REFC]
.nc:
    mov    [R13+an.l0+alist.i_cost8x8], eax
    mov    dword [R12+mb.i_sub_partition], D_L0_8x8*0x01010101
.select:
    mov    eax, [R13+ME16+me.cost]
    mov    ecx, P_L0
    mov    edx, D_16x16
    mov    esi, [R13+an.l0+alist.i_cost8x8]
    cmp    dword [R13+an.b_early_terminate], 0
    je .take8x8
    cmp    esi, eax
    jge .keep16x16
.take8x8:
    mov    eax, esi
    mov    ecx, P_8x8
    mov    edx, D_8x8
.keep16x16:
    mov    [rsp+S_COST], eax
    mov    [rsp+S_TYPE], ecx
    mov    [rsp+S_PART], edx
    cmp    dword [rbx+ap.gate], 0
    jne .done
    cmp    dword [R13+an.b_early_terminate], 0
    je .sub
    mov    eax, [R13+ME8+1*me_size+me.cost_mv]
    add    eax, [R13+ME8+2*me_size+me.cost_mv]
    add    eax, [R13+ME16+me.cost]
    cmp    [R13+an.l0+alist.i_cost8x8], eax
    jge .done
.sub:
    mov    eax, [R13+ME8+2*me_size+me.cost_mv]
    add    eax, [R13+ME8+2*me_size+me.i_ref_cost]
    add    eax, [R13+ME8+3*me_size+me.cost_mv]
    add    eax, [R13+ME8+3*me_size+me.i_ref_cost]
    inc    eax
    sar    eax, 1
    add    eax, [R13+an.i_satd8x8+2*4]
    add    eax, [R13+an.i_satd8x8+3*4]
    mov    [R13+an.i_cost_est16x8+4], eax
    P2 0
    mov    eax, [R13+an.l0+alist.i_cost16x8]
    cmp    eax, [rsp+S_COST]
    jge .no16x8
    mov    [rsp+S_COST], eax
    mov    dword [rsp+S_TYPE], P_L0
    mov    dword [rsp+S_PART], D_16x8
.no16x8:
    mov    eax, [R13+ME8+1*me_size+me.cost_mv]
    add    eax, [R13+ME8+1*me_size+me.i_ref_cost]
    add    eax, [R13+ME8+3*me_size+me.cost_mv]
    add    eax, [R13+ME8+3*me_size+me.i_ref_cost]
    inc    eax
    sar    eax, 1
    add    eax, [R13+an.i_satd8x8+1*4]
    add    eax, [R13+an.i_satd8x8+3*4]
    mov    [R13+an.i_cost_est8x16+4], eax
    P2 1
    mov    eax, [R13+an.l0+alist.i_cost8x16]
    cmp    eax, [rsp+S_COST]
    jge .done
    mov    [rsp+S_COST], eax
    mov    dword [rsp+S_TYPE], P_L0
    mov    dword [rsp+S_PART], D_8x16
.done:
    mov    eax, [rsp+S_COST]
    mov    [rbx+ap.i_cost], eax
    mov    eax, [rsp+S_TYPE]
    mov    [rbx+ap.i_type], eax
    mov    eax, [rsp+S_PART]
    mov    [rbx+ap.i_partition], eax
    RET

; LOAD_FENC, LOAD_HPELS and LOAD_WPELS (encoder/analyse.c) of the x264_me_t at rdi,
; list 0 ref esi (>= 0), luma offset edx (x), ecx (y) >= 0, without 4:4:4.
; rbx c, R12 mb, R13 a. Clobbers rax, rcx, rdx, rsi, R8-R11, xmm0-1.
ap_load:
    mov    rax, [R13+an.p_cost_mv]
    mov    [rdi+me.p_cost_mv], rax
    mov    rax, [R12+PIC+mb_pic.i_stride]
    mov    [rdi+me.i_stride], rax
    mov    eax, [R12+PIC+mb_pic.i_stride+8]
    mov    [rdi+me.i_stride+8], eax
    mov    R8d, [rbx+ap.v_shift]
    sarx   R8d, ecx, R8d                ; y >> CHROMA_V_SHIFT
    mov    eax, ecx
    shl    eax, 4
    add    eax, edx
    cdqe
    mov    R9, [R12+PIC+mb_pic.p_fenc]
    lea    R9, [R9+rax*SIZEOF_PIXEL]
    mov    [rdi+me.p_fenc], R9
    mov    eax, R8d
    shl    eax, 4
    mov    R9d, edx
    sar    R9d, 1
    add    eax, R9d
    cdqe
    mov    R9, [R12+PIC+mb_pic.p_fenc+8]
    lea    R9, [R9+rax*SIZEOF_PIXEL]
    mov    [rdi+me.p_fenc+8], R9
    mov    R9, [R12+PIC+mb_pic.p_fenc+16]
    lea    R9, [R9+rax*SIZEOF_PIXEL]
    mov    [rdi+me.p_fenc+16], R9
    mov    eax, [R12+PIC+mb_pic.i_fld_uv_y]
    add    eax, R8d
    mov    [rdi+me.i_fld_uv_y], eax
    imul   ecx, [R12+PIC+mb_pic.i_stride]
    add    ecx, edx
    movsxd R10, ecx                     ; luma offset
    imul   R8d, [R12+PIC+mb_pic.i_stride+4]
    add    R8d, edx
    movsxd R8, R8d                      ; chroma offset
    mov    [rdi+me.i_ref], esi
    imul   R11d, esi, 12*8
    lea    R11, [R12+R11+PIC+mb_pic.p_fref]
    lea    rax, [R10*SIZEOF_PIXEL]
    vmovq  xmm0, rax
    vpbroadcastq xmm0, xmm0
    vpaddq xmm1, xmm0, [R11]
    vmovdqu [rdi+me.p_fref], xmm1
    vpaddq xmm1, xmm0, [R11+16]
    vmovdqu [rdi+me.p_fref+16], xmm1
    lea    rcx, [R8*SIZEOF_PIXEL]
    vmovq  xmm1, rcx
    vpbroadcastq xmm1, xmm1
    vpaddq xmm1, xmm1, [R11+32]
    vmovdqu [rdi+me.p_fref+32], xmm1
    mov    rcx, [R12+PIC+mb_pic.p_fref_w+rsi*8]
    add    rcx, rax
    mov    [rdi+me.p_fref_w], rcx
    mov    rcx, [R12+PIC+mb_pic.p_integral+rsi*8]
    lea    rcx, [rcx+R10*2]
    mov    [rdi+me.integral], rcx
    mov    ecx, [rbx+ap.interlaced]
    sarx   eax, esi, ecx
    imul   eax, eax, 3*wt_size
    add    rax, [rbx+ap.weight]
    mov    [rdi+me.weight], rax
    ret

%endif ; UNIX64
