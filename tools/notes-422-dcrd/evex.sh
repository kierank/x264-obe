# Copyright (C) 2026 Open Broadcast Systems Ltd
# EVEX scan: functions whose name lacks avx512/icl must have 0 EVEX (0x62-first) instructions
# local labels (fn.label) count to their function; nasm macro-locals (..@) are skipped
for o in "$@"; do
  objdump -d -M intel $o | awk -v O=$o '
    /^[0-9a-f]+ <.*>:$/ { fn=$2; gsub(/[<>:]/,"",fn); if(fn !~ /^\.\.@/) { cur=fn; sub(/\..*/,"",cur) } next }
    /^\s+[0-9a-f]+:\t/ { split($0,t,"\t"); b=t[2]; gsub(/^ +| +$/,"",b); n=split(b,a," "); i=1;
       while(a[i] ~ /^(66|67|f2|f3|2e|3e|26|64|65|36)$/) i++;
       if(a[i]=="62") { if(cur ~ /avx512|icl/) e512[cur]++; else { bad[cur]++ } } else if (cur ~ /avx2_bmi2/) navx2[cur]++ }
    END { nb=0; for(f in bad) { print O" EVEX in non-avx512 fn " f ": " bad[f]; nb++ }
          tot=0; for(f in e512) tot+=e512[f]; print O": non-avx512 functions with EVEX: " nb ", EVEX insns inside avx512/icl fns: " tot;
          for(f in navx2) print "  " f ": " navx2[f] " non-EVEX insns" }'
done
