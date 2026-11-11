# checkasm per commit, tip first; progressive output to $S/ck3.out
S=/mnt/c/Users/kiera/AppData/Local/Temp/claude/e03b5c369dad1c6c/21f3df22-ec8f-4b2d-9d81-e76f5ec2f88e/scratchpad/cab10
O=$S/ck3.out; TIP=241bb592; C=${C:-4}
JOBS="$TIP:8 $TIP:10 d625b235:8b d04be24f:10 2b83c12c:10 a2d60ded:10 3b31def8:10 873f5dea:10 5cf6d4ae:10 bcc7df8d:10 7641d69e:10 d57d0370:10 d57d0370:8 873f5dea:8"
echo "start $(date -u) cpu $C" >> $O
for j in $JOBS; do s=${j%%:*}; d=${j#*:}; nb=0; [ $d = 8b ] && { d=8; nb=1; }
  B=/tmp/cab10t/$s-$d; rm -rf $B; mkdir -p $B; cd $B; tar xf $S/tars/$s.tar
  ./configure --bit-depth=$d --enable-static --disable-opencl --extra-cflags=-fno-pie --extra-ldflags=-no-pie > cfg.log 2>&1
  if ! make -j8 checkasm$d > make.log 2>&1; then echo "$s $d-bit BUILD FAILED"; tail -15 make.log; continue; fi >> $O
  echo "$s $d-bit built $(date -u +%T), CR files $(grep -rlI $'\r' --include=*.c --include=*.h --include=*.asm . | wc -l), C warnings in bitstream.c/checkasm.c: $(grep 'warning:' make.log | grep -c 'bitstream\.c\|checkasm\.c')" >> $O
  [ $nb = 1 ] && continue
  for seed in 1 2 3 4 5; do
    timeout 1200 taskset -c $C ./checkasm$d $seed > ck_$seed.txt 2>&1; r=$?
    echo "$s checkasm$d seed $seed rc $r $(date -u +%T): $(grep -c FAILED ck_$seed.txt) FAILED; $(tail -1 ck_$seed.txt); cabac lines: $(grep -i 'cabac' ck_$seed.txt | sort | uniq -c | tr -s ' ' | tr '\n' '|')" >> $O
    grep FAILED ck_$seed.txt | head -5 >> $O
  done
  if [ $s = $TIP ]; then
    bash $S/evex.sh $(find $B -name "cabac-a*.o") 2>&1 | grep -v "^  x264_8" >> $O
    [ $d = 10 ] && { taskset -c 2 ./checkasm10 --bench=cabac_block_residual 1 > bench10.txt 2>&1; grep -E "^nop|cabac_block_residual" bench10.txt >> $O; }
  fi
  if [ $s = d625b235 ]; then # 8-bit library identity, every object, base vs tip
    cd /tmp/cab10t; n=0; bad=0
    for o in $(cd d625b235-8 && find . -name '*.o' | sort); do for sec in .text .rodata .data; do
      objcopy -O binary -j $sec d625b235-8/$o a.bin 2>/dev/null; objcopy -O binary -j $sec $TIP-8/$o b.bin 2>/dev/null
      cmp -s a.bin b.bin || { echo "8-bit $o $sec DIFFERS" >> $O; bad=$((bad+1)); }; done; n=$((n+1)); done
    echo "8-bit identity: $n objects x .text/.rodata/.data, $bad differences (d625b235 vs $TIP)" >> $O
  fi
done
echo "end $(date -u)" >> $O
