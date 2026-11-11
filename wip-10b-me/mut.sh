# each mutation of ${ML:-mutlist.txt} (find<TAB>replace, \n escapes) on the worktree's me-64.asm in ~/me10/mut;
# harness10 1 round (+ checkasm10 seed 1 with $1 = ck); expect a mismatch / FAILED / crash
W=/mnt/c/Users/kiera/AppData/Local/Temp/claude/e03b5c369dad1c6c/21f3df22-ec8f-4b2d-9d81-e76f5ec2f88e/scratchpad/me10
M=~/me10/mut
[ -f $M/config.mak ] || { rsync -a ~/me10/b10/ $M/; }
i=0
while IFS=$'\t' read -r a b; do i=$((i+1))
  [ -n "${ONLY:-}" ] && [ "$ONLY" != "$i" ] && continue
  cp ~/me10/b10/common/x86/me-64.asm $M/common/x86/me-64.asm
  perl $W/mut.pl $M/common/x86/me-64.asm "$a" "$b" || { echo "mut $i: no match"; continue; }
  (cd $M && make libx264.a >/dev/null 2>&1 && make checkasm10 >/dev/null 2>&1) || { echo "mut $i: build failed"; continue; }
  bash $W/hb.sh $M $M/harness10 >/dev/null 2>&1 || { echo "mut $i: harness build failed"; continue; }
  r=$(cd $M && timeout 900 taskset -c 2 ./harness10 1 2>&1 | grep -E 'MISMATCH|FAILED' | head -2 | tr '\n' ' '); rc=$?
  [ -z "$r" ] && r=$( (cd $M && timeout 900 taskset -c 2 ./harness10 1 >/dev/null 2>&1) || echo "crash/exit $?")
  c=""
  if [ "$1" = ck ]; then c=$(cd $M && timeout 900 taskset -c 2 ./checkasm10 1 2>&1 | grep -E 'me_search_fpel.*FAILED|Segmentation' | head -1 | cut -c1-120); c=" | ck: ${c:-SURVIVED}"; fi
  echo "mut $i: ${r:-SURVIVED}$c" | cut -c1-260
done < $W/${ML:-mutlist.txt}
cp ~/me10/b10/common/x86/me-64.asm $M/common/x86/me-64.asm
