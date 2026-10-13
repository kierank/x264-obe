#!/bin/sh
# worst-case-gen.sh: synthetic worst-case clips for x264-obe per-frame cost tests.
# Uses ffmpeg only. POSIX sh, Linux. Writes y4m files. See worst-case-content.md.
#
#   SMOKE=1 sh worst-case-gen.sh            run every selected graph for 0.1 s into null; writes nothing.
#                                           Do this first: the graphs were written without an ffmpeg to test on.
#   LIST=1  sh worst-case-gen.sh            list the cases
#   OUT=/data/wc sh worst-case-gen.sh       generate the priority-1 cases in all three formats
#   OUT=/data/wc CASES="dip field" FORMATS="i422_10" DUR=6 sh worst-case-gen.sh
#
# Formats (all 1920x1080):
#   p420_8   1080p50  8-bit 4:2:0   progressive
#   p422_10  1080p50 10-bit 4:2:2   progressive
#   i422_10  1080i25 10-bit 4:2:2   TRUE interlaced: tinterlace=interleave_top takes the top
#            field from 50p frame 2n and the bottom field from frame 2n+1, then setfield=tff.
#            Check with: ffmpeg -i X_i422_10.y4m -vf idet -an -f null -  (expect TFF, ~0 progressive)
# Every case is built at 1080p50 yuv444p 8-bit and converted per format. Chroma is subsampled
# horizontally only for 4:2:2, so the interlaced 4:2:2 chroma keeps its field structure.
#
# Raw size per case at DUR=6: p420_8 0.93 GB, p422_10 2.5 GB, i422_10 1.25 GB.
#
# Environment:
#   OUT      output directory (default ./wc). No spaces.
#   CASES    case names (default: the priority-1 set $P1)
#   FORMATS  default "p420_8 p422_10 i422_10"
#   DUR      seconds per clip (default 6: 300 frames at 50p, 150 at 25i)
#   ILF      tinterlace flags for i422_10, e.g. vlpf; empty = no vertical filter (harder, the default)
#   BAND_Y, BAND_H  band rows for "band" (default 272, 272: MB rows 17..33, slice 1 of 4 at
#            1080p t4 and inside slice 1 of 4 at 1080i t4)
#   FFMPEG   ffmpeg binary (default ffmpeg)

set -euf

OUT=${OUT:-./wc}
DUR=${DUR:-6}
FORMATS=${FORMATS:-"p420_8 p422_10 i422_10"}
ILF=${ILF:-}
BAND_Y=${BAND_Y:-272}
BAND_H=${BAND_H:-272}
FFMPEG=${FFMPEG:-ffmpeg}
SMOKE=${SMOKE:-0}
LIST=${LIST:-0}

P1="flicker blind band cuts grain"
P2="dip pfade xfade field fieldmix chroma spin shuffle"
P3="baseline shake chromafade strobe qpfloor flickergrain bandflicker"
CASES=${CASES:-$P1}

[ "$SMOKE" = 1 ] && DUR=0.1
ILFOPT=""
[ -n "$ILF" ] && ILFOPT=":flags=$ILF"

# ---------------------------------------------------------------- building blocks

# Static, detailed, colourful texture of size $1, repeated at 50 fps.
# One mandelbrot frame (seahorse valley, deep zoom), looped forever.
tex() {
    printf '%s' "mandelbrot=s=$1:r=50:start_x=-0.743643887037151:start_y=0.13182590420533:start_scale=0.00015:end_scale=0.00015:maxiter=500:outer=normalized_iteration_count:inner=mincol,trim=end_frame=1,loop=loop=-1:size=1,setpts=N/(50*TB),format=yuv444p"
}

# Typical smooth camera move over the texture: up to ~5 px per 50p frame.
pan() {
    printf '%s' "$(tex 2560x1440),crop=1920:1080:x='320+300*sin(2*PI*t/7)':y='180+170*sin(2*PI*t/5)'"
}

ts() {
    printf '%s' "testsrc2=s=1920x1080:r=50,format=yuv444p"
}

# Multiply luma, and chroma around 128, by the gain expression $1 (geq: N frame, T seconds).
gain() {
    printf '%s' "geq=lum='clip(lum(X,Y)*($1),0,255)':cb='clip(128+(cb(X,Y)-128)*($1),0,255)':cr='clip(128+(cr(X,Y)-128)*($1),0,255)'"
}

