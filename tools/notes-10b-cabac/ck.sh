# checkasm8/10 seeds 1-5 per commit; tip first. Output to $S/ck.out progressively.
S=/mnt/c/Users/kiera/AppData/Local/Temp/claude/e03b5c369dad1c6c/21f3df22-ec8f-4b2d-9d81-e76f5ec2f88e/scratchpad/cab10
O=$S/ck.out
SHAS="${SHAS:-f4f70c82 d625b235 e2c72e53 b469bac9 3b31def8 873f5dea 5cf6d4ae bcc7df8d 7641d69e d57d0370}"
echo "start $(date -u)" >> $O
for s in $SHAS; do
  for d in 8 10; do
    B=/tmp/cab10t/$s-$d; mkdir -p $B; cd $B; tar xf $S/tars/$s.tar
    echo "$s: CR files $(grep -rlI $'\r' --include=*.c --include=*.h --include=*.asm . | wc -l)" >> $O
    ./configure --bit-depth=$d --enable-static --disable-opencl --disable-cli --extra-cflags=-fno-pie --extra-ldflags=-no-pie > cfg.log 2>&1
    if ! make -j8 checkasm$d > make.log 2>&1; then echo "$s $d-bit BUILD FAILED"; tail -15 make.log; fi >> $O
    echo "$s $d-bit warnings in bitstream/cabac/checkasm: $(grep 'warning:' make.log | grep -c 'bitstream\.c\|cabac\|checkasm\.c')" >> $O
    [ "$s" = d625b235 ] && [ $d = 10 ] && continue
    for seed in 1 2 3 4 5; do
      taskset -c 2 ./checkasm$d $seed > ck_$seed.txt 2>&1; r=$?
      echo "$s checkasm$d seed $seed rc $r: $(grep -c FAILED ck_$seed.txt) FAILED; $(grep -i 'cabac' ck_$seed.txt | tr -s ' ' | tr '\n' '|')" >> $O
    done
  done
  if [ "$s" = f4f70c82 ]; then
    bash $S/evex.sh $(find /tmp/cab10t/$s-10 /tmp/cab10t/$s-8 -name "cabac-a*.o") 2>&1 | grep -v "^  x264_8" >> $O
    cd /tmp/cab10t/$s-10 && taskset -c 2 ./checkasm10 --bench=cabac_block_residual 1 > bench10.txt 2>&1; grep -E "^nop|cabac_block_residual" bench10.txt >> $O
  fi
done
# 8-bit byte identity: every object of the 8-bit library, base vs tip, sections .text .rodata .data
cd /tmp/cab10t
n=0; bad=0
for o in $(cd d625b235-8 && find . -name '*.o' | sort); do
  for sec in .text .rodata .data; do
    objcopy -O binary -j $sec d625b235-8/$o /tmp/cab10t/a.bin 2>/dev/null; objcopy -O binary -j $sec f4f70c82-8/$o /tmp/cab10t/b.bin 2>/dev/null
    cmp -s a.bin b.bin || { echo "8-bit $o $sec DIFFERS" >> $O; bad=$((bad+1)); }
  done; n=$((n+1))
done
echo "8-bit identity: $n objects, $bad section differences (base d625b235 vs tip f4f70c82)" >> $O
echo "end $(date -u)" >> $O
