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

SECTION_RODATA 64

; cabac_range_lps by state: [4*state + (range>>6) - 4]
hdr_range_lps:
    db 2, 2, 2, 2, 2, 2, 2, 2, 6, 7, 8, 9, 6, 7, 8, 9
    db 6, 7, 9, 10, 6, 7, 9, 10, 6, 8, 9, 11, 6, 8, 9, 11
    db 7, 8, 10, 11, 7, 8, 10, 11, 7, 9, 10, 12, 7, 9, 10, 12
    db 7, 9, 11, 12, 7, 9, 11, 12, 8, 9, 11, 13, 8, 9, 11, 13
    db 8, 10, 12, 14, 8, 10, 12, 14, 9, 11, 12, 14, 9, 11, 12, 14
    db 9, 11, 13, 15, 9, 11, 13, 15, 10, 12, 14, 16, 10, 12, 14, 16
    db 10, 12, 15, 17, 10, 12, 15, 17, 11, 13, 15, 18, 11, 13, 15, 18
    db 11, 14, 16, 19, 11, 14, 16, 19, 12, 14, 17, 20, 12, 14, 17, 20
    db 12, 15, 18, 21, 12, 15, 18, 21, 13, 16, 19, 22, 13, 16, 19, 22
    db 14, 17, 20, 23, 14, 17, 20, 23, 14, 18, 21, 24, 14, 18, 21, 24
    db 15, 19, 22, 25, 15, 19, 22, 25, 16, 20, 23, 27, 16, 20, 23, 27
    db 17, 21, 25, 28, 17, 21, 25, 28, 18, 22, 26, 30, 18, 22, 26, 30
    db 19, 23, 27, 31, 19, 23, 27, 31, 20, 24, 29, 33, 20, 24, 29, 33
    db 21, 26, 30, 35, 21, 26, 30, 35, 22, 27, 32, 37, 22, 27, 32, 37
    db 23, 28, 33, 39, 23, 28, 33, 39, 24, 30, 35, 41, 24, 30, 35, 41
    db 26, 31, 37, 43, 26, 31, 37, 43, 27, 33, 39, 45, 27, 33, 39, 45
    db 29, 35, 41, 48, 29, 35, 41, 48, 30, 37, 43, 50, 30, 37, 43, 50
    db 32, 39, 46, 53, 32, 39, 46, 53, 33, 41, 48, 56, 33, 41, 48, 56
    db 35, 43, 51, 59, 35, 43, 51, 59, 37, 45, 54, 62, 37, 45, 54, 62
    db 39, 48, 56, 65, 39, 48, 56, 65, 41, 50, 59, 69, 41, 50, 59, 69
    db 43, 53, 63, 72, 43, 53, 63, 72, 46, 56, 66, 76, 46, 56, 66, 76
    db 48, 59, 69, 80, 48, 59, 69, 80, 51, 62, 73, 85, 51, 62, 73, 85
    db 53, 65, 77, 89, 53, 65, 77, 89, 56, 69, 81, 94, 56, 69, 81, 94
    db 59, 72, 86, 99, 59, 72, 86, 99, 62, 76, 90, 104, 62, 76, 90, 104
    db 66, 80, 95, 110, 66, 80, 95, 110, 69, 85, 100, 116, 69, 85, 100, 116
    db 73, 89, 105, 122, 73, 89, 105, 122, 77, 94, 111, 128, 77, 94, 111, 128
    db 81, 99, 117, 135, 81, 99, 117, 135, 85, 104, 123, 142, 85, 104, 123, 142
    db 90, 110, 130, 150, 90, 110, 130, 150, 95, 116, 137, 158, 95, 116, 137, 158
    db 100, 122, 144, 166, 100, 122, 144, 166, 105, 128, 152, 175, 105, 128, 152, 175
    db 111, 135, 160, 185, 111, 135, 160, 185, 116, 142, 169, 195, 116, 142, 169, 195
    db 123, 150, 178, 205, 123, 150, 178, 205, 128, 158, 187, 216, 128, 158, 187, 216
    db 128, 167, 197, 227, 128, 167, 197, 227, 128, 176, 208, 240, 128, 176, 208, 240

SECTION .text

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

; tmp: the third temporary, r7 unless r7 is the PIC base
%ifdef PIC
    %define GLOBAL +r7-$$
    %define tmpq r9
    %define tmpd r9d
    %assign hdr_regs 10
%else
    %define GLOBAL
    %define tmpq r7
    %define tmpd r7d
    %assign hdr_regs 9
%endif

; low/range/queue stay in r3/r4d/r5d for the whole element; queue is unbiased,
; so the state between elements is the one of the per-bin functions

; the bins of r2 lsb first up to its top set bit, bin i with ctx byte i%8 of r1
; clobbers r2, r6, r8, tmp
%macro HDR_BINS 0
%%loop:
    movzx   tmpd, r1b
    movzx   r6d, byte [r0+tmpq+cb.state]
    mov     r8d, r4d
    shr     r8d, 6
%ifdef PIC
    lea      r8, [r7+r8]
    movzx   r8d, byte [r8+r6*4+hdr_range_lps-4-$$]
%else
    movzx   r8d, byte [hdr_range_lps-4+r8+r6*4]
%endif
    sub     r4d, r8d
    shr      r2, 1
    adc     r6d, r6d                ; 2*state+bin
    test    r6b, 3                  ; odd parity: bin != mps
    lea    tmpq, [r3+r4]
    cmovpo  r4d, r8d
    cmovpo   r3, tmpq
    movzx   r6d, byte [cabac_transition+r6 GLOBAL]
    movzx   r8d, r1b
    mov [r0+r8+cb.state], r6b
    lzcnt   r6d, r4d
    sub     r6d, 23
    shlx    r4d, r4d, r6d
    shlx     r3, r3, r6
    add     r5d, r6d
    jge %%putbyte
%%next:
    ror      r1, 8
    cmp      r2, 1
    jne %%loop
    jmp %%end
%%putbyte:
    call .putbyte
    jmp %%next
%%end:
%endmacro

; x264_cabac_putbyte while queue >= 0; clobbers r6, r8, tmp
%macro HDR_PUTBYTE 0
.putbyte:
    lea     r8d, [r5+10]
    shrx     r6, r3, r8             ; out: carry, byte
    bzhi     r3, r3, r8
    sub     r5d, 8
    cmp     r6b, 0xff
    je .postpone
    mov    tmpq, [r0+cb.p]
    mov     r8d, r6d
    shr     r8d, 8
    add [tmpq-1], r8b
    cmp dword [r0+cb.bytes_outstanding], 0
    jne .outstanding
.write:
    mov  [tmpq], r6b
    inc    tmpq
    mov [r0+cb.p], tmpq
    test    r5d, r5d
    jge .putbyte
    ret
.outstanding:
    dec     r8d                     ; carry-1
.outstanding_loop:
    mov  [tmpq], r8b
    inc    tmpq
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
cglobal cabac_encode_bins_bmi2, 4,hdr_regs
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
