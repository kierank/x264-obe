# checkasm8 + checkasm10 at the given seeds (default 1-5), summary lines
for s in ${@:-1 2 3 4 5}; do
  for b in 8 10; do
    r=$(cd ~/me10/$([ $b = 10 ] && echo c10 || echo b8) && taskset -c 2 ./checkasm$b $s 2>&1)
    echo "checkasm$b seed $s: $(echo "$r" | grep -cE 'FAILED') failed; $(echo "$r" | grep -E 'me_search_fpel' | tr '\n' ' ')"
    echo "$r" | grep -E 'FAILED' | head -5
  done
done
