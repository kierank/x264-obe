# EVEX scan of the 10-bit avx2 entry (whole body: the function symbol to the next one), and 8-bit me-64-8.o
# byte identity vs origin/speed-next (raw bytes + relocations of every function)
W=/mnt/c/Users/kiera/AppData/Local/Temp/claude/e03b5c369dad1c6c/21f3df22-ec8f-4b2d-9d81-e76f5ec2f88e/scratchpad/me10
O=~/me10/c10/common/x86/me-64-10.o
for f in x264_10_me_search_fpel_avx2 x264_10_me_search_fpel_inline_avx512 x264_10_me_search_fpel_avx512; do
  objdump -d --no-show-raw-insn --disassemble=$f $O > /tmp/me10d.txt 2>/dev/null
  n=$(grep -c '^ ' /tmp/me10d.txt); ev=$(objdump -d --disassemble=$f $O | grep -cP '^\s+[0-9a-f]+:\s+62 ')
  z=$(grep -cE 'zmm|[xy]mm(1[6-9]|2[0-9]|3[01])|\{k|%k[0-7]' /tmp/me10d.txt); lo=$(grep -cE '[xy]mm([0-9]|1[0-5])\b' /tmp/me10d.txt)
  echo "$f insns=$n evex62=$ev zmm/hi/k=$z ymm0-15-refs=$lo"
done
# 8-bit: base object from origin/speed-next's me-64.asm
cd ~/me10/b8
nasm -f elf64 -DSTACK_ALIGNMENT=64 -DHAS_CAVLC=0 -DARCH_X86_64=1 -I./common/x86/ -o /tmp/me10_base8.o $W/base-me-64.asm -DBIT_DEPTH=8 -Dprivate_prefix=x264_8 2>/dev/null
nasm -f elf64 -DSTACK_ALIGNMENT=64 -DHAS_CAVLC=0 -DARCH_X86_64=1 -I./common/x86/ -o /tmp/me10_new8.o common/x86/me-64.asm -DBIT_DEPTH=8 -Dprivate_prefix=x264_8 2>/dev/null
a=$(objdump -dr /tmp/me10_base8.o | tail -n +4 | md5sum); b=$(objdump -dr /tmp/me10_new8.o | tail -n +4 | md5sum)
[ "$a" = "$b" ] && echo "8-bit me-64-8.o: code + relocations identical to origin/speed-next" || echo "8-bit me-64-8.o DIFFERS"
a=$(objdump -s -j .rodata /tmp/me10_base8.o | tail -n +4 | md5sum); b=$(objdump -s -j .rodata /tmp/me10_new8.o | tail -n +4 | md5sum)
[ "$a" = "$b" ] && echo "8-bit rodata identical" || echo "8-bit rodata DIFFERS"
