#!/bin/sh
# Copyright (C) 2026 Open Broadcast Systems Ltd
#
# Builds libx264.a of an x264 tree (--bit-depth=all), links tools/wavgdrv/wavgdrv.c
# against it and runs it RUNS times pinned to CPU, memory bound to NODE.
#
# usage: run.sh <x264 tree> [cpu] [node] [runs] [outdir] [-- wavgdrv options]
#   tree: a git checkout (WAVG_COMMIT, default HEAD, is exported with git archive)
#         or a plain source directory
#   defaults: cpu 24, node 6, runs 3, outdir /dev/shm/wavgdrv-out
#   WAVG_BUILD: build directory (default /dev/shm/wavgdrv-build)

set -e

SRC=$1
[ -n "$SRC" ] || { sed -n '4,12p' "$0"; exit 1; }
shift
CPU=24; NODE=6; RUNS=3; OUT=/dev/shm/wavgdrv-out
for v in CPU NODE RUNS OUT; do
    [ $# -gt 0 ] && [ "$1" != "--" ] || break
    eval "$v=\$1"
    shift
done
[ "$1" = "--" ] && shift
BUILD=${WAVG_BUILD:-/dev/shm/wavgdrv-build}
COMMIT=${WAVG_COMMIT:-HEAD}

rm -rf "$BUILD"
mkdir -p "$BUILD/src" "$OUT"
if git -C "$SRC" rev-parse --git-dir >/dev/null 2>&1; then
    REV=$(git -C "$SRC" rev-parse --short=8 "$COMMIT")
    git -C "$SRC" -c core.autocrlf=false archive "$COMMIT" | tar -x -C "$BUILD/src"
else
    REV=unknown
    cp -a "$SRC"/. "$BUILD/src"
fi
DRV="$BUILD/src/tools/wavgdrv/wavgdrv.c"
[ -f "$DRV" ] || DRV="$(cd "$(dirname "$0")" && pwd)/wavgdrv.c"
echo "tree $SRC rev $REV  driver $DRV  build $BUILD"

cd "$BUILD/src"
./configure --bit-depth=all --disable-cli --enable-static --extra-ldflags=-no-pie > "$BUILD/configure.log" 2>&1 ||
    { tail -20 "$BUILD/configure.log"; exit 1; }
make -j"$(nproc)" lib-static > "$BUILD/make.log" 2>&1 || { tail -30 "$BUILD/make.log"; exit 1; }
gcc -O2 -std=gnu11 -Wall -DWAVG_REV="\"$REV\"" -o "$BUILD/wavgdrv" "$DRV" "$BUILD/src/libx264.a" \
    -lm -lpthread -ldl -no-pie
cd "$BUILD"

echo "host $(hostname)  $(uptime)"
if [ ! -e "/sys/devices/system/node/node$NODE/cpu$CPU" ]; then
    echo "WARNING: cpu $CPU is not in node $NODE"
fi
if pgrep -x obdd >/dev/null 2>&1 || pgrep -x obed >/dev/null 2>&1; then
    echo "WARNING: decoders/encoders running (stop them via SNMP before timing)"
    pgrep -a -x obdd || true
    pgrep -a -x obed || true
fi
if command -v numactl >/dev/null 2>&1; then
    BIND="numactl --cpunodebind=$NODE --membind=$NODE"
else
    BIND=""
    echo "WARNING: no numactl, cpu pinning only"
fi

i=1
while [ "$i" -le "$RUNS" ]; do
    t0=$(date +%s)
    $BIND "$BUILD/wavgdrv" -c "$CPU" "$@" > "$OUT/run$i.txt" || echo "run $i: exit $? (2 = mismatching cells)"
    t1=$(date +%s)
    echo "run $i: $((t1 - t0)) s -> $OUT/run$i.txt"
    i=$((i + 1))
done

echo
echo "VERDICT lines per run (ratio = A/B ticks, CI over repetitions):"
i=1
while [ "$i" -le "$RUNS" ]; do
    echo "== run $i"
    grep -E '^(VERDICT|SKIP|# done)' "$OUT/run$i.txt"
    i=$((i + 1))
done
grep -l MISMATCH "$OUT"/run*.txt >/dev/null 2>&1 && echo "MISMATCH present: grep MISMATCH $OUT/run*.txt"
exit 0
