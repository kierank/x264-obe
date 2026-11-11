# Shared phases of the Xeon E A/B jobs; xeone-jobs/<pkg>/*.sh source this file.
# Copyright (C) 2026 Open Broadcast Systems Ltd
#
# Machine: Xeon E-2478 (Raptor Cove: AVX2 + AVX-VNNI, no AVX-512, no SlowGather), the Intel AVX2 timing judge.
# x264 runs on cpu 12 or 14 only. Builds run on cpus 12-15 in build windows; timing only in timing blocks.
#
# Phases (one per invocation; nothing else heavy on the box during live / md5 / time):
#   build      trees (per-sha dirs) + binaries + checkasm 3 seeds          -> build window
#   live       perf record -e cycles:u symbol samples, base and arm, every cell; then the job's counter trees
#   md5        gate: recon md5 across base/base'/arm/arm', bitstream md5 within one sha (base/base', arm/arm')
#   time [R]   R paired rounds (default ROUNDS=9), base/base'/arm/arm' rotated per round -> timing block
#   report     per cell: median cycles:u and instructions:u per arm, paired median arm-base %, A/A %, faster-in-N
#   clean      remove the work dir
# Env: CORE (12; or 14), CORES (12,14: cells with --threads > 1), BUILD_CPUS (12-15), MAKEJ (4),
#      CLIPS (/home/obe/x264-clips), FRAMES (30), ROUNDS (9),
#      REPO (~/x264j/src: the local clone of github kierank/x264-obe; cloned there if missing), W (work dir),
#      XE_TEST=1 (source only, for dry checks of the cells: XE_TEST=1 bash -c '. "$0"; xe_cell <cell>; echo $CO' <job>.sh).
#
# A job script sets, then sources this file, then defines modes / hooks, then calls xe_main "$@":
#   JOB, AB (variant), BRANCHES, BASE, ARM (shas; base' / arm' are second builds of the same sha),
#   BITDEPTH (8 | 10 | all), CELLS (timed + md5), MD5CELLS (md5 only), LIVE_RE (egrep of the symbols),
#   NULLCELLS (cell names expected to show 0 samples of the changed code; timed, excluded from the verdict),
#   COUNT_TREES / COUNT_RE (counter trees, never timed, and the stderr line they print), SHA_<tree> (sha override).
# Cell = clip:mode[:frames]; mode = MODE_<mode> options; "mode@10" adds --output-depth 10 (BITDEPTH=all builds).
#   *422* clips get --output-csp i422 and --profile high422; 10-bit 4:2:0 gets --profile high10; -i clips --tff.
# Hooks: xe_patch <tree> <flavour> (runs in the tree before configure; non-zero = abort), xe_cflags <tree> <flavour>
#   (extra cflags), xe_asflags <tree> <flavour>, xe_bench (checkasm --bench lines in build), xe_phase_<name> (extra phases).
# Flavours: t = timing build (-fno-pie), m = md5 build (-fno-pie -fno-fast-math -ffp-contract=off),
#           c = counter build (as m). Every tree lives in $W/<tree>-<sha8>-<flavour>: no two cells or shas share binaries.

CORE=${CORE:-12}; CORES=${CORES:-12,14}; BUILD_CPUS=${BUILD_CPUS:-12-15}; MAKEJ=${MAKEJ:-4}
CLIPS=${CLIPS:-/home/obe/x264-clips}; FRAMES=${FRAMES:-30}; ROUNDS=${ROUNDS:-9}
REPO=${REPO:-$HOME/x264j/src}; SRC=$REPO; GITHUB=https://github.com/kierank/x264-obe   # REPO: a local clone path
BITDEPTH=${BITDEPTH:-8}
EVENTS=${EVENTS:-cycles:u,instructions:u}
W=${W:-$HOME/xeone/$JOB${AB:+-$AB}-${BASE:0:8}-${ARM:0:8}}
LOWLAT="--preset veryfast --tune zerolatency --intra-refresh --keyint 30 --bitrate 20000 --vbv-maxrate 20000 --vbv-bufsize 667 --nal-hrd fakevbr --aud --pic-struct --open-gop --profile high --threads 1"
NORMAL="--subme 6 --me hex --ref 2 --no-mixed-refs --no-chroma-me --trellis 1 --partitions i8x8,i4x4 --psy-rd 1.0:0 --bframes 3 --rc-lookahead 24 --keyint 30 --bitrate 20000 --vbv-maxrate 20000 --vbv-bufsize 20000 --nal-hrd fakevbr --aud --pic-struct --open-gop --profile high --threads 1"
MODE_lowlat=$LOWLAT; MODE_normal=$NORMAL

