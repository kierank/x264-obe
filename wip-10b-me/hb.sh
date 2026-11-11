# builds ~/me10/harness10 against ~/me10/b10 (the worktree build) with the base (origin/speed-next)
# me-64.asm's 10-bit avx2 entry as fpel_b0_avx2
set -e
W=/mnt/c/Users/kiera/AppData/Local/Temp/claude/e03b5c369dad1c6c/21f3df22-ec8f-4b2d-9d81-e76f5ec2f88e/scratchpad/me10
D=${1:-$HOME/me10/b10}; O=${2:-$HOME/me10/harness10}
sed 's/\r$//' $W/harness10.c > $D/harness10_src.c
sed 's/\r$//' $W/base-me-64.asm > $D/base_me.asm
cd $D
if [ ! -f base_me10.o ]; then
nasm -f elf64 -DSTACK_ALIGNMENT=64 -DHAS_CAVLC=0 -DARCH_X86_64=1 -I./common/x86/ -o base_me10.o base_me.asm -DBIT_DEPTH=10 -Dprivate_prefix=x264_10 2>/dev/null
objcopy --redefine-sym x264_10_me_search_fpel_avx2=fpel_b0_avx2 --localize-symbol x264_10_me_search_fpel_avx512 --localize-symbol x264_10_me_search_fpel_zmm_avx512 base_me10.o harness_b0me.o
fi
gcc -O2 -std=gnu99 -fno-pie -no-pie -fomit-frame-pointer -fno-tree-vectorize -mpreferred-stack-boundary=6 -I. -DHIGH_BIT_DEPTH=1 -DBIT_DEPTH=10 -o $O harness10_src.c harness_b0me.o libx264.a -lm -lpthread -ldl
ls -la $O
