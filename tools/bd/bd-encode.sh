#!/bin/sh
# bd-encode.sh: rate points for BD-rate, obed-style VBV encodes, one line each
# usage: [BD_RC=crf] bd-encode.sh <x264> <arm label> <normal|lowlat> <8|10> <source> <out.tsv> <kbps...> [-- extra x264 options]
# <source>: .y4m (8-bit 4:2:0), or raw 10-bit 4:2:2 1920x1080 (.yuv); set
#   BD_INPUT to override the input options, BD_FRAMES (default 300) the length.
# Output, tab separated, appended to <out.tsv>:
#   arm config depth source target_kbps kbps psnr_y psnr_u psnr_v psnr_yuv611 ssim_y_db fps md5
# psnr_yuv611 = (6Y + U + V) / 8 of the per-plane mean PSNRs.
set -e
X264=$1; ARM=$2; CFG=$3; DEPTH=$4; SRC=$5; OUT=$6; shift 6
RATES=""
while [ $# -gt 0 ] && [ "$1" != "--" ]; do RATES="$RATES $1"; shift; done
[ "$1" = "--" ] && shift
EXTRA="$*"
FRAMES=${BD_FRAMES:-300}

case $SRC in
    *.y4m) INPUT="--fps 25 --tff ${BD_CSP:---output-csp i420} $SRC" ;;
    *)     INPUT="--input-res 1920x1080 --fps 25 --tff --input-csp i422 --output-csp i422 --input-depth 10 $SRC" ;;
esac
[ -n "$BD_INPUT" ] && INPUT="$BD_INPUT $SRC"

COMMON="--output-depth $DEPTH --aud --pic-struct --open-gop --threads 8 --keyint 24 --colorprim bt709 --transfer bt709 --colormatrix bt709 --overscan crop --psnr --ssim"
[ "$BD_RC" = crf ] || COMMON="$COMMON --nal-hrd fakevbr"

for R in $RATES; do
    # BD_RC=crf: the rate points are CRF values and there is no VBV. That is
    # deterministic with frame threads, unlike VBV (10-bit normal varies ~1% run
    # to run), so rank arms with it and confirm with the obed VBV mode.
    if [ "$BD_RC" = crf ]; then
        RC="--crf $R"; RCL="--crf $R"
    else
        RC="--bitrate $R --vbv-maxrate $R --vbv-bufsize $R"
        RCL="--bitrate $R --vbv-maxrate $R --vbv-bufsize $((R / 2))"
    fi
    case $CFG in
        normal) OPTS="$COMMON $RC --ref 4 --bframes 3 --rc-lookahead 24" ;;
        lowlat) OPTS="$COMMON --preset veryfast --tune zerolatency $RCL" ;;
        *) echo "bd-encode.sh: config must be normal or lowlat" >&2; exit 1 ;;
    esac
    LOG=$(mktemp)
    BS=$(mktemp)
    # shellcheck disable=SC2086
    "$X264" $OPTS $EXTRA $INPUT --frames "$FRAMES" -o "$BS" 2> "$LOG"
    awk -v arm="$ARM" -v cfg="$CFG" -v depth="$DEPTH" -v src="$(basename "$SRC")" -v r="$R" \
        -v md5="$(md5sum "$BS" | cut -c1-12)" '
        /PSNR Mean/ {
            for (i = 1; i <= NF; i++) {
                split($i, kv, ":")
                if (kv[1] == "Y") y = kv[2]; else if (kv[1] == "U") u = kv[2]
                else if (kv[1] == "V") v = kv[2]; else if (kv[1] == "kb/s") kbps = kv[2]
            }
        }
        /SSIM Mean/ { match($0, /\( *[0-9.]+db\)/); s = substr($0, RSTART + 1, RLENGTH - 4); gsub(/ /, "", s) } # %6.3f: below 10 dB has a leading space
        /encoded [0-9]+ frames/ { for (i = 1; i <= NF; i++) if ($i == "fps,") fps = $(i-1) }
        END {
            if (y == "" || kbps == "") { print "bd-encode.sh: no PSNR line in the x264 log" > "/dev/stderr"; exit 1 }
            printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%.4f\t%s\t%s\t%s\n", arm, cfg, depth, src, r, kbps, y, u, v, (6*y + u + v) / 8, s, fps, md5
        }' "$LOG" >> "$OUT"
    rm -f "$LOG" "$BS"
done
