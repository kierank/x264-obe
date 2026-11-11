S=/mnt/c/Users/kiera/AppData/Local/Temp/claude/e03b5c369dad1c6c/21f3df22-ec8f-4b2d-9d81-e76f5ec2f88e/scratchpad/cab10
cd /tmp/cab10
F10="-f elf64 -DARCH_X86_64=1 -DHAVE_ALIGNED_STACK=1 -DSTACK_ALIGNMENT=64 -DHIGH_BIT_DEPTH=1 -DBIT_DEPTH=10 -Dprivate_prefix=x264_10"
i=0
while IFS='|' read -r name from to; do
  [ -z "$name" ] && continue; i=$((i+1))
  awk -v f="$from" -v t="$to" 'BEGIN{d=0} { if( !d && index($0, f) == 1 ) { $0 = t; d=1 } print } END{ if(!d) print "NOMATCH" > "/dev/stderr" }' x86/cabac-a.asm > x86/mut.asm 2> mut.err
  if [ -s mut.err ]; then echo "M$i $name: pattern not found"; continue; fi
  nasm -Ix86/ $F10 -o mut.o x86/mut.asm 2> mut.log || { echo "M$i $name: assemble error"; continue; }
  gcc -O2 -mpreferred-stack-boundary=6 -I/tmp/cab10 -DK4=1 -DK8=1 -DK422=1 -DICL2 -no-pie -o drvm $S/drv.c mut.o cpu.o 2>/dev/null
  echo "M$i $name: $(timeout 300 taskset -c 2 ./drvm test 300 2>&1 | grep '(new)' | grep -c FAILED) new kernel(s) FAILED"
done < $S/mutlist.txt
