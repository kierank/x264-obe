# Copyright (C) 2026 Open Broadcast Systems Ltd
S=/mnt/c/Users/kiera/AppData/Local/Temp/claude/e03b5c369dad1c6c/21f3df22-ec8f-4b2d-9d81-e76f5ec2f88e/scratchpad/dcrd
cd /tmp/dcrd
C="-f elf64 -DARCH_X86_64=1 -DHAVE_ALIGNED_STACK=1 -DSTACK_ALIGNMENT=64"
i=0
while IFS='|' read -r name from to; do
  [ -z "$name" ] && continue; i=$((i+1))
  awk -v f="$from" -v t="$to" 'BEGIN{d=0} /^%macro RD422_CTX/ { on=1 } { if( !d && (on || index(f, "rd422_") == 1) && index($0, f) == 1 ) { $0 = t; d=1 } print } END{ if(!d) print "NOMATCH" > "/dev/stderr" }' x86/cabac-a.asm > x86/mut.asm 2> mut.err
  if [ -s mut.err ]; then echo "M$i $name: pattern not found"; continue; fi
  r=""
  for d in 8 10; do
    if [ $d = 8 ]; then F="$C -DHIGH_BIT_DEPTH=0 -DBIT_DEPTH=8 -Dprivate_prefix=x264_8"; else F="$C -DHIGH_BIT_DEPTH=1 -DBIT_DEPTH=10 -Dprivate_prefix=x264_10"; fi
    nasm -Ix86/ $F -o mut.o x86/mut.asm 2> mut.log || { r="$r $d:asm-error"; continue; }
    gcc -O2 -mpreferred-stack-boundary=6 -I/tmp/dcrd -DBIT_DEPTH=$d $DRVX -no-pie -o drvm $S/drv422.c mut.o cpu$d.o 2>/dev/null
    r="$r $d-bit: $(timeout 300 taskset -c 2 ./drvm test 3000 2>&1 | grep -E '^(avx2|icl2) ' | tr -s ' ' | tr '\n' ' ')"
  done
  echo "M$i $name:$r"
done < $S/mutlist.txt
