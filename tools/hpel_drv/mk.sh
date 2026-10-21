#!/bin/bash
# Copyright (C) 2026 Open Broadcast Systems Ltd
# mk.sh <old common/x86 dir> <new common/x86 dir> [nasm]: build ./drv (8-bit hpel_filter(_copy)_avx2, old vs new)
#   ./drv [full=1] [seed] [only: -1 both, 0 old, 1 new]   correctness, guard pages, XINUSE, callee-saved
#   ./drv bench [W=1920] [H=1080] [rounds=11] [reps=20] [copy=0]   whole frames, ns/frame, old/new alternating
set -e
O=$1; N=$2; NA=${3:-nasm}; D=$(cd "$(dirname "$0")"; pwd)
cd "$D"
for k in old new; do
  S=$O; [ $k = new ] && S=$N
  F="-f elf64 -DSTACK_ALIGNMENT=64 -DARCH_X86_64=1 -I$S/ -DBIT_DEPTH=8 -DHIGH_BIT_DEPTH=0 -Dprivate_prefix=${k}8"
  $NA $F -o $k-mc.o $S/mc-a2.asm 2>&1 | grep -E "error" && exit 1
  $NA $F -o $k-const.o $S/const-a.asm 2>&1 | grep -E "error" && exit 1
done
$NA -f elf64 -o tramp.o tramp.asm
gcc -O1 -g -no-pie -o drv drv.c tramp.o old-mc.o old-const.o new-mc.o new-const.o
echo built