xe_die() { echo "$JOB: $*" >&2; exit 1; }

xe_treesha() { # tree name -> sha
    local v="SHA_$1"
    [ -n "${!v:-}" ] && { echo "${!v}"; return; }
    case $1 in base*) echo $BASE ;; arm*) echo $ARM ;; *) xe_die "no sha for tree $1 (set SHA_$1)" ;; esac
}
xe_dir() { local s; s=$(xe_treesha $1); echo $W/$1-${s:0:8}-$2; }
xe_bin() { echo $(xe_dir $1 $2)/x264; }

xe_src() { # the local clone, with every branch of the job fetched to a remote-tracking ref
    [ -d $SRC/.git ] || git clone -q $GITHUB $SRC || xe_die "clone $GITHUB -> $SRC failed"
    local b s
    for b in $BRANCHES; do git -C $SRC fetch -q origin "+refs/heads/$b:refs/remotes/origin/$b" || xe_die "fetch $b failed"; done
    for s in $BASE $ARM; do git -C $SRC rev-parse -q --verify "$s^{commit}" > /dev/null || xe_die "$s is not in $SRC"; done
}

xe_tree() { # tree flavour: one clone of the tree's sha, patched by the job, configured and built
    local n=$1 f=$2 s d cf as ck
    s=$(xe_treesha $n); d=$(xe_dir $n $f)
    [ -x $d/x264 ] && { echo "have $(basename $d)"; return 0; }
    rm -rf $d
    git clone -q --shared --no-checkout $SRC $d && git -C $d checkout -q --detach $s || { echo "checkout $s failed"; return 1; }
    [ "$(git -C $d rev-parse HEAD)" = "$(git -C $SRC rev-parse "$s^{commit}")" ] || { echo "WRONG TREE $d"; return 1; }
    if declare -F xe_patch > /dev/null; then (cd $d && xe_patch $n $f) || { echo "PATCH FAILED $n-$f"; return 1; }; fi
    cf="-fno-pie"; [ $f != t ] && cf="-fno-pie -fno-fast-math -ffp-contract=off"
    declare -F xe_cflags > /dev/null && cf="$cf $(xe_cflags $n $f)"
    as=""; declare -F xe_asflags > /dev/null && as=$(xe_asflags $n $f)
    ck=""; [ $f = t ] && case $BITDEPTH in 8) ck=checkasm8 ;; 10) ck=checkasm10 ;; all) ck="checkasm8 checkasm10" ;; esac
    (cd $d && taskset -c $BUILD_CPUS ./configure --bit-depth=$BITDEPTH --enable-static --disable-opencl --disable-lavf --disable-ffms \
        --disable-gpac --disable-lsmash --extra-cflags="$cf" --extra-ldflags="-no-pie" ${as:+--extra-asflags="$as"} > cfg.log 2>&1) ||
        { tail -5 $d/cfg.log; echo "configure failed $d"; return 1; }
    # Pin the version string: the SEI carries it, and a patched (dirty, "M") tree or a different r-count changes the
    # I-frame size, which under tight VBV (lowlat 667/1667) diverges rate control and recon (.44 44-CB, 11-11).
    sed -i -e 's|^#define X264_VERSION .*|#define X264_VERSION " rpinned"|' -e 's|^#define X264_POINTVER .*|#define X264_POINTVER "0.0.pinned"|' $d/x264_config.h
    grep -q '"0.0.pinned"' $d/x264_config.h || { echo "version pin failed $d"; return 1; }
    (cd $d && taskset -c $BUILD_CPUS make -j$MAKEJ x264 $ck > make.log 2>&1) || { tail -20 $d/make.log; echo "make failed $d"; return 1; }
    echo "built $(basename $d): $(git -C $d log -1 --format='%h %s' | cut -c1-90)${cf:+ [cflags $cf]}"
}

