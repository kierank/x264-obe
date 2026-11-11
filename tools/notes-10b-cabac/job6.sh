S=/mnt/c/Users/kiera/AppData/Local/Temp/claude/e03b5c369dad1c6c/21f3df22-ec8f-4b2d-9d81-e76f5ec2f88e/scratchpad/cab10
{
mkdir -p /tmp/cab10/x86; cp $S/head-cabac-a.asm /tmp/cab10/x86/head.asm
export XSYM=x264_10_cabac_block_residual_rd2_internal_avx512icl XKIND=0
export X1D=-DRD4_ICL_LEVELS_MIN=0 X1N=i0 X2D=-DRD4_ICL_LEVELS_MIN=1 X2N=i1 X3D=-DRD4_ICL_LEVELS_MIN=3 X3N=i3 X4D=-DRD4_ICL_LEVELS_MIN=5 X4N=i5
DRVX="-DK4=1 -DK8=1 -DK422=1 -DICL2" bash $S/build.sh 2>&1 | grep -v "warning\|from macro\|^$\|^0000"
cd /tmp/cab10
bash $S/evex.sh new.o new_pic.o | grep -v "^  "
# 8-bit identity of cabac-a: .text/.rodata/.data, base vs tree, non-PIC
for sec in .text .rodata .data; do objcopy -O binary -j $sec b8/base8.o a.bin; objcopy -O binary -j $sec n8/new8.o b.bin; cmp -s a.bin b.bin && echo "8-bit cabac-a $sec identical (PIC: last build)" || echo "8-bit cabac-a $sec DIFFERS"; done
( cd b8 && nasm -I./ -f elf32 -DARCH_X86_64=0 -DHAVE_ALIGNED_STACK=1 -DSTACK_ALIGNMENT=16 -DHIGH_BIT_DEPTH=0 -DBIT_DEPTH=8 -Dprivate_prefix=x264_8 -o /tmp/cab10/x32b.o cabac-a.asm 2>&1 | grep error | head -2; echo "base x86_32 rc done" )
for d in drvx drv_pic; do echo "== $d"; timeout 600 taskset -c 2 ./$d test 1500; done
taskset -c 2 ./drvx ibench > /dev/null
for r in 1 2; do taskset -c 2 ./drvx ibench; done
echo "== mutations"
bash $S/mut.sh
} > $S/job6.out 2>&1
bash $S/ck2.sh
true
