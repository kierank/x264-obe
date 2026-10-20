;*****************************************************************************
;* bitstream-a.asm: x86 bitstream functions
;*****************************************************************************
;* Copyright (C) 2010-2014 x264 project
;*
;* Authors: Jason Garrett-Glaser <darkshikari@gmail.com>
;*          Henrik Gramner <henrik@gramner.com>
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

; vpermb indices, byte 2i+1 = i: bytes 0-31 and 32-63 interleaved with 0x03
nal_ilv_idx:
%assign nal_i 0
%rep 64
    db 0, nal_i
    %assign nal_i nal_i+1
%endrep
%undef nal_i

SECTION .text

;-----------------------------------------------------------------------------
; uint8_t *x264_nal_escape( uint8_t *dst, uint8_t *src, uint8_t *end )
;-----------------------------------------------------------------------------
%macro NAL_LOOP 2
%%escape:
    ; Detect false positive to avoid unneccessary escape loop
    xor      r3d, r3d
    cmp byte [r0+r1-1], 0
    setnz    r3b
    xor       k3, k4
    jnz .escape
    jmp %%continue
ALIGN 16
%1:
    mova [r0+r1+mmsize], m1
    pcmpeqb   m1, m0
    mova [r0+r1], m2
    pcmpeqb   m2, m0
    pmovmskb r3d, m1
    %2        m1, [r1+r2+3*mmsize]
    pmovmskb r4d, m2
    %2        m2, [r1+r2+2*mmsize]
    shl       k3, mmsize
    or        k3, k4
    lea       k4, [2*r3+1]
    and       k4, k3
    jnz %%escape
%%continue:
    add       r1, 2*mmsize
    jl %1
%endmacro

%macro NAL_ESCAPE 0
%if mmsize == 32
    %xdefine k3 r3
    %xdefine k4 r4
%else
    %xdefine k3 r3d
    %xdefine k4 r4d
%endif

cglobal nal_escape, 3,5
    movzx    r3d, byte [r1]
    sub       r1, r2 ; r1 = offset of current src pointer from end of src
    pxor      m0, m0
    mov     [r0], r3b
    sub       r0, r1 ; r0 = projected end of dst, assuming no more escapes
    or       r3d, 0xffffff00 ; ignore data before src

    ; Start off by jumping into the escape loop in case there's an escape at the start.
    ; And do a few more in scalar until dst is aligned.
    jmp .escape_loop

%if mmsize == 16
    NAL_LOOP .loop_aligned, mova
    jmp .ret
%endif
    NAL_LOOP .loop_unaligned, movu
.ret:
    movifnidn rax, r0
    RET

.escape:
    ; Skip bytes that are known to be valid
    and       k4, k3
    tzcnt     k4, k4
    xor      r3d, r3d ; the last two bytes are known to be zero
    add       r1, r4
.escape_loop:
    inc       r1
    jge .ret
    movzx    r4d, byte [r1+r2]
    shl      r3d, 8
    or       r3d, r4d
    test     r3d, 0xfffffc ; if the last two bytes are 0 and the current byte is <=3
    jz .add_escape_byte
.escaped:
    lea      r4d, [r0+r1]
    mov  [r0+r1], r3b
    test     r4d, mmsize-1 ; Do SIMD when dst is aligned
    jnz .escape_loop
    movu      m1, [r1+r2+mmsize]
    movu      m2, [r1+r2]
%if mmsize == 16
    lea      r4d, [r1+r2]
    test     r4d, mmsize-1
    jz .loop_aligned
%endif
    jmp .loop_unaligned

.add_escape_byte:
    mov byte [r0+r1], 3
    inc       r0
    or       r3d, 0x0300
    jmp .escaped
%endmacro

INIT_MMX mmx2
NAL_ESCAPE
INIT_XMM sse2
NAL_ESCAPE
%if ARCH_X86_64
INIT_YMM avx2
NAL_ESCAPE
%undef k3
%undef k4

;-----------------------------------------------------------------------------
; avx512icl: Z = zero bytes, L = bytes <= 3, C = L & Z<<1 & Z<<2 (continued
; from the previous block). An escape at i is C[i] && !escape[i-1]: every
; other bit of each run of C, from the start of the run. Blocks run up to the
; next aligned dst, so no read or write passes either end. A block with
; escapes interleaves 0x03 before every byte and vpcompressb keeps the 0x03s
; of the escapes.
;-----------------------------------------------------------------------------
INIT_ZMM avx512icl
cglobal nal_escape, 3,11,6
    sub       r1, r2              ; r1 = offset of src from end
    jge .ret
    sub       r0, r1              ; r0 = projected end of dst
    xor      r5d, r5d             ; zero bytes, the last two source bytes in bits 62-63
    xor      r6d, r6d             ; escape before the last source byte
    mov      r7d, 3
    vpbroadcastb m3, r7d
    movu      m4, [nal_ilv_idx]
    movu      m5, [nal_ilv_idx+64]
    mov       r9, 0xaaaaaaaaaaaaaaaa
    kmovq     k6, r9
    not       r9                  ; even bits
    jmp .block

