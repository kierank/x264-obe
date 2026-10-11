#!/bin/sh
# Turn a perf profile into a function order for
#   ./configure --hot-order=FILE    (implies --enable-func-sections)
# Hottest functions first; each function is placed after its heaviest
# caller (C3: Ottoni & Maher, CGO 2017) when call or branch edges are
# present. Only sampled functions are listed, so ISA variants that are
# never dispatched stay out of the hot region.

usage() {
    cat >&2 <<EOF
usage: $0 [options] perf.txt...      (- reads stdin)
       $0 -c ORDERFILE -b BINARY     (check the order in a linked binary)
       $0 -m gold|ld|insert ORDERFILE [OBJECTS...]
                                     (linker file, used by configure/Makefile)
input, any mix of:
  perf report --no-children --sort symbol --stdio     heat
  perf script            from perf record [-g|--call-graph=...]
                         heat from the sampled IP, call edges from the stack
  perf script -F brstacksym   from perf record -b / -j any_call,u
                         branch edges (pair it with a perf report for heat)
options:
  -b BINARY  keep only functions defined in BINARY (nm), take sizes from it
  -t PCT     drop functions below PCT% of total heat [0]
  -n N       keep at most the N hottest functions [all]
  -p BYTES   C3 cluster size cap [4096]
  -s SEED    output the same set in a seeded random order (control)
  -c FILE    with -b: report how much of FILE's order BINARY follows
  -m FMT     map ORDERFILE's symbols to the sections holding them in OBJECTS
             (objdump -t; by name without objects) and print a gold
             --section-ordering-file, a GNU ld one, or an INSERT script
EOF
    exit 1
}

nmbin= tmin=0 nmax=0 cap=4096 seed= check= mapfmt=
while getopts b:t:n:p:s:c:m:h o; do
    case $o in
        b) nmbin=$OPTARG ;;
        t) tmin=$OPTARG ;;
        n) nmax=$OPTARG ;;
        p) cap=$OPTARG ;;
        s) seed=$OPTARG ;;
        c) check=$OPTARG ;;
        m) mapfmt=$OPTARG ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

nmfile=
if [ -n "$nmbin" ]; then
    nmfile=${TMPDIR:-/tmp}/hot-order.$$
    trap 'rm -f "$nmfile"' EXIT
    trap 'exit 1' INT TERM
    ${NM:-nm} -n -S --defined-only "$nmbin" > "$nmfile" || exit 1
    [ -s "$nmfile" ] || { echo "$0: no symbols in $nmbin (stripped?)" >&2; exit 1; }
fi

