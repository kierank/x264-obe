;*****************************************************************************
;* cabac-hdr-a.asm: x86 cabac header syntax
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

SECTION .text

cextern_common cabac_range_lps
cextern_common cabac_transition

struc cb
    .low: resd 1
    .range: resd 1
    .queue: resd 1
    .bytes_outstanding: resd 1
    .start: resq 1
    .p: resq 1
    .end: resq 1
    align 64, resb 1
    .bits_encoded: resd 1
    .state: resb 1024
endstruc

%ifdef PIC
    %define GLOBAL +r7-$$
%else
    %define GLOBAL
%endif

; low/range/queue stay in r3/r4d/r5d for the whole element; queue is unbiased,
; so the state between elements is the one of the per-bin functions

; the bins of r2 lsb first up to its top set bit, contexts from the bytes of r1
; clobbers r1, r2, r6, r8, r9
%macro HDR_BINS 0
%%loop:
    movzx   r6d, r1b
    movzx   r6d, byte [r0+r6+cb.state]
    mov     r8d, r4d
    shr     r8d, 6
    mov     r9d, r6d
    and     r9d, ~1
%ifdef PIC
    lea      r9, [r7+r9*2]
    movzx   r8d, byte [r9+r8+cabac_range_lps-4-$$]
%else
    movzx   r8d, byte [cabac_range_lps-4+r8+r9*2]
%endif
    sub     r4d, r8d
    mov     r9d, r6d
    shr      r2, 1
    adc     r9d, r6d                ; 2*state+bin
    test    r9b, 3                  ; odd parity: bin != mps
    lea      r6, [r3+r4]
    cmovpo  r4d, r8d
    cmovpo   r3, r6
    movzx   r6d, byte [cabac_transition+r9 GLOBAL]
    movzx   r8d, r1b
    mov [r0+r8+cb.state], r6b
    lzcnt   r6d, r4d
    sub     r6d, 23
    shlx    r4d, r4d, r6d
    shlx     r3, r3, r6
    add     r5d, r6d
    jge %%putbyte
%%next:
    mov      r6, r1
    shr      r6, 8
    cmovnz   r1, r6                 ; the top ctx byte repeats
    cmp      r2, 1
    jne %%loop
    jmp %%end
%%putbyte:
    call .putbyte
    jmp %%next
%%end:
%endmacro

; x264_cabac_putbyte while queue >= 0; clobbers r6, r8, r9
%macro HDR_PUTBYTE 0
.putbyte:
    lea     r8d, [r5+10]
    shrx     r6, r3, r8             ; out: carry, byte
    bzhi     r3, r3, r8
    sub     r5d, 8
    cmp     r6b, 0xff
    je .postpone
    mov      r9, [r0+cb.p]
    mov     r8d, r6d
    shr     r8d, 8
    add  [r9-1], r8b
    cmp dword [r0+cb.bytes_outstanding], 0
    jne .outstanding
.write:
    mov    [r9], r6b
    inc      r9
    mov [r0+cb.p], r9
    test    r5d, r5d
    jge .putbyte
    ret
.outstanding:
    dec     r8d                     ; carry-1
.outstanding_loop:
    mov    [r9], r8b
    inc      r9
    dec dword [r0+cb.bytes_outstanding]
    jg .outstanding_loop
    jmp .write
.postpone:
    inc dword [r0+cb.bytes_outstanding]
    test    r5d, r5d
    jge .putbyte
    ret
%endmacro

;-----------------------------------------------------------------------------
; void cabac_encode_bins( x264_cabac_t *cb, uint64_t ctx, uint32_t bins, int n )
;-----------------------------------------------------------------------------
cglobal cabac_encode_bins_bmi2, 4,10
%ifdef PIC
    lea      r7, [$$]
%endif
    bzhi    r2d, r2d, r3d
    bts      r2, r3                 ; stop bit
    mov     r3d, [r0+cb.low]
    mov     r4d, [r0+cb.range]
    mov     r5d, [r0+cb.queue]
    HDR_BINS
    mov [r0+cb.low], r3d
    mov [r0+cb.range], r4d
    mov [r0+cb.queue], r5d
    RET
    HDR_PUTBYTE