# Pseudo-random per-frame gain, +-5% at most: lighting flicker, auto-iris hunting, LED walls.
GFLICK='1+0.03*sin(N*2.1)+0.02*sin(N*0.77)'
# Dip to black and back every 3 s: 2 s steady, 0.5 s down, 0.5 s up.
GDIP='if(lt(mod(T,3),2),1,abs(mod(T,3)-2.5)*2)'

# Displacement map for "shuffle": one random vector per 16x16 block per frame, +-30 px.
dmap() {
    printf '%s' "color=c=black:s=120x68:r=50,format=yuv444p,lutyuv=y=128:u=128:v=128,noise=c0s=60:c0f=t+u:c0_seed=$1,scale=1920:1088:flags=neighbor,crop=1920:1080:0:0,geq=lum='lum(X,Y)':cb='lum(X,Y)':cr='lum(X,Y)'"
}

# Tails run per output format: $1 input label, $2 output label, $3 frame rate of that branch.
tail_none() {
    printf '%s' "[$1]null[$2]"
}

# Lowres-blind noise. Each aligned 2x2 luma block gets +d,-d,-d,+d: a checkerboard times one
# even random d per block per frame. With d even, all four planes of x264's lowres filter
# (common/mc.c:553-557) come out unchanged (exact at 8-bit, within 1 LSB after the 10-bit
# conversion). So scenecut, slicetype, VBV planning and weightp do not see it, but the
# full-resolution analysis does. The base is squeezed to 64..191 so nothing clips, because
# clipping would break the cancellation. On for 0.7 s, off for 0.7 s, out of phase with
# keyint 24. For i422_10 it is applied after tinterlace, so it aligns to the coded frame.
tail_blind() {
    printf '%s' "[$1]lutyuv=y=64+val/2[$1b];color=c=black:s=1920x1080:r=$3,format=yuv444p,lutyuv=y=128:u=128:v=128,noise=c0s=60:c0f=t+u,geq=lum='128+2*floor((lum(2*floor(X/2),2*floor(Y/2))-128)/2)*(1-2*mod(X+Y,2))':cb=128:cr=128[$1n];[$1b][$1n]blend=c0_expr='A+(B-128)*gt(mod(T,1.4),0.7)':c1_expr=A:c2_expr=A[$2]"
}

# ---------------------------------------------------------------- cases
# Each sets MAIN (a graph ending in [m], 1080p50 yuv444p) and optionally TAILP / TAILI.

describe() {
    case $1 in
    flicker)      echo "P1 per-frame random global luma+chroma gain (+-5%) on a colourful pan: weightp every frame" ;;
    blind)        echo "P1 lowres-blind 2x2 checker noise, toggled 0.7 s on/off: RC/VBV/scenecut blind, row re-encodes" ;;
    band)         echo "P1 static slate + one 272-row band of fast-scrolling detail with temporal noise: slice imbalance" ;;
    cuts)         echo "P1 rapid cuts (2-7 frames) between 3 moving scenes + single-frame white flashes (one field at 1080i)" ;;
    grain)        echo "P1 heavy temporal grain (luma+chroma) on a moving detailed pan: no skips, full intra, dense RD" ;;
    dip)          echo "P2 dip to black and back every 3 s on saturated content: the known fade case, realistic timing" ;;
    pfade)        echo "P2 lower 40% fades (lower-third style), top static: weight helps part, hurts the rest" ;;
    xfade)        echo "P2 continuous crossfade between two moving scenes" ;;
    field)        echo "P2 fast horizontal pan (15 px/50p frame): true field motion at 1080i, progressive control at 50p" ;;
    fieldmix)     echo "P2 alternating 16-px columns of moving and static texture: field/frame MB pairs alternate" ;;
    chroma)       echo "P2 saturated fine chroma pattern, moving, plus chroma noise: 4:2:2 chroma load" ;;
    spin)         echo "P2 detailed texture rotating 90 deg/s: non-translational motion, ME and partition load" ;;
    shuffle)      echo "P2 every 16x16 block displaced by a random +-30 px vector per frame: ME failure (pathological)" ;;
    baseline)     echo "P3 control: smooth pan + light grain (typical synthetic)" ;;
    shake)        echo "P3 control: large erratic but spatially uniform motion (predictors should keep ME cheap)" ;;
    chromafade)   echo "P3 control: chroma-only saturation pulse, luma constant (no chroma weights expected)" ;;
    strobe)       echo "P3 two unrelated scenes alternating every frame (pathological sustained cut)" ;;
    qpfloor)      echo "P3 static bars + +-1 LSB temporal noise: ABR drives QP down, every MB coded" ;;
    flickergrain) echo "P3 combo: flicker + heavy grain" ;;
    bandflicker)  echo "P3 combo: slice band + global flicker" ;;
    *)            return 1 ;;
    esac
}

