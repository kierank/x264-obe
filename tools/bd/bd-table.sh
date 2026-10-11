#!/bin/sh
# bd-table.sh: BD-rate of every arm against an anchor arm, from bd-encode.sh output
# usage: bd-table.sh <results.tsv> <anchor arm> [bdrate.awk path]
# One line per (arm, config, depth, source) and metric (PSNR-Y, PSNR-YUV 6:1:1, SSIM-Y dB).
TSV=$1; ANCHOR=$2; BDAWK=${3:-$(dirname "$0")/bdrate.awk}
for key in $(awk -F'\t' -v a="$ANCHOR" '$1 != a { print $1 "|" $2 "|" $3 "|" $4 }' "$TSV" | sort -u); do
    arm=${key%%|*}; rest=${key#*|}
    cfg=${rest%%|*}; rest=${rest#*|}
    depth=${rest%%|*}; src=${rest#*|}
    for m in 7:psnr_y 10:psnr_yuv 11:ssim_db; do
        col=${m%%:*}; name=${m#*:}
        res=$(awk -F'\t' -v a="$ANCHOR" -v t="$arm" -v c="$cfg" -v d="$depth" -v s="$src" -v col="$col" '
            $2 == c && $3 == d && $4 == s && $1 == a { print "anchor", $6, $col }
            $2 == c && $3 == d && $4 == s && $1 == t { print "test", $6, $col }' "$TSV" | awk -f "$BDAWK" 2>&1)
        printf "%-24s %-7s %2s-bit %-28s %-9s %s\n" "$arm" "$cfg" "$depth" "$src" "$name" "$res"
    done
done