xe_cell() { # cell -> CL (clip file) CO (options) CC (cpus) CN (name)
    local spec=$1 clip mode rest fr d10="" depth prof
    clip=${spec%%:*}; rest=${spec#*:}; mode=${rest%%:*}; fr=$FRAMES
    [ "$rest" != "$mode" ] && fr=${rest#*:}
    case $mode in *@10) d10=1; mode=${mode%@10} ;; esac
    local v="MODE_$mode"; CO=${!v:-}; [ -n "$CO" ] || xe_die "no MODE_$mode for cell $spec"
    depth=$BITDEPTH; [ -n "$d10" ] && { CO="$CO --output-depth 10"; depth=10; }
    prof=high; [ "$depth" = 10 ] && prof=high10
    case $clip in *422*) CO="$CO --output-csp i422"; prof=high422 ;; esac
    case " $CO " in *" --profile "*) CO=$(echo "$CO" | sed "s/--profile [a-z0-9]*/--profile $prof/") ;; *) [ $prof != high ] && CO="$CO --profile $prof" ;; esac
    case $clip in *-i) CO="$CO --tff" ;; esac
    [ "$fr" != 0 ] && CO="$CO --frames $fr"
    CL=$CLIPS/$clip.y4m; CN=${spec//:/_}; CN=${CN//@/-}
    case " $CO " in *" --threads 1 "*) CC=$CORE ;; *) CC=$CORES ;; esac
}

xe_run() { # tree flavour cell tag [extra x264 args...]: one untimed encode, stream to $W/out/<tag>.264, stderr to .log
    local b; b=$(xe_bin $1 $2); xe_cell $3; local t=$4; shift 4
    taskset -c $CC $b $CO "$@" -o $W/out/$t.264 $CL 2> $W/out/$t.log
}

xe_perf() { # tree cell -> the EVENTS values in order, space separated (NA when not counted)
    local b; b=$(xe_bin $1 t); xe_cell $2
    taskset -c $CC perf stat -x, -e $EVENTS -o $W/out/perf.txt -- $b $CO -o /dev/null $CL 2> $W/out/perf.log ||
        { echo "$EVENTS" | tr ',' '\n' | sed 's/.*/NA/' | tr '\n' ' '; return; }
    local e; for e in $(echo $EVENTS | tr ',' ' '); do
        awk -F, -v e=$e 'index( $3, e ) && $1 ~ /^[0-9.]+$/ { v += $1; n++ } END { if( n ) printf "%.0f ", v; else printf "NA " }' $W/out/perf.txt
    done
}

xe_build() {
    mkdir -p $W/out; xe_src
    local f n a s
    for f in t m; do for n in base base2 arm arm2; do xe_tree $n $f || exit 1; done; done
    for n in ${COUNT_TREES:-}; do xe_tree $n c || exit 1; done
    md5sum $(xe_bin base t) $(xe_bin base2 t) $(xe_bin arm t) $(xe_bin arm2 t) | sed "s|$W/||"   # base == base', arm == arm' expected
    local ck=checkasm8; [ $BITDEPTH = 10 ] && ck=checkasm10
    for a in base arm; do for s in 1001 2002 3003; do
        (cd $(xe_dir $a t) && taskset -c $CORE ./$ck $s > $W/out/ck_${a}_$s.txt 2>&1); echo "$a $ck seed $s rc $? $(grep -c FAILED $W/out/ck_${a}_$s.txt) FAILED: $(tail -1 $W/out/ck_${a}_$s.txt)"
    done; done
    if [ $BITDEPTH = all ]; then for a in base arm; do
        (cd $(xe_dir $a t) && taskset -c $CORE ./checkasm10 1001 > $W/out/ck10_$a.txt 2>&1); echo "$a checkasm10 seed 1001 rc $? $(tail -1 $W/out/ck10_$a.txt)"
    done; fi
    declare -F xe_bench > /dev/null && xe_bench
    for a in base arm; do echo "$a: $($(xe_bin $a t) --version 2>/dev/null | head -1)"; done
}

xe_isnull() { case " ${NULLCELLS:-} " in *" $1 "*) return 0 ;; esac; return 1; }