if [ -n "$check" ]; then
    [ -n "$nmfile" ] || usage
    awk -v nmfile="$nmfile" '
    function hex(s,    i, c, v) {
        v = 0; s = tolower(s)
        for (i = 1; i <= length(s); i++) {
            c = index("0123456789abcdef", substr(s, i, 1))
            if (!c) break
            v = v * 16 + c - 1
        }
        return v
    }
    { sub(/#.*/, ""); gsub(/[ \t\r]/, "") }
    $0 != "" && !($0 in rank) { rank[$0] = ++n }
    END {
        while ((getline line < nmfile) > 0) {
            k = split(line, fld, " ")
            if (k == 4) { a = fld[1]; t = fld[3]; s = fld[4] } else if (k == 3) { a = fld[1]; t = fld[2]; s = fld[3] } else continue
            if (t !~ /^[tTwWiI]$/ || !(s in rank) || (s in seen)) continue
            seen[s] = 1; found++
            if (prev && rank[s] < prev) inv++
            prev = rank[s]
            if (found == 1) lo = hex(a)
            hi = hex(a)
        }
        # an applied order leaves only a few inversions (shared asm sections,
        # same-named statics); an unordered link leaves about half
        printf "%d of %d ordered symbols in binary, %d of %d neighbours out of order, span %d bytes (first to last start)\n", found, n, inv, (found > 1 ? found - 1 : 0), hi - lo
        exit !found
    }' "$check"
    exit $?
fi

if [ -n "$mapfmt" ]; then
    case $mapfmt in gold|ld|insert) ;; *) usage ;; esac
    [ $# -ge 1 ] || usage
    order=$1; shift
    symfile=${TMPDIR:-/tmp}/hot-order-map.$$
    trap 'rm -f "$symfile"' EXIT
    trap 'exit 1' INT TERM
    : > "$symfile"
    if [ $# -gt 0 ]; then
        ${OBJDUMP:-objdump} -t "$@" > "$symfile" || exit 1
    fi
    awk -v fmt="$mapfmt" -v symfile="$symfile" -v mapped=$# '
    function emit(s) { if (!(s in done)) { done[s] = 1; out[++k] = s } }
    # objdump -t: addr flags section<TAB>size [.hidden] name
    FILENAME == symfile {
        t = index($0, "\t"); if (!t) next
        nl = split(substr($0, 1, t - 1), L, " "); sec = L[nl]
        nr = split(substr($0, t + 1), R, " "); name = R[nr]
        if (sec !~ /^\.text\./ || ((name, sec) in seen)) next
        seen[name, sec] = 1; secs[name] = secs[name] " " sec
        next
    }
    { sub(/#.*/, ""); gsub(/[ \t\r]/, "") }
    $0 == "" { next }
    mapped { n = split(secs[$0], S, " "); for (i = 1; i <= n; i++) emit(S[i]); next }
    { emit(".text." $0); emit(".text.hot." $0); emit(".text.startup." $0) }
    END {
        if (fmt == "gold") { for (i = 1; i <= k; i++) print out[i]; exit }
        print "SECTIONS"; print "{"
        print (fmt == "ld" ? "  .text :" : "  .text.x264_hot :")
        print "  {"
        for (i = 1; i <= k; i++) print "    *(" out[i] ")"
        print "  }"; print "}"
        if (fmt == "insert") print "INSERT BEFORE .text;"
    }' "$symfile" "$order"
    exit $?
fi

[ $# -ge 1 ] || usage

awk -v nmfile="$nmfile" -v tmin="$tmin" -v nmax="$nmax" -v cap="$cap" -v seed="$seed" '
function err(s) { print "hot-order: " s | "cat 1>&2" }
function hex(s,    i, c, v) {
    v = 0; s = tolower(s)
    for (i = 1; i <= length(s); i++) {
        c = index("0123456789abcdef", substr(s, i, 1))
        if (!c) break
        v = v * 16 + c - 1
    }
    return v
}
# function name a sample or label belongs to, "" if not ours
function norm(s) {
    sub(/\+0x[0-9a-fA-F]+$/, "", s)
    if (s == "" || s ~ /^\[/ || s ~ /^(0x)?[0-9a-fA-F]+$/ || s ~ /@/) return ""
    # nasm local labels (func.loop) belong to func; gcc clone suffixes are
    # separate functions with their own sections
    if (s ~ /\./ && s !~ /\.(constprop|isra|part|lto_priv|localalias|clone|cold)(\.|$)/)
        sub(/\..*/, "", s)
    # split-off cold parts live in .text.unlikely.*
    if (s ~ /\.cold(\.[0-9]+)?$/) return ""
    return s
}
# caller a -> callee b (or branch source/target)
function edge(a, b) {
    a = norm(a); b = norm(b)
    if (a == "" || b == "" || a == b) return
    if (!((a, b) in w)) pl[b] = pl[b] " " a
    w[a, b]++
    nedge++
}
function before(a, b, K) { return K[a] > K[b] || (K[a] == K[b] && a < b) }
function qs(A, K, lo, hi,    i, last, t, m) {
    if (lo >= hi) return
    m = int((lo + hi) / 2); t = A[lo]; A[lo] = A[m]; A[m] = t
    last = lo
    for (i = lo + 1; i <= hi; i++)
        if (before(A[i], A[lo], K)) { last++; t = A[last]; A[last] = A[i]; A[i] = t }
    t = A[lo]; A[lo] = A[last]; A[last] = t
    qs(A, K, lo, last - 1); qs(A, K, last + 1, hi)
}

/^#/ { next }
/^[ \t]*$/ { inframe = 0; next }
{
    nb = 0
    for (i = 1; i <= NF; i++)
        if ($i ~ /^[^\/(][^\/]*\/[^\/]+\/[A-Z-]+\//) {
            split($i, bt, "/"); edge(bt[1], bt[2]); edge(bt[2], bt[1])
            s = norm(bt[1]); if (s != "") hb[s]++
            s = norm(bt[2]); if (s != "") hb[s]++
            nb++
        }
    if (nb) { inframe = 0; next }
}
# perf report: last percentage before [.] is Self
/\[\.\] / {
    pct = ""
    for (i = 1; i <= NF && $i != "[.]"; i++) if ($i ~ /^[0-9.]+%$/) pct = $i
    if (pct != "") {
        s = substr($0, index($0, "[.] ") + 4); sub(/[ \t]+$/, "", s)
        s = norm(s); if (s != "") hr[s] += pct + 0
    }
    next
}
# perf script callchain frame: addr sym+off (dso); first frame is the IP
/^[ \t]+[0-9a-fA-F]+ [^ ]+( \(.*\))?[ \t]*$/ {
    if (!inframe) { s = norm($2); if (s != "") hs[s]++; inframe = 1 }
    else edge($2, prev)
    prev = $2
    next
}
# perf script sample header; without a callchain it ends in addr sym (dso)
{
    inframe = 0
    if (NF >= 3 && $(NF - 2) ~ /^[0-9a-fA-F]+$/ && $NF ~ /^\(.*\)$/) {
        s = norm($(NF - 1)); if (s != "") hs[s]++
    }
}

END {
    for (s in hr) { src = "perf report"; break }
    if (src == "") for (s in hs) { src = "perf script samples"; break }
    if (src == "") for (s in hb) { src = "branch records"; break }
    if (src == "") { err("no samples parsed"); exit 1 }
    if (src == "perf report") for (s in hr) H[s] = hr[s]
    else if (src == "perf script samples") for (s in hs) H[s] = hs[s]
    else for (s in hb) H[s] = hb[s]

    if (nmfile != "") {
        while ((getline line < nmfile) > 0) {
            k = split(line, fld, " ")
            if (k == 4) { a = fld[1]; z = fld[2]; t = fld[3]; s = fld[4] }
            else if (k == 3) { a = fld[1]; z = ""; t = fld[2]; s = fld[3] }
            else continue
            if (t !~ /^[tTwWiI]$/ || norm(s) != s) continue
            intext[s] = 1
            ns++; addr[ns] = hex(a); name[ns] = s
            if (z != "" && hex(z) > 0) size[s] = hex(z)
        }
        # nasm symbols carry no size: use the distance to the next function
        for (i = 1; i < ns; i++)
            if (!(name[i] in size) && addr[i + 1] > addr[i]) size[name[i]] = addr[i + 1] - addr[i]
    }

    total = 0
    for (s in H) total += H[s]
    n = 0
    for (s in H) {
        if (nmfile != "" && !(s in intext)) { nbin++; continue }
        if (H[s] * 100 < tmin * total) { nlow++; continue }
        F[++n] = s
    }
    qs(F, H, 1, n)
    if (nmax > 0 && n > nmax) { nlow += n - nmax; n = nmax }

    for (i = 1; i <= n; i++) {
        f = F[i]; inset[f] = 1; cl[f] = f; nx[f] = ""; tl[f] = f
        cs[f] = (f in size) ? size[f] : 64; ch[f] = H[f]; kept += H[f]
    }

    # C3: append each cluster headed by a hot function to its heaviest
    # caller cluster, unless the merge is too big, the edge is weak, or the
    # caller cluster would lose too much density
    for (i = 1; i <= n; i++) {
        f = F[i]
        if (cl[f] != f) continue
        best = ""; bw = 0; tw = 0
        m = split(pl[f], P, " ")
        for (j = 1; j <= m; j++) {
            p = P[j]
            if (!(p in inset)) continue
            tw += w[p, f]
            if (cl[p] == f) continue
            if (w[p, f] > bw || (w[p, f] == bw && p < best)) { bw = w[p, f]; best = p }
        }
        if (best == "" || bw * 10 <= tw) continue
        a = cl[best]
        if (cs[a] + cs[f] > cap) continue
        if (ch[a] / cs[a] > 8 * (ch[a] + ch[f]) / (cs[a] + cs[f])) continue
        nx[tl[a]] = f; tl[a] = tl[f]
        for (g = f; g != ""; g = nx[g]) cl[g] = a
        cs[a] += cs[f]; ch[a] += ch[f]; merged++
    }

    nh = 0
    for (i = 1; i <= n; i++) if (cl[F[i]] == F[i]) { C[++nh] = F[i]; D[F[i]] = ch[F[i]] / cs[F[i]] }
    qs(C, D, 1, nh)
    k = 0
    for (i = 1; i <= nh; i++) for (g = C[i]; g != ""; g = nx[g]) O[++k] = g

    if (seed != "") {
        srand(seed)
        for (i = k; i > 1; i--) { j = int(rand() * i) + 1; t = O[i]; O[i] = O[j]; O[j] = t }
    }
    for (i = 1; i <= k; i++) print O[i]

    err(sprintf("%d functions (%.1f%% of %s heat), %d dropped below threshold/-n, %d not in binary, %d edges, %d merges into %d clusters%s",
        k, total ? 100 * kept / total : 0, src, nlow, nbin, nedge, merged + 0, nh, seed != "" ? ", shuffled" : ""))
}' "$@"
