set -e
W=/mnt/c/Users/kiera/AppData/Local/Temp/claude/e03b5c369dad1c6c/21f3df22-ec8f-4b2d-9d81-e76f5ec2f88e/scratchpad
WT=$W/wt-10b-cabac
S=$W/cab10
mkdir -p /tmp/cab10/x86 /tmp/cab10/b8 && cd /tmp/cab10
rm -f /tmp/cab10/new.o /tmp/cab10/new_pic.o /tmp/cab10/drv /tmp/cab10/drv_pic /tmp/cab10/drvx
for f in x86inc.asm x86util.asm cabac-a.asm cpu-a.asm; do cp $WT/common/x86/$f x86/$f; done
cp $WT/common/x86/x86inc.asm $WT/common/x86/x86util.asm b8/; cp $S/base-cabac-a.asm b8/cabac-a.asm
{ echo '#include <stdint.h>'; echo '#define FIX8(f) ((int)(f*(1<<8)+.5))'; sed -n '/^const uint8_t x264_cabac_range_lps/,/^const uint8_t x264_count_cat_m1/p' $WT/common/tables.c; } > tables.h
C="-f elf64 -DARCH_X86_64=1 -DHAVE_ALIGNED_STACK=1 -DSTACK_ALIGNMENT=64"
F10="$C -DHIGH_BIT_DEPTH=1 -DBIT_DEPTH=10 -Dprivate_prefix=x264_10"
F8="$C -DHIGH_BIT_DEPTH=0 -DBIT_DEPTH=8 -Dprivate_prefix=x264_8"
nasm -Ix86/ $F10 -o cpu.o x86/cpu-a.asm
nasm -Ix86/ $F10 $NASMX -o new.o x86/cabac-a.asm
nasm -Ix86/ $F10 -DPIC $NASMX -o new_pic.o x86/cabac-a.asm
G="gcc -O2 -mpreferred-stack-boundary=6 -I/tmp/cab10 $DRVX"
$G -no-pie -o drv $S/drv.c new.o cpu.o
$G -pie -fPIE -o drv_pic $S/drv.c new_pic.o cpu.o
echo "driver built"
# 8-bit: the object must be identical to the base (same path, same flags), non-PIC and PIC
for p in "" "-DPIC"; do
  ( cd b8 && nasm -I./ $F8 $p -o base8.o cabac-a.asm )
  ( mkdir -p n8 && cp x86/cabac-a.asm x86/x86inc.asm x86/x86util.asm n8/ && cd n8 && nasm -I./ $F8 $p -o new8.o cabac-a.asm )
  cmp b8/base8.o n8/new8.o && echo "8-bit object identical to base ($p)" || echo "8-bit object DIFFERS ($p)"
done
# win64 and x86_32 assemble, both depths
for d in "-DHIGH_BIT_DEPTH=0 -DBIT_DEPTH=8 -Dprivate_prefix=x264_8" "-DHIGH_BIT_DEPTH=1 -DBIT_DEPTH=10 -Dprivate_prefix=x264_10"; do
  nasm -Ix86/ -f win64 -DARCH_X86_64=1 -DHAVE_ALIGNED_STACK=1 -DSTACK_ALIGNMENT=16 $d -o w64.o x86/cabac-a.asm && echo "win64 ok: $d"
  nasm -Ix86/ -f elf32 -DARCH_X86_64=0 -DHAVE_ALIGNED_STACK=1 -DSTACK_ALIGNMENT=16 $d -o x32.o x86/cabac-a.asm && echo "x86_32 ok: $d"
done
nm new.o | grep -E " T .*(avx2_bmi2|rd2)"
# extra arms of one symbol: X{1..4}S source (default the tree), X{1..4}D nasm defines, X{1..4}N names
if [ -n "${XSYM:-}" ]; then
  for x in 1 2 3 4; do
    eval src=\${X${x}S:-x86/cabac-a.asm}; eval d=\${X${x}D:-}
    nasm -Ix86/ $F10 $d -o x${x}full.o $src
    objcopy --keep-global-symbol=$XSYM x${x}full.o tmp.o
    objcopy --redefine-sym $XSYM=x${x}_fn tmp.o x${x}.o
  done
  $G -DXARMS -DXKIND=$XKIND -DX1NAME="\"$X1N\"" -DX2NAME="\"$X2N\"" -DX3NAME="\"$X3N\"" -DX4NAME="\"$X4N\"" -no-pie -o drvx $S/drv.c new.o x1.o x2.o x3.o x4.o cpu.o
  echo "built xarms $X1N $X2N $X3N $X4N"
fi