xe_live() { # perf samples of LIVE_RE, base and arm, every cell (timing builds, pinned like the timed runs)
    mkdir -p $W/out; local spec a f tot hits
    for spec in ${LIVECELLS:-$CELLS}; do xe_cell $spec
        [ -f $CL ] || { echo "$CN: SKIP (no $CL)"; continue; }
        for a in base arm; do f=$W/out/live_${a}_$CN.data
            taskset -c $CC perf record -q -e cycles:u -o $f -- $(xe_bin $a t) $CO -o /dev/null $CL 2> /dev/null
            perf report -q -n --stdio -i $f --sort sym 2> /dev/null > $f.txt
            tot=$(awk '$2 ~ /^[0-9]+$/ { s += $2 } END { print s + 0 }' $f.txt)
            hits=$(grep -E "$LIVE_RE" $f.txt | awk '{ printf "%s %s (%s); ", $NF, $2, $1 }')
            echo "$CN $a$(xe_isnull $CN && echo ' [null cell]'): ${hits:-0 samples of /$LIVE_RE/} [$tot samples]"
        done
    done
    local n c
    for n in ${COUNT_TREES:-}; do for spec in ${COUNTCELLS:-$CELLS}; do xe_cell $spec
        [ -f $CL ] || continue
        c=${spec//[:@]/_}
        xe_run $n c $spec cnt_${n}_$c > /dev/null
        echo "$CN $n: $(grep -E "$COUNT_RE" $W/out/cnt_${n}_$c.log | tr '\n' ' ')"
        rm -f $W/out/cnt_${n}_$c.264
    done; done
}

xe_md5() { # recon across the 4 arms; bitstream within one sha
    mkdir -p $W/out; local spec a nr nb na bad v
    for spec in $CELLS ${MD5CELLS:-}; do xe_cell $spec
        [ -f $CL ] || { echo "$CN: SKIP (no $CL)"; continue; }
        bad=""
        for a in base base2 arm arm2; do
            taskset -c $CC $(xe_bin $a m) $CO --dump-yuv $W/out/rec_$a.yuv -o $W/out/bs_$a.264 $CL 2> $W/out/md5_$a.log || bad="$bad $a:rc$?"
            [ -s $W/out/rec_$a.yuv ] && [ -s $W/out/bs_$a.264 ] || bad="$bad $a:empty"
        done
        nr=$(md5sum $W/out/rec_{base,base2,arm,arm2}.yuv | awk '{print $1}' | sort -u | wc -l)
        nb=$(md5sum $W/out/bs_{base,base2}.264 | awk '{print $1}' | sort -u | wc -l)
        na=$(md5sum $W/out/bs_{arm,arm2}.264 | awk '{print $1}' | sort -u | wc -l)
        v=PASS; [ "$nr $nb $na" = "1 1 1" ] || v=FAIL; [ -n "$bad" ] && v="FAIL ($bad )"
        case " ${MD5_DIFF_OK:-} " in *" $CN "*) [ "$nb $na" = "1 1" ] && [ -z "$bad" ] && v="EXPECTED-DIFF (recon $nr distinct, output-changing arm)" ;; esac
        echo "$CN: recon md5 distinct across 4 arms $nr, bitstream distinct base/base' $nb arm/arm' $na: $v"
        rm -f $W/out/rec_*.yuv $W/out/bs_*.264
    done
}

xe_time() { # R rounds after the ones already in times.txt (an interrupted block resumes)
    mkdir -p $W/out; local R=${1:-$ROUNDS} r0=0 r k a spec arms=(base base2 arm arm2)
    [ -s $W/times.txt ] && r0=$(awk '$1 > m { m = $1 } END { print m + 0 }' $W/times.txt)
    echo "# $(date -u +%FT%TZ) $EVENTS CORE $CORE rounds $((r0 + 1))-$((r0 + R))" >> $W/times.log
    for spec in $CELLS; do xe_cell $spec; [ -f $CL ] && xe_perf base $spec > /dev/null; done   # warm-up, discarded
    for r in $(seq $((r0 + 1)) $((r0 + R))); do for spec in $CELLS; do xe_cell $spec
        [ -f $CL ] || continue
        for k in 0 1 2 3; do a=${arms[$(( (k + r) % 4 ))]}
            echo "$r $CN $a $(xe_perf $a $spec)" >> $W/times.txt
        done
    done; done
    echo "rounds $((r0 + 1))-$((r0 + R)) in $W/times.txt ($(grep -c ' NA' $W/times.txt) lines with NA)"
}