setcase() {
    TAILP=tail_none
    TAILI=tail_none
    case $1 in
    flicker)
        MAIN="$(pan),eq=saturation=1.4,$(gain "$GFLICK")[m]" ;;
    blind)
        MAIN="$(pan)[m]"; TAILP=tail_blind; TAILI=tail_blind ;;
    band)
        MAIN="color=c=0x304858:s=1920x1080:r=50,format=yuv444p,noise=c0s=6:c0f=u[bg];$(tex 2560x1440),crop=1920:$BAND_H:x='mod(t*1500,640)':y=600,noise=c0s=40:c0f=t+u:c1s=20:c1f=t+u:c2s=20:c2f=t+u[bd];[bg][bd]overlay=x=0:y=$BAND_Y:format=yuv444[m]" ;;
    cuts)
        MAIN="$(pan)[c0];$(ts)[c1];life=s=480x270:r=50:mold=10:ratio=0.35:life_color=0xFFB060:death_color=0x103050:mold_color=0x406080,scale=1920:1080:flags=neighbor,format=yuv444p[c2];color=c=white:s=1920x1080:r=50,format=yuv444p[fl];[c0][c1]overlay=format=yuv444:enable='between(mod(n,29),3,7)+between(mod(n,29),17,18)'[x1];[x1][c2]overlay=format=yuv444:enable='between(mod(n,29),8,9)+between(mod(n,29),19,23)'[x2];[x2][fl]overlay=format=yuv444:enable='eq(mod(n,37),11)'[m]" ;;
    grain)
        MAIN="$(pan),noise=c0s=30:c0f=t+u:c1s=12:c1f=t+u:c2s=12:c2f=t+u[m]" ;;
    dip)
        MAIN="$(pan),eq=saturation=1.8,$(gain "$GDIP")[m]" ;;
    pfade)
        MAIN="$(pan),eq=saturation=1.4,geq=lum='if(gt(Y,H*0.6),clip(lum(X,Y)*($GDIP),0,255),lum(X,Y))':cb='if(gt(Y,H*0.6),clip(128+(cb(X,Y)-128)*($GDIP),0,255),cb(X,Y))':cr='if(gt(Y,H*0.6),clip(128+(cr(X,Y)-128)*($GDIP),0,255),cr(X,Y))'[m]" ;;
    xfade)
        MAIN="$(pan)[a];$(ts)[b];[a][b]blend=all_expr='A*(abs(mod(T,4)-2)/2)+B*(1-abs(mod(T,4)-2)/2)'[m]" ;;
    field)
        MAIN="$(tex 2560x1440),crop=1920:1080:x='320+300*sin(2*PI*t/2.5)':y='180+60*sin(2*PI*t/3.7)'[m]" ;;
    fieldmix)
        MAIN="$(tex 2560x1440),split[fma][fmb];[fma]crop=1920:1080:x='320+300*sin(2*PI*t/2.5)':y=180[fmc];[fmb]crop=1920:1080:x=100:y=300[fmd];[fmc][fmd]blend=all_expr='if(mod(floor(X/16),2),A,B)'[m]" ;;
    chroma)
        MAIN="$(pan),geq=lum='lum(X,Y)':cb='clip(128+110*sin(X*0.9+T*7)*sin(Y*0.35),0,255)':cr='clip(128+110*cos(X*0.45-T*5)*sin(Y*0.8+T*3),0,255)',noise=c1s=30:c1f=t+u:c2s=30:c2f=t+u[m]" ;;
    spin)
        MAIN="$(tex 2304x2304),rotate=a='2*PI*t/4':ow=1920:oh=1080:c=black[m]" ;;
    shuffle)
        MAIN="$(tex 2560x1440),crop=1920:1080:x=300:y=200[shb];$(dmap 1)[shx];$(dmap 2)[shy];[shb][shx][shy]displace=edge=smear[m]" ;;
    baseline)
        MAIN="$(pan),noise=c0s=4:c0f=t+u[m]" ;;
    shake)
        MAIN="$(tex 2560x1440),crop=1920:1080:x='320+150*sin(2*PI*t*3.3)+120*sin(2*PI*t*7.1)':y='180+80*sin(2*PI*t*4.7)+60*sin(2*PI*t*9.3)'[m]" ;;
    chromafade)
        MAIN="$(pan),eq=saturation=1.6,geq=lum='lum(X,Y)':cb='128+(cb(X,Y)-128)*(0.5+0.5*cos(2*PI*T/2))':cr='128+(cr(X,Y)-128)*(0.5+0.5*cos(2*PI*T/2))'[m]" ;;
    strobe)
        MAIN="$(pan)[a];$(ts)[b];[a][b]overlay=format=yuv444:enable='mod(n,2)'[m]" ;;
    qpfloor)
        MAIN="smptehdbars=s=1920x1080:r=50,format=yuv444p,noise=c0s=2:c0f=t+u[m]" ;;
    flickergrain)
        MAIN="$(pan),eq=saturation=1.4,$(gain "$GFLICK"),noise=c0s=30:c0f=t+u:c1s=12:c1f=t+u:c2s=12:c2f=t+u[m]" ;;
    bandflicker)
        MAIN="color=c=0x304858:s=1920x1080:r=50,format=yuv444p,noise=c0s=6:c0f=u[bg];$(tex 2560x1440),crop=1920:$BAND_H:x='mod(t*1500,640)':y=600,noise=c0s=40:c0f=t+u:c1s=20:c1f=t+u:c2s=20:c2f=t+u[bd];[bg][bd]overlay=x=0:y=$BAND_Y:format=yuv444,$(gain "$GFLICK")[m]" ;;
    *)
        echo "unknown case: $1" >&2; exit 1 ;;
    esac
}

