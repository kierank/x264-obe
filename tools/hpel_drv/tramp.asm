; Copyright (C) 2026 Open Broadcast Systems Ltd
; tramp(fn, args[9], out[2]): dirty zmm0-31 and k1-k7, magic callee-saved GPRs, call fn(args...),
; out[0] = XINUSE (xgetbv ecx=1), out[1] = mask of callee-saved GPRs that changed
BITS 64
default rel
section .data
align 64
junk: times 8 dq 0x9e3779b97f4a7c15
g_fn: dq 0
g_out: dq 0
section .text
global tramp
tramp:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov [g_fn], rdi
    mov [g_out], rdx
    mov rax, rsi
%assign i 0
%rep 32
    vmovdqu64 zmm %+ i, [junk]
    vpaddq zmm %+ i, zmm %+ i, [junk]
%assign i i+1
%endrep
    kmovq k1, [junk]
    kmovq k2, [junk]
    knotq k3, k1
    kmovq k4, k3
    kmovq k5, k1
    kmovq k6, k3
    kmovq k7, k1
    mov rbx, 0x1111111111111111
    mov rbp, 0x2222222222222222
    mov r12, 0x3333333333333333
    mov r13, 0x4444444444444444
    mov r14, 0x5555555555555555
    mov r15, 0x6666666666666666
    sub rsp, 32
    mov r10, [rax+48]
    mov [rsp], r10
    mov r10, [rax+56]
    mov [rsp+8], r10
    mov r10, [rax+64]
    mov [rsp+16], r10
    mov rdi, [rax]
    mov rsi, [rax+8]
    mov rdx, [rax+16]
    mov rcx, [rax+24]
    mov r8,  [rax+32]
    mov r9,  [rax+40]
    mov r10, 0x7777777777777777
    mov r11, 0x7777777777777777
    call [g_fn]
    add rsp, 32
    mov ecx, 1
    xgetbv
    mov r11, [g_out]
    mov [r11], rax
    xor eax, eax
%macro CHK 3
    mov rcx, %2
    cmp %1, rcx
    setne dl
    movzx edx, dl
    shl edx, %3
    or eax, edx
%endmacro
    CHK rbx, 0x1111111111111111, 0
    CHK rbp, 0x2222222222222222, 1
    CHK r12, 0x3333333333333333, 2
    CHK r13, 0x4444444444444444, 3
    CHK r14, 0x5555555555555555, 4
    CHK r15, 0x6666666666666666, 5
    mov [r11+8], rax
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; instrument self-tests
global bad_upper, bad_rbx, good_fn
bad_upper:
    vpxor ymm0, ymm0, ymm0
    vpcmpeqb ymm1, ymm1, ymm1
    ret
bad_rbx:
    vzeroupper
    mov rbx, 1
    ret
good_fn:
    vzeroupper
    ret
