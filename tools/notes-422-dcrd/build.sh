# Copyright (C) 2026 Open Broadcast Systems Ltd
set -e
W=/mnt/c/Users/kiera/AppData/Local/Temp/claude/e03b5c369dad1c6c/21f3df22-ec8f-4b2d-9d81-e76f5ec2f88e/scratchpad
WT=$W/wt-422-dcrd
S=$W/dcrd
B=/tmp/dcrd
mkdir -p $B/x86 && cd $B
for f in x86inc.asm x86util.asm cabac-a.asm cpu-a.asm; do cp $WT/common/x86/$f x86/$f; done
[ -n "$ASMSRC" ] && cp $ASMSRC x86/cabac-a.asm
{ echo '#include <stdint.h>'; echo '#define FIX8(f) ((int)(f*(1<<8)+.5))'; sed -n '/^const uint8_t x264_cabac_range_lps/,/^const uint8_t x264_count_cat_m1/p' $WT/common/tables.c; } > tables.h
C="-f elf64 -DARCH_X86_64=1 -DHAVE_ALIGNED_STACK=1 -DSTACK_ALIGNMENT=64"
for d in 8 10; do
  if [ $d = 8 ]; then F="$C -DHIGH_BIT_DEPTH=0 -DBIT_DEPTH=8 -Dprivate_prefix=x264_8"; else F="$C -DHIGH_BIT_DEPTH=1 -DBIT_DEPTH=10 -Dprivate_prefix=x264_10"; fi
  nasm -Ix86/ $F -o cpu$d.o x86/cpu-a.asm
  nasm -Ix86/ $F $NASMX -o new$d.o x86/cabac-a.asm
  nasm -Ix86/ $F -DPIC $NASMX -o newpic$d.o x86/cabac-a.asm
  G="gcc -O2 -mpreferred-stack-boundary=6 -I$B -DBIT_DEPTH=$d $DRVX"
  $G -no-pie -o drv$d $S/drv422.c new$d.o cpu$d.o
  $G -pie -fPIE -o drvpic$d $S/drv422.c newpic$d.o cpu$d.o
  nasm -Ix86/ -f win64 -DARCH_X86_64=1 -DHAVE_ALIGNED_STACK=1 -DSTACK_ALIGNMENT=16 $(echo $F | sed 's/-f elf64 -DARCH_X86_64=1 -DHAVE_ALIGNED_STACK=1 -DSTACK_ALIGNMENT=64//') -o w64_$d.o x86/cabac-a.asm && echo "win64 $d ok"
done
echo built
# extra arms of the avx2 symbol: X1D/X2D nasm defines, at depth XD
if [ -n "${X1D:-}" ]; then
  for d in 8 10; do
    if [ $d = 8 ]; then F="$C -DHIGH_BIT_DEPTH=0 -DBIT_DEPTH=8 -Dprivate_prefix=x264_8"; p=x264_8; else F="$C -DHIGH_BIT_DEPTH=1 -DBIT_DEPTH=10 -Dprivate_prefix=x264_10"; p=x264_10; fi
    for x in 1 2; do
      eval dd=\${X${x}D}
      eval xs=\${X${x}S:-x86/cabac-a.asm}
      eval xn=\${X${x}N:-cabac_block_residual_422_dc_rd_internal_avx2_bmi2}
      nasm -Ix86/ $F $dd -o x${x}full.o $xs
      objcopy --keep-global-symbol=${p}_$xn x${x}full.o tmp.o
      objcopy --redefine-sym ${p}_$xn=x${x}_fn tmp.o x${x}_$d.o
    done
    gcc -O2 -mpreferred-stack-boundary=6 -I$B -DBIT_DEPTH=$d -DXARMS $DRVX -no-pie -o drvx$d $S/drv422.c new$d.o x1_$d.o x2_$d.o cpu$d.o
  done
  echo "built xarms"
fi