xe_report() { # times.txt: round cell arm ev1 ev2 ... ; base2 = base', arm2 = arm'
    [ -s $W/times.txt ] || xe_die "no $W/times.txt"
    echo "== $JOB${AB:+ AB=$AB}: base $BASE (base, base2), arm $ARM (arm, arm2); CORE $CORE; $EVENTS"
    awk -v EV="$EVENTS" -v NULLS=" ${NULLCELLS:-} " '
    function med( v, n,   i, j, x ) { for( i = 1; i <= n; i++ ) for( j = i+1; j <= n; j++ ) if( v[j] < v[i] ) { x = v[i]; v[i] = v[j]; v[j] = x }
                                    return n % 2 ? v[(n+1)/2] : (v[n/2] + v[n/2+1]) / 2 }
    function num( x ) { return x ~ /^[0-9]+(\.[0-9]+)?$/ }
    { for( e = 4; e <= NF; e++ ) val[$2" "$1" "$3" "(e-3)] = $(e); if( !($2 in seen) ) { seen[$2] = 1; cl[++nc] = $2 } if( $1 > R ) R = $1 }
    END { ne = split( EV, E, "," )
      for( i = 1; i <= nc; i++ ) for( j = i+1; j <= nc; j++ ) if( cl[j] < cl[i] ) { x = cl[i]; cl[i] = cl[j]; cl[j] = x }
      for( i = 1; i <= nc; i++ ) { c = cl[i]
        for( q = 1; q <= ne; q++ ) { m = 0; f = 0
          for( r = 1; r <= R; r++ ) { k = c" "r
            if( !num( val[k" base "q] ) || !num( val[k" base2 "q] ) || !num( val[k" arm "q] ) || !num( val[k" arm2 "q] ) ) continue
            m++; vb[m] = val[k" base "q]; vb2[m] = val[k" base2 "q]; va[m] = val[k" arm "q]; va2[m] = val[k" arm2 "q]
            pd[m] = 100*((va[m]+va2[m])/(vb[m]+vb2[m])-1); d1[m] = 100*(va[m]/vb[m]-1); d2[m] = 100*(va2[m]/vb2[m]-1)
            ab[m] = 100*(vb2[m]/vb[m]-1); aa[m] = 100*(va2[m]/va[m]-1); f += (va[m]+va2[m] < vb[m]+vb2[m]) }
          if( !m ) { printf "%s %s: no complete rounds\n", c, E[q]; continue }
          if( q == 1 )
            printf "%s%s (%d rounds): arm-base %+.2f %% (arm/base %+.2f, arm2/base2 %+.2f), A/A base2/base %+.2f %% arm2/arm %+.2f %%, arm faster in %d/%d\n",
              c, index( NULLS, " "c" " ) ? " [null cell]" : "", m, med(pd,m), med(d1,m), med(d2,m), med(ab,m), med(aa,m), f, m
          else
            printf "    %s paired arm-base %+.3f %%, A/A base2/base %+.3f %%\n", E[q], med(pd,m), med(ab,m)
          printf "    %s median: base %.0f base2 %.0f arm %.0f arm2 %.0f\n", E[q], med(vb,m), med(vb2,m), med(va,m), med(va2,m)
        } } }' $W/times.txt
}

xe_main() {
    case "${1:-}" in
    build)  xe_build ;;
    live)   xe_live ;;
    md5)    xe_md5 ;;
    time)   xe_time "${2:-}" ;;
    report) xe_report ;;
    clean)  rm -rf $W ;;
    *) if [ -n "${1:-}" ] && declare -F xe_phase_$1 > /dev/null; then local p=$1; shift; xe_phase_$p "$@"
       else echo "usage: $0 build | live | md5 | time [rounds] | report | clean${XE_PHASES:+ | $XE_PHASES}   (W=$W)"; exit 1; fi ;;
    esac
}
