# Copyright (C) 2026 Open Broadcast Systems Ltd
# checkasm8/10 seeds 1-5 per sha (tars/<sha>.tar), EVEX scan + cabac bench on the first sha
S=/mnt/c/Users/kiera/AppData/Local/Temp/claude/e03b5c369dad1c6c/21f3df22-ec8f-4b2d-9d81-e76f5ec2f88e/scratchpad/dcrd
O=$S/ck.out
echo "start $(date -u)" >> $O
first=1
for s in $SHAS; do
  for d in 8 10; do
    B=/tmp/dcrdt/$s-$d; rm -rf $B; mkdir -p $B; cd $B; tar xf $S/tars/$s.tar
    echo "$s: CR files $(grep -rlI $'\r' --include=*.c --include=*.h --include=*.asm . | wc -l)" >> $O
    ./configure --bit-depth=$d --enable-static --disable-opencl --disable-cli --extra-cflags=-fno-pie --extra-ldflags=-no-pie > cfg.log 2>&1
    if ! make -j8 checkasm$d > make.log 2>&1; then echo "$s $d-bit BUILD FAILED"; tail -15 make.log; fi >> $O
    echo "$s $d-bit warnings in bitstream/cabac/checkasm: $(grep 'warning:' make.log | grep -c 'bitstream\.c\|cabac\|checkasm\.c')" >> $O
    for seed in 1 2 3 4 5; do
      taskset -c 2 ./checkasm$d $seed > ck_$seed.txt 2>&1; r=$?
      echo "$s checkasm$d seed $seed rc $r: $(grep -c FAILED ck_$seed.txt) FAILED; $(grep -i 'cabac' ck_$seed.txt | tr -s ' ' | tr '\n' '|')" >> $O
    done
    if [ $first = 1 ]; then
      taskset -c 2 ./checkasm$d --bench=cabac_block_residual_422 1 > bench$d.txt 2>&1; grep -E "^nop|422" bench$d.txt >> $O
    fi
  done
  if [ $first = 1 ]; then
    bash $S/evex.sh $(find /tmp/dcrdt/$s-10 /tmp/dcrdt/$s-8 -name "cabac-a*.o") 2>&1 >> $O
    for d in 8 10; do objdump -d /tmp/dcrdt/$s-$d/common/x86/cabac-a-$d.o 2>/dev/null | grep -c "" ; done >> $O
  fi
  first=0
done
echo "end $(date -u)" >> $O