# ---------------------------------------------------------------- emitter

emit() {
    name=$1
    n=0
    for f in $FORMATS; do n=$((n + 1)); done
    labels=""
    k=0
    while [ $k -lt $n ]; do labels="$labels[wcs$k]"; k=$((k + 1)); done
    g="$MAIN;[m]split=$n$labels"
    args=""
    k=0
    for f in $FORMATS; do
        case $f in
        p420_8)
            g="$g;$($TAILP wcs$k wct$k 50);[wct$k]format=yuv420p[wco$k]" ;;
        p422_10)
            g="$g;$($TAILP wcs$k wct$k 50);[wct$k]format=yuv422p10le[wco$k]" ;;
        i422_10)
            g="$g;[wcs$k]tinterlace=mode=interleave_top$ILFOPT,setfield=tff[wcu$k];$($TAILI wcu$k wct$k 25);[wct$k]format=yuv422p10le[wco$k]" ;;
        *)
            echo "unknown format: $f" >&2; exit 1 ;;
        esac
        if [ "$SMOKE" = 1 ]; then
            dst="-f null -"
        else
            dst="$OUT/${name}_$f.y4m"
        fi
        args="$args -map [wco$k] -t $DUR -strict -1 $dst"
        k=$((k + 1))
    done
    # $args is split on purpose; set -f stops [oN] globbing
    # shellcheck disable=SC2086
    "$FFMPEG" -nostdin -hide_banner -loglevel error -y -filter_complex "$g" $args
}

# ---------------------------------------------------------------- main

if [ "$LIST" = 1 ]; then
    for c in $P1 $P2 $P3; do printf '%-13s %s\n' "$c" "$(describe "$c")"; done
    exit 0
fi

[ "$SMOKE" = 1 ] || mkdir -p "$OUT"
for c in $CASES; do
    describe "$c" > /dev/null || { echo "unknown case: $c" >&2; exit 1; }
    setcase "$c"
    printf '%s: %s\n' "$c" "$(describe "$c")"
    t0=$(date +%s)
    emit "$c"
    printf '  done in %ss\n' $(( $(date +%s) - t0 ))
done
if [ "$SMOKE" = 1 ]; then
    echo "smoke: every selected graph ran"
else
    ls -l "$OUT"
fi