.loop:
    cmp       r1, -2*mmsize
    jg .loop1
ALIGN 16
.loop2:
    movu      m0, [r2+r1]
    movu      m1, [r2+r1+mmsize]
    vptestnmb k1, m0, m0
    vptestnmb k2, m1, m1
    kmovq     r3, k1
    kmovq     r4, k2
    bt        r5, 63
    mov       r7, r3
    adc       r7, r3
    and       r7, r3              ; two zero bytes in a row
    jnz .block
    mova [r0+r1], m0
    mov       r5, r3
    xor      r6d, r6d
    bt        r3, 63
    mov       r8, r4
    adc       r8, r4
    and       r8, r4
    jnz .block2
    mova [r0+r1+mmsize], m1
    mov       r5, r4
    add       r1, 2*mmsize
    cmp       r1, -2*mmsize
    jle .loop2
    cmp       r1, -mmsize
    jg .tail
.loop1:
    movu      m0, [r2+r1]
    vptestnmb k1, m0, m0
    kmovq     r3, k1
    bt        r5, 63
    mov       r4, r3
    adc       r4, r3
    and       r4, r3              ; two zero bytes in a row
    jnz .block
    mova [r0+r1], m0
    mov       r5, r3
    xor      r6d, r6d
    add       r1, mmsize
.tail:
    test      r1, r1
    jge .ret
    jmp .block
.block2:
    add       r1, mmsize
.block:
    ; up to the next aligned dst or the end of src
    lea       r8, [r0+r1]
    not       r8
    and      r8d, mmsize-1
    inc      r8d
    mov       r7, r1
    neg       r7
    cmp       r7, r8
    cmovb     r8, r7              ; r8 = len
    mov       r7, -1
    bzhi      r7, r7, r8
    kmovq     k1, r7
    vmovdqu8  m0 {k1}{z}, [r2+r1]
    vptestnmb k2 {k1}, m0, m0
    vpcmpub   k3 {k1}, m0, m3, 2
    kmovq     r3, k2              ; Z
    kmovq     r4, k3              ; L
    mov       r7, r3
    shld      r7, r5, 1
    and       r4, r7
    mov       r7, r3
    shld      r7, r5, 2
    and       r4, r7              ; C
    shr       r5, 1
    lea       r7, [r8-1]
    shrx      r5, r5, r7
    mov      r7d, mmsize
    sub      r7d, r8d
    shlx      r3, r3, r7
    or        r5, r3
    andn      r4, r6, r4
    jz .noescape
    lea       r7, [r4+r4]
    andn      r7, r7, r4          ; run starts
    and       r7, r9
    add       r7, r4
    xor       r7, r4
    and       r7, r4              ; runs starting at an even bit
    xor       r7, r9
    andn      r4, r7, r4          ; escapes
    lea       r7, [r8-1]
    shrx      r6, r4, r7
    and      r6d, 1
    mov      r3d, r4d
    pdep      r3, r3, r9
    xor       r3, r9
    not       r3
    kmovq     k4, r3
    mov       r3, r4
    shr       r3, 32
    pdep      r3, r3, r9
    xor       r3, r9
    not       r3
    kmovq     k5, r3
    vmovdqa64 m1, m3
    vpermb    m1 {k6}, m4, m0
    vpcompressb m1 {k4}{z}, m1
    vmovdqa64 m2, m3
    vpermb    m2 {k6}, m5, m0
    vpcompressb m2 {k5}{z}, m2
    popcnt   r3d, r4d             ; escapes in bytes 0-31
    shr       r4, 32
    popcnt   r4d, r4d             ; escapes in bytes 32-63
    mov     r10, -1
    mov      r7d, 32
    cmp      r8d, r7d
    cmovb    r7d, r8d
    add      r7d, r3d
    bzhi      r7, r10, r7
    kmovq     k4, r7
    vmovdqu8 [r0+r1] {k4}, m1
    add       r0, r3
    xor      r3d, r3d
    mov      r7d, r8d
    sub      r7d, 32
    cmovb    r7d, r3d
    add      r7d, r4d
    bzhi      r7, r10, r7
    kmovq     k5, r7
    vmovdqu8 [r0+r1+32] {k5}, m2
    add       r0, r4
    add       r1, r8
    jmp .next
.noescape:
    vmovdqu8 [r0+r1] {k1}, m0
    xor      r6d, r6d
    add       r1, r8
.next:
    test      r1, r1
    jge .ret
    lea       r7, [r0+r1]
    test     r7d, mmsize-1
    jnz .block
    cmp       r1, -mmsize
    jg .block
    mov       r7, r5
    shr       r7, 62
    cmp      r7d, 3
    jne .loop
    jmp .block
.ret:
    mov      rax, r0
    RET
%endif
